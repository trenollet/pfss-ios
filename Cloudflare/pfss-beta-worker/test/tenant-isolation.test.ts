import { createHash } from "node:crypto";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker, {
  completeOwnerAuthorization,
  startOwnerAuthorization,
} from "../src/index";
import {
  IdentityConfigurationError,
  LocalManagedOwnerIdentityProvider,
  ManagedOwnerIdentityProvider,
  WorkOSManagedOwnerIdentityProvider,
  managedIdentityConfigurationFromBindings,
  validateManagedIdentityConfiguration,
} from "../src/account-identity-provider";

interface SeededIdentity {
  tenantID: string;
  memberID: string;
  deviceID: string;
  token: string;
}

interface SeededOperationsIdentity {
  administratorID: string;
  token: string;
}

async function seedOperationsIdentity(
  label: string,
  role: "platformOwner" | "supportAdministrator" |
    "billingAdministrator" | "readOnlyAuditor" = "platformOwner",
): Promise<SeededOperationsIdentity> {
  const administratorID = crypto.randomUUID();
  const token = `operations-${crypto.randomUUID()}${crypto.randomUUID()}`;
  const now = new Date();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO operations_administrators
        (id, normalized_email, provider_subject, display_name, role, status,
         created_at, activated_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, 'active', ?6, ?6, ?6)`,
    ).bind(administratorID, `${label.toLowerCase().replace(/\s+/g, "-")}@pfss.test`,
      `user_${crypto.randomUUID().replace(/-/g, "")}`, label, role,
      now.toISOString()),
    env.DB.prepare(
      `INSERT INTO operations_sessions
        (id, administrator_id, token_digest, device_id, device_name,
         created_at, last_seen_at, expires_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7)`,
    ).bind(crypto.randomUUID(), administratorID,
      createHash("sha256").update(token).digest("hex"), crypto.randomUUID(),
      `${label} iPhone`, now.toISOString(),
      new Date(now.getTime() + 60 * 60 * 1000).toISOString()),
  ]);
  return { administratorID, token };
}

function operationsRequest(
  identity: SeededOperationsIdentity,
  path: string,
  init: RequestInit = {},
): Request {
  return new Request(`https://pfss.test${path}`, {
    ...init,
    headers: {
      ...Object.fromEntries(new Headers(init.headers).entries()),
      authorization: `Bearer ${identity.token}`,
    },
  });
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

describe("synchronization push registration", () => {
  it("binds a token to the authenticated tenant and device", async () => {
    const owner = await seedIdentity("Push Owner");
    const token = "a1".repeat(32);
    const response = await worker.fetch(request(owner, "/v1/sync/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token, appBuild: "20.7.5" }),
    }), env);

    expect(response.status).toBe(200);
    const row = await env.DB.prepare(
      `SELECT tenant_id AS tenantID, device_id AS deviceID,
              environment, app_build AS appBuild
         FROM synchronization_push_registrations
        WHERE token = ?1`,
    ).bind(token).first<{
      tenantID: string;
      deviceID: string;
      environment: string;
      appBuild: string;
    }>();
    expect(row).toEqual({
      tenantID: owner.tenantID,
      deviceID: owner.deviceID,
      environment: "sandbox",
      appBuild: "20.7.5",
    });
  });

  it("rejects malformed tokens and only unregisters the calling device", async () => {
    const owner = await seedIdentity("Push Isolation");
    const peer = await seedAdditionalDevice(owner, "Push Peer");
    const ownerToken = "b2".repeat(32);
    const peerToken = "c3".repeat(32);
    for (const [identity, token] of [[owner, ownerToken], [peer, peerToken]] as const) {
      expect((await worker.fetch(request(identity, "/v1/sync/push", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token, appBuild: "20.7.5" }),
      }), env)).status).toBe(200);
    }
    expect((await worker.fetch(request(owner, "/v1/sync/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: "not-a-token", appBuild: "20.7.5" }),
    }), env)).status).toBe(400);
    expect((await worker.fetch(request(owner, "/v1/sync/push", {
      method: "DELETE",
    }), env)).status).toBe(200);

    const remaining = await env.DB.prepare(
      `SELECT device_id AS deviceID, token
         FROM synchronization_push_registrations
        WHERE tenant_id = ?1`,
    ).bind(owner.tenantID).all<{ deviceID: string; token: string }>();
    expect(remaining.results).toEqual([{
      deviceID: peer.deviceID,
      token: peerToken,
    }]);
  });

  it("records lifecycle telemetry only for the receiving device", async () => {
    const owner = await seedIdentity("Push Telemetry Owner");
    const peer = await seedAdditionalDevice(owner, "Push Telemetry Peer");
    const deliveryID = crypto.randomUUID();
    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO synchronization_push_deliveries
        (id, tenant_id, device_id, source_device_id, cursor, environment,
         apns_request_id, requested_at, accepted_at)
       VALUES (?1, ?2, ?3, ?4, 42, 'sandbox', ?5, ?6, ?6)`,
    ).bind(
      deliveryID,
      owner.tenantID,
      peer.deviceID,
      owner.deviceID,
      crypto.randomUUID(),
      now,
    ).run();

    expect((await worker.fetch(request(owner, "/v1/sync/push-events", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deliveryID, event: "received", cursor: 41 }),
    }), env)).status).toBe(404);

    for (const event of ["received", "syncStarted", "syncCompleted"]) {
      expect((await worker.fetch(request(peer, "/v1/sync/push-events", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ deliveryID, event, cursor: 42 }),
      }), env)).status).toBe(200);
    }
    const delivery = await env.DB.prepare(
      `SELECT received_at AS receivedAt, sync_started_at AS syncStartedAt,
              sync_completed_at AS syncCompletedAt,
              device_reported_cursor AS reportedCursor
         FROM synchronization_push_deliveries WHERE id = ?1`,
    ).bind(deliveryID).first<{
      receivedAt: string | null;
      syncStartedAt: string | null;
      syncCompletedAt: string | null;
      reportedCursor: number | null;
    }>();
    expect(delivery?.receivedAt).toBeTruthy();
    expect(delivery?.syncStartedAt).toBeTruthy();
    expect(delivery?.syncCompletedAt).toBeTruthy();
    expect(delivery?.reportedCursor).toBe(42);
  });
});

describe("synchronization health monitoring", () => {
  it("is tenant scoped, manager authorized, and payload free", async () => {
    const owner = await seedIdentity("Health Owner");
    const manager = await seedMemberInTenant(owner, "Health Manager", "manager");
    const employee = await seedMemberInTenant(owner, "Health Employee", "member");
    const foreignOwner = await seedIdentity("Foreign Health Owner");
    const now = new Date().toISOString();
    const operationID = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO synchronization_change_log
          (tenant_id, tenant_sequence, operation_id, device_id, revision,
           payload_json, accepted_at)
         VALUES (?1, 1, ?2, ?3, ?4, '{}', ?5)`,
      ).bind(owner.tenantID, crypto.randomUUID(), owner.deviceID,
        crypto.randomUUID(), now),
      env.DB.prepare(
        `INSERT INTO synchronization_quarantines
          (id, tenant_id, operation_id, entity_type, entity_id,
           source_member_id, source_device_id, operation_json, failure_json,
           status, policy_version, detected_at)
         VALUES (?1, ?2, ?3, 'job', ?4, ?5, ?6, ?7, ?8,
                 'unresolved', 1, ?9)`,
      ).bind(
        crypto.randomUUID(), owner.tenantID, operationID, crypto.randomUUID(),
        employee.memberID, employee.deviceID,
        JSON.stringify({
          id: operationID,
          entityType: "job",
          metadata: { privatePayloadMarker: "must-not-leak" },
        }),
        JSON.stringify({ reason: "schema_validation_failed" }),
        now,
      ),
      env.DB.prepare(
        `INSERT INTO synchronization_quarantines
          (id, tenant_id, operation_id, entity_type, entity_id,
           source_member_id, source_device_id, operation_json, failure_json,
           status, policy_version, detected_at)
         VALUES (?1, ?2, ?3, 'customer', ?4, ?5, ?6, '{}', '{}',
                 'unresolved', 1, ?7)`,
      ).bind(
        crypto.randomUUID(), foreignOwner.tenantID, crypto.randomUUID(),
        crypto.randomUUID(), foreignOwner.memberID, foreignOwner.deviceID, now,
      ),
    ]);

    expect((await worker.fetch(
      request(employee, "/v1/sync/health"), env,
    )).status).toBe(403);
    const response = await worker.fetch(
      request(manager, "/v1/sync/health"), env,
    );
    expect(response.status).toBe(200);
    const body = await response.json<{
      status: string;
      serverCursor: number;
      summary: { activeDevices: number; quarantinedChanges: number };
      devices: Array<{ deviceID: string; behindBy: number }>;
      trendsLast7Days: {
        byEntity: Array<{ entityType: string; count: number }>;
        quarantineReasons: Array<{ reason: string; count: number }>;
      };
    }>();
    expect(body.status).toBe("actionRequired");
    expect(body.serverCursor).toBe(1);
    expect(body.summary.activeDevices).toBe(3);
    expect(body.summary.quarantinedChanges).toBe(1);
    expect(body.devices.every((device) => device.behindBy === 1)).toBe(true);
    expect(body.trendsLast7Days.byEntity).toContainEqual({
      entityType: "job",
      count: 1,
    });
    expect(body.trendsLast7Days.quarantineReasons).toContainEqual({
      reason: "schema_validation_failed",
      count: 1,
    });
    expect(JSON.stringify(body)).not.toContain("must-not-leak");
    expect(JSON.stringify(body)).not.toContain(foreignOwner.tenantID);
  });

  it("opens and resolves device alerts without exposing queue contents", async () => {
    const owner = await seedIdentity("Alert Owner");
    const employee = await seedMemberInTenant(owner, "Alert Employee", "member");
    const report = (retryAttempts24h: number) => request(
      employee,
      "/v1/sync/device-health",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          appBuild: "20.7.12",
          queueCount: 2,
          oldestQueuedAt: new Date(Date.now() - 60_000).toISOString(),
          failedCount: 0,
          waitingRetryCount: 2,
          retryAttempts24h,
          blockedDependencyCount: 0,
          conflictedCount: 0,
          quarantinedCount: 0,
          privateQueueContents: "must-not-leak",
        }),
      },
    );

    expect((await worker.fetch(report(10), env)).status).toBe(200);
    let response = await worker.fetch(request(owner, "/v1/sync/health"), env);
    let body = await response.json<{
      alerts: Array<{ kind: string; deviceID: string; title: string }>;
      summary: { activeAlerts: number };
    }>();
    expect(body.summary.activeAlerts).toBe(1);
    expect(body.alerts).toHaveLength(1);
    expect(body.alerts[0].kind).toBe("excessiveRetries");
    expect(body.alerts[0].deviceID).toBe(employee.deviceID);
    expect(JSON.stringify(body)).not.toContain("must-not-leak");

    expect((await worker.fetch(report(0), env)).status).toBe(200);
    response = await worker.fetch(request(owner, "/v1/sync/health"), env);
    body = await response.json();
    expect(body.summary.activeAlerts).toBe(0);
    expect(body.alerts).toEqual([]);
    const resolved = await env.DB.prepare(
      `SELECT status, resolved_at AS resolvedAt
         FROM synchronization_health_alerts
        WHERE tenant_id = ?1 AND fingerprint = ?2`,
    ).bind(
      owner.tenantID,
      `excessiveRetries:${employee.deviceID}`,
    ).first<{ status: string; resolvedAt: string | null }>();
    expect(resolved?.status).toBe("resolved");
    expect(resolved?.resolvedAt).toBeTruthy();
  });
});

async function sendVersionedMutation(
  identity: SeededIdentity,
  options: {
    entityType: string;
    entityID: string;
    baseRevision: string | null;
    mutationKind: "wholeRecord" | "fieldPatch" | "appendFact" | "domainCommand";
    changedFields: string[];
    record: Record<string, unknown>;
    baseRecord?: Record<string, unknown>;
    commandName?: string;
    sequenceNumber: number;
  },
): Promise<Response> {
  const operationID = crypto.randomUUID();
  const timestamp = new Date(Date.now() + options.sequenceNumber * 1_000).toISOString();
  const mutation = Buffer.from(JSON.stringify({
    schemaVersion: 2,
    operationID,
    entityType: options.entityType,
    recordID: options.entityID,
    baseRevision: options.baseRevision,
    mutationKind: options.mutationKind,
    changedFields: options.changedFields,
    commandName: options.commandName,
    baseRecordData: options.baseRecord === undefined
      ? undefined
      : Buffer.from(JSON.stringify(options.baseRecord)).toString("base64"),
    recordData: Buffer.from(JSON.stringify(options.record)).toString("base64"),
    clientCreatedAt: timestamp,
    deviceModifiedAt: timestamp,
  })).toString("base64");
  return worker.fetch(request(identity, "/v1/operations", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      id: operationID,
      idempotencyKey: `phase20-${crypto.randomUUID()}`,
      sequenceNumber: options.sequenceNumber,
      type: "recordMutation",
      entityType: options.entityType,
      entityID: options.entityID,
      actionName: "upsertRecord",
      baseRevision: options.baseRevision,
      payload: { schemaVersion: 1, contentType: "application/json", body: mutation },
      createdAt: timestamp,
    }),
  }), env);
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

function validAccountRegistrationBody(): Record<string, unknown> {
  return {
    idempotencyKey: crypto.randomUUID(),
    identityAssertion: "verified-identity-assertion-reference",
    authenticationMethod: "passkey",
    owner: {
      displayName: "  Geoff Nordmyer  ",
      email: "  OWNER@EXAMPLE.COM  ",
    },
    company: {
      displayName: "  PFSS Development  ",
      timeZoneID: "America/Chicago",
    },
    requestedPlanCode: "  TEAM-ANNUAL  ",
    consent: {
      termsVersion: "terms-2026-07",
      privacyVersion: "privacy-2026-07",
      acceptedAt: new Date().toISOString(),
    },
    device: {
      id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      displayName: "  Owner iPad  ",
    },
  };
}

function uniqueAccountRegistrationBody(): Record<string, unknown> {
  const body = validAccountRegistrationBody();
  const suffix = crypto.randomUUID();
  body.identityAssertion = `verified-identity-assertion-${suffix}`;
  (body.owner as Record<string, unknown>).email = `${suffix}@example.com`;
  (body.company as Record<string, unknown>).displayName = `PFSS ${suffix}`;
  return body;
}

async function startAccountRegistration(
  body: Record<string, unknown> = uniqueAccountRegistrationBody(),
): Promise<Response> {
  const assertion = body.identityAssertion as string;
  const assertionDigest = createHash("sha256").update(assertion).digest("hex");
  const existing = await env.DB.prepare(
    "SELECT id FROM owner_authorization_attempts WHERE identity_assertion_digest = ?1",
  ).bind(assertionDigest).first<{ id: string }>();
  if (!existing) {
    const owner = body.owner as Record<string, unknown>;
    const email = String(owner.email).trim().toLowerCase();
    const existingContact = await env.DB.prepare(
      `SELECT subject_id AS subjectID FROM verified_contact_addresses
        WHERE kind = 'email' AND normalized_value = ?1`,
    ).bind(email).first<{ subjectID: string }>();
    const subjectID = existingContact?.subjectID ?? crypto.randomUUID();
    const now = new Date();
    const statements: D1PreparedStatement[] = [];
    if (!existingContact) {
      statements.push(env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, ?2, 'active', ?3, ?3)`,
      ).bind(subjectID, String(owner.displayName).trim(), now.toISOString()));
      statements.push(env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', ?3, ?4, ?4)`,
      ).bind(
        crypto.randomUUID(), subjectID, email, now.toISOString(),
      ));
    }
    statements.push(env.DB.prepare(
      `INSERT INTO owner_authorization_attempts
        (id, state_digest, code_challenge, redirect_uri, status, subject_id,
         subject_was_created, identity_assertion_digest, provider_method,
         expires_at, verified_at, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, 'verified', ?5, ?6, ?7, ?8, ?9, ?10, ?10, ?10)`,
    ).bind(
      crypto.randomUUID(), createHash("sha256").update(crypto.randomUUID())
        .digest("hex"), "c".repeat(43),
      "https://identity.staging.pfss.test/callback", subjectID,
      existingContact ? 0 : 1, assertionDigest, body.authenticationMethod,
      new Date(now.getTime() + 300_000).toISOString(), now.toISOString(),
    ));
    await env.DB.batch(statements);
  }
  return worker.fetch(new Request(
    "https://pfss.test/v1/account-registration/attempts",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  ), env);
}

describe("production account registration foundation", () => {
  it("normalizes the public contract without echoing identity evidence", async () => {
    const response = await worker.fetch(new Request(
      "https://pfss.test/v1/account-registration/validate",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(validAccountRegistrationBody()),
      },
    ), env);
    expect(response.status).toBe(200);
    const body = await response.json<{
      valid: boolean;
      status: string;
      registration: Record<string, unknown> & {
        owner: { displayName: string; email: string };
        company: { displayName: string };
        requestedPlanCode: string;
        device: { displayName: string };
      };
    }>();
    expect(body.valid).toBe(true);
    expect(body.status).toBe("started");
    expect(body.registration.owner).toEqual({
      displayName: "Geoff Nordmyer",
      email: "owner@example.com",
    });
    expect(body.registration.company.displayName).toBe("PFSS Development");
    expect(body.registration.requestedPlanCode).toBe("team-annual");
    expect(body.registration.device.displayName).toBe("Owner iPad");
    expect(body.registration).not.toHaveProperty("identityAssertion");
    expect(body.registration).not.toHaveProperty("tenantID");
    expect(body.registration).not.toHaveProperty("role");
    expect(body.registration).not.toHaveProperty("entitlements");
  });

  it("rejects client-selected authority and infrastructure at any depth", async () => {
    const privileged = validAccountRegistrationBody();
    privileged.tenantID = crypto.randomUUID();
    const tenantResponse = await worker.fetch(new Request(
      "https://pfss.test/v1/account-registration/validate",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(privileged),
      },
    ), env);
    expect(tenantResponse.status).toBe(400);
    expect(await tenantResponse.json()).toEqual({
      error: "forbidden_registration_field",
      field: "tenantID",
    });

    const nested = validAccountRegistrationBody();
    (nested.company as Record<string, unknown>).entitlements = {
      employeeLimit: 9999,
    };
    const entitlementResponse = await worker.fetch(new Request(
      "https://pfss.test/v1/account-registration/validate",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(nested),
      },
    ), env);
    expect(entitlementResponse.status).toBe(400);
    expect(await entitlementResponse.json()).toEqual({
      error: "forbidden_registration_field",
      field: "company.entitlements",
    });

    const clientGrant = validAccountRegistrationBody();
    clientGrant.accessSource = "internalBusinessGrant";
    const grantResponse = await worker.fetch(new Request(
      "https://pfss.test/v1/account-registration/validate",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(clientGrant),
      },
    ), env);
    expect(grantResponse.status).toBe(400);
    expect(await grantResponse.json()).toEqual({
      error: "forbidden_registration_field",
      field: "accessSource",
    });
  });

  it("rejects invalid identity, profile, plan, and consent inputs", async () => {
    const invalid = validAccountRegistrationBody();
    (invalid.owner as Record<string, unknown>).email = "not-an-email";
    (invalid.company as Record<string, unknown>).timeZoneID = "PFSS/Unknown";
    invalid.requestedPlanCode = "owner plan $1";
    (invalid.consent as Record<string, unknown>).acceptedAt =
      new Date(Date.now() - 86_400_001).toISOString();
    const response = await worker.fetch(new Request(
      "https://pfss.test/v1/account-registration/validate",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(invalid),
      },
    ), env);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "invalid_registration_request",
    });
  });

  it("applies the versioned production-account schema and constraints", async () => {
    const expectedTables = [
      "authentication_subjects",
      "authentication_identities",
      "verified_contact_addresses",
      "account_recovery_methods",
      "account_registration_attempts",
      "legal_consents",
      "subscription_accounts",
      "plan_allocations",
    ];
    const tables = await env.DB.prepare(
      `SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN (${expectedTables.map(() => "?").join(",")})`,
    ).bind(...expectedTables).all<{ name: string }>();
    expect(new Set(tables.results.map((row) => row.name)))
      .toEqual(new Set(expectedTables));

    const memberColumns = await env.DB.prepare(
      "PRAGMA table_info(tenant_members)",
    ).all<{ name: string }>();
    expect(memberColumns.results.map((column) => column.name))
      .toContain("authentication_subject_id");

    await expect(env.DB.prepare(
      `INSERT INTO authentication_subjects
        (id, display_name, status, created_at, updated_at)
       VALUES (?1, ?2, 'unknown', ?3, ?3)`,
    ).bind(crypto.randomUUID(), "Invalid", new Date().toISOString()).run())
      .rejects.toThrow();

    const identity = await seedIdentity("Allocation Constraint");
    await expect(env.DB.prepare(
      `INSERT INTO plan_allocations
        (id, tenant_id, access_source, plan_code, effective_at, created_at)
       VALUES (?1, ?2, 'internalBusinessGrant', 'internal-full', ?3, ?3)`,
    ).bind(crypto.randomUUID(), identity.tenantID, new Date().toISOString()).run())
      .rejects.toThrow();
  });

  it("starts once, stores only credential digests, and creates no company", async () => {
    const companyTables = [
      "tenants", "tenant_members", "devices", "subscription_accounts",
    ];
    const countsBefore = new Map<string, number>();
    for (const table of companyTables) {
      const count = await env.DB.prepare(
        `SELECT COUNT(*) AS count FROM ${table}`,
      ).first<{ count: number }>();
      countsBefore.set(table, count?.count ?? 0);
    }
    const registration = uniqueAccountRegistrationBody();
    const assertion = registration.identityAssertion as string;
    const response = await startAccountRegistration(registration);
    expect(response.status).toBe(201);
    const receipt = await response.json<{
      registrationAttempt: { id: string; status: string };
      registrationToken: string;
      tokenIssued: boolean;
    }>();
    expect(receipt.registrationAttempt.status).toBe("started");
    expect(receipt.registrationToken.length).toBeGreaterThan(40);
    expect(receipt.tokenIssued).toBe(true);

    const stored = await env.DB.prepare(
      `SELECT identity_assertion_digest AS assertionDigest,
              registration_token_digest AS tokenDigest
         FROM account_registration_attempts WHERE id = ?1`,
    ).bind(receipt.registrationAttempt.id).first<{
      assertionDigest: string;
      tokenDigest: string;
    }>();
    expect(stored?.assertionDigest).toBe(
      createHash("sha256").update(assertion).digest("hex"),
    );
    expect(stored?.assertionDigest).not.toContain(assertion);
    expect(stored?.tokenDigest).toBe(
      createHash("sha256").update(receipt.registrationToken).digest("hex"),
    );
    expect(stored?.tokenDigest).not.toBe(receipt.registrationToken);

    for (const table of companyTables) {
      const count = await env.DB.prepare(
        `SELECT COUNT(*) AS count FROM ${table}`,
      ).first<{ count: number }>();
      expect(count?.count).toBe(countsBefore.get(table));
    }
  });

  it("atomically provisions the first Owner, company, plan, device, consent, and audit", async () => {
    const registration = uniqueAccountRegistrationBody();
    const started = await startAccountRegistration(registration);
    expect(started.status).toBe(201);
    const startReceipt = await started.json<{
      registrationAttempt: { id: string };
      registrationToken: string;
    }>();
    const completionPath =
      `/v1/account-registration/attempts/${startReceipt.registrationAttempt.id}/complete`;
    const completed = await worker.fetch(new Request(
      `https://pfss.test${completionPath}`,
      {
        method: "POST",
        headers: {
          "x-pfss-registration-token": startReceipt.registrationToken,
        },
      },
    ), env);
    expect(completed.status).toBe(201);
    const receipt = await completed.json<{
      registrationAttempt: { status: string };
      tenant: { id: string; displayName: string };
      owner: { memberID: string; role: string };
      device: { id: string; deviceToken: string };
      plan: {
        code: string;
        accessSource: string;
        entitlements: { userLimit: number; jobLimit: number };
      };
      tokenIssued: boolean;
    }>();
    expect(receipt.registrationAttempt.status).toBe("active");
    expect(receipt.tenant.displayName).toContain("PFSS");
    expect(receipt.owner.role).toBe("owner");
    expect(receipt.plan.code).toBe("beta");
    expect(receipt.plan.accessSource).toBe("betaGrant");
    expect(receipt.plan.entitlements.userLimit).toBe(5);
    expect(receipt.plan.entitlements.jobLimit).toBe(3_000);
    expect(receipt.tokenIssued).toBe(true);

    const sessionResponse = await worker.fetch(new Request(
      "https://pfss.test/v1/session",
      { headers: { authorization: `Bearer ${receipt.device.deviceToken}` } },
    ), env);
    expect(sessionResponse.status).toBe(200);
    const session = await sessionResponse.json<{
      tenant: { displayName: string };
      member: { id: string; role: string };
    }>();
    expect(session.tenant.displayName).toBe(receipt.tenant.displayName);
    expect(session.member).toMatchObject({
      id: receipt.owner.memberID,
      role: "owner",
    });

    const persisted = await env.DB.prepare(
      `SELECT registration.status,
              registration.subject_id AS subjectID,
              registration.tenant_id AS tenantID,
              consent.subject_id AS consentSubjectID,
              allocation.access_source AS accessSource,
              audit.event_type AS auditEvent
         FROM account_registration_attempts AS registration
         JOIN legal_consents AS consent
           ON consent.registration_attempt_id = registration.id
         JOIN plan_allocations AS allocation
           ON allocation.tenant_id = registration.tenant_id
         JOIN access_audit_events AS audit
           ON audit.tenant_id = registration.tenant_id
          AND audit.event_type = 'account.registration_completed'
        WHERE registration.id = ?1`,
    ).bind(startReceipt.registrationAttempt.id).first<{
      status: string;
      subjectID: string;
      tenantID: string;
      consentSubjectID: string;
      accessSource: string;
      auditEvent: string;
    }>();
    expect(persisted).toMatchObject({
      status: "active",
      tenantID: receipt.tenant.id,
      accessSource: "betaGrant",
      auditEvent: "account.registration_completed",
    });
    expect(persisted?.consentSubjectID).toBe(persisted?.subjectID);

    const repeated = await worker.fetch(new Request(
      `https://pfss.test${completionPath}`,
      {
        method: "POST",
        headers: {
          "x-pfss-registration-token": startReceipt.registrationToken,
        },
      },
    ), env);
    expect(repeated.status).toBe(200);
    expect(await repeated.json()).toMatchObject({
      registrationAttempt: { status: "active" },
      deviceToken: null,
      tokenIssued: false,
    });
    const tenantCount = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM tenants WHERE id = ?1",
    ).bind(receipt.tenant.id).first<{ count: number }>();
    expect(tenantCount?.count).toBe(1);
  });

  it("rolls back every company resource when first-device provisioning fails", async () => {
    const registration = uniqueAccountRegistrationBody();
    (registration.device as Record<string, unknown>).displayName =
      "Failure Injection Device";
    const started = await startAccountRegistration(registration);
    const receipt = await started.json<{
      registrationAttempt: { id: string };
      registrationToken: string;
    }>();
    await env.DB.prepare(
      `CREATE TRIGGER fail_registration_device
       BEFORE INSERT ON devices
       WHEN NEW.display_name = 'Failure Injection Device'
       BEGIN
         SELECT RAISE(ABORT, 'injected registration device failure');
       END`,
    ).run();
    const tenantCountBefore = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM tenants",
    ).first<{ count: number }>();
    const failed = await worker.fetch(new Request(
      `https://pfss.test/v1/account-registration/attempts/${receipt.registrationAttempt.id}/complete`,
      {
        method: "POST",
        headers: { "x-pfss-registration-token": receipt.registrationToken },
      },
    ), env);
    await env.DB.prepare("DROP TRIGGER fail_registration_device").run();
    expect(failed.status).toBe(503);
    expect(await failed.json()).toEqual({
      error: "registration_provisioning_failed",
    });
    const stored = await env.DB.prepare(
      `SELECT status, tenant_id AS tenantID
         FROM account_registration_attempts WHERE id = ?1`,
    ).bind(receipt.registrationAttempt.id).first<{
      status: string;
      tenantID: string | null;
    }>();
    expect(stored).toMatchObject({ status: "started", tenantID: null });
    const tenantCountAfter = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM tenants",
    ).first<{ count: number }>();
    expect(tenantCountAfter?.count).toBe(tenantCountBefore?.count);
  });

  it("requires external plan authorization outside staging", async () => {
    const started = await startAccountRegistration();
    const receipt = await started.json<{
      registrationAttempt: { id: string };
      registrationToken: string;
    }>();
    const productionEnv = Object.assign(Object.create(env), {
      PFSS_ENVIRONMENT: "production",
    });
    const response = await worker.fetch(new Request(
      `https://pfss.test/v1/account-registration/attempts/${receipt.registrationAttempt.id}/complete`,
      {
        method: "POST",
        headers: { "x-pfss-registration-token": receipt.registrationToken },
      },
    ), productionEnv);
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "plan_authorization_required",
    });
  });

  it("retries the same request safely and rejects changed idempotent input", async () => {
    const registration = uniqueAccountRegistrationBody();
    const first = await startAccountRegistration(registration);
    const firstReceipt = await first.json<{
      registrationAttempt: { id: string };
      registrationToken: string;
    }>();
    const retry = await startAccountRegistration(registration);
    expect(retry.status).toBe(200);
    const retryReceipt = await retry.json<{
      registrationAttempt: { id: string };
      registrationToken: null;
      tokenIssued: boolean;
    }>();
    expect(retryReceipt.registrationAttempt.id)
      .toBe(firstReceipt.registrationAttempt.id);
    expect(retryReceipt.registrationToken).toBeNull();
    expect(retryReceipt.tokenIssued).toBe(false);

    const changed = structuredClone(registration);
    (changed.company as Record<string, unknown>).displayName = "Changed Company";
    const conflict = await startAccountRegistration(changed);
    expect(conflict.status).toBe(409);
    expect(await conflict.json()).toEqual({ error: "idempotency_key_reused" });
  });

  it("uses one safe outcome for duplicate identity and company requests", async () => {
    const now = new Date().toISOString();
    const subjectID = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Existing Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now),
      env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', 'owner@example.com', ?3, ?3)`,
      ).bind(crypto.randomUUID(), subjectID, now),
    ]);
    const identityDuplicate = await startAccountRegistration(
      validAccountRegistrationBody(),
    );
    expect(identityDuplicate.status).toBe(409);
    const identityError = await identityDuplicate.json();

    await env.DB.prepare(
      "DELETE FROM verified_contact_addresses WHERE subject_id = ?1",
    ).bind(subjectID).run();
    const first = uniqueAccountRegistrationBody();
    (first.owner as Record<string, unknown>).email = "different@example.com";
    await startAccountRegistration(first);
    const companyDuplicate = uniqueAccountRegistrationBody();
    (companyDuplicate.company as Record<string, unknown>).displayName =
      (first.company as Record<string, unknown>).displayName;
    const companyResponse = await startAccountRegistration(companyDuplicate);
    expect(companyResponse.status).toBe(409);
    expect(await companyResponse.json()).toEqual(identityError);
    expect(identityError).toEqual({
      error: "account_or_company_requires_sign_in",
    });
  });

  it("authenticates status, expires stale attempts, and cancels idempotently", async () => {
    const started = await startAccountRegistration();
    const receipt = await started.json<{
      registrationAttempt: { id: string };
      registrationToken: string;
    }>();
    const path = `/v1/account-registration/attempts/${receipt.registrationAttempt.id}`;
    const unauthenticated = await worker.fetch(
      new Request(`https://pfss.test${path}`), env,
    );
    expect(unauthenticated.status).toBe(401);
    const wrongToken = await worker.fetch(new Request(`https://pfss.test${path}`, {
      headers: { "x-pfss-registration-token": "incorrect-token" },
    }), env);
    expect(wrongToken.status).toBe(404);

    const headers = {
      "x-pfss-registration-token": receipt.registrationToken,
    };
    const cancelled = await worker.fetch(new Request(
      `https://pfss.test${path}/cancel`, { method: "POST", headers },
    ), env);
    expect(cancelled.status).toBe(200);
    const cancelledBody = await cancelled.json<{
      registrationAttempt: { status: string; cancelledAt: string };
    }>();
    expect(cancelledBody.registrationAttempt.status).toBe("cancelled");
    expect(cancelledBody.registrationAttempt.cancelledAt).toBeTruthy();
    const repeated = await worker.fetch(new Request(
      `https://pfss.test${path}/cancel`, { method: "POST", headers },
    ), env);
    expect((await repeated.json() as {
      registrationAttempt: { status: string };
    }).registrationAttempt.status).toBe("cancelled");

    const expiringBody = uniqueAccountRegistrationBody();
    const expiring = await startAccountRegistration(expiringBody);
    const expiringReceipt = await expiring.json<{
      registrationAttempt: { id: string };
      registrationToken: string;
    }>();
    await env.DB.prepare(
      `UPDATE account_registration_attempts SET expires_at = ?2 WHERE id = ?1`,
    ).bind(
      expiringReceipt.registrationAttempt.id,
      new Date(Date.now() - 1000).toISOString(),
    ).run();
    const expired = await worker.fetch(new Request(
      `https://pfss.test/v1/account-registration/attempts/${expiringReceipt.registrationAttempt.id}`,
      { headers: {
        "x-pfss-registration-token": expiringReceipt.registrationToken,
      } },
    ), env);
    expect((await expired.json() as {
      registrationAttempt: { status: string };
    }).registrationAttempt.status).toBe("expired");
  });
});

describe("managed Owner identity boundary", () => {
  it("persists state, verifies WorkOS once, and consumes identity evidence", async () => {
    const state = "s".repeat(43);
    const verifier = "v".repeat(43);
    const challenge = createHash("sha256").update(verifier).digest("base64url");
    const redirectURI = "https://identity.staging.pfss.test/callback";
    const verifiedEmail = `${crypto.randomUUID()}@example.com`;
    const provider: ManagedOwnerIdentityProvider = {
      async startAuthorization(request) {
        return {
          authorizationURL: `https://signin.workos.test/?state=${request.state}`,
          state: request.state,
          expiresAt: new Date(Date.now() + 300_000).toISOString(),
        };
      },
      async exchangeAuthorizationCode() {
        return {
          providerKey: "workos",
          providerSubject: `user_${crypto.randomUUID().replace(/-/g, "")}`,
          verifiedEmail,
          displayName: "Verified Owner",
          authenticationMethod: "MagicAuth",
        };
      },
    };
    const started = await startOwnerAuthorization(new Request(
      "https://pfss.test/v1/owner-auth/authorize",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          state, codeChallenge: challenge, redirectURI,
          emailHint: verifiedEmail,
        }),
      },
    ), env, provider);
    expect(started.status).toBe(201);

    const completed = await completeOwnerAuthorization(new Request(
      "https://pfss.test/v1/owner-auth/callback",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          state,
          code: "authorization_code_12345",
          codeVerifier: verifier,
          redirectURI,
        }),
      },
    ), env, provider);
    expect(completed.status).toBe(200);
    const identity = await completed.json<{
      identityAssertion: string;
      authenticationMethod: "password" | "passkey" |
        "signInWithApple" | "federated";
      owner: { displayName: string; email: string };
    }>();
    expect(identity.identityAssertion).toMatch(/^pfss_owner_/);
    expect(identity.authenticationMethod).toBe("federated");
    expect(identity.owner.email).toBe(verifiedEmail);

    const replayed = await completeOwnerAuthorization(new Request(
      "https://pfss.test/v1/owner-auth/callback",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          state,
          code: "authorization_code_12345",
          codeVerifier: verifier,
          redirectURI,
        }),
      },
    ), env, provider);
    expect(replayed.status).toBe(409);

    const registration = uniqueAccountRegistrationBody();
    registration.identityAssertion = identity.identityAssertion;
    registration.authenticationMethod = identity.authenticationMethod;
    (registration.owner as Record<string, unknown>).displayName =
      identity.owner.displayName;
    (registration.owner as Record<string, unknown>).email = identity.owner.email;
    const receipt = await startAccountRegistration(registration);
    expect(receipt.status).toBe(201);
    const authorization = await env.DB.prepare(
      `SELECT status FROM owner_authorization_attempts
        WHERE identity_assertion_digest = ?1`,
    ).bind(
      createHash("sha256").update(identity.identityAssertion).digest("hex"),
    ).first<{ status: string }>();
    expect(authorization?.status).toBe("consumed");
  });

  it("rejects wrong PKCE verifier and expires stale authorization state", async () => {
    const state = "x".repeat(43);
    const verifier = "y".repeat(43);
    const challenge = createHash("sha256").update(verifier).digest("base64url");
    const redirectURI = "https://identity.staging.pfss.test/callback";
    const provider = new LocalManagedOwnerIdentityProvider();
    const startProvider: ManagedOwnerIdentityProvider = {
      startAuthorization: async (request) => ({
        authorizationURL: `https://signin.workos.test/?state=${request.state}`,
        state: request.state,
        expiresAt: new Date(Date.now() + 300_000).toISOString(),
      }),
      exchangeAuthorizationCode: (...arguments_) =>
        provider.exchangeAuthorizationCode(...arguments_),
    };
    await startOwnerAuthorization(new Request(
      "https://pfss.test/v1/owner-auth/authorize",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ state, codeChallenge: challenge, redirectURI }),
      },
    ), env, startProvider);
    const wrongVerifier = await completeOwnerAuthorization(new Request(
      "https://pfss.test/v1/owner-auth/callback",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          state,
          code: "authorization_code_12345",
          codeVerifier: "z".repeat(43),
          redirectURI,
        }),
      },
    ), env, provider);
    expect(wrongVerifier.status).toBe(400);
    await env.DB.prepare(
      `UPDATE owner_authorization_attempts SET expires_at = ?2
        WHERE state_digest = ?1`,
    ).bind(
      createHash("sha256").update(state).digest("hex"),
      new Date(Date.now() - 1000).toISOString(),
    ).run();
    const expired = await completeOwnerAuthorization(new Request(
      "https://pfss.test/v1/owner-auth/callback",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          state,
          code: "authorization_code_12345",
          codeVerifier: verifier,
          redirectURI,
        }),
      },
    ), env, provider);
    expect(expired.status).toBe(410);
  });

  it("rejects cross-environment and insecure managed identity configuration", () => {
    expect(() => validateManagedIdentityConfiguration({
      providerKey: "workos",
      deploymentEnvironment: "production",
      providerEnvironment: "staging",
      clientID: "client_production123",
      apiKey: "sk_production_secret123",
      apiBaseURL: "https://api.workos.com",
      issuer: "https://identity.pfss.com",
      redirectURIs: ["https://identity.pfss.com/callback"],
    })).toThrow(IdentityConfigurationError);

    expect(() => validateManagedIdentityConfiguration({
      providerKey: "workos",
      deploymentEnvironment: "staging",
      providerEnvironment: "staging",
      clientID: "client_staging123",
      apiKey: "sk_staging_secret123",
      apiBaseURL: "https://api.workos.com",
      issuer: "http://identity.staging.pfss.test",
      redirectURIs: ["https://identity.staging.pfss.test/callback"],
    })).toThrow(IdentityConfigurationError);

    expect(() => validateManagedIdentityConfiguration({
      providerKey: "workos",
      deploymentEnvironment: "staging",
      providerEnvironment: "staging",
      clientID: "client_staging123",
      apiKey: "sk_staging_secret123",
      apiBaseURL: "https://api.workos.com",
      issuer: "https://identity.staging.pfss.test",
      redirectURIs: ["https://identity.staging.pfss.test/callback"],
    })).not.toThrow();
  });

  it("loads only explicit matching WorkOS environment bindings", () => {
    const configuration = managedIdentityConfigurationFromBindings({
      PFSS_ENVIRONMENT: "staging",
      WORKOS_ENVIRONMENT: "staging",
      WORKOS_CLIENT_ID: "client_staging123",
      WORKOS_API_KEY: "sk_staging_secret123",
      WORKOS_API_BASE_URL: "https://api.workos.com",
      WORKOS_ISSUER: "https://identity.staging.pfss.test",
      WORKOS_REDIRECT_URIS: JSON.stringify([
        "https://identity.staging.pfss.test/callback",
      ]),
    });
    expect(configuration.providerKey).toBe("workos");
    expect(configuration.apiKey).toBe("sk_staging_secret123");
    expect(configuration.redirectURIs).toEqual([
      "https://identity.staging.pfss.test/callback",
    ]);

    expect(() => managedIdentityConfigurationFromBindings({
      PFSS_ENVIRONMENT: "staging",
      WORKOS_ENVIRONMENT: "staging",
      WORKOS_CLIENT_ID: "client_staging123",
      WORKOS_API_BASE_URL: "https://api.workos.com",
      WORKOS_ISSUER: "https://identity.staging.pfss.test",
      WORKOS_REDIRECT_URIS: JSON.stringify([
        "https://identity.staging.pfss.test/callback",
      ]),
    })).toThrow("Invalid managed identity API key");

    expect(() => managedIdentityConfigurationFromBindings({
      PFSS_ENVIRONMENT: "production",
      WORKOS_ENVIRONMENT: "staging",
      WORKOS_CLIENT_ID: "client_staging123",
      WORKOS_API_KEY: "sk_staging_secret123",
      WORKOS_API_BASE_URL: "https://api.workos.com",
      WORKOS_ISSUER: "https://identity.staging.pfss.test",
      WORKOS_REDIRECT_URIS: "not-json",
    })).toThrow(IdentityConfigurationError);
  });

  it("keeps local authorization deterministic and rejects untrusted callbacks", async () => {
    const adapter = new LocalManagedOwnerIdentityProvider();
    const state = "s".repeat(43);
    const session = await adapter.startAuthorization({
      state,
      codeChallenge: "c".repeat(43),
      redirectURI: "https://local.pfss.test/auth/callback",
    });
    expect(session.state).toBe(state);
    expect(session.authorizationURL).toContain("https://local.pfss.test/authorize");

    await expect(adapter.startAuthorization({
      state,
      codeChallenge: "c".repeat(43),
      redirectURI: "https://attacker.example/callback",
    })).rejects.toThrow(IdentityConfigurationError);

    const identity = await adapter.exchangeAuthorizationCode(
      "local-verified-code",
      "v".repeat(43),
      "https://local.pfss.test/auth/callback",
    );
    expect(identity.providerKey).toBe("workos");
    expect(identity.verifiedEmail).toBe("owner@local.pfss.test");
  });

  it("builds WorkOS PKCE authorization and returns only verified identity", async () => {
    let exchangeBody: Record<string, unknown> | undefined;
    const adapter = new WorkOSManagedOwnerIdentityProvider({
      providerKey: "workos",
      deploymentEnvironment: "staging",
      providerEnvironment: "staging",
      clientID: "client_staging123",
      apiKey: "sk_staging_secret123",
      apiBaseURL: "https://api.workos.com",
      issuer: "https://identity.staging.pfss.test",
      redirectURIs: ["https://identity.staging.pfss.test/callback"],
    }, async (_input, init) => {
      exchangeBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(JSON.stringify({
        user: {
          id: "user_verified123",
          email: " OWNER@EXAMPLE.COM ",
          email_verified: true,
          first_name: "Geoff",
          last_name: "Nordmyer",
        },
        authentication_method: "MagicAuth",
        access_token: "must-not-be-returned",
        refresh_token: "must-not-be-returned",
      }), { status: 200, headers: { "content-type": "application/json" } });
    });
    const state = "s".repeat(43);
    const codeChallenge = "c".repeat(43);
    const session = await adapter.startAuthorization({
      state,
      codeChallenge,
      redirectURI: "https://identity.staging.pfss.test/callback",
      emailHint: "owner@example.com",
    });
    const authorizationURL = new URL(session.authorizationURL);
    expect(authorizationURL.origin).toBe("https://api.workos.com");
    expect(authorizationURL.searchParams.get("provider")).toBe("authkit");
    expect(authorizationURL.searchParams.get("code_challenge_method")).toBe("S256");
    expect(authorizationURL.searchParams.get("code_challenge"))
      .toBe(codeChallenge);

    const identity = await adapter.exchangeAuthorizationCode(
      "authorization_code_12345",
      "v".repeat(43),
      "https://identity.staging.pfss.test/callback",
    );
    expect(exchangeBody).toEqual({
      client_id: "client_staging123",
      client_secret: "sk_staging_secret123",
      grant_type: "authorization_code",
      code: "authorization_code_12345",
      code_verifier: "v".repeat(43),
    });
    expect(identity).toEqual({
      providerKey: "workos",
      providerSubject: "user_verified123",
      verifiedEmail: "owner@example.com",
      displayName: "Geoff Nordmyer",
      authenticationMethod: "MagicAuth",
    });
    expect(identity).not.toHaveProperty("accessToken");
    expect(identity).not.toHaveProperty("refreshToken");
  });

  it("rejects unverified WorkOS identities", async () => {
    const adapter = new WorkOSManagedOwnerIdentityProvider({
      providerKey: "workos",
      deploymentEnvironment: "staging",
      providerEnvironment: "staging",
      clientID: "client_staging123",
      apiKey: "sk_staging_secret123",
      apiBaseURL: "https://api.workos.com",
      issuer: "https://identity.staging.pfss.test",
      redirectURIs: ["https://identity.staging.pfss.test/callback"],
    }, async () => new Response(JSON.stringify({
      user: {
        id: "user_unverified123",
        email: "owner@example.com",
        email_verified: false,
      },
      authentication_method: "MagicAuth",
    }), { status: 200 }));
    await expect(adapter.exchangeAuthorizationCode(
      "authorization_code_12345",
      "v".repeat(43),
      "https://identity.staging.pfss.test/callback",
    )).rejects.toThrow("incomplete or unverified");
  });
});

describe("tenant isolation", () => {
  it("shares technician job declines with managers and resolves them idempotently", async () => {
    const owner = await seedIdentity("Decline Owner", "owner");
    const manager = await seedMemberInTenant(owner, "Decline Manager", "manager");
    const technician = await seedMemberInTenant(owner, "Decline Technician", "member");
    const employeeID = crypto.randomUUID();
    await env.DB.prepare(
      "UPDATE tenant_members SET employee_id = ?1 WHERE id = ?2",
    ).bind(employeeID, technician.memberID).run();

    const assignmentID = crypto.randomUUID();
    const jobID = crypto.randomUUID();
    const now = new Date().toISOString();
    const assignment = {
      id: assignmentID,
      jobID,
      jobNumber: "JOB-DECLINE-001",
      customerNumber: "PPS-DECLINE-001",
      status: "Scheduled",
      crew: { members: [{
        id: crypto.randomUUID(), employeeID,
        role: "Primary Technician", assignedDate: now, removedDate: null,
      }] },
    };
    const recordData = Buffer.from(JSON.stringify(assignment)).toString("base64");
    const mutation = Buffer.from(JSON.stringify({ recordData })).toString("base64");
    const operation = {
      id: crypto.randomUUID(), idempotencyKey: crypto.randomUUID(),
      type: "recordMutation", entityType: "assignment", entityID: assignmentID,
      payload: { body: mutation }, createdAt: now,
    };
    const accepted = await worker.fetch(request(owner, "/v1/operations", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify(operation),
    }), env);
    expect(accepted.status).toBe(201);

    const idempotencyKey = crypto.randomUUID();
    const submit = () => worker.fetch(request(technician, "/v1/job-declines", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ assignmentID, jobID, reason: "Schedule conflict", idempotencyKey }),
    }), env);
    expect((await submit()).status).toBe(201);
    const duplicate = await submit();
    expect(duplicate.status).toBe(200);
    expect((await duplicate.json<{ duplicate: boolean }>()).duplicate).toBe(true);

    const inbox = await worker.fetch(
      request(manager, "/v1/job-declines?status=pending"), env,
    );
    const listed = await inbox.json<{ reviews: Array<{ id: string }> }>();
    expect(listed.reviews).toHaveLength(1);
    const reviewID = listed.reviews[0].id;
    const resolve = () => worker.fetch(request(
      manager, `/v1/job-declines/${reviewID}/resolve`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "rescheduled", note: "Moved to Friday" }),
      },
    ), env);
    expect((await resolve()).status).toBe(200);
    const repeated = await resolve();
    expect((await repeated.json<{ duplicate: boolean }>()).duplicate).toBe(true);
  });
  it("synchronizes mileage only across devices owned by the same member", async () => {
    const owner = await seedIdentity("Mileage Owner");
    const secondDevice = await seedAdditionalDevice(owner, "Mileage Second");
    const otherMember = await seedMemberInTenant(owner, "Other Member", "manager");
    const tripID = crypto.randomUUID();
    const now = new Date().toISOString();
    const trip = {
      id: tripID, accountID: owner.tenantID, userID: owner.memberID,
      originatingDeviceID: owner.deviceID, entrySource: "automatic",
      startedAt: now, endedAt: now, timeZoneIdentifier: "America/Chicago",
      route: [{ latitude: 35.4, longitude: -97.5, timestamp: now,
        horizontalAccuracyMeters: 5, speedMetersPerSecond: 12 }],
      distanceMeters: 1609.344, classification: "personal",
      businessPurpose: "", note: "private", createdAt: now, updatedAt: now,
      detectionVersion: 1, accuracy: { acceptedPointCount: 1,
        rejectedPointCount: 0, averageHorizontalAccuracyMeters: 5 },
      classificationHistory: [],
    };
    const upload = await worker.fetch(request(owner, "/v1/mileage/sync", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ cursor: 0, trips: [{ id: tripID,
        originatingDeviceID: owner.deviceID, classification: "personal",
        startedAt: now, updatedAt: now, payload: trip }], deletions: [] }),
    }), env);
    expect(upload.status).toBe(200);

    const restored = await worker.fetch(request(secondDevice, "/v1/mileage/sync", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ cursor: 0, trips: [], deletions: [] }),
    }), env);
    const restoredBody = await restored.json<{ changes: Array<{
      payload?: { id: string; note: string };
    }> }>();
    expect(restoredBody.changes[0]?.payload?.id).toBe(tripID);
    expect(restoredBody.changes[0]?.payload?.note).toBe("private");

    const isolated = await worker.fetch(request(otherMember, "/v1/mileage/sync", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ cursor: 0, trips: [], deletions: [] }),
    }), env);
    const isolatedBody = await isolated.json<{ changes: unknown[] }>();
    expect(isolatedBody.changes).toEqual([]);
  });

  it("exposes business summaries without route or personal-trip details", async () => {
    const owner = await seedIdentity("Mileage Summary");
    const manager = await seedMemberInTenant(owner, "Mileage Manager", "manager");
    const now = new Date().toISOString();
    const uploadTrip = async (classification: "business" | "personal") => {
      const id = crypto.randomUUID();
      const payload = { id, startedAt: now, distanceMeters: 3218.688,
        businessPurpose: "Customer visit", route: [{ latitude: 35.4 }] };
      return worker.fetch(request(owner, "/v1/mileage/sync", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ cursor: 0, trips: [{ id,
          originatingDeviceID: owner.deviceID, classification,
          startedAt: now, updatedAt: now, payload }], deletions: [] }),
      }), env);
    };
    expect((await uploadTrip("business")).status).toBe(200);
    expect((await uploadTrip("personal")).status).toBe(200);
    const summary = await worker.fetch(request(manager,
      `/v1/mileage/business-summary?from=${encodeURIComponent(now)}&through=${encodeURIComponent(now)}`), env);
    expect(summary.status).toBe(200);
    const body = await summary.json<{ trips: Array<Record<string, unknown>> }>();
    expect(body.trips).toHaveLength(1);
    expect(body.trips[0]?.businessPurpose).toBe("Customer visit");
    expect(body.trips[0]).not.toHaveProperty("route");
  });
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

  it("keeps the tenant feed gap-free across reversed timestamps, partial rejection, and duplicate replay", async () => {
    const owner = await seedIdentity("Failure Mode Feed");
    const member = await seedMemberInTenant(owner, "Failure Mode Member");
    const makeOperation = (label: string, createdAt: string) => ({
      id: crypto.randomUUID(),
      idempotencyKey: `failure-mode-${label}-${crypto.randomUUID()}`,
      type: "recordMutation",
      entityType: "customer",
      entityID: crypto.randomUUID(),
      actionName: "upsertRecord",
      payload: { schemaVersion: 1, contentType: "test", body: "e30=" },
      createdAt,
    });
    const firstAccepted = makeOperation("newer-clock", "2026-08-23T01:00:00Z");
    const secondAccepted = makeOperation("older-clock", "2026-08-22T01:00:00Z");
    const submit = (operation: unknown) => worker.fetch(
      request(member, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(operation),
      }),
      env,
    );

    expect((await submit(firstAccepted)).status).toBe(201);
    const rejected = await submit({
      ...makeOperation("invalid", "2026-08-23T01:01:00Z"),
      idempotencyKey: "",
    });
    expect(rejected.status).toBe(400);
    expect((await submit(secondAccepted)).status).toBe(201);
    expect((await submit(firstAccepted)).status).toBe(200);

    const feed = await worker.fetch(
      request(owner, "/v1/sync/changes?after=0"), env,
    );
    expect(feed.status).toBe(200);
    const body = await feed.json<{
      cursor: number;
      changes: Array<{
        sequence: number;
        operation: { idempotencyKey: string };
      }>;
    }>();
    const acceptedChanges = body.changes.filter((change) =>
      change.operation.idempotencyKey === firstAccepted.idempotencyKey ||
      change.operation.idempotencyKey === secondAccepted.idempotencyKey
    );
    expect(acceptedChanges.map((change) => change.operation.idempotencyKey))
      .toEqual([firstAccepted.idempotencyKey, secondAccepted.idempotencyKey]);
    expect(acceptedChanges[1]?.sequence).toBe(acceptedChanges[0]!.sequence + 1);
    expect(body.cursor).toBe(acceptedChanges[1]?.sequence);

    const afterFirst = await worker.fetch(
      request(owner, `/v1/sync/changes?after=${acceptedChanges[0]?.sequence}`), env,
    );
    const afterFirstBody = await afterFirst.json<{
      cursor: number;
      changes: Array<{ operation: { idempotencyKey: string } }>;
    }>();
    expect(afterFirstBody.cursor).toBe(acceptedChanges[1]?.sequence);
    expect(afterFirstBody.changes.map((change) => change.operation.idempotencyKey))
      .toEqual([secondAccepted.idempotencyKey]);

    const stored = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM synchronized_operations
        WHERE tenant_id = ?1 AND idempotency_key IN (?2, ?3)`,
    ).bind(
      owner.tenantID,
      firstAccepted.idempotencyKey,
      secondAccepted.idempotencyKey,
    ).first<{ count: number }>();
    expect(stored?.count).toBe(2);
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

  it("allows Members to record catalog usage without changing protected fields", async () => {
    const owner = await seedIdentity("Catalog Usage Authority");
    const member = await seedMemberInTenant(owner, "Catalog Usage Member");
    const catalogID = crypto.randomUUID();
    const catalogRecord = {
      id: catalogID,
      itemName: "Window Cleaning",
      itemDescription: "Routine service",
      defaultQuantity: 1,
      defaultPrice: 100,
      estimatedMinutesPerUnit: 60,
      itemType: "Service",
      taxTreatment: "Non-Taxable",
      usageCount: 0,
      lastUsedDate: null,
      lifecycleStatus: "Active",
    };
    const operation = (
      record: typeof catalogRecord,
      baseRevision: string | null,
    ) => ({
      id: crypto.randomUUID(),
      idempotencyKey: `catalog-usage-${crypto.randomUUID()}`,
      type: "recordMutation",
      entityType: "catalog",
      entityID: catalogID,
      actionName: "upsertRecord",
      baseRevision,
      payload: {
        schemaVersion: 1,
        contentType: "application/json",
        body: Buffer.from(JSON.stringify({
          recordData: Buffer.from(JSON.stringify(record)).toString("base64"),
        })).toString("base64"),
      },
      createdAt: new Date().toISOString(),
    });

    const created = await worker.fetch(request(owner, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(operation(catalogRecord, null)),
    }), env);
    expect(created.status).toBe(201);
    const createdBody = await created.json<{ revision: string }>();

    const usedAt = new Date().toISOString();
    const usageUpdate = {
      ...catalogRecord,
      usageCount: 1,
      lastUsedDate: usedAt,
    };
    const accepted = await worker.fetch(request(member, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(operation(usageUpdate, createdBody.revision)),
    }), env);
    expect(accepted.status).toBe(201);
    const acceptedBody = await accepted.json<{ revision: string }>();

    const priceChange = { ...usageUpdate, defaultPrice: 1 };
    const forbidden = await worker.fetch(request(member, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(operation(priceChange, acceptedBody.revision)),
    }), env);
    expect(forbidden.status).toBe(403);
  });

  it("restricts recurring-work templates to Managers and Owners", async () => {
    const owner = await seedIdentity("Recurring Work Authority");
    const member = await seedMemberInTenant(owner, "Recurring Work Member");
    const templateID = crypto.randomUUID();
    const mutation = (identity: SeededIdentity) => request(
      identity,
      "/v1/operations",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: `recurring-work-${crypto.randomUUID()}`,
          type: "recordMutation",
          entityType: "recurringWork",
          entityID: templateID,
          actionName: "upsertRecord",
          createdAt: new Date().toISOString(),
        }),
      },
    );

    const memberResponse = await worker.fetch(mutation(member), env);
    expect(memberResponse.status).toBe(403);

    const ownerResponse = await worker.fetch(mutation(owner), env);
    expect(ownerResponse.status).toBe(201);
    const stored = await env.DB.prepare(
      `SELECT entity_id AS entityID FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'recurringWork'`,
    ).bind(owner.tenantID).first<{ entityID: string }>();
    expect(stored?.entityID).toBe(templateID.toLowerCase());
  });

  it("restricts synchronized company profiles to Managers and Owners", async () => {
    const owner = await seedIdentity("Company Profile Authority");
    const member = await seedMemberInTenant(owner, "Company Profile Member");
    const profileID = "00000000-0000-0000-0000-000000000001";
    const mutation = (identity: SeededIdentity) => request(
      identity,
      "/v1/operations",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: `company-profile-${crypto.randomUUID()}`,
          type: "recordMutation",
          entityType: "custom",
          entityID: profileID,
          actionName: "upsertRecord",
          createdAt: new Date().toISOString(),
        }),
      },
    );

    const memberResponse = await worker.fetch(mutation(member), env);
    expect(memberResponse.status).toBe(403);

    const ownerResponse = await worker.fetch(mutation(owner), env);
    expect(ownerResponse.status).toBe(201);
    const stored = await env.DB.prepare(
      `SELECT entity_id AS entityID FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'custom'`,
    ).bind(owner.tenantID).first<{ entityID: string }>();
    expect(stored?.entityID).toBe(profileID);
  });

  it("preserves the cloud technician when a Member submits a stale job snapshot", async () => {
    const owner = await seedIdentity("Protected Job Owner");
    const member = await seedMemberInTenant(owner, "Protected Job Technician");
    const authorizedTechnicianID = crypto.randomUUID();
    const staleTechnicianID = crypto.randomUUID();
    const jobID = crypto.randomUUID();
    const now = new Date().toISOString();
    const makeOperation = (
      record: Record<string, unknown>,
      baseRevision: string | null,
    ) => {
      const recordData = Buffer.from(JSON.stringify(record)).toString("base64");
      const mutation = Buffer.from(JSON.stringify({
        entityType: "job", entityID: jobID, recordData, modifiedAt: now,
      })).toString("base64");
      return {
        id: crypto.randomUUID(),
        idempotencyKey: crypto.randomUUID(),
        type: "recordMutation",
        entityType: "job",
        entityID: jobID,
        actionName: "upsertRecord",
        baseRevision,
        payload: { schemaVersion: 1, contentType: "test", body: mutation },
        createdAt: now,
      };
    };

    const created = await worker.fetch(request(owner, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(makeOperation({
        id: jobID,
        status: "Assigned",
        primaryTechnicianID: authorizedTechnicianID,
      }, null)),
    }), env);
    expect(created.status).toBe(201);
    const revision = (await created.json<{ revision: string }>()).revision;

    const updated = await worker.fetch(request(member, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(makeOperation({
        id: jobID,
        status: "Traveling",
        primaryTechnicianID: staleTechnicianID,
      }, revision)),
    }), env);
    expect(updated.status).toBe(201);

    const stored = await env.DB.prepare(
      `SELECT operation_json AS operationJSON FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'job' AND entity_id = ?2`,
    ).bind(owner.tenantID, jobID.toLowerCase()).first<{ operationJSON: string }>();
    const operation = JSON.parse(stored!.operationJSON) as {
      payload: { body: string };
      metadata: { serverProtectedFields: string[] };
    };
    const mutation = JSON.parse(Buffer.from(operation.payload.body, "base64")
      .toString("utf8")) as { recordData: string };
    const record = JSON.parse(Buffer.from(mutation.recordData, "base64")
      .toString("utf8")) as { status: string; primaryTechnicianID: string };
    expect(record.status).toBe("Traveling");
    expect(record.primaryTechnicianID).toBe(authorizedTechnicianID);
    expect(operation.metadata.serverProtectedFields).toEqual(["primaryTechnicianID"]);
  });

  it("allows a Member to synchronize a new Job assigned to their own profile", async () => {
    const owner = await seedIdentity("Offline Job Owner");
    const member = await seedMemberInTenant(owner, "Offline Job Technician");
    const employeeID = crypto.randomUUID();
    await env.DB.prepare(
      "UPDATE tenant_members SET employee_id = ?1 WHERE id = ?2",
    ).bind(employeeID, member.memberID).run();
    const jobID = crypto.randomUUID();
    const now = new Date().toISOString();
    const send = async (primaryTechnicianID: string | null) => {
      const recordData = Buffer.from(JSON.stringify({
        id: jobID, status: "Assigned", primaryTechnicianID,
      })).toString("base64");
      const mutation = Buffer.from(JSON.stringify({
        entityType: "job", entityID: jobID, recordData, modifiedAt: now,
      })).toString("base64");
      return worker.fetch(request(member, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: crypto.randomUUID(),
          type: "recordMutation",
          entityType: "job",
          entityID: jobID,
          actionName: "upsertRecord",
          payload: { schemaVersion: 1, contentType: "test", body: mutation },
          createdAt: now,
        }),
      }), env);
    };

    expect((await send(employeeID)).status).toBe(201);

    const unauthorizedJobID = crypto.randomUUID();
    const recordData = Buffer.from(JSON.stringify({
      id: unauthorizedJobID,
      status: "Assigned",
      primaryTechnicianID: crypto.randomUUID(),
    })).toString("base64");
    const mutation = Buffer.from(JSON.stringify({
      entityType: "job", entityID: unauthorizedJobID, recordData, modifiedAt: now,
    })).toString("base64");
    const forbidden = await worker.fetch(request(member, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        id: crypto.randomUUID(), idempotencyKey: crypto.randomUUID(),
        type: "recordMutation", entityType: "job", entityID: unauthorizedJobID,
        actionName: "upsertRecord",
        payload: { schemaVersion: 1, contentType: "test", body: mutation },
        createdAt: now,
      }),
    }), env);
    expect(forbidden.status).toBe(403);
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

  it("applies Owner-approved Manager promotions to the linked membership", async () => {
    const owner = await seedIdentity("Employee Promotion Owner");
    const member = await seedMemberInTenant(owner, "Promoted Field Employee");
    const employeeID = crypto.randomUUID();
    await seedEmployeeRecord(owner, employeeID, ["Technician"]);
    await env.DB.prepare(
      "UPDATE tenant_members SET employee_id = ?1 WHERE id = ?2",
    ).bind(employeeID, member.memberID).run();

    const submitRoles = async (roles: string[]) => {
      const now = new Date().toISOString();
      const recordData = Buffer.from(JSON.stringify({
        id: employeeID,
        firstName: "Promoted",
        lastName: "Employee",
        role: roles[0],
        roles,
      })).toString("base64");
      const mutation = Buffer.from(JSON.stringify({
        entityType: "employee",
        entityID: employeeID,
        recordData,
        modifiedAt: now,
      })).toString("base64");
      return worker.fetch(request(owner, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          idempotencyKey: `employee-role-${crypto.randomUUID()}`,
          type: "recordMutation",
          entityType: "employee",
          entityID: employeeID,
          actionName: "upsertRecord",
          payload: { schemaVersion: 1, contentType: "test", body: mutation },
          createdAt: now,
        }),
      }), env);
    };

    expect((await submitRoles(["Manager", "Technician"])).status).toBe(201);
    const promotedSession = await worker.fetch(request(member, "/v1/session"), env);
    expect(promotedSession.status).toBe(200);
    expect((await promotedSession.json<{
      member: { role: string };
    }>()).member.role).toBe("manager");

    expect((await submitRoles(["Technician"])).status).toBe(201);
    const demotedSession = await worker.fetch(request(member, "/v1/session"), env);
    expect((await demotedSession.json<{
      member: { role: string };
    }>()).member.role).toBe("member");

    const audit = await env.DB.prepare(
      `SELECT event_type AS eventType FROM access_audit_events
        WHERE tenant_id = ?1 AND target_member_id = ?2
          AND event_type IN ('member.promoted_to_manager', 'member.demoted_to_member')
        ORDER BY created_at ASC`,
    ).bind(owner.tenantID, member.memberID).all<{ eventType: string }>();
    expect(audit.results.map((event) => event.eventType)).toEqual([
      "member.promoted_to_manager",
      "member.demoted_to_member",
    ]);
  });

  it("requires an Owner to change a linked Manager access role", async () => {
    const owner = await seedIdentity("Promotion Authority Owner");
    const manager = await seedMemberInTenant(owner, "Existing Manager", "manager");
    const target = await seedMemberInTenant(owner, "Promotion Target");
    const employeeID = crypto.randomUUID();
    await seedEmployeeRecord(owner, employeeID, ["Technician"]);
    await env.DB.prepare(
      "UPDATE tenant_members SET employee_id = ?1 WHERE id = ?2",
    ).bind(employeeID, target.memberID).run();
    const now = new Date().toISOString();
    const recordData = Buffer.from(JSON.stringify({
      id: employeeID,
      role: "Manager",
      roles: ["Manager", "Technician"],
    })).toString("base64");
    const mutation = Buffer.from(JSON.stringify({
      entityType: "employee", entityID: employeeID, recordData, modifiedAt: now,
    })).toString("base64");
    const response = await worker.fetch(request(manager, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        id: crypto.randomUUID(),
        idempotencyKey: `manager-promotion-${crypto.randomUUID()}`,
        type: "recordMutation",
        entityType: "employee",
        entityID: employeeID,
        actionName: "upsertRecord",
        payload: { schemaVersion: 1, contentType: "test", body: mutation },
        createdAt: now,
      }),
    }), env);

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "employee_access_role_change_requires_owner",
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
      conflicts: Array<{
        id: string;
        sourceDeviceID: string;
        affectedFields: string[];
        operationalImpact: string;
        policyVersion: number;
      }>;
    }>();
    expect(managerInbox.status).toBe(200);
    expect(managerConflicts.conflicts).toContainEqual(expect.objectContaining({
      id: conflict.conflictID,
      sourceDeviceID: secondDevice.deviceID,
      affectedFields: ["record"],
      policyVersion: 1,
    }));
    expect(managerConflicts.conflicts[0].operationalImpact.length).toBeGreaterThan(10);

    const resolved = await worker.fetch(
      request(manager, `/v1/sync/conflicts/${conflict.conflictID}/resolve`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          resolution: "keptDevice",
          reason: "",
          affectedFields: ["phone"],
        }),
      }),
      env,
    );
    expect(resolved.status).toBe(200);
    const resolvedBody = await resolved.json<{
      entityType: string;
      entityID: string;
      finalRevision: string;
    }>();
    expect(resolvedBody).toMatchObject({
      entityType: "customer",
      entityID: entityID.toLowerCase(),
    });
    expect(resolvedBody.finalRevision).not.toBe(secondRevision);
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
      resolutions: Array<{
        id: string;
        entityType: string;
        entityID: string;
        resolution: string;
        finalRevision: string;
      }>;
    }>();
    expect(sourceReceiptBody.resolutions).toContainEqual(expect.objectContaining({
      id: conflict.conflictID,
      entityType: "customer",
      entityID: entityID.toLowerCase(),
      resolution: "keptDevice",
      finalRevision: resolvedBody.finalRevision,
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
        policyVersion: number;
      }>;
    }>();
    expect(auditBody.events).toContainEqual(expect.objectContaining({
      id: conflict.conflictID,
      resolverRole: "manager",
      reason: "Manager or Owner chose the device version without an additional note.",
      affectedFields: ["phone"],
      policyVersion: 1,
    }));
    expect(auditBody.events[0].finalRevision).not.toBe(secondRevision);
    const clearedInbox = await worker.fetch(
      request(owner, "/v1/sync/conflicts"), env,
    );
    expect((await clearedInbox.json<{ conflicts: unknown[] }>()).conflicts)
      .toHaveLength(0);

    const duplicateResolution = await worker.fetch(
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
    expect(duplicateResolution.status).toBe(200);
    await expect(duplicateResolution.json()).resolves.toMatchObject({
      id: conflict.conflictID,
      resolution: "keptDevice",
      finalRevision: resolvedBody.finalRevision,
      duplicate: true,
    });
    const resolutionChanges = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM synchronization_change_log
        WHERE tenant_id = ?1 AND operation_id IN (
          SELECT id FROM synchronized_operations
           WHERE tenant_id = ?1 AND idempotency_key = ?2
        )`,
    ).bind(
      owner.tenantID,
      `conflict-resolution-${conflict.conflictID}`,
    ).first<{ count: number }>();
    expect(resolutionChanges?.count).toBe(1);
  });

  it("atomically discards the exact conflict set from a revoked device", async () => {
    const owner = await seedIdentity("Revoked Cleanup Owner");
    const revokedDevice = await seedAdditionalDevice(owner, "Revoked Cleanup iPhone");
    const entityIDs = [crypto.randomUUID(), crypto.randomUUID()];
    for (const [index, entityID] of entityIDs.entries()) {
      const accepted = await sendVersionedMutation(owner, {
        entityType: "customer", entityID, baseRevision: null,
        mutationKind: "wholeRecord", changedFields: [],
        record: { id: entityID, name: `Cloud ${index}` },
        sequenceNumber: index + 1,
      });
      expect(accepted.status).toBe(201);
      const revision = (await accepted.json<{ revision: string }>()).revision;
      const stale = await sendVersionedMutation(revokedDevice, {
        entityType: "customer", entityID,
        baseRevision: crypto.randomUUID(),
        mutationKind: "wholeRecord", changedFields: [],
        record: { id: entityID, name: `Retained Device ${index}` },
        sequenceNumber: index + 1,
      });
      expect(stale.status).toBe(409);
      expect((await stale.json<{ currentRevision: string }>()).currentRevision)
        .toBe(revision);
    }

    const whileActive = await worker.fetch(request(owner,
      "/v1/sync/conflicts/discard-revoked-device", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          sourceDeviceID: revokedDevice.deviceID,
          expectedCount: 2,
          reason: "Discard retained changes from revoked test device.",
        }),
      }), env);
    expect(whileActive.status).toBe(409);
    await expect(whileActive.json()).resolves.toEqual({
      error: "source_device_must_be_revoked",
    });

    await env.DB.prepare(
      `UPDATE devices SET revoked_at = ?1 WHERE tenant_id = ?2 AND id = ?3`,
    ).bind(new Date().toISOString(), owner.tenantID, revokedDevice.deviceID).run();
    const encodedDeviceID = encodeURIComponent(revokedDevice.deviceID);
    const scope = await worker.fetch(request(owner,
      `/v1/sync/conflicts/revoked-device-scope?sourceDeviceID=${encodedDeviceID}`),
    env);
    expect(scope.status).toBe(200);
    await expect(scope.json()).resolves.toEqual({
      sourceDeviceID: revokedDevice.deviceID,
      conflictCount: 2,
      isRevoked: true,
    });
    const wrongCount = await worker.fetch(request(owner,
      "/v1/sync/conflicts/discard-revoked-device", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          sourceDeviceID: revokedDevice.deviceID,
          expectedCount: 1,
          reason: "Discard retained changes from revoked test device.",
        }),
      }), env);
    expect(wrongCount.status).toBe(409);
    await expect(wrongCount.json()).resolves.toMatchObject({
      error: "revoked_device_conflict_count_changed",
      currentCount: 2,
    });

    const resolved = await worker.fetch(request(owner,
      "/v1/sync/conflicts/discard-revoked-device", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          sourceDeviceID: revokedDevice.deviceID,
          expectedCount: 2,
          reason: "Discard retained changes from revoked test device.",
        }),
      }), env);
    expect(resolved.status).toBe(200);
    await expect(resolved.json()).resolves.toMatchObject({
      sourceDeviceID: revokedDevice.deviceID,
      resolvedCount: 2,
      resolution: "keptCloud",
    });
    const rows = await env.DB.prepare(
      `SELECT
         (SELECT COUNT(*) FROM synchronization_conflicts
           WHERE tenant_id = ?1 AND source_device_id = ?2
             AND status = 'keptCloud') AS resolved,
         (SELECT COUNT(*) FROM synchronized_operations
           WHERE tenant_id = ?1
             AND idempotency_key LIKE 'conflict-resolution-%') AS operations,
         (SELECT COUNT(*) FROM synchronization_change_log
           WHERE tenant_id = ?1 AND operation_id LIKE 'conflict-resolution-%') AS changes,
         (SELECT COUNT(*) FROM access_audit_events
           WHERE tenant_id = ?1 AND event_type = 'sync.conflict_resolved') AS audits`,
    ).bind(owner.tenantID, revokedDevice.deviceID).first<{
      resolved: number; operations: number; changes: number; audits: number;
    }>();
    expect(rows).toEqual({ resolved: 2, operations: 2, changes: 2, audits: 2 });
    const resolutionPayloads = await env.DB.prepare(
      `SELECT payload_json AS payloadJSON FROM synchronization_change_log
        WHERE tenant_id = ?1 AND operation_id LIKE 'conflict-resolution-%'`,
    ).bind(owner.tenantID).all<{ payloadJSON: string }>();
    expect(resolutionPayloads.results).toHaveLength(2);
    for (const row of resolutionPayloads.results) {
      const payload = JSON.parse(row.payloadJSON) as {
        id?: string; idempotencyKey?: string;
      };
      expect(payload.id).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
      );
      expect(payload.idempotencyKey).toMatch(/^conflict-resolution-/);
    }
  });

  it("three-way merges independent Phase 20 field changes", async () => {
    const owner = await seedIdentity("Three Way Merge Owner");
    const secondDevice = await seedAdditionalDevice(owner, "Three Way iPad");
    const entityID = crypto.randomUUID();
    const original = { id: entityID, name: "Original", phone: "111" };
    const created = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision: null,
      mutationKind: "wholeRecord", changedFields: [], record: original,
      sequenceNumber: 1,
    });
    expect(created.status).toBe(201);
    const baseRevision = (await created.json<{ revision: string }>()).revision;

    const cloudChange = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision,
      mutationKind: "fieldPatch", changedFields: ["name"],
      baseRecord: original, record: { ...original, name: "Cloud Name" },
      sequenceNumber: 2,
    });
    expect(cloudChange.status).toBe(201);
    const cloudRevision = (await cloudChange.json<{ revision: string }>()).revision;

    const deviceChange = await sendVersionedMutation(secondDevice, {
      entityType: "customer", entityID, baseRevision,
      mutationKind: "fieldPatch", changedFields: ["phone"],
      baseRecord: original, record: { ...original, phone: "222" },
      sequenceNumber: 1,
    });
    expect(deviceChange.status).toBe(201);
    const merged = await deviceChange.json<{ revision: string }>();
    expect(merged.revision).not.toBe(cloudRevision);

    const stored = await env.DB.prepare(
      `SELECT operation_json AS operationJSON FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?2`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{ operationJSON: string }>();
    const operation = JSON.parse(stored!.operationJSON) as {
      metadata: { verifiedThreeWayMerge: boolean };
      payload: { body: string };
    };
    const mutation = JSON.parse(Buffer.from(operation.payload.body, "base64")
      .toString("utf8")) as { recordData: string };
    const record = JSON.parse(Buffer.from(mutation.recordData, "base64")
      .toString("utf8")) as { name: string; phone: string };
    expect(operation.metadata.verifiedThreeWayMerge).toBe(true);
    expect(record).toMatchObject({ name: "Cloud Name", phone: "222" });
  });

  it("creates a focused review only for the contradictory Phase 20 field", async () => {
    const owner = await seedIdentity("Focused Conflict Owner");
    const secondDevice = await seedAdditionalDevice(owner, "Focused Conflict iPad");
    const entityID = crypto.randomUUID();
    const original = { id: entityID, name: "Original", phone: "111" };
    const created = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision: null,
      mutationKind: "wholeRecord", changedFields: [], record: original,
      sequenceNumber: 1,
    });
    const baseRevision = (await created.json<{ revision: string }>()).revision;
    const cloudRecord = { ...original, phone: "333" };
    const cloudChange = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision,
      mutationKind: "fieldPatch", changedFields: ["phone"],
      baseRecord: original, record: cloudRecord,
      sequenceNumber: 2,
    });
    expect(cloudChange.status).toBe(201);
    const cloudRevision = (await cloudChange.json<{ revision: string }>()).revision;

    const deviceChange = await sendVersionedMutation(secondDevice, {
      entityType: "customer", entityID, baseRevision,
      mutationKind: "fieldPatch", changedFields: ["name", "phone"],
      baseRecord: original,
      record: { ...original, name: "Device Name", phone: "222" },
      sequenceNumber: 1,
    });
    expect(deviceChange.status).toBe(409);
    const conflictID = (await deviceChange.json<{ conflictID: string }>()).conflictID;

    const inbox = await worker.fetch(request(owner, "/v1/sync/conflicts"), env);
    const inboxBody = await inbox.json<{
      conflicts: Array<{
        id: string;
        affectedFields: string[];
        operationalImpact: string;
        policyVersion: number;
      }>;
    }>();
    expect(inboxBody.conflicts).toContainEqual(expect.objectContaining({
      id: conflictID,
      affectedFields: ["phone"],
      policyVersion: 1,
    }));
    expect(inboxBody.conflicts[0].operationalImpact)
      .toContain("shared company information");

    const newerCloudChange = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision: cloudRevision,
      mutationKind: "fieldPatch", changedFields: ["phone"],
      baseRecord: cloudRecord, record: { ...cloudRecord, phone: "444" },
      sequenceNumber: 3,
    });
    expect(newerCloudChange.status).toBe(201);
    const staleReview = await worker.fetch(
      request(owner, `/v1/sync/conflicts/${conflictID}/resolve`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          resolution: "keptCloud",
          reason: "The current customer phone number was verified.",
          affectedFields: ["phone"],
        }),
      }),
      env,
    );
    expect(staleReview.status).toBe(409);
    await expect(staleReview.json()).resolves.toMatchObject({
      error: "conflict_changed_since_review",
    });

    const resolved = await worker.fetch(
      request(owner, `/v1/sync/conflicts/${conflictID}/resolve`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          resolution: "keptCloud",
          reason: "The current customer phone number was verified.",
          affectedFields: ["name", "phone"],
        }),
      }),
      env,
    );
    expect(resolved.status).toBe(200);
    await expect(resolved.json()).resolves.toMatchObject({
      id: conflictID,
      resolution: "keptCloud",
      affectedFields: ["phone"],
      policyVersion: 1,
    });
  });

  it("merges nested assignment history as append-only facts", async () => {
    const owner = await seedIdentity("Append History Owner");
    const secondDevice = await seedAdditionalDevice(owner, "Append History iPad");
    const entityID = crypto.randomUUID();
    const firstEvent = { id: crypto.randomUUID(), type: "created" };
    const cloudEvent = { id: crypto.randomUUID(), type: "dispatchNote" };
    const deviceEvent = { id: crypto.randomUUID(), type: "fieldNote" };
    const original = { id: entityID, history: { events: [firstEvent] } };
    const created = await sendVersionedMutation(owner, {
      entityType: "assignment", entityID, baseRevision: null,
      mutationKind: "wholeRecord", changedFields: [], record: original,
      sequenceNumber: 1,
    });
    expect(created.status).toBe(201);
    const baseRevision = (await created.json<{ revision: string }>()).revision;

    const cloudChange = await sendVersionedMutation(owner, {
      entityType: "assignment", entityID, baseRevision,
      mutationKind: "domainCommand", commandName: "assignment.updateNotes",
      changedFields: ["dispatchNotes", "history"], baseRecord: original,
      record: {
        ...original,
        dispatchNotes: "Call first",
        history: { events: [firstEvent, cloudEvent] },
      },
      sequenceNumber: 2,
    });
    expect(cloudChange.status).toBe(201);

    const deviceChange = await sendVersionedMutation(secondDevice, {
      entityType: "assignment", entityID, baseRevision,
      mutationKind: "domainCommand", commandName: "assignment.updateNotes",
      changedFields: ["fieldNotes", "history"], baseRecord: original,
      record: {
        ...original,
        fieldNotes: "Gate was locked",
        history: { events: [firstEvent, deviceEvent] },
      },
      sequenceNumber: 1,
    });
    expect(deviceChange.status).toBe(201);

    const stored = await env.DB.prepare(
      `SELECT operation_json AS operationJSON FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'assignment' AND entity_id = ?2`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{ operationJSON: string }>();
    const operation = JSON.parse(stored!.operationJSON) as { payload: { body: string } };
    const mutation = JSON.parse(Buffer.from(operation.payload.body, "base64")
      .toString("utf8")) as { recordData: string };
    const record = JSON.parse(Buffer.from(mutation.recordData, "base64")
      .toString("utf8")) as {
        dispatchNotes: string;
        fieldNotes: string;
        history: { events: Array<{ id: string }> };
      };
    expect(record.dispatchNotes).toBe("Call first");
    expect(record.fieldNotes).toBe("Gate was locked");
    expect(record.history.events.map((event) => event.id))
      .toEqual([firstEvent.id, cloudEvent.id, deviceEvent.id]);
  });

  it("accepts recurring-work hold scheduling as an authorized domain command", async () => {
    const owner = await seedIdentity("Recurring Work Hold Owner");
    const entityID = crypto.randomUUID();
    const original = {
      id: entityID,
      status: "active",
      heldScheduledDate: null,
    };
    const created = await sendVersionedMutation(owner, {
      entityType: "recurringWork", entityID, baseRevision: null,
      mutationKind: "wholeRecord", changedFields: [], record: original,
      sequenceNumber: 1,
    });
    expect(created.status).toBe(201);
    const baseRevision = (await created.json<{ revision: string }>()).revision;

    const held = await sendVersionedMutation(owner, {
      entityType: "recurringWork", entityID, baseRevision,
      mutationKind: "domainCommand", commandName: "recurringWork.update",
      changedFields: ["heldScheduledDate"], baseRecord: original,
      record: { ...original, heldScheduledDate: "2026-08-24T14:00:00Z" },
      sequenceNumber: 2,
    });

    expect(held.status).toBe(201);
  });

  it("accepts assignment rescheduling with its system-maintained update date", async () => {
    const owner = await seedIdentity("Assignment Reschedule Owner");
    const entityID = crypto.randomUUID();
    const original = {
      id: entityID,
      scheduling: { scheduledStart: "2026-08-24T14:00:00Z" },
      history: { events: [] },
      updatedDate: "2026-08-24T13:00:00Z",
    };
    const created = await sendVersionedMutation(owner, {
      entityType: "assignment", entityID, baseRevision: null,
      mutationKind: "wholeRecord", changedFields: [], record: original,
      sequenceNumber: 1,
    });
    expect(created.status).toBe(201);
    const baseRevision = (await created.json<{ revision: string }>()).revision;

    const rescheduled = await sendVersionedMutation(owner, {
      entityType: "assignment", entityID, baseRevision,
      mutationKind: "domainCommand", commandName: "assignment.reschedule",
      changedFields: ["history", "scheduling", "updatedDate"],
      baseRecord: original,
      record: {
        ...original,
        scheduling: { scheduledStart: "2026-08-25T14:00:00Z" },
        history: { events: [{ id: crypto.randomUUID(), type: "rescheduled" }] },
        updatedDate: "2026-08-24T13:10:05Z",
      },
      sequenceNumber: 2,
    });

    expect(rescheduled.status).toBe(201);
    const quarantine = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM synchronization_quarantines
        WHERE tenant_id = ?1`,
    ).bind(owner.tenantID).first<{ count: number }>();
    expect(quarantine?.count).toBe(0);
  });

  it("unions timeline notes from legacy whole-record job mutations", async () => {
    const owner = await seedIdentity("Timeline Note Owner");
    const technician = await seedAdditionalDevice(owner, "Timeline Note Technician");
    const entityID = crypto.randomUUID();
    const originalEvent = {
      id: crypto.randomUUID(),
      type: "created",
      title: "Job Created",
      timestamp: new Date().toISOString(),
    };
    const ownerNote = {
      id: crypto.randomUUID(),
      type: "technicianNote",
      title: "Owner note",
      timestamp: new Date(Date.now() + 1_000).toISOString(),
    };
    const technicianNote = {
      id: crypto.randomUUID(),
      type: "technicianNote",
      title: "Technician note",
      timestamp: new Date(Date.now() + 2_000).toISOString(),
    };
    const original = { id: entityID, status: "assigned", timelineEvents: [originalEvent] };
    const created = await sendVersionedMutation(owner, {
      entityType: "job",
      entityID,
      baseRevision: null,
      mutationKind: "wholeRecord",
      changedFields: [],
      record: original,
      sequenceNumber: 1,
    });
    expect(created.status).toBe(201);
    const baseRevision = (await created.json<{ revision: string }>()).revision;

    const ownerChange = await sendVersionedMutation(owner, {
      entityType: "job",
      entityID,
      baseRevision,
      mutationKind: "wholeRecord",
      changedFields: [],
      record: { ...original, timelineEvents: [originalEvent, ownerNote] },
      sequenceNumber: 2,
    });
    expect(ownerChange.status).toBe(201);

    const technicianChange = await sendVersionedMutation(technician, {
      entityType: "job",
      entityID,
      baseRevision,
      mutationKind: "wholeRecord",
      changedFields: [],
      record: { ...original, timelineEvents: [originalEvent, technicianNote] },
      sequenceNumber: 1,
    });
    expect(technicianChange.status).toBe(201);

    const stored = await env.DB.prepare(
      `SELECT operation_json AS operationJSON FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'job' AND entity_id = ?2`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{ operationJSON: string }>();
    const operation = JSON.parse(stored!.operationJSON) as {
      metadata?: Record<string, string>;
      payload: { body: string };
    };
    const mutation = JSON.parse(Buffer.from(operation.payload.body, "base64")
      .toString("utf8")) as { recordData: string };
    const record = JSON.parse(Buffer.from(mutation.recordData, "base64")
      .toString("utf8")) as { timelineEvents: Array<{ id: string }> };
    expect(record.timelineEvents.map((event) => event.id))
      .toEqual([originalEvent.id, ownerNote.id, technicianNote.id]);
    expect(operation.metadata?.serverMergePolicy).toBe("appendOnlyUnionV1");
  });

  it("does not apply the unsafe whole-record rebase to Phase 20 mutations", async () => {
    const owner = await seedIdentity("Safe Rebase Owner");
    const entityID = crypto.randomUUID();
    const original = { id: entityID, name: "Original" };
    const created = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision: null,
      mutationKind: "wholeRecord", changedFields: [], record: original,
      sequenceNumber: 1,
    });
    const baseRevision = (await created.json<{ revision: string }>()).revision;
    const second = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision,
      mutationKind: "wholeRecord", changedFields: [],
      baseRecord: original, record: { ...original, name: "Second" },
      sequenceNumber: 2,
    });
    expect(second.status).toBe(201);
    const unsafeSuccessor = await sendVersionedMutation(owner, {
      entityType: "customer", entityID, baseRevision,
      mutationKind: "wholeRecord", changedFields: [],
      baseRecord: original, record: { ...original, name: "Third" },
      sequenceNumber: 3,
    });
    expect(unsafeSuccessor.status).toBe(409);
  });

  it("retains the legacy same-device causal rebase for pre-Phase-20 mutations", async () => {
    const owner = await seedIdentity("Causal Successor Owner");
    const entityID = crypto.randomUUID();
    const send = (
      label: string,
      baseRevision: string | null,
      sequenceNumber: number,
    ) => {
      const operationID = crypto.randomUUID();
      const timestamp = new Date(Date.now() + sequenceNumber * 1_000).toISOString();
      const recordData = Buffer.from(JSON.stringify({
        id: entityID,
        name: label,
      })).toString("base64");
      const mutation = Buffer.from(JSON.stringify({
        schemaVersion: 1,
        operationID,
        entityType: "customer",
        recordID: entityID,
        baseRevision,
        mutationKind: "wholeRecord",
        changedFields: [],
        recordData,
        clientCreatedAt: timestamp,
        deviceModifiedAt: timestamp,
      })).toString("base64");
      return worker.fetch(request(owner, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: operationID,
          idempotencyKey: `causal-${crypto.randomUUID()}`,
          sequenceNumber,
          type: "recordMutation",
          entityType: "customer",
          entityID,
          actionName: "upsertRecord",
          baseRevision,
          payload: { schemaVersion: 1, contentType: "application/json", body: mutation },
          createdAt: timestamp,
        }),
      }), env);
    };

    const first = await send("created", null, 1);
    expect(first.status).toBe(201);
    const firstRevision = (await first.json<{ revision: string }>()).revision;
    const second = await send("scheduled", firstRevision, 2);
    expect(second.status).toBe(201);
    const secondRevision = (await second.json<{ revision: string }>()).revision;

    // This operation was already queued behind sequence 2 and therefore still
    // carries sequence 2's original base. It is causally newer, not concurrent.
    const third = await send("workflow-updated", firstRevision, 3);
    expect(third.status).toBe(201);
    const thirdBody = await third.json<{ revision: string }>();
    expect(thirdBody.revision).not.toBe(secondRevision);

    const stored = await env.DB.prepare(
      `SELECT operation_json AS operationJSON FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?2`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{ operationJSON: string }>();
    const operation = JSON.parse(stored!.operationJSON) as {
      baseRevision: string;
      sequenceNumber: number;
      metadata: { serverMergePolicy: string };
      payload: { body: string };
    };
    const mutation = JSON.parse(Buffer.from(operation.payload.body, "base64")
      .toString("utf8")) as { baseRevision: string; recordData: string };
    const record = JSON.parse(Buffer.from(mutation.recordData, "base64")
      .toString("utf8")) as { name: string };
    expect(operation.baseRevision).toBe(secondRevision);
    expect(mutation.baseRevision).toBe(secondRevision);
    expect(operation.sequenceNumber).toBe(3);
    expect(operation.metadata.serverMergePolicy).toBe("sameDeviceCausalSuccessorV1");
    expect(record.name).toBe("workflow-updated");
  });

  it("automatically keeps cloud data when a device change is over eight hours stale", async () => {
    const owner = await seedIdentity("Stale Window Owner");
    const staleDevice = await seedAdditionalDevice(owner, "Week Offline iPad");
    const entityID = crypto.randomUUID();
    const send = (
      identity: SeededIdentity,
      label: string,
      baseRevision: string | null,
      createdAt: string,
    ) => worker.fetch(request(identity, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        id: crypto.randomUUID(),
        idempotencyKey: `stale-window-${crypto.randomUUID()}`,
        type: "recordMutation",
        entityType: "customer",
        entityID,
        actionName: "upsertRecord",
        baseRevision,
        payload: { schemaVersion: 1, contentType: "test", body: label },
        createdAt,
      }),
    }), env);

    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const first = await send(owner, "original", null, weekAgo);
    const firstRevision = (await first.json<{ revision: string }>()).revision;
    const current = await send(
      owner,
      "current cloud value",
      firstRevision,
      new Date().toISOString(),
    );
    const currentRevision = (await current.json<{ revision: string }>()).revision;

    const stale = await send(staleDevice, "obsolete iPad value", firstRevision, weekAgo);
    expect(stale.status).toBe(200);
    const receipt = await stale.json<{
      revision: string;
      supersededByCloud: boolean;
      currentOperation: { payload: { body: string } };
    }>();
    expect(receipt.supersededByCloud).toBe(true);
    expect(receipt.revision).toBe(currentRevision);
    expect(receipt.currentOperation.payload.body).toBe("current cloud value");

    const accepted = await env.DB.prepare(
      `SELECT operation_json AS operationJSON
         FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?2`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{
      operationJSON: string;
    }>();
    expect(JSON.parse(accepted!.operationJSON).payload.body)
      .toBe("current cloud value");

    const unresolved = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM synchronization_conflicts
        WHERE tenant_id = ?1 AND entity_id = ?2 AND status = 'unresolved'`,
    ).bind(owner.tenantID, entityID.toLowerCase()).first<{ count: number }>();
    expect(Number(unresolved?.count ?? 0)).toBe(0);
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

    const canonicalEmployeeID = crypto.randomUUID();
    await seedEmployeeRecord(alphaOwner, canonicalEmployeeID, ["Technician"]);
    const alphaBaseline = await worker.fetch(
      request(alphaMember, "/v1/sync/baseline-records"),
      env,
    );
    expect(alphaBaseline.status).toBe(200);
    const alphaBaselineBody = await alphaBaseline.json<{
      cursor: number;
      records: Array<{
        revision: string;
        operation: { entityType?: string; entityID?: string; status?: string };
      }>;
    }>();
    expect(alphaBaselineBody.records).toHaveLength(1);
    expect(alphaBaselineBody.records[0]?.operation).toMatchObject({
      entityType: "employee",
      entityID: canonicalEmployeeID,
      status: "synchronized",
    });

    const bravoBaseline = await worker.fetch(
      request(bravoOwner, "/v1/sync/baseline-records"),
      env,
    );
    expect((await bravoBaseline.json<{ records: unknown[] }>()).records).toHaveLength(0);

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

  it("stores redacted tenant-scoped sync diagnostics with audited access", async () => {
    const owner = await seedIdentity("Diagnostic Owner");
    const member = await seedMemberInTenant(owner, "Diagnostic Technician");
    const otherMember = await seedMemberInTenant(owner, "Other Technician");
    const outsider = await seedIdentity("Diagnostic Outsider");
    const operationID = crypto.randomUUID();
    const response = await worker.fetch(request(
      member,
      "/v1/support/sync-diagnostics",
      {
        method: "POST",
        headers: {
          "content-type": "application/vnd.pfss.sync-diagnostics+json",
        },
        body: JSON.stringify({
          schemaVersion: 1,
          generatedAt: new Date().toISOString(),
          description: "Assignment synchronization failed after field work.",
          app: { version: "1.0", build: "20.7.1" },
          device: {
            model: "iPad",
            systemName: "iPadOS",
            systemVersion: "26.5",
          },
          synchronization: {
            cursor: 42,
            connectivity: "online",
            cloudAccessStatus: "available",
          },
          inventory: {
            customers: 16,
            sites: 15,
            leads: 8,
            estimates: 1,
            jobs: 46,
            invoices: 11,
            employees: 3,
            catalogItems: 8,
            recurringWorkTemplates: 3,
            assignments: 151,
          },
          operations: [{
            operationID,
            entityType: "assignment",
            recordID: crypto.randomUUID(),
            status: "failed",
            failure: {
              category: "validation",
              code: "invalid_domain_command",
              isRetryable: false,
              occurredAt: new Date().toISOString(),
            },
            payload: { customerName: "Must Never Be Stored", body: "secret" },
          }],
        }),
      },
    ), env);
    expect(response.status).toBe(201);
    const submitted = await response.json<{
      caseCode: string; submittedAt: string; expiresAt: string;
    }>();
    expect(submitted.caseCode).toMatch(/^PFSS-[A-Z2-9]{4}-[A-Z2-9]{4}$/);

    const row = await env.DB.prepare(
      `SELECT tenant_id AS tenantID, source_member_id AS sourceMemberID,
              source_device_id AS sourceDeviceID, object_key AS objectKey
         FROM synchronization_diagnostics WHERE case_code = ?1`,
    ).bind(submitted.caseCode).first<{
      tenantID: string; sourceMemberID: string; sourceDeviceID: string;
      objectKey: string;
    }>();
    expect(row).toMatchObject({
      tenantID: member.tenantID,
      sourceMemberID: member.memberID,
      sourceDeviceID: member.deviceID,
    });
    const stored = await env.ARCHIVES.get(row!.objectKey);
    const storedText = await stored!.text();
    expect(storedText).not.toContain("Must Never Be Stored");
    expect(storedText).not.toContain('"payload"');
    expect(JSON.parse(storedText)).toMatchObject({
      header: {
        caseCode: submitted.caseCode,
        tenantID: member.tenantID,
        sourceMemberID: member.memberID,
        sourceDeviceID: member.deviceID,
      },
      diagnostic: {
        app: { version: "1.0", build: "20.7.1" },
        inventory: { catalogItems: 8, assignments: 151 },
        operations: [{ operationID, status: "failed" }],
      },
    });

    expect((await worker.fetch(
      request(member, `/v1/support/sync-diagnostics/${submitted.caseCode}`), env,
    )).status).toBe(200);
    expect((await worker.fetch(
      request(otherMember, `/v1/support/sync-diagnostics/${submitted.caseCode}`), env,
    )).status).toBe(403);
    expect((await worker.fetch(
      request(outsider, `/v1/support/sync-diagnostics/${submitted.caseCode}`), env,
    )).status).toBe(404);
    expect((await worker.fetch(
      request(member, `/v1/support/sync-diagnostics/${submitted.caseCode}`, {
        method: "DELETE",
      }), env,
    )).status).toBe(403);
    expect((await worker.fetch(
      request(owner, `/v1/support/sync-diagnostics/${submitted.caseCode}`, {
        method: "DELETE",
      }), env,
    )).status).toBe(200);
    expect(await env.ARCHIVES.get(row!.objectKey)).toBeNull();

    const audit = await env.DB.prepare(
      `SELECT event_type AS eventType FROM access_audit_events
        WHERE tenant_id = ?1 AND event_type LIKE 'support.sync_diagnostics_%'
        ORDER BY created_at`,
    ).bind(owner.tenantID).all<{ eventType: string }>();
    expect(audit.results.map((event) => event.eventType)).toEqual([
      "support.sync_diagnostics_submitted",
      "support.sync_diagnostics_accessed",
      "support.sync_diagnostics_deleted",
    ]);
  });

  it("centralizes tenant quarantine review and returns an audited source receipt", async () => {
    const owner = await seedIdentity("Quarantine Owner", "owner");
    const member = await seedMemberInTenant(owner, "Quarantine Technician");
    const refreshedMemberDevice = await seedAdditionalDevice(
      member, "Quarantine Technician Refreshed",
    );
    const outsider = await seedIdentity("Quarantine Outsider", "owner");
    const operationID = crypto.randomUUID();
    const entityID = crypto.randomUUID();
    const operation = {
      id: operationID,
      idempotencyKey: `quarantine-${operationID}`,
      type: "recordMutation",
      entityType: "customer",
      entityID,
      actionName: "upsertRecord",
      payload: { schemaVersion: 1, contentType: "test", body: "dGVzdA==" },
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: "failed",
      sequenceNumber: 1,
      retryAttempts: [],
      metadata: { quarantinedAt: new Date().toISOString() },
    };
    const report = await worker.fetch(request(member, "/v1/sync/quarantines/report", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ operation, reason: "Schema validation failed." }),
    }), env);
    expect(report.status).toBe(201);
    const { quarantineID } = await report.json<{ quarantineID: string }>();

    expect((await worker.fetch(
      request(member, "/v1/sync/quarantines"), env,
    )).status).toBe(403);
    const inbox = await worker.fetch(
      request(owner, "/v1/sync/quarantines"), env,
    );
    const inboxBody = await inbox.json<{ quarantines: Array<{
      id: string; operationID: string; failure: { reason: string };
    }> }>();
    expect(inboxBody.quarantines).toHaveLength(1);
    expect(inboxBody.quarantines[0]).toMatchObject({
      id: quarantineID,
      operationID,
      failure: { reason: "Schema validation failed." },
    });
    expect((await (await worker.fetch(
      request(outsider, "/v1/sync/quarantines"), env,
    )).json<{ quarantines: unknown[] }>()).quarantines).toHaveLength(0);

    const resolved = await worker.fetch(request(
      owner,
      `/v1/sync/quarantines/${quarantineID}/resolve`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action: "discard",
          reason: "",
        }),
      },
    ), env);
    expect(resolved.status).toBe(200);
    const duplicate = await worker.fetch(request(
      owner,
      `/v1/sync/quarantines/${quarantineID}/resolve`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action: "discard",
          reason: "Device change was invalid and should be discarded.",
        }),
      },
    ), env);
    expect((await duplicate.json<{ duplicate: boolean }>()).duplicate).toBe(true);

    const receipts = await worker.fetch(
      request(member, "/v1/sync/quarantine-resolutions"), env,
    );
    expect((await receipts.json<{ resolutions: Array<{
      operationID: string; action: string;
    }> }>()).resolutions).toContainEqual(expect.objectContaining({
      operationID,
      action: "discard",
    }));
    const refreshedDeviceReceipts = await worker.fetch(
      request(refreshedMemberDevice, "/v1/sync/quarantine-resolutions"), env,
    );
    expect((await refreshedDeviceReceipts.json<{ resolutions: Array<{
      operationID: string; action: string;
    }> }>()).resolutions).toContainEqual(expect.objectContaining({
      operationID,
      action: "discard",
    }));
    const audit = await env.DB.prepare(
      `SELECT COUNT(*) AS count, MAX(metadata_json) AS metadataJSON
         FROM access_audit_events
        WHERE tenant_id = ?1 AND event_type = 'sync.quarantine_resolved'`,
    ).bind(owner.tenantID).first<{ count: number; metadataJSON: string }>();
    expect(Number(audit?.count ?? 0)).toBe(1);
    expect(JSON.parse(audit?.metadataJSON ?? "{}").reason).toBe(
      "Manager or Owner discarded the device change without an additional note.",
    );

    const rereport = await worker.fetch(request(
      member,
      "/v1/sync/quarantines/report",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operation,
          reason: "The retried operation failed validation again.",
        }),
      },
    ), env);
    expect(rereport.status).toBe(200);
    const reopened = await worker.fetch(
      request(owner, "/v1/sync/quarantines"), env,
    );
    expect((await reopened.json<{ quarantines: Array<{ id: string }> }>()
    ).quarantines).toContainEqual(expect.objectContaining({ id: quarantineID }));

    const replacementID = crypto.randomUUID();
    const replacementMutation = Buffer.from(JSON.stringify({
      entityType: "customer",
      entityID,
      recordData: Buffer.from(JSON.stringify({ id: entityID, name: "Repaired" }))
        .toString("base64"),
      modifiedAt: new Date().toISOString(),
    })).toString("base64");
    const replacement = {
      ...operation,
      id: replacementID,
      idempotencyKey: `repair-${replacementID}`,
      status: "pending",
      payload: { schemaVersion: 1, contentType: "test", body: replacementMutation },
    };
    expect((await worker.fetch(request(owner, "/v1/operations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(replacement),
    }), env)).status).toBe(201);
    const repaired = await worker.fetch(request(
      owner,
      `/v1/sync/quarantines/${quarantineID}/resolve`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action: "repair",
          reason: "Manager corrected and approved the customer record.",
          replacementOperationID: replacementID,
        }),
      },
    ), env);
    expect(repaired.status).toBe(200);
    const repairRow = await env.DB.prepare(
      `SELECT resolution_action AS action,
              replacement_operation_id AS replacementOperationID
         FROM synchronization_quarantines WHERE id = ?1`,
    ).bind(quarantineID).first<{
      action: string; replacementOperationID: string;
    }>();
    expect(repairRow).toEqual({
      action: "repair",
      replacementOperationID: replacementID,
    });
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

  it("creates and links an Owner employee profile with operational roles", async () => {
    const owner = await seedIdentity("Working Owner");
    const response = await worker.fetch(
      request(owner, "/v1/account/owner-work-profile", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ roles: ["salesperson", "technician"] }),
      }),
      env,
    );
    expect(response.status).toBe(201);
    const receipt = await response.json<{ employeeID: string; roles: string[] }>();
    expect(receipt.roles).toEqual(["Salesperson", "Technician"]);

    const member = await env.DB.prepare(
      "SELECT role, employee_id AS employeeID FROM tenant_members WHERE id = ?1",
    ).bind(owner.memberID).first<{ role: string; employeeID: string }>();
    expect(member).toEqual({ role: "owner", employeeID: receipt.employeeID });

    const feed = await worker.fetch(request(owner, "/v1/sync/changes"), env);
    const payload = await feed.json<{ changes: Array<{ operation: any }> }>();
    const mutation = JSON.parse(Buffer.from(
      payload.changes[0].operation.payload.body,
      "base64",
    ).toString());
    const record = JSON.parse(Buffer.from(mutation.recordData, "base64").toString());
    expect(record.roles).toEqual(["Salesperson", "Technician"]);
    expect(record.lifecycleStatus).toBe("Active");
  });

  it("returns the current Owner account entitlement and usage receipt", async () => {
    const owner = await seedIdentity("Entitlement Owner");
    const accountID = crypto.randomUUID();
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO subscription_accounts
          (id, tenant_id, status, created_at, updated_at)
         VALUES (?1, ?2, 'trialing', ?3, ?3)`,
      ).bind(accountID, owner.tenantID, now),
      env.DB.prepare(
        `INSERT INTO plan_allocations
          (id, tenant_id, subscription_account_id, access_source, plan_code,
           entitlements_json, effective_at, created_at)
         VALUES (?1, ?2, ?3, 'appStoreSubscription', 'trial-14-day', ?4, ?5, ?5)`,
      ).bind(crypto.randomUUID(), owner.tenantID, accountID, JSON.stringify({
        userLimit: 2,
        deviceLimit: 4,
        recordLimits: { leads: 5, customers: 5, jobs: 10 },
        modules: ["sales", "service", "dispatch", "reporting"],
      }), now),
    ]);

    const response = await worker.fetch(
      request(owner, "/v1/account/entitlements"),
      env,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      appAccountToken: owner.tenantID.toLowerCase(),
      planCode: "trial-14-day",
      subscriptionStatus: "trialing",
      accessMode: "full",
      usage: {
        users: 1,
        employees: 0,
        devices: 1,
        owners: 1,
        leads: 0,
        customers: 0,
        jobs: 0,
      },
    });
  });

  it("keeps Owner work roles separate from membership authority", async () => {
    const owner = await seedIdentity("Owner Role Boundary");
    const manager = await seedMemberInTenant(owner, "Manager", "manager");
    const forbidden = await worker.fetch(
      request(manager, "/v1/account/owner-work-profile", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ roles: ["technician"] }),
      }),
      env,
    );
    expect(forbidden.status).toBe(403);

    const escalation = await worker.fetch(
      request(owner, "/v1/account/owner-work-profile", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ roles: ["owner"] }),
      }),
      env,
    );
    expect(escalation.status).toBe(400);
  });

  it("signs an existing Owner into a second device and consumes the assertion", async () => {
    const owner = await seedIdentity("Returning Owner");
    const subjectID = crypto.randomUUID();
    const assertion = `pfss_owner_${crypto.randomUUID()}${crypto.randomUUID()}`;
    const now = new Date();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Returning Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now.toISOString()),
      env.DB.prepare(
        `UPDATE tenant_members SET authentication_subject_id = ?1 WHERE id = ?2`,
      ).bind(subjectID, owner.memberID),
      env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', 'returning@example.com', ?3, ?3)`,
      ).bind(crypto.randomUUID(), subjectID, now.toISOString()),
      env.DB.prepare(
        `INSERT INTO owner_authorization_attempts
          (id, state_digest, code_challenge, redirect_uri, status, subject_id,
           identity_assertion_digest, expires_at, created_at, updated_at)
         VALUES (?1, ?2, 'challenge', 'https://pfss.test/callback', 'verified',
                 ?3, ?4, ?5, ?6, ?6)`,
      ).bind(
        crypto.randomUUID(), crypto.randomUUID(), subjectID,
        createHash("sha256").update(assertion).digest("hex"),
        new Date(now.getTime() + 300_000).toISOString(), now.toISOString(),
      ),
    ]);
    const deviceID = crypto.randomUUID();
    const response = await worker.fetch(new Request(
      "https://pfss.test/v1/owner-auth/sign-in",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          identityAssertion: assertion,
          deviceID,
          deviceName: "Second Owner iPad",
        }),
      },
    ), env);
    expect(response.status).toBe(201);
    const receipt = await response.json<{
      tenant: { id: string };
      device: { id: string; deviceToken: string };
    }>();
    expect(receipt.tenant.id).toBe(owner.tenantID);
    expect(receipt.device.id).toBe(deviceID);
    const sessionResponse = await worker.fetch(new Request(
      "https://pfss.test/v1/session",
      { headers: { authorization: `Bearer ${receipt.device.deviceToken}` } },
    ), env);
    expect(sessionResponse.status).toBe(200);
    expect((await sessionResponse.json<{ member: { email: string } }>())
      .member.email).toBe("returning@example.com");

    const replay = await worker.fetch(new Request(
      "https://pfss.test/v1/owner-auth/sign-in",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          identityAssertion: assertion,
          deviceID: crypto.randomUUID(),
          deviceName: "Replay",
        }),
      },
    ), env);
    expect(replay.status).toBe(401);
  });

  it("issues one-time Owner recovery codes and restores a replacement device", async () => {
    const owner = await seedIdentity("Recovery Owner");
    const subjectID = crypto.randomUUID();
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Recovery Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now),
      env.DB.prepare(
        `UPDATE tenant_members SET authentication_subject_id = ?1 WHERE id = ?2`,
      ).bind(subjectID, owner.memberID),
    ]);

    const generated = await worker.fetch(request(
      owner,
      "/v1/account-recovery/codes",
      { method: "POST" },
    ), env);
    expect(generated.status).toBe(201);
    const codeReceipt = await generated.json<{ recoveryCodes: string[] }>();
    expect(codeReceipt.recoveryCodes).toHaveLength(8);
    expect(new Set(codeReceipt.recoveryCodes).size).toBe(8);

    const status = await worker.fetch(request(
      owner,
      "/v1/account-recovery/codes",
    ), env);
    expect(await status.json()).toMatchObject({ availableCodes: 8 });

    const deviceID = crypto.randomUUID();
    const recovered = await worker.fetch(new Request(
      "https://pfss.test/v1/account-recovery/redeem",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          recoveryCode: codeReceipt.recoveryCodes[0].toLowerCase(),
          deviceID,
          deviceName: "Recovered iPad",
        }),
      },
    ), env);
    expect(recovered.status).toBe(201);
    const receipt = await recovered.json<{
      device: { deviceToken: string };
    }>();
    expect((await worker.fetch(new Request(
      "https://pfss.test/v1/session",
      { headers: { authorization: `Bearer ${receipt.device.deviceToken}` } },
    ), env)).status).toBe(200);

    const replay = await worker.fetch(new Request(
      "https://pfss.test/v1/account-recovery/redeem",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          recoveryCode: codeReceipt.recoveryCodes[0],
          deviceID: crypto.randomUUID(),
          deviceName: "Replay",
        }),
      },
    ), env);
    expect(replay.status).toBe(401);

    const audit = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM access_audit_events
        WHERE tenant_id = ?1 AND event_type = 'account.recovered'`,
    ).bind(owner.tenantID).first<{ count: number }>();
    expect(audit?.count).toBe(1);
  });

  it("does not allow non-Owners to replace recovery codes", async () => {
    const member = await seedIdentity("Recovery Member", "member");
    const response = await worker.fetch(request(
      member,
      "/v1/account-recovery/codes",
      { method: "POST" },
    ), env);
    expect(response.status).toBe(403);
  });

  it("verifies an exact invited email before activating a second Owner", async () => {
    const owner = await seedIdentity("Primary Owner");
    const invitationResponse = await worker.fetch(request(
      owner,
      "/v1/owner-invitations",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: "Second Owner",
          email: "second-owner@example.com",
        }),
      },
    ), env);
    expect(invitationResponse.status).toBe(201);
    const invitation = await invitationResponse.json<{
      memberID: string;
      invitationCode: string;
    }>();

    const subjectID = crypto.randomUUID();
    const assertion = `pfss_owner_${crypto.randomUUID()}${crypto.randomUUID()}`;
    const now = new Date();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Second Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now.toISOString()),
      env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', 'second-owner@example.com', ?3, ?3)`,
      ).bind(crypto.randomUUID(), subjectID, now.toISOString()),
      env.DB.prepare(
        `INSERT INTO owner_authorization_attempts
          (id, state_digest, code_challenge, redirect_uri, status, subject_id,
           identity_assertion_digest, expires_at, created_at, updated_at)
         VALUES (?1, ?2, 'challenge', 'https://pfss.test/callback', 'verified',
                 ?3, ?4, ?5, ?6, ?6)`,
      ).bind(
        crypto.randomUUID(), crypto.randomUUID(), subjectID,
        createHash("sha256").update(assertion).digest("hex"),
        new Date(now.getTime() + 300_000).toISOString(), now.toISOString(),
      ),
    ]);
    const deviceID = crypto.randomUUID();
    const accepted = await worker.fetch(new Request(
      "https://pfss.test/v1/owner-invitations/accept",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          invitationCode: invitation.invitationCode,
          identityAssertion: assertion,
          deviceID,
          deviceName: "Second Owner iPhone",
        }),
      },
    ), env);
    expect(accepted.status).toBe(201);
    const membership = await env.DB.prepare(
      `SELECT role, status, authentication_subject_id AS subjectID
         FROM tenant_members WHERE id = ?1`,
    ).bind(invitation.memberID).first<{
      role: string;
      status: string;
      subjectID: string;
    }>();
    expect(membership).toEqual({
      role: "owner",
      status: "active",
      subjectID,
    });

    const replay = await worker.fetch(new Request(
      "https://pfss.test/v1/owner-invitations/accept",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          invitationCode: invitation.invitationCode,
          identityAssertion: assertion,
          deviceID: crypto.randomUUID(),
          deviceName: "Replay",
        }),
      },
    ), env);
    expect(replay.status).toBe(401);

    const revoked = await worker.fetch(request(
      owner,
      `/v1/owner-members/${invitation.memberID}/revoke`,
      { method: "POST" },
    ), env);
    expect(revoked.status).toBe(200);
    const protectedSelf = await worker.fetch(request(
      owner,
      `/v1/owner-members/${owner.memberID}/revoke`,
      { method: "POST" },
    ), env);
    expect(protectedSelf.status).toBe(409);
  });

  it("rejects a verified identity that does not match the Owner invitation", async () => {
    const owner = await seedIdentity("Invitation Mismatch");
    const created = await worker.fetch(request(owner, "/v1/owner-invitations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        displayName: "Expected Owner",
        email: "expected@example.com",
      }),
    }), env);
    const invitation = await created.json<{ invitationCode: string }>();
    const subjectID = crypto.randomUUID();
    const assertion = `pfss_owner_${crypto.randomUUID()}${crypto.randomUUID()}`;
    const now = new Date();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Wrong Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now.toISOString()),
      env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', 'wrong@example.com', ?3, ?3)`,
      ).bind(crypto.randomUUID(), subjectID, now.toISOString()),
      env.DB.prepare(
        `INSERT INTO owner_authorization_attempts
          (id, state_digest, code_challenge, redirect_uri, status, subject_id,
           identity_assertion_digest, expires_at, created_at, updated_at)
         VALUES (?1, ?2, 'challenge', 'https://pfss.test/callback', 'verified',
                 ?3, ?4, ?5, ?6, ?6)`,
      ).bind(crypto.randomUUID(), crypto.randomUUID(), subjectID,
        createHash("sha256").update(assertion).digest("hex"),
        new Date(now.getTime() + 300_000).toISOString(), now.toISOString()),
    ]);
    const response = await worker.fetch(new Request(
      "https://pfss.test/v1/owner-invitations/accept",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          invitationCode: invitation.invitationCode,
          identityAssertion: assertion,
          deviceID: crypto.randomUUID(),
          deviceName: "Wrong Device",
        }),
      },
    ), env);
    expect(response.status).toBe(403);
  });

  it("keeps Operations APIs isolated from company device credentials", async () => {
    const owner = await seedIdentity("Operations Isolation");
    const response = await worker.fetch(request(
      owner,
      "/v1/operations/accounts",
    ), env);
    expect(response.status).toBe(401);
  });

  it("lists accounts and returns tenant-scoped Operations detail", async () => {
    const first = await seedIdentity("Operations Alpha");
    const second = await seedIdentity("Operations Bravo");
    await seedMemberInTenant(first, "Alpha Technician");
    const administrator = await seedOperationsIdentity("Platform Owner");
    const subjectID = crypto.randomUUID();
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Operations Alpha Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now),
      env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', 'alpha.owner@example.com', ?3, ?3)`,
      ).bind(crypto.randomUUID(), subjectID, now),
      env.DB.prepare(
        `UPDATE tenant_members SET authentication_subject_id = ?1
          WHERE tenant_id = ?2 AND id = ?3`,
      ).bind(subjectID, first.tenantID, first.memberID),
    ]);

    const listing = await worker.fetch(operationsRequest(
      administrator,
      "/v1/operations/accounts?search=Operations%20Alpha&status=active",
    ), env);
    expect(listing.status).toBe(200);
    const listBody = await listing.json<{
      accounts: Array<{ id: string; displayName: string; activeUsers: number }>;
    }>();
    expect(listBody.accounts).toHaveLength(1);
    expect(listBody.accounts[0]).toMatchObject({
      id: first.tenantID,
      displayName: "Operations Alpha Business",
      activeUsers: 2,
    });

    const detail = await worker.fetch(operationsRequest(
      administrator,
      `/v1/operations/accounts/${first.tenantID}`,
    ), env);
    expect(detail.status).toBe(200);
    const detailBody = await detail.json<{
      account: { id: string };
      members: Array<{ id: string; email: string | null }>;
      devices: Array<{
        id: string;
        memberID: string;
        memberName: string;
        memberEmail: string | null;
        status: string;
        lastSeenAt: string;
      }>;
    }>();
    expect(detailBody.account.id).toBe(first.tenantID);
    expect(detailBody.members).toHaveLength(2);
    expect(detailBody.devices.length).toBeGreaterThanOrEqual(2);
    expect(detailBody.members.find((member) => member.id === first.memberID)?.email)
      .toBe("alpha.owner@example.com");
    const ownerDevice = detailBody.devices.find(
      (device) => device.memberID === first.memberID,
    );
    expect(ownerDevice).toMatchObject({
      memberName: "Operations Alpha Member",
      memberEmail: "alpha.owner@example.com",
      status: "active",
    });
    expect(ownerDevice?.lastSeenAt).toBeTruthy();
    expect(detailBody.members.some((member) => member.id === second.memberID))
      .toBe(false);
  });

  it("finds every account containing a matching user email", async () => {
    const first = await seedIdentity("Email Search Alpha");
    const second = await seedIdentity("Email Search Bravo");
    const third = await seedIdentity("Email Search Charlie");
    const administrator = await seedOperationsIdentity("Email Search Owner");
    const subjectID = crypto.randomUUID();
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO authentication_subjects
          (id, display_name, status, created_at, updated_at)
         VALUES (?1, 'Shared Owner', 'active', ?2, ?2)`,
      ).bind(subjectID, now),
      env.DB.prepare(
        `INSERT INTO verified_contact_addresses
          (id, subject_id, kind, normalized_value, verified_at, created_at)
         VALUES (?1, ?2, 'email', 'shared.owner@example.com', ?3, ?3)`,
      ).bind(crypto.randomUUID(), subjectID, now),
      env.DB.prepare(
        `UPDATE tenant_members SET authentication_subject_id = ?1
          WHERE id = ?2 AND tenant_id = ?3`,
      ).bind(subjectID, first.memberID, first.tenantID),
      env.DB.prepare(
        `UPDATE tenant_members SET authentication_subject_id = ?1
          WHERE id = ?2 AND tenant_id = ?3`,
      ).bind(subjectID, second.memberID, second.tenantID),
      env.DB.prepare(
        `INSERT INTO operations_account_email_index
          (tenant_id, source_kind, source_id, normalized_email,
           display_name, role_hint, updated_at)
         VALUES (?1, 'employeeRecord', ?2, 'field.tech@example.com',
                 'Field Technician', 'Technician', ?3)`,
      ).bind(third.tenantID, crypto.randomUUID(), now),
    ]);

    const sharedResult = await worker.fetch(operationsRequest(
      administrator,
      "/v1/operations/accounts?search=SHARED.OWNER%40EXAMPLE.COM&status=all",
    ), env);
    expect(sharedResult.status).toBe(200);
    const sharedBody = await sharedResult.json<{
      accounts: Array<{ id: string }>;
    }>();
    expect(sharedBody.accounts.map((account) => account.id).sort())
      .toEqual([first.tenantID, second.tenantID].sort());

    const employeeResult = await worker.fetch(operationsRequest(
      administrator,
      "/v1/operations/accounts?search=field.tech%40example.com&status=all",
    ), env);
    expect(employeeResult.status).toBe(200);
    const employeeBody = await employeeResult.json<{
      accounts: Array<{ id: string }>;
    }>();
    expect(employeeBody.accounts.map((account) => account.id))
      .toEqual([third.tenantID]);
  });

  it("grants an audited, immediately visible Operations plan override", async () => {
    const account = await seedIdentity("Override Target");
    const administrator = await seedOperationsIdentity("Override Owner");
    const expiresAt = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
      .toISOString();
    const response = await worker.fetch(operationsRequest(
      administrator,
      `/v1/operations/accounts/${account.tenantID}/plan-override`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          planCode: "beta",
          reason: "Approved invited beta testing account",
          permanent: false,
          expiresAt,
        }),
      },
    ), env);
    expect(response.status).toBe(201);
    const receipt = await response.json<{
      planCode: string;
      entitlements: { userLimit: number; jobLimit: number };
    }>();
    expect(receipt).toMatchObject({
      planCode: "beta",
      entitlements: { userLimit: 5, jobLimit: 3000 },
    });

    const detail = await worker.fetch(operationsRequest(
      administrator,
      `/v1/operations/accounts/${account.tenantID}`,
    ), env);
    expect(await detail.json()).toMatchObject({
      account: {
        planCode: "beta",
        accessSource: "betaGrant",
        overrideReason: "Approved invited beta testing account",
      },
    });
    const audit = await env.DB.prepare(
      `SELECT event_type AS eventType, reason FROM operations_audit_events
        WHERE target_tenant_id = ?1 AND event_type =
          'operations.plan_override.granted'`,
    ).bind(account.tenantID).first<{ eventType: string; reason: string }>();
    expect(audit).toEqual({
      eventType: "operations.plan_override.granted",
      reason: "Approved invited beta testing account",
    });
  });

  it("rejects plan overrides from support and read-only roles", async () => {
    const account = await seedIdentity("Protected Override Target");
    const support = await seedOperationsIdentity(
      "Support Only", "supportAdministrator",
    );
    const response = await worker.fetch(operationsRequest(
      support,
      `/v1/operations/accounts/${account.tenantID}/plan-override`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          planCode: "pro",
          reason: "Support must not grant billing access",
          permanent: true,
        }),
      },
    ), env);
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({
      error: "operations_plan_override_forbidden",
    });
  });

  it("enforces an audited account hold immediately and restores access", async () => {
    const account = await seedIdentity("Held Account");
    const administrator = await seedOperationsIdentity("Security Owner");
    const hold = await worker.fetch(operationsRequest(
      administrator, `/v1/operations/accounts/${account.tenantID}/hold`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({
          status: "securityHold",
          reason: "Investigating suspicious account access",
          permanent: true,
        }),
      },
    ), env);
    expect(hold.status).toBe(200);
    const blocked = await worker.fetch(request(account, "/v1/session"), env);
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toMatchObject({
      error: "account_access_on_hold",
      hold: { type: "securityHold" },
    });

    const restored = await worker.fetch(operationsRequest(
      administrator, `/v1/operations/accounts/${account.tenantID}/reactivate`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ reason: "Security review completed successfully" }),
      },
    ), env);
    expect(restored.status).toBe(200);
    expect((await worker.fetch(request(account, "/v1/session"), env)).status)
      .toBe(200);
    const events = await env.DB.prepare(
      `SELECT action FROM operations_account_lifecycle_events
        WHERE tenant_id = ?1 ORDER BY created_at`,
    ).bind(account.tenantID).all<{ action: string }>();
    expect(events.results.map((event) => event.action))
      .toEqual(["hold", "reactivate"]);
  });

  it("restricts billing and support holds to their authorized roles", async () => {
    const account = await seedIdentity("Role Matrix Account");
    const billing = await seedOperationsIdentity(
      "Billing Admin", "billingAdministrator",
    );
    const support = await seedOperationsIdentity(
      "Support Admin", "supportAdministrator",
    );
    const apply = (administrator: SeededOperationsIdentity, status: string) =>
      worker.fetch(operationsRequest(
        administrator, `/v1/operations/accounts/${account.tenantID}/hold`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({
            status, reason: "Authorized operational hold reason", permanent: true,
          }),
        },
      ), env);
    expect((await apply(billing, "billingHold")).status).toBe(200);
    expect((await apply(billing, "securityHold")).status).toBe(403);
    expect((await apply(support, "supportHold")).status).toBe(200);
    expect((await apply(support, "billingHold")).status).toBe(403);
  });

  it("returns a read-only platform summary to an authorized auditor", async () => {
    await seedIdentity("Operations Summary");
    const auditor = await seedOperationsIdentity(
      "Read Only Auditor",
      "readOnlyAuditor",
    );
    const response = await worker.fetch(operationsRequest(
      auditor,
      "/v1/operations/summary",
    ), env);
    expect(response.status).toBe(200);
    const summary = await response.json<{
      accounts: { total: number };
      users: { active: number };
      devices: { active: number };
    }>();
    expect(summary.accounts.total).toBeGreaterThan(0);
    expect(summary.users.active).toBeGreaterThan(0);
    expect(summary.devices.active).toBeGreaterThan(0);
  });
});
