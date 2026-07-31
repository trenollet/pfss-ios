import { createHash } from "node:crypto";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";

interface SeededIdentity {
  tenantID: string;
  memberID: string;
  deviceID: string;
  token: string;
}

async function seedIdentity(
  label: string,
  role: "owner" | "manager" | "member" = "owner",
): Promise<SeededIdentity> {
  const tenantID = crypto.randomUUID();
  const memberID = crypto.randomUUID();
  const deviceID = crypto.randomUUID();
  const token = `${label}-${crypto.randomUUID()}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO tenants (id, display_name, status, created_at) VALUES (?1, ?2, 'active', ?3)",
    ).bind(tenantID, `${label} Business`, now),
    env.DB.prepare(
      `INSERT INTO tenant_members
        (id, tenant_id, display_name, role, status, created_at, activated_at)
       VALUES (?1, ?2, ?3, ?4, 'active', ?5, ?5)`,
    ).bind(memberID, tenantID, `${label} Member`, role, now),
    env.DB.prepare(
      `INSERT INTO devices
        (id, tenant_id, member_id, display_name, token_hash, created_at, last_seen_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
    ).bind(deviceID, tenantID, memberID, `${label} Device`, tokenHash, now),
  ]);
  return { tenantID, memberID, deviceID, token };
}

async function seedAdditionalDevice(
  identity: SeededIdentity,
  label: string,
): Promise<SeededIdentity> {
  const deviceID = crypto.randomUUID();
  const token = `${label}-${crypto.randomUUID()}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO devices
      (id, tenant_id, member_id, display_name, token_hash, created_at, last_seen_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
  ).bind(
    deviceID,
    identity.tenantID,
    identity.memberID,
    `${label} Device`,
    tokenHash,
    now,
  ).run();
  return { ...identity, deviceID, token };
}

async function seedMemberInTenant(
  owner: SeededIdentity,
  label: string,
  role: "owner" | "manager" | "member" = "member",
): Promise<SeededIdentity> {
  const memberID = crypto.randomUUID();
  const deviceID = crypto.randomUUID();
  const token = `${label}-${crypto.randomUUID()}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO tenant_members
        (id, tenant_id, display_name, role, status, created_at, activated_at)
       VALUES (?1, ?2, ?3, ?4, 'active', ?5, ?5)`,
    ).bind(memberID, owner.tenantID, label, role, now),
    env.DB.prepare(
      `INSERT INTO devices
        (id, tenant_id, member_id, display_name, token_hash, created_at, last_seen_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
    ).bind(deviceID, owner.tenantID, memberID, `${label} Device`, tokenHash, now),
  ]);
  return { tenantID: owner.tenantID, memberID, deviceID, token };
}

function request(
  identity: SeededIdentity,
  path: string,
  init: RequestInit = {},
): Request {
  const headers = new Headers(init.headers);
  headers.set("authorization", `Bearer ${identity.token}`);
  return new Request(`https://pfss.test${path}`, { ...init, headers });
}

async function seedEmployeeRecord(
  identity: SeededIdentity,
  employeeID: string,
  roles: string[],
): Promise<void> {
  const now = new Date().toISOString();
  const recordData = Buffer.from(JSON.stringify({
    id: employeeID,
    firstName: "Linked",
    lastName: "Employee",
    role: roles[0] ?? "Technician",
    roles,
  })).toString("base64");
  const mutation = Buffer.from(JSON.stringify({
    entityType: "employee",
    entityID: employeeID,
    recordData,
    modifiedAt: now,
  })).toString("base64");
  const operation = {
    id: crypto.randomUUID(),
    idempotencyKey: `employee-${employeeID}`,
    type: "recordMutation",
    entityType: "employee",
    entityID: employeeID,
    actionName: "upsertRecord",
    payload: { schemaVersion: 1, contentType: "test", body: mutation },
    createdAt: now,
  };
  await env.DB.prepare(
    `INSERT INTO synchronized_records
      (tenant_id, entity_type, entity_id, revision, operation_json,
       updated_by_member_id, updated_by_device_id, updated_at)
     VALUES (?1, 'employee', ?2, ?3, ?4, ?5, ?6, ?7)`,
  ).bind(
    identity.tenantID, employeeID.toLowerCase(), crypto.randomUUID(),
    JSON.stringify(operation), identity.memberID, identity.deviceID, now,
  ).run();
}

describe("tenant isolation", () => {
  it("publishes record changes only to devices in the same tenant", async () => {
    const alphaOwner = await seedIdentity("Sync Alpha");
    const alphaMember = await seedMemberInTenant(alphaOwner, "Sync Member");
    const bravoOwner = await seedIdentity("Sync Bravo");
    const operation = {
      id: crypto.randomUUID(),
      idempotencyKey: `record-${crypto.randomUUID()}`,
      type: "recordMutation",
      entityType: "customer",
      entityID: crypto.randomUUID(),
      actionName: "upsertRecord",
      payload: { schemaVersion: 1, contentType: "test", body: "e30=" },
      createdAt: new Date().toISOString(),
    };
    const accepted = await worker.fetch(
      request(alphaMember, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(operation),
      }),
      env,
    );
    expect(accepted.status).toBe(201);

    const alphaFeed = await worker.fetch(
      request(alphaOwner, "/v1/sync/changes?after=0"), env,
    );
    const alphaBody = await alphaFeed.json<{
      cursor: number;
      changes: Array<{ sourceDeviceID: string; operation: typeof operation }>;
    }>();
    expect(alphaBody.cursor).toBeGreaterThan(0);
    expect(alphaBody.changes.some((change) =>
      change.operation.idempotencyKey === operation.idempotencyKey &&
      change.sourceDeviceID === alphaMember.deviceID
    )).toBe(true);

    const bravoFeed = await worker.fetch(
      request(bravoOwner, "/v1/sync/changes?after=0"), env,
    );
    const bravoBody = await bravoFeed.json<{ changes: unknown[] }>();
    expect(bravoBody.changes).toHaveLength(0);
  });

  it("prevents Members from changing protected catalog records", async () => {
    const owner = await seedIdentity("Protected Records");
    const member = await seedMemberInTenant(owner, "Protected Member");
    const response = await worker.fetch(
      request(member, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: `catalog-${crypto.randomUUID()}`,
          type: "recordMutation",
          entityType: "catalog",
          entityID: crypto.randomUUID(),
          actionName: "upsertRecord",
        }),
      }),
      env,
    );
    expect(response.status).toBe(403);
  });

  it("prevents Members from promoting their own employee record", async () => {
    const owner = await seedIdentity("Employee Role Authority");
    const member = await seedMemberInTenant(owner, "Field Employee");
    const employeeID = crypto.randomUUID();
    await seedEmployeeRecord(owner, employeeID, ["Technician"]);
    await env.DB.prepare(
      "UPDATE tenant_members SET employee_id = ?1 WHERE id = ?2",
    ).bind(employeeID, member.memberID).run();

    const recordData = Buffer.from(JSON.stringify({
      id: employeeID,
      firstName: "Field",
      lastName: "Employee",
      role: "Manager",
      roles: ["Manager", "Technician"],
    })).toString("base64");
    const mutation = Buffer.from(JSON.stringify({
      entityType: "employee",
      entityID: employeeID,
      recordData,
      modifiedAt: new Date().toISOString(),
    })).toString("base64");
    const response = await worker.fetch(
      request(member, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: `self-promotion-${crypto.randomUUID()}`,
          type: "recordMutation",
          entityType: "employee",
          entityID: employeeID,
          actionName: "upsertRecord",
          payload: { schemaVersion: 1, contentType: "test", body: mutation },
          createdAt: new Date().toISOString(),
        }),
      }),
      env,
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "employee_role_change_requires_manager",
    });
  });

  it("requires a Manager or Owner for reviewed local conflict overrides", async () => {
    const owner = await seedIdentity("Conflict Authority");
    const member = await seedMemberInTenant(owner, "Conflict Member");
    const manager = await seedMemberInTenant(
      owner,
      "Conflict Manager",
      "manager",
    );
    const send = (identity: SeededIdentity) => worker.fetch(
      request(identity, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: `reviewed-${crypto.randomUUID()}`,
          type: "recordMutation",
          entityType: "customer",
          entityID: crypto.randomUUID(),
          actionName: "upsertRecord",
          metadata: { conflictResolution: "keptLocal" },
        }),
      }),
      env,
    );

    const memberResponse = await send(member);
    expect(memberResponse.status).toBe(403);
    expect((await memberResponse.json<{ error: string }>()).error)
      .toBe("conflict_override_requires_manager");
    expect((await send(manager)).status).toBe(201);
  });

  it("rejects stale record revisions without replacing the canonical value", async () => {
    const owner = await seedIdentity("Revision Owner");
    const member = await seedMemberInTenant(owner, "Revision Member");
    const manager = await seedMemberInTenant(owner, "Revision Manager", "manager");
    const secondDevice = await seedAdditionalDevice(owner, "Revision Second");
    const entityID = crypto.randomUUID();
    const send = (
      identity: SeededIdentity,
      label: string,
      baseRevision: string | null,
    ) => worker.fetch(request(identity, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        id: crypto.randomUUID(),
        idempotencyKey: `revision-${crypto.randomUUID()}`,
        type: "recordMutation",
        entityType: "customer",
        entityID,
        actionName: "upsertRecord",
        baseRevision,
        payload: { schemaVersion: 1, contentType: "test", body: label },
        createdAt: new Date().toISOString(),
      }),
    }), env);

    const first = await send(owner, "first", null);
    expect(first.status).toBe(201);
    const firstRevision = (await first.json<{ revision: string }>()).revision;
    const second = await send(owner, "second", firstRevision);
    expect(second.status).toBe(201);
    const secondRevision = (await second.json<{ revision: string }>()).revision;

    const stale = await send(secondDevice, "stale", firstRevision);
    expect(stale.status).toBe(409);
    const conflict = await stale.json<{
      error: string;
      conflictID: string;
      currentRevision: string;
      currentOperation: { payload: { body: string } };
    }>();
    expect(conflict.error).toBe("record_conflict");
    expect(conflict.currentRevision).toBe(secondRevision);
    expect(conflict.currentOperation.payload.body).toBe("second");

    const recoveredReport = await worker.fetch(
      request(secondDevice, "/v1/sync/conflicts/report", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operation: {
            id: crypto.randomUUID(),
            idempotencyKey: `recovered-${crypto.randomUUID()}`,
            type: "recordMutation",
            entityType: "customer",
            entityID,
            actionName: "upsertRecord",
            payload: { schemaVersion: 1, contentType: "test", body: "stale" },
            createdAt: new Date().toISOString(),
          },
        }),
      }),
      env,
    );
    expect(recoveredReport.status).toBe(201);
    expect((await recoveredReport.json<{ conflictID: string }>()).conflictID)
      .toBe(conflict.conflictID);

    const memberInbox = await worker.fetch(
      request(member, "/v1/sync/conflicts"), env,
    );
    expect(memberInbox.status).toBe(403);

    const managerInbox = await worker.fetch(
      request(manager, "/v1/sync/conflicts"), env,
    );
    const managerConflicts = await managerInbox.json<{
      conflicts: Array<{ id: string; sourceDeviceID: string }>;
    }>();
    expect(managerInbox.status).toBe(200);
    expect(managerConflicts.conflicts).toContainEqual(expect.objectContaining({
      id: conflict.conflictID,
      sourceDeviceID: secondDevice.deviceID,
    }));

    const resolved = await worker.fetch(
      request(manager, `/v1/sync/conflicts/${conflict.conflictID}/resolve`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          resolution: "keptDevice",
          reason: "Verified the employee's corrected phone number.",
          affectedFields: ["phone"],
        }),
      }),
      env,
    );
    expect(resolved.status).toBe(200);
    const acceptedResolution = await env.DB.prepare(
      `SELECT operation_json AS operationJSON
         FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?2`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{
      operationJSON: string;
    }>();
    const resolvedOperation = JSON.parse(
      acceptedResolution?.operationJSON ?? "{}",
    ) as { payload?: { body?: string }; metadata?: { serverConflictID?: string } };
    expect(resolvedOperation.payload?.body).toBe("stale");
    expect(resolvedOperation.metadata?.serverConflictID)
      .toBe(conflict.conflictID);
    const sourceReceipts = await worker.fetch(
      request(secondDevice, "/v1/sync/conflict-resolutions"), env,
    );
    const sourceReceiptBody = await sourceReceipts.json<{
      resolutions: Array<{ id: string; resolution: string }>;
    }>();
    expect(sourceReceiptBody.resolutions).toContainEqual(expect.objectContaining({
      id: conflict.conflictID,
      resolution: "keptDevice",
    }));
    const managerAudit = await worker.fetch(
      request(manager, "/v1/sync/conflict-audit"), env,
    );
    expect(managerAudit.status).toBe(403);
    const ownerAudit = await worker.fetch(
      request(owner, "/v1/sync/conflict-audit"), env,
    );
    const auditBody = await ownerAudit.json<{
      events: Array<{
        id: string;
        resolverName: string;
        resolverRole: string;
        reason: string;
        affectedFields: string[];
        finalRevision: string;
      }>;
    }>();
    expect(auditBody.events).toContainEqual(expect.objectContaining({
      id: conflict.conflictID,
      resolverRole: "manager",
      reason: "Verified the employee's corrected phone number.",
      affectedFields: ["phone"],
    }));
    expect(auditBody.events[0].finalRevision).not.toBe(secondRevision);
    const clearedInbox = await worker.fetch(
      request(owner, "/v1/sync/conflicts"), env,
    );
    expect((await clearedInbox.json<{ conflicts: unknown[] }>()).conflicts)
      .toHaveLength(0);
  });

  it("keeps backup listing and download inside the authenticated tenant", async () => {
    const alpha = await seedIdentity("Alpha");
    const bravo = await seedIdentity("Bravo");
    const upload = async (identity: SeededIdentity, value: string) =>
      worker.fetch(request(identity, "/v1/backups", {
        method: "POST",
        headers: { "content-type": "application/vnd.pfss.archive+json" },
        body: value,
      }), env);

    expect((await upload(alpha, "alpha-archive")).status).toBe(201);
    expect((await upload(bravo, "bravo-archive")).status).toBe(201);

    const alphaList = await worker.fetch(request(alpha, "/v1/backups"), env);
    const bravoList = await worker.fetch(request(bravo, "/v1/backups"), env);
    expect((await alphaList.json<{ backups: unknown[] }>()).backups).toHaveLength(1);
    expect((await bravoList.json<{ backups: unknown[] }>()).backups).toHaveLength(1);

    const alphaLatest = await worker.fetch(
      request(alpha, "/v1/backups/latest"), env,
    );
    const bravoLatest = await worker.fetch(
      request(bravo, "/v1/backups/latest"), env,
    );
    expect(await alphaLatest.text()).toBe("alpha-archive");
    expect(await bravoLatest.text()).toBe("bravo-archive");
  });

  it("scopes identical operation keys independently per tenant", async () => {
    const alpha = await seedIdentity("Operation Alpha");
    const bravo = await seedIdentity("Operation Bravo");
    const operation = {
      id: crypto.randomUUID(),
      idempotencyKey: "shared-looking-key",
      type: "workflow",
      entityType: "job",
      actionName: "update",
    };
    const send = (identity: SeededIdentity, id: string) => worker.fetch(
      request(identity, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...operation, id }),
      }),
      env,
    );

    expect((await send(alpha, operation.id)).status).toBe(201);
    expect((await send(bravo, crypto.randomUUID())).status).toBe(201);
    const duplicate = await send(alpha, crypto.randomUUID());
    expect((await duplicate.json<{ duplicate: boolean }>()).duplicate).toBe(true);

    const counts = await env.DB.prepare(
      `SELECT tenant_id AS tenantID, COUNT(*) AS count
         FROM synchronized_operations
        WHERE idempotency_key = ?1 GROUP BY tenant_id`,
    ).bind(operation.idempotencyKey).all<{ tenantID: string; count: number }>();
    expect(counts.results).toEqual(expect.arrayContaining([
      { tenantID: alpha.tenantID, count: 1 },
      { tenantID: bravo.tenantID, count: 1 },
    ]));
  });

  it("never lets an owner manage a device from another tenant", async () => {
    const alpha = await seedIdentity("Owner Alpha");
    const bravo = await seedIdentity("Owner Bravo");
    const response = await worker.fetch(
      request(alpha, `/v1/devices/${bravo.deviceID}/revoke`, { method: "POST" }),
      env,
    );
    expect(response.status).toBe(404);
    const bravoSession = await worker.fetch(request(bravo, "/v1/session"), env);
    expect(bravoSession.status).toBe(200);
  });
});

describe("membership authorization", () => {
  it("records only allowlisted Owner recovery events without secret metadata", async () => {
    const owner = await seedIdentity("Recovery Owner", "owner");
    const member = await seedIdentity("Recovery Member", "member");
    const event = {
      eventType: "recovery.external_backup",
      provider: "googleDrive",
      refreshToken: "must-not-be-recorded",
      filename: "must-not-be-recorded.pfssarchive",
    };

    const denied = await worker.fetch(request(member, "/v1/recovery/audit", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event),
    }), env);
    expect(denied.status).toBe(403);

    const recorded = await worker.fetch(request(owner, "/v1/recovery/audit", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event),
    }), env);
    expect(recorded.status).toBe(201);

    const audit = await env.DB.prepare(
      `SELECT event_type AS eventType, metadata_json AS metadataJSON
         FROM access_audit_events
        WHERE tenant_id = ?1 AND event_type = 'recovery.external_backup'`,
    ).bind(owner.tenantID).first<{
      eventType: string;
      metadataJSON: string;
    }>();
    expect(audit?.eventType).toBe("recovery.external_backup");
    expect(JSON.parse(audit?.metadataJSON ?? "{}")).toEqual({
      provider: "googleDrive",
    });
  });

  it("allows owners to invite while preventing members from administering", async () => {
    const owner = await seedIdentity("Admin Owner", "owner");
    const member = await seedIdentity("Basic Member", "member");
    await seedEmployeeRecord(owner, "employee-manager-1", ["Manager"]);
    const ownerInvite = await worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "New Manager",
          role: "manager",
          employeeID: "employee-manager-1",
        }),
      }),
      env,
    );
    expect(ownerInvite.status).toBe(201);
    expect((await ownerInvite.json<{ enrollmentCode: string }>()).enrollmentCode)
      .toMatch(/^PFSS-/);
    const ownerMembers = await worker.fetch(request(owner, "/v1/members"), env);
    const linkedMember = (await ownerMembers.json<{
      members: Array<{ employeeID: string | null }>;
    }>()).members.find((member) => member.employeeID === "employee-manager-1");
    expect(linkedMember).toBeDefined();

    const technicianID = `employee-${crypto.randomUUID()}`;
    await seedEmployeeRecord(owner, technicianID, ["Technician"]);
    const elevatedTechnician = await worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "Overprivileged Technician",
          role: "manager",
          employeeID: technicianID,
        }),
      }),
      env,
    );
    expect(elevatedTechnician.status).toBe(409);
    expect((await elevatedTechnician.json<{ error: string }>()).error)
      .toBe("invitation_role_mismatch");

    const memberList = await worker.fetch(request(member, "/v1/members"), env);
    expect(memberList.status).toBe(403);
    const memberInvite = await worker.fetch(
      request(member, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ displayName: "Unauthorized", role: "member" }),
      }),
      env,
    );
    expect(memberInvite.status).toBe(403);
  });

  it("protects the current session and rejects another device after revocation", async () => {
    const owner = await seedIdentity("Revocation Owner", "owner");
    const secondDevice = await seedAdditionalDevice(owner, "Second Owner");
    const selfRevocation = await worker.fetch(
      request(owner, `/v1/devices/${owner.deviceID}/revoke`, { method: "POST" }),
      env,
    );
    expect(selfRevocation.status).toBe(409);
    const response = await worker.fetch(
      request(owner, `/v1/devices/${secondDevice.deviceID}/revoke`, { method: "POST" }),
      env,
    );
    expect(response.status).toBe(200);
    const denied = await worker.fetch(
      request(secondDevice, "/v1/session"), env,
    );
    expect(denied.status).toBe(403);
    const removal = await denied.json<{
      error: string;
      directive: { type: string; deviceID: string };
    }>();
    expect(removal.error).toBe("company_data_removal_required");
    expect(removal.directive).toMatchObject({
      type: "remove_company_data",
      deviceID: secondDevice.deviceID,
    });
    const acknowledged = await worker.fetch(
      request(secondDevice, "/v1/device-removal/acknowledge", {
        method: "POST",
      }),
      env,
    );
    expect(acknowledged.status).toBe(200);
    expect((await worker.fetch(request(secondDevice, "/v1/session"), env)).status)
      .toBe(401);
    expect((await worker.fetch(request(owner, "/v1/session"), env)).status)
      .toBe(200);
  });

  it("cancels an invitation without retaining a usable clear-text secret", async () => {
    const owner = await seedIdentity("Invitation Owner", "owner");
    const created = await worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ displayName: "Cancelled Member", role: "member" }),
      }),
      env,
    );
    const invitation = await created.json<{
      memberID: string;
      enrollmentCode: string;
    }>();
    const cancelled = await worker.fetch(
      request(owner, `/v1/invitations/${invitation.memberID}/cancel`, {
        method: "POST",
      }),
      env,
    );
    expect(cancelled.status).toBe(200);
    const enrollment = await worker.fetch(
      new Request("https://pfss.test/v1/beta/enroll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          enrollmentCode: invitation.enrollmentCode,
          deviceID: crypto.randomUUID(),
          deviceName: "Rejected Device",
        }),
      }),
      env,
    );
    expect(enrollment.status).toBe(403);
  });

  it("does not consume an invitation when device creation fails", async () => {
    const owner = await seedIdentity("Enrollment Recovery Owner", "owner");
    const created = await worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "Enrollment Recovery Member",
          role: "member",
        }),
      }),
      env,
    );
    const invitation = await created.json<{
      memberID: string;
      enrollmentCode: string;
    }>();
    const enrollmentRequest = (deviceID: string) => new Request(
      "https://pfss.test/v1/beta/enroll",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          enrollmentCode: invitation.enrollmentCode,
          deviceID,
          deviceName: "Replacement Device",
        }),
      },
    );

    const collision = await worker.fetch(
      enrollmentRequest(owner.deviceID),
      env,
    );
    expect(collision.status).toBe(409);
    expect((await collision.json<{ error: string }>()).error)
      .toBe("device_identifier_in_use");
    const codeAfterFailure = await env.DB.prepare(
      `SELECT redeemed_at AS redeemedAt FROM enrollment_codes
        WHERE member_id = ?1`,
    ).bind(invitation.memberID).first<{ redeemedAt: string | null }>();
    expect(codeAfterFailure?.redeemedAt).toBeNull();

    const retry = await worker.fetch(
      enrollmentRequest(crypto.randomUUID()),
      env,
    );
    expect(retry.status).toBe(201);
  });

  it("expires employee invitations before listing or re-inviting", async () => {
    const owner = await seedIdentity("Invitation Expiry Owner", "owner");
    const employeeID = `employee-${crypto.randomUUID()}`;
    const create = () => worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "Expired Invite Employee",
          role: "member",
          employeeID,
        }),
      }),
      env,
    );
    const first = await create();
    expect(first.status).toBe(201);
    const firstInvitation = await first.json<{ memberID: string }>();
    await env.DB.prepare(
      `UPDATE enrollment_codes SET expires_at = ?1 WHERE member_id = ?2`,
    ).bind("2000-01-01T00:00:00.000Z", firstInvitation.memberID).run();

    const listed = await worker.fetch(request(owner, "/v1/members"), env);
    expect(listed.status).toBe(200);
    const firstMember = (await listed.json<{
      members: Array<{ id: string; status: string }>;
    }>()).members.find((member) => member.id === firstInvitation.memberID);
    expect(firstMember?.status).toBe("revoked");

    const replacement = await create();
    expect(replacement.status).toBe(201);
    const replacementInvitation = await replacement.json<{ memberID: string }>();
    expect(replacementInvitation.memberID).not.toBe(firstInvitation.memberID);
    const audit = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM access_audit_events
        WHERE tenant_id = ?1 AND event_type = 'invitation.expired'
          AND target_member_id = ?2`,
    ).bind(owner.tenantID, firstInvitation.memberID).first<{ count: number }>();
    expect(audit?.count).toBe(1);
  });

  it("suspends, restores, and revokes a member without affecting the owner", async () => {
    const owner = await seedIdentity("Lifecycle Owner", "owner");
    const member = await seedMemberInTenant(owner, "Lifecycle Member");
    const act = (action: string) => worker.fetch(
      request(owner, `/v1/members/${member.memberID}/${action}`, {
        method: "POST",
      }),
      env,
    );

    expect((await act("suspend")).status).toBe(200);
    expect((await worker.fetch(request(member, "/v1/session"), env)).status)
      .toBe(403);
    expect((await act("reactivate")).status).toBe(200);
    expect((await worker.fetch(request(member, "/v1/session"), env)).status)
      .toBe(200);
    expect((await act("revoke")).status).toBe(200);
    const removal = await worker.fetch(request(member, "/v1/session"), env);
    expect(removal.status).toBe(403);
    expect((await removal.json<{ error: string }>()).error)
      .toBe("company_data_removal_required");
    expect((await worker.fetch(request(owner, "/v1/session"), env)).status)
      .toBe(200);
  });

  it("secures archive, reactivation, revocation, and replacement device as one lifecycle", async () => {
    const owner = await seedIdentity("Employee Lifecycle Owner", "owner");
    const employeeID = `employee-${crypto.randomUUID()}`;
    const member = await seedMemberInTenant(owner, "Lifecycle Employee");
    await env.DB.prepare(
      "UPDATE tenant_members SET employee_id = ?1 WHERE id = ?2",
    ).bind(employeeID, member.memberID).run();

    const secureForArchive = () => worker.fetch(
      request(owner, `/v1/employees/${employeeID}/secure-for-archive`, {
        method: "POST",
      }),
      env,
    );
    const secured = await secureForArchive();
    expect(secured.status).toBe(200);
    expect(await secured.json()).toEqual({
      action: "suspendedMembership",
      membershipStatus: "suspended",
    });
    expect((await worker.fetch(request(member, "/v1/session"), env)).status)
      .toBe(403);

    const securedAgain = await secureForArchive();
    expect(await securedAgain.json()).toEqual({
      action: "none",
      membershipStatus: "suspended",
    });
    expect((await worker.fetch(
      request(owner, `/v1/members/${member.memberID}/reactivate`, {
        method: "POST",
      }),
      env,
    )).status).toBe(200);
    expect((await worker.fetch(request(member, "/v1/session"), env)).status)
      .toBe(200);

    expect((await worker.fetch(
      request(owner, `/v1/members/${member.memberID}/revoke`, {
        method: "POST",
      }),
      env,
    )).status).toBe(200);
    const removal = await worker.fetch(request(member, "/v1/session"), env);
    expect((await removal.json<{ error: string }>()).error)
      .toBe("company_data_removal_required");

    const replacementInvite = await worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "Lifecycle Employee",
          role: "member",
          employeeID,
        }),
      }),
      env,
    );
    expect(replacementInvite.status).toBe(201);
    const replacement = await replacementInvite.json<{
      memberID: string;
      enrollmentCode: string;
    }>();
    const replacementEnrollment = await worker.fetch(
      new Request("https://pfss.test/v1/beta/enroll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          enrollmentCode: replacement.enrollmentCode,
          deviceID: crypto.randomUUID(),
          deviceName: "Replacement Device",
        }),
      }),
      env,
    );
    expect(replacementEnrollment.status).toBe(201);
    expect(replacement.memberID).not.toBe(member.memberID);

    const audit = await env.DB.prepare(
      `SELECT metadata_json AS metadataJSON FROM access_audit_events
        WHERE tenant_id = ?1 AND event_type = 'member.suspended'
          AND target_member_id = ?2 ORDER BY created_at DESC LIMIT 1`,
    ).bind(owner.tenantID, member.memberID).first<{ metadataJSON: string }>();
    expect(JSON.parse(audit?.metadataJSON ?? "{}").reason)
      .toBe("employeeArchived");
  });

  it("re-invites a revoked employee with a new membership and credential", async () => {
    const owner = await seedIdentity("Reinvite Owner", "owner");
    const employeeID = `employee-${crypto.randomUUID()}`;
    const invite = async () => worker.fetch(
      request(owner, "/v1/invitations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "Returning Employee",
          role: "member",
          employeeID,
        }),
      }),
      env,
    );

    const firstInvite = await invite();
    expect(firstInvite.status).toBe(201);
    const first = await firstInvite.json<{
      memberID: string;
      enrollmentCode: string;
    }>();
    const firstEnrollment = await worker.fetch(
      new Request("https://pfss.test/v1/beta/enroll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          enrollmentCode: first.enrollmentCode,
          deviceID: crypto.randomUUID(),
          deviceName: "Original Device",
        }),
      }),
      env,
    );
    expect(firstEnrollment.status).toBe(201);
    expect((await worker.fetch(
      request(owner, `/v1/members/${first.memberID}/revoke`, {
        method: "POST",
      }),
      env,
    )).status).toBe(200);

    const secondInvite = await invite();
    expect(secondInvite.status).toBe(201);
    const second = await secondInvite.json<{
      memberID: string;
      enrollmentCode: string;
    }>();
    expect(second.memberID).not.toBe(first.memberID);
    const secondEnrollment = await worker.fetch(
      new Request("https://pfss.test/v1/beta/enroll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          enrollmentCode: second.enrollmentCode,
          deviceID: crypto.randomUUID(),
          deviceName: "Replacement Device",
        }),
      }),
      env,
    );
    expect(secondEnrollment.status).toBe(201);

    const memberships = await env.DB.prepare(
      `SELECT status FROM tenant_members
        WHERE tenant_id = ?1 AND employee_id = ?2
        ORDER BY created_at ASC`,
    ).bind(owner.tenantID, employeeID).all<{ status: string }>();
    expect(memberships.results.map((member) => member.status))
      .toEqual(["revoked", "active"]);
  });

  it("allows only Owners to create, list, or download recovery archives", async () => {
    const owner = await seedIdentity("Backup Policy Owner", "owner");
    const manager = await seedMemberInTenant(
      owner,
      "Backup Policy Manager",
      "manager",
    );
    const member = await seedMemberInTenant(owner, "Backup Policy Member");
    const upload = (identity: SeededIdentity) => worker.fetch(
      request(identity, "/v1/backups", {
        method: "POST",
        headers: { "content-type": "application/vnd.pfss.archive+json" },
        body: "company-archive",
      }),
      env,
    );

    expect((await upload(owner)).status).toBe(201);
    for (const identity of [manager, member]) {
      expect((await upload(identity)).status).toBe(403);
      expect((await worker.fetch(request(identity, "/v1/backups"), env)).status)
        .toBe(403);
      expect(
        (await worker.fetch(request(identity, "/v1/backups/latest"), env)).status,
      ).toBe(403);
    }
  });

  it("blocks suspended and revoked Owner credentials from every recovery endpoint", async () => {
    const suspended = await seedIdentity("Suspended Recovery Owner", "owner");
    const revoked = await seedIdentity("Revoked Recovery Owner", "owner");
    const upload = (identity: SeededIdentity) => worker.fetch(
      request(identity, "/v1/backups", {
        method: "POST",
        headers: { "content-type": "application/vnd.pfss.archive+json" },
        body: "company-archive",
      }),
      env,
    );
    expect((await upload(suspended)).status).toBe(201);
    expect((await upload(revoked)).status).toBe(201);

    await env.DB.prepare(
      "UPDATE tenant_members SET status = 'suspended' WHERE id = ?1",
    ).bind(suspended.memberID).run();
    for (const path of ["/v1/backups", "/v1/backups/latest"]) {
      const response = await worker.fetch(request(suspended, path), env);
      expect(response.status).toBe(403);
      expect((await response.json<{ error: string }>()).error)
        .toBe("access_suspended");
    }
    const suspendedAudit = await worker.fetch(
      request(suspended, "/v1/recovery/audit", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ eventType: "recovery.archive_restored" }),
      }),
      env,
    );
    expect(suspendedAudit.status).toBe(403);
    expect((await suspendedAudit.json<{ error: string }>()).error)
      .toBe("access_suspended");

    const revokedAt = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE devices SET revoked_at = ?1, data_removal_required_at = ?1
        WHERE id = ?2`,
    ).bind(revokedAt, revoked.deviceID).run();
    const removal = await worker.fetch(
      request(revoked, "/v1/backups/latest"),
      env,
    );
    expect(removal.status).toBe(403);
    expect((await removal.json<{ error: string }>()).error)
      .toBe("company_data_removal_required");

    const acknowledged = await worker.fetch(
      request(revoked, "/v1/device-removal/acknowledge", { method: "POST" }),
      env,
    );
    expect(acknowledged.status).toBe(200);
    expect((await worker.fetch(
      request(revoked, "/v1/backups/latest"),
      env,
    )).status).toBe(401);
  });

  it("bootstraps tenant members without exposing recovery administration", async () => {
    const alphaOwner = await seedIdentity("Bootstrap Alpha", "owner");
    const alphaMember = await seedMemberInTenant(alphaOwner, "Bootstrap Member");
    const bravoOwner = await seedIdentity("Bootstrap Bravo", "owner");
    const publish = (identity: SeededIdentity, body: string) => worker.fetch(
      request(identity, "/v1/sync/snapshot", {
        method: "POST",
        headers: { "content-type": "application/vnd.pfss.archive+json" },
        body,
      }),
      env,
    );

    expect((await publish(alphaOwner, "alpha-current-state")).status).toBe(201);
    expect((await publish(alphaMember, "member-overwrite")).status).toBe(403);
    expect((await publish(bravoOwner, "bravo-current-state")).status).toBe(201);

    const alphaBootstrap = await worker.fetch(
      request(alphaMember, "/v1/sync/bootstrap"),
      env,
    );
    expect(alphaBootstrap.status).toBe(200);
    expect(await alphaBootstrap.text()).toBe("alpha-current-state");
    expect(alphaBootstrap.headers.get("cache-control")).toBe("no-store");

    const bravoBootstrap = await worker.fetch(
      request(bravoOwner, "/v1/sync/bootstrap"),
      env,
    );
    expect(await bravoBootstrap.text()).toBe("bravo-current-state");
    expect((await worker.fetch(
      request(alphaMember, "/v1/backups"),
      env,
    )).status).toBe(403);
  });

  it("protects Owner memberships and purges only aged credential material", async () => {
    const owner = await seedIdentity("Cleanup Owner", "owner");
    const secondOwner = await seedMemberInTenant(owner, "Protected Owner", "owner");
    const protectedResponse = await worker.fetch(
      request(owner, `/v1/members/${secondOwner.memberID}/revoke`, {
        method: "POST",
      }),
      env,
    );
    expect(protectedResponse.status).toBe(403);

    const oldDate = new Date(Date.now() - 100 * 24 * 60 * 60 * 1000).toISOString();
    await env.DB.prepare(
      `UPDATE devices
          SET revoked_at = ?1,
              data_removal_required_at = ?1,
              data_removal_acknowledged_at = ?1
        WHERE tenant_id = ?2 AND id = ?3`,
    ).bind(oldDate, secondOwner.tenantID, secondOwner.deviceID).run();
    await env.DB.prepare(
      `INSERT INTO enrollment_codes
        (code_hash, tenant_id, member_id, expires_at, redeemed_at, created_at)
       VALUES (?1, ?2, ?3, ?4, ?4, ?4)`,
    ).bind(
      `old-code-${crypto.randomUUID()}`,
      owner.tenantID,
      secondOwner.memberID,
      oldDate,
    ).run();

    const cleanup = await worker.fetch(
      request(owner, "/v1/access/cleanup", { method: "POST" }),
      env,
    );
    expect(cleanup.status).toBe(200);
    const device = await env.DB.prepare(
      `SELECT token_hash AS tokenHash, credentials_purged_at AS purgedAt
         FROM devices WHERE tenant_id = ?1 AND id = ?2`,
    ).bind(owner.tenantID, secondOwner.deviceID).first<{
      tokenHash: string;
      purgedAt: string | null;
    }>();
    expect(device?.tokenHash).toContain("purged:");
    expect(device?.purgedAt).not.toBeNull();
    const oldCodes = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM enrollment_codes WHERE tenant_id = ?1 AND created_at = ?2",
    ).bind(owner.tenantID, oldDate).first<{ count: number }>();
    expect(oldCodes?.count).toBe(0);
  });
});
