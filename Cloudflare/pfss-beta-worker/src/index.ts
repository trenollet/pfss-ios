interface Env {
  DB: D1Database;
  ARCHIVES: R2Bucket;
}

type TenantRole = "owner" | "manager" | "member";

interface DeviceIdentity {
  tenantID: string;
  tenantName: string;
  memberID: string;
  employeeID: string | null;
  memberName: string;
  role: TenantRole;
  memberStatus: "invited" | "active" | "suspended" | "revoked";
  deviceID: string;
  deviceName: string;
  revokedAt: string | null;
  dataRemovalRequiredAt: string | null;
  dataRemovalAcknowledgedAt: string | null;
  tenantStatus: string;
}

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };
const archiveMediaType = "application/vnd.pfss.archive+json";

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: jsonHeaders });
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function bearer(request: Request): string | null {
  const authorization = request.headers.get("authorization") ?? "";
  return authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : null;
}

function canManageMembers(identity: DeviceIdentity): boolean {
  return identity.role === "owner" || identity.role === "manager";
}

function canResolveConflicts(identity: DeviceIdentity): boolean {
  return identity.role === "owner" || identity.role === "manager";
}

async function recordSynchronizationConflict(
  env: Env,
  identity: DeviceIdentity,
  operation: Record<string, unknown>,
  entityType: string,
  entityID: string,
  currentRevision: string,
  currentOperation: Record<string, unknown>,
): Promise<string> {
  const existing = await env.DB.prepare(
    `SELECT id FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND source_device_id = ?2
        AND entity_type = ?3 AND entity_id = ?4 AND status = 'unresolved'`,
  ).bind(
    identity.tenantID, identity.deviceID, entityType, entityID,
  ).first<{ id: string }>();
  const conflictID = existing?.id ?? crypto.randomUUID();
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO synchronization_conflicts
      (id, tenant_id, entity_type, entity_id, source_member_id,
       source_device_id, local_operation_json, cloud_operation_json,
       cloud_revision, status, detected_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'unresolved', ?10)
     ON CONFLICT(id) DO UPDATE SET
       local_operation_json = excluded.local_operation_json,
       cloud_operation_json = excluded.cloud_operation_json,
       cloud_revision = excluded.cloud_revision`,
  ).bind(
    conflictID, identity.tenantID, entityType, entityID,
    identity.memberID, identity.deviceID, JSON.stringify(operation),
    JSON.stringify(currentOperation), currentRevision, now,
  ).run();
  return conflictID;
}

async function listSynchronizationConflicts(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canResolveConflicts(identity)) return json({ error: "forbidden" }, 403);
  const result = await env.DB.prepare(
    `SELECT id, entity_type AS entityType, entity_id AS entityID,
            source_member_id AS sourceMemberID,
            source_device_id AS sourceDeviceID,
            local_operation_json AS localOperationJSON,
            cloud_operation_json AS cloudOperationJSON,
            cloud_revision AS cloudRevision, detected_at AS detectedAt
       FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND status = 'unresolved'
      ORDER BY detected_at ASC`,
  ).bind(identity.tenantID).all<{
    id: string;
    entityType: string;
    entityID: string;
    sourceMemberID: string;
    sourceDeviceID: string;
    localOperationJSON: string;
    cloudOperationJSON: string;
    cloudRevision: string;
    detectedAt: string;
  }>();
  return json({ conflicts: result.results.map((row) => ({
    id: row.id,
    entityType: row.entityType,
    entityID: row.entityID,
    sourceMemberID: row.sourceMemberID,
    sourceDeviceID: row.sourceDeviceID,
    localOperation: JSON.parse(row.localOperationJSON),
    cloudOperation: JSON.parse(row.cloudOperationJSON),
    cloudRevision: row.cloudRevision,
    detectedAt: row.detectedAt,
  })) });
}

async function listSourceConflictResolutions(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const result = await env.DB.prepare(
    `SELECT id, status AS resolution, resolved_at AS resolvedAt
       FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND source_device_id = ?2
        AND status IN ('keptCloud', 'keptDevice')
      ORDER BY resolved_at ASC`,
  ).bind(identity.tenantID, identity.deviceID).all<{
    id: string;
    resolution: "keptCloud" | "keptDevice";
    resolvedAt: string;
  }>();
  return json({ resolutions: result.results });
}

async function listConflictAudit(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  const result = await env.DB.prepare(
    `SELECT synchronization_conflicts.id,
            synchronization_conflicts.entity_type AS entityType,
            synchronization_conflicts.entity_id AS entityID,
            synchronization_conflicts.status AS resolution,
            synchronization_conflicts.detected_at AS detectedAt,
            synchronization_conflicts.resolved_at AS resolvedAt,
            synchronization_conflicts.resolver_role AS resolverRole,
            synchronization_conflicts.resolution_reason AS reason,
            synchronization_conflicts.affected_fields_json AS fieldsJSON,
            synchronization_conflicts.local_operation_json AS localOperationJSON,
            synchronization_conflicts.cloud_operation_json AS cloudOperationJSON,
            synchronization_conflicts.cloud_revision AS originalCloudRevision,
            synchronization_conflicts.final_revision AS finalRevision,
            tenant_members.display_name AS resolverName
       FROM synchronization_conflicts
       LEFT JOIN tenant_members
         ON tenant_members.tenant_id = synchronization_conflicts.tenant_id
        AND tenant_members.id = synchronization_conflicts.resolved_by_member_id
      WHERE synchronization_conflicts.tenant_id = ?1
        AND synchronization_conflicts.status IN ('keptCloud', 'keptDevice')
      ORDER BY synchronization_conflicts.resolved_at DESC
      LIMIT 200`,
  ).bind(identity.tenantID).all<{
    id: string;
    entityType: string;
    entityID: string;
    resolution: string;
    detectedAt: string;
    resolvedAt: string;
    resolverRole: string | null;
    reason: string | null;
    fieldsJSON: string;
    localOperationJSON: string;
    cloudOperationJSON: string;
    originalCloudRevision: string;
    finalRevision: string | null;
    resolverName: string | null;
  }>();
  return json({ events: result.results.map((row) => ({
    id: row.id,
    entityType: row.entityType,
    entityID: row.entityID,
    resolution: row.resolution,
    detectedAt: row.detectedAt,
    resolvedAt: row.resolvedAt,
    resolverRole: row.resolverRole,
    resolverName: row.resolverName ?? "Unknown authorized user",
    reason: row.reason,
    affectedFields: JSON.parse(row.fieldsJSON),
    localOperation: JSON.parse(row.localOperationJSON),
    cloudOperation: JSON.parse(row.cloudOperationJSON),
    originalCloudRevision: row.originalCloudRevision,
    finalRevision: row.finalRevision ?? row.originalCloudRevision,
  })) });
}

async function reportSynchronizationConflict(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const body = await request.json<{
    operation?: Record<string, unknown>;
  }>();
  const operation = body.operation;
  if (!operation) {
    return json({ error: "invalid_conflict_report" }, 400);
  }
  const entityType = String(operation.entityType ?? "");
  const entityID = String(operation.entityID ?? "").toLowerCase();
  if (!entityType || !entityID) {
    return json({ error: "invalid_conflict_report" }, 400);
  }
  const current = await env.DB.prepare(
    `SELECT revision, operation_json AS operationJSON
       FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
  ).bind(identity.tenantID, entityType, entityID).first<{
    revision: string;
    operationJSON: string;
  }>();
  if (!current) {
    return json({ error: "conflict_report_record_missing" }, 409);
  }
  const baseRevision = operation.baseRevision == null
    ? null
    : String(operation.baseRevision);
  if (baseRevision === current.revision) {
    return json({ error: "conflict_report_not_stale" }, 409);
  }
  const conflictID = await recordSynchronizationConflict(
    env, identity, operation, entityType, entityID,
    current.revision, JSON.parse(current.operationJSON),
  );
  return json({ conflictID }, 201);
}

async function resolveSynchronizationConflict(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
  conflictID: string,
): Promise<Response> {
  if (!canResolveConflicts(identity)) return json({ error: "forbidden" }, 403);
  const body = await request.json<{
    resolution?: string;
    reason?: string;
    affectedFields?: string[];
  }>();
  if (body.resolution !== "keptCloud" && body.resolution !== "keptDevice") {
    return json({ error: "invalid_conflict_resolution" }, 400);
  }
  const conflict = await env.DB.prepare(
    `SELECT local_operation_json AS localOperationJSON,
            cloud_operation_json AS cloudOperationJSON,
            cloud_revision AS cloudRevision
       FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND id = ?2 AND status = 'unresolved'`,
  ).bind(identity.tenantID, conflictID).first<{
    localOperationJSON: string;
    cloudOperationJSON: string;
    cloudRevision: string;
  }>();
  if (!conflict) return json({ error: "conflict_not_found" }, 404);

  let finalRevision = conflict.cloudRevision;
  if (body.resolution === "keptDevice") {
    const operation = JSON.parse(conflict.localOperationJSON) as
      Record<string, unknown>;
    operation.id = crypto.randomUUID();
    operation.idempotencyKey = `conflict-resolution-${conflictID}`;
    operation.baseRevision = conflict.cloudRevision;
    operation.metadata = {
      ...(operation.metadata && typeof operation.metadata === "object"
        ? operation.metadata as Record<string, unknown>
        : {}),
      conflictResolution: "keptLocal",
      serverConflictID: conflictID,
    };
    const accepted = await acceptOperation(
      new Request("https://pfss.internal/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(operation),
      }),
      env,
      identity,
    );
    if (!accepted.ok) return accepted;
    finalRevision = (await accepted.json<{ revision: string }>()).revision;
  } else {
    const receipt = JSON.parse(conflict.cloudOperationJSON) as
      Record<string, unknown>;
    const receiptID = crypto.randomUUID();
    const receiptKey = `conflict-resolution-${conflictID}`;
    receipt.id = receiptID;
    receipt.idempotencyKey = receiptKey;
    receipt.metadata = {
      ...(receipt.metadata && typeof receipt.metadata === "object"
        ? receipt.metadata as Record<string, unknown>
        : {}),
      conflictResolution: "keptRemote",
      serverConflictID: conflictID,
    };
    await env.DB.prepare(
      `INSERT INTO synchronized_operations
        (id, tenant_id, device_id, idempotency_key, operation_type,
         entity_type, entity_id, action_name, payload_json, created_at,
         accepted_at, revision)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10, ?11)`,
    ).bind(
      receiptID, identity.tenantID, identity.deviceID, receiptKey,
      String(receipt.type ?? "recordMutation"),
      String(receipt.entityType ?? "custom"),
      receipt.entityID ? String(receipt.entityID) : null,
      String(receipt.actionName ?? "upsertRecord"),
      JSON.stringify(receipt), new Date().toISOString(),
      conflict.cloudRevision,
    ).run();
  }

  const now = new Date().toISOString();
  const result = await env.DB.prepare(
    `UPDATE synchronization_conflicts
        SET status = ?1, resolved_at = ?2,
            resolved_by_member_id = ?3, resolved_by_device_id = ?4,
            resolver_role = ?5, resolution_reason = ?6,
            affected_fields_json = ?7, final_revision = ?8
      WHERE tenant_id = ?9 AND id = ?10 AND status = 'unresolved'`,
  ).bind(
    body.resolution, now, identity.memberID, identity.deviceID,
    identity.role, body.reason?.trim().slice(0, 500) || null,
    JSON.stringify((body.affectedFields ?? []).slice(0, 100)),
    finalRevision, identity.tenantID, conflictID,
  ).run();
  if (result.meta.changes !== 1) {
    return json({ error: "conflict_not_found" }, 404);
  }
  await accessAuditStatement(env, identity.tenantID, "sync.conflict_resolved", {
    actorMemberID: identity.memberID,
    actorDeviceID: identity.deviceID,
    metadata: {
      conflictID,
      resolution: body.resolution,
      resolverRole: identity.role,
      affectedFields: JSON.stringify(body.affectedFields ?? []),
      finalRevision,
      reason: body.reason?.trim().slice(0, 500) ?? "",
    },
    createdAt: now,
  }).run();
  return json({ id: conflictID, resolution: body.resolution, resolvedAt: now });
}

function accessAuditStatement(
  env: Env,
  tenantID: string,
  eventType: string,
  options: {
    actorMemberID?: string | null;
    actorDeviceID?: string | null;
    targetMemberID?: string | null;
    targetDeviceID?: string | null;
    metadata?: Record<string, string>;
    createdAt?: string;
  } = {},
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO access_audit_events
      (id, tenant_id, actor_member_id, actor_device_id, event_type,
       target_member_id, target_device_id, metadata_json, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
  ).bind(
    crypto.randomUUID(),
    tenantID,
    options.actorMemberID ?? null,
    options.actorDeviceID ?? null,
    eventType,
    options.targetMemberID ?? null,
    options.targetDeviceID ?? null,
    JSON.stringify(options.metadata ?? {}),
    options.createdAt ?? new Date().toISOString(),
  );
}

const recoveryAuditEvents = new Set([
  "recovery.archive_created",
  "recovery.external_backup",
  "recovery.archive_imported",
  "recovery.archive_restored",
  "recovery.local_data_cleared",
]);

const recoveryAuditProviders = new Set([
  "localFile", "localHistory", "iCloud", "googleDrive", "pfssCloud",
]);

async function recordRecoveryAudit(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  const body = await request.json<{
    eventType?: string;
    provider?: string;
  }>();
  if (!body.eventType || !recoveryAuditEvents.has(body.eventType)) {
    return json({ error: "invalid_event_type" }, 400);
  }
  if (body.provider && !recoveryAuditProviders.has(body.provider)) {
    return json({ error: "invalid_provider" }, 400);
  }
  const createdAt = new Date().toISOString();
  await accessAuditStatement(env, identity.tenantID, body.eventType, {
    actorMemberID: identity.memberID,
    actorDeviceID: identity.deviceID,
    metadata: body.provider ? { provider: body.provider } : {},
    createdAt,
  }).run();
  return json({ recordedAt: createdAt }, 201);
}

function canManageTarget(
  identity: DeviceIdentity,
  targetRole: TenantRole,
): boolean {
  if (targetRole === "owner") return false;
  return identity.role === "owner" ||
    (identity.role === "manager" && targetRole === "member");
}

async function authenticate(
  request: Request,
  env: Env,
): Promise<DeviceIdentity | Response> {
  const token = bearer(request);
  if (!token) return json({ error: "unauthorized" }, 401);
  const tokenHash = await sha256(token);
  const device = await env.DB.prepare(
    `SELECT devices.tenant_id AS tenantID,
            tenants.display_name AS tenantName,
            devices.member_id AS memberID,
            tenant_members.employee_id AS employeeID,
            tenant_members.display_name AS memberName,
            tenant_members.role AS role,
            tenant_members.status AS memberStatus,
            devices.id AS deviceID,
            devices.display_name AS deviceName,
            devices.revoked_at AS revokedAt,
            devices.data_removal_required_at AS dataRemovalRequiredAt,
            devices.data_removal_acknowledged_at AS dataRemovalAcknowledgedAt,
            tenants.status AS tenantStatus
       FROM devices
       JOIN tenants ON tenants.id = devices.tenant_id
       JOIN tenant_members
         ON tenant_members.id = devices.member_id
        AND tenant_members.tenant_id = devices.tenant_id
      WHERE devices.token_hash = ?1`,
  ).bind(tokenHash).first<DeviceIdentity>();
  if (!device) return json({ error: "unauthorized" }, 401);
  const removalIssuedAt = device.dataRemovalRequiredAt ?? device.revokedAt;
  if (removalIssuedAt && !device.dataRemovalAcknowledgedAt) {
    return json({
      error: "company_data_removal_required",
      directive: {
        type: "remove_company_data",
        tenantID: device.tenantID,
        deviceID: device.deviceID,
        issuedAt: removalIssuedAt,
      },
    }, 403);
  }
  if (
    device.revokedAt || device.memberStatus === "revoked" ||
    device.tenantStatus !== "active"
  ) {
    return json({ error: "unauthorized" }, 401);
  }
  if (device.memberStatus === "suspended") {
    return json({ error: "access_suspended" }, 403);
  }
  if (device.memberStatus !== "active") {
    return json({ error: "unauthorized" }, 401);
  }
  await env.DB.prepare(
    "UPDATE devices SET last_seen_at = ?1 WHERE tenant_id = ?2 AND id = ?3",
  ).bind(new Date().toISOString(), device.tenantID, device.deviceID).run();
  return device;
}

async function acknowledgeCompanyDataRemoval(
  request: Request,
  env: Env,
): Promise<Response> {
  const token = bearer(request);
  if (!token) return json({ error: "unauthorized" }, 401);
  const tokenHash = await sha256(token);
  const device = await env.DB.prepare(
    `SELECT tenant_id AS tenantID, member_id AS memberID, id AS deviceID,
            data_removal_required_at AS requiredAt,
            data_removal_acknowledged_at AS acknowledgedAt
       FROM devices
      WHERE token_hash = ?1`,
  ).bind(tokenHash).first<{
    tenantID: string;
    memberID: string;
    deviceID: string;
    requiredAt: string | null;
    acknowledgedAt: string | null;
  }>();
  if (!device?.requiredAt) return json({ error: "unauthorized" }, 401);
  if (device.acknowledgedAt) return json({ acknowledged: true });

  const acknowledgedAt = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE devices SET data_removal_acknowledged_at = ?1
        WHERE tenant_id = ?2 AND id = ?3
          AND data_removal_required_at IS NOT NULL
          AND data_removal_acknowledged_at IS NULL`,
    ).bind(acknowledgedAt, device.tenantID, device.deviceID),
    accessAuditStatement(env, device.tenantID, "device.data_removed", {
      actorMemberID: device.memberID,
      actorDeviceID: device.deviceID,
      targetMemberID: device.memberID,
      targetDeviceID: device.deviceID,
      metadata: { removalRequiredAt: device.requiredAt },
      createdAt: acknowledgedAt,
    }),
  ]);
  return json({ acknowledged: true, acknowledgedAt });
}

async function enroll(request: Request, env: Env): Promise<Response> {
  const body = await request.json<{
    enrollmentCode?: string;
    deviceID?: string;
    deviceName?: string;
  }>();
  if (!body.enrollmentCode || !body.deviceID || !body.deviceName) {
    return json({ error: "invalid_enrollment_request" }, 400);
  }
  const codeHash = await sha256(body.enrollmentCode.trim());
  const now = new Date().toISOString();
  const code = await env.DB.prepare(
    `SELECT enrollment_codes.tenant_id AS tenantID,
            enrollment_codes.member_id AS memberID
       FROM enrollment_codes
       JOIN tenants ON tenants.id = enrollment_codes.tenant_id
       JOIN tenant_members
         ON tenant_members.id = enrollment_codes.member_id
        AND tenant_members.tenant_id = enrollment_codes.tenant_id
      WHERE enrollment_codes.code_hash = ?1
        AND enrollment_codes.redeemed_at IS NULL
        AND enrollment_codes.expires_at > ?2
        AND tenants.status = 'active'
        AND tenant_members.status IN ('invited', 'active')`,
  ).bind(codeHash, now).first<{ tenantID: string; memberID: string }>();
  if (!code) return json({ error: "invalid_or_expired_enrollment_code" }, 403);

  const existingDevice = await env.DB.prepare(
    `SELECT 1 FROM devices WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(code.tenantID, body.deviceID).first();
  if (existingDevice) {
    return json({ error: "device_identifier_in_use" }, 409);
  }

  const deviceToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const tokenHash = await sha256(deviceToken);
  const [inserted] = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO devices
        (id, tenant_id, member_id, display_name, token_hash, created_at, last_seen_at)
       SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?6
         FROM enrollment_codes
        WHERE code_hash = ?7 AND redeemed_at IS NULL`,
    ).bind(
      body.deviceID,
      code.tenantID,
      code.memberID,
      body.deviceName.trim().slice(0, 100),
      tokenHash,
      now,
      codeHash,
    ),
    env.DB.prepare(
      `UPDATE enrollment_codes SET redeemed_at = ?1
        WHERE code_hash = ?2 AND redeemed_at IS NULL
          AND EXISTS (
            SELECT 1 FROM devices
             WHERE tenant_id = ?3 AND id = ?4 AND token_hash = ?5
          )`,
    ).bind(now, codeHash, code.tenantID, body.deviceID, tokenHash),
    env.DB.prepare(
      `UPDATE tenant_members
          SET status = 'active', activated_at = COALESCE(activated_at, ?1)
        WHERE tenant_id = ?2 AND id = ?3
          AND status IN ('invited', 'active')
          AND EXISTS (
            SELECT 1 FROM devices
             WHERE tenant_id = ?2 AND id = ?4 AND token_hash = ?5
          )`,
    ).bind(now, code.tenantID, code.memberID, body.deviceID, tokenHash),
    env.DB.prepare(
      `INSERT INTO access_audit_events
        (id, tenant_id, actor_member_id, actor_device_id, event_type,
         target_member_id, target_device_id, metadata_json, created_at)
       SELECT ?1, ?2, ?3, ?4, 'device.enrolled', ?3, ?4, '{}', ?5
        WHERE EXISTS (
          SELECT 1 FROM devices
           WHERE tenant_id = ?2 AND id = ?4 AND token_hash = ?6
        )`,
    ).bind(
      crypto.randomUUID(),
      code.tenantID,
      code.memberID,
      body.deviceID,
      now,
      tokenHash,
    ),
  ]);
  if (inserted.meta.changes !== 1) {
    return json({ error: "enrollment_code_already_used" }, 409);
  }
  return json({ deviceToken, enrolledAt: now }, 201);
}

function session(identity: DeviceIdentity): Response {
  return json({
    tenant: { displayName: identity.tenantName },
    member: {
      id: identity.memberID,
      displayName: identity.memberName,
      role: identity.role,
      employeeID: identity.employeeID,
    },
    device: { id: identity.deviceID, displayName: identity.deviceName },
  });
}

async function expireTenantInvitations(
  env: Env,
  tenantID: string,
  now = new Date(),
): Promise<number> {
  const expired = await env.DB.prepare(
    `SELECT tenant_members.id
       FROM tenant_members
       JOIN enrollment_codes
         ON enrollment_codes.tenant_id = tenant_members.tenant_id
        AND enrollment_codes.member_id = tenant_members.id
      WHERE tenant_members.tenant_id = ?1
        AND tenant_members.status = 'invited'
        AND enrollment_codes.redeemed_at IS NULL
        AND enrollment_codes.cancelled_at IS NULL
        AND enrollment_codes.expires_at <= ?2`,
  ).bind(tenantID, now.toISOString()).all<{ id: string }>();
  if (expired.results.length === 0) return 0;
  const statements: D1PreparedStatement[] = [];
  for (const member of expired.results) {
    statements.push(
      env.DB.prepare(
        `UPDATE tenant_members
            SET status = 'revoked', revoked_at = ?1
          WHERE tenant_id = ?2 AND id = ?3 AND status = 'invited'`,
      ).bind(now.toISOString(), tenantID, member.id),
      accessAuditStatement(env, tenantID, "invitation.expired", {
        targetMemberID: member.id,
        createdAt: now.toISOString(),
      }),
    );
  }
  await env.DB.batch(statements);
  return expired.results.length;
}

async function listMembers(env: Env, identity: DeviceIdentity): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  await expireTenantInvitations(env, identity.tenantID);
  const result = await env.DB.prepare(
    `SELECT id, employee_id AS employeeID, display_name AS displayName, role, status,
            created_at AS createdAt, activated_at AS activatedAt
       FROM tenant_members
      WHERE tenant_id = ?1
      ORDER BY created_at ASC`,
  ).bind(identity.tenantID).all();
  return json({ members: result.results });
}

async function createInvitation(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const body = await request.json<{
    displayName?: string;
    role?: TenantRole;
    employeeID?: string;
  }>();
  const displayName = body.displayName?.trim().slice(0, 100) ?? "";
  const role = body.role ?? "member";
  const employeeID = body.employeeID?.trim().slice(0, 100) ?? "";
  if (!displayName || !["manager", "member"].includes(role)) {
    return json({ error: "invalid_invitation" }, 400);
  }
  if (identity.role === "manager" && role !== "member") {
    return json({ error: "forbidden" }, 403);
  }
  await expireTenantInvitations(env, identity.tenantID);
  if (employeeID) {
    const approvedRole = await approvedTenantRoleForEmployee(
      env,
      identity.tenantID,
      employeeID.toLowerCase(),
    );
    if (approvedRole === "owner") {
      return json({ error: "owner_access_requires_account_workflow" }, 409);
    }
    if (!approvedRole && role === "manager") {
      return json({ error: "employee_role_not_synchronized" }, 409);
    }
    if (approvedRole && role !== approvedRole) {
      return json({
        error: "invitation_role_mismatch",
        approvedRole,
      }, 409);
    }
  }

  const now = new Date();
  const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  const memberID = crypto.randomUUID();
  const enrollmentCode = `PFSS-${crypto.randomUUID()}${crypto.randomUUID()}`;
  const codeHash = await sha256(enrollmentCode);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO tenant_members
        (id, tenant_id, employee_id, display_name, role, status, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, 'invited', ?6)`,
    ).bind(
      memberID,
      identity.tenantID,
      employeeID || null,
      displayName,
      role,
      now.toISOString(),
    ),
    env.DB.prepare(
      `INSERT INTO enrollment_codes
        (code_hash, tenant_id, member_id, expires_at, redeemed_at, created_at)
       VALUES (?1, ?2, ?3, ?4, NULL, ?5)`,
    ).bind(
      codeHash,
      identity.tenantID,
      memberID,
      expiresAt.toISOString(),
      now.toISOString(),
    ),
    accessAuditStatement(env, identity.tenantID, "invitation.created", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: memberID,
      metadata: { role, employeeID },
      createdAt: now.toISOString(),
    }),
  ]);
  return json({
    memberID,
    employeeID: employeeID || null,
    enrollmentCode,
    expiresAt: expiresAt.toISOString(),
  }, 201);
}

async function approvedTenantRoleForEmployee(
  env: Env,
  tenantID: string,
  employeeID: string,
): Promise<TenantRole | null> {
  const record = await env.DB.prepare(
    `SELECT operation_json AS operationJSON
       FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = 'employee' AND entity_id = ?2`,
  ).bind(tenantID, employeeID).first<{ operationJSON: string }>();
  if (!record) return null;
  try {
    const operation = JSON.parse(record.operationJSON) as {
      payload?: { body?: string };
    };
    const mutation = JSON.parse(atob(operation.payload?.body ?? "")) as {
      recordData?: string;
    };
    const employee = JSON.parse(atob(mutation.recordData ?? "")) as {
      role?: string;
      roles?: string[];
    };
    const roles = new Set(employee.roles ?? (employee.role ? [employee.role] : []));
    if (roles.has("Owner")) return "owner";
    if (roles.has("Manager")) return "manager";
    return "member";
  } catch {
    return null;
  }
}

function employeeRolesFromOperation(
  operation: Record<string, unknown>,
): string[] | null {
  try {
    const payload = operation.payload as { body?: string } | undefined;
    const mutation = JSON.parse(atob(payload?.body ?? "")) as {
      recordData?: string;
    };
    const employee = JSON.parse(atob(mutation.recordData ?? "")) as {
      role?: string;
      roles?: string[];
    };
    return [...new Set(employee.roles ?? (employee.role ? [employee.role] : []))]
      .sort();
  } catch {
    return null;
  }
}

async function listDevices(env: Env, identity: DeviceIdentity): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const result = await env.DB.prepare(
    `SELECT devices.id, devices.display_name AS displayName,
            devices.member_id AS memberID,
            tenant_members.display_name AS memberName,
            tenant_members.role,
            devices.created_at AS createdAt,
            devices.last_seen_at AS lastSeenAt,
            devices.revoked_at AS revokedAt
       FROM devices
       JOIN tenant_members
         ON tenant_members.id = devices.member_id
        AND tenant_members.tenant_id = devices.tenant_id
      WHERE devices.tenant_id = ?1
      ORDER BY devices.created_at ASC`,
  ).bind(identity.tenantID).all();
  return json({ devices: result.results });
}

async function revokeDevice(
  env: Env,
  identity: DeviceIdentity,
  deviceID: string,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  if (deviceID === identity.deviceID) {
    return json({ error: "cannot_revoke_current_device" }, 409);
  }
  const target = await env.DB.prepare(
    `SELECT tenant_members.role AS role, devices.member_id AS memberID
       FROM devices
       JOIN tenant_members
         ON tenant_members.id = devices.member_id
        AND tenant_members.tenant_id = devices.tenant_id
      WHERE devices.tenant_id = ?1 AND devices.id = ?2`,
  ).bind(identity.tenantID, deviceID).first<{
    role: TenantRole;
    memberID: string;
  }>();
  if (!target) return json({ error: "not_found" }, 404);
  if (identity.role === "manager" && target.role !== "member") {
    return json({ error: "forbidden" }, 403);
  }
  const now = new Date().toISOString();
  const [result] = await env.DB.batch([
    env.DB.prepare(
      `UPDATE devices
          SET revoked_at = ?1, data_removal_required_at = ?1
        WHERE tenant_id = ?2 AND id = ?3 AND revoked_at IS NULL`,
    ).bind(now, identity.tenantID, deviceID),
    accessAuditStatement(env, identity.tenantID, "device.revoked", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: target.memberID,
      targetDeviceID: deviceID,
      createdAt: now,
    }),
  ]);
  return json({ revoked: result.meta.changes === 1 });
}

async function cancelInvitation(
  env: Env,
  identity: DeviceIdentity,
  memberID: string,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const target = await env.DB.prepare(
    `SELECT role, status FROM tenant_members
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, memberID).first<{
    role: TenantRole;
    status: string;
  }>();
  if (!target) return json({ error: "not_found" }, 404);
  if (!canManageTarget(identity, target.role)) {
    return json({ error: "protected_role" }, 403);
  }
  if (target.status !== "invited") {
    return json({ error: "invitation_not_pending" }, 409);
  }
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE enrollment_codes
          SET cancelled_at = ?1, cancelled_by_member_id = ?2
        WHERE tenant_id = ?3 AND member_id = ?4
          AND redeemed_at IS NULL AND cancelled_at IS NULL`,
    ).bind(now, identity.memberID, identity.tenantID, memberID),
    env.DB.prepare(
      `UPDATE tenant_members SET status = 'revoked', revoked_at = ?1
        WHERE tenant_id = ?2 AND id = ?3 AND status = 'invited'`,
    ).bind(now, identity.tenantID, memberID),
    accessAuditStatement(env, identity.tenantID, "invitation.cancelled", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: memberID,
      createdAt: now,
    }),
  ]);
  return json({ cancelled: true });
}

async function updateMemberLifecycle(
  env: Env,
  identity: DeviceIdentity,
  memberID: string,
  action: "suspend" | "reactivate" | "revoke",
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  if (memberID === identity.memberID) {
    return json({ error: "cannot_modify_current_member" }, 409);
  }
  const target = await env.DB.prepare(
    `SELECT role, status FROM tenant_members
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, memberID).first<{
    role: TenantRole;
    status: "invited" | "active" | "suspended" | "revoked";
  }>();
  if (!target) return json({ error: "not_found" }, 404);
  if (!canManageTarget(identity, target.role)) {
    return json({ error: "protected_role" }, 403);
  }

  const allowed =
    (action === "suspend" && target.status === "active") ||
    (action === "reactivate" && target.status === "suspended") ||
    (action === "revoke" && ["active", "suspended"].includes(target.status));
  if (!allowed) return json({ error: "invalid_member_transition" }, 409);

  const now = new Date().toISOString();
  const nextStatus = action === "reactivate" ? "active" :
    action === "suspend" ? "suspended" : "revoked";
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `UPDATE tenant_members
          SET status = ?1,
              revoked_at = CASE WHEN ?1 = 'revoked' THEN ?2 ELSE revoked_at END
        WHERE tenant_id = ?3 AND id = ?4`,
    ).bind(nextStatus, now, identity.tenantID, memberID),
  ];
  if (action === "revoke") {
    statements.push(
      env.DB.prepare(
        `UPDATE devices
            SET revoked_at = COALESCE(revoked_at, ?1),
                data_removal_required_at = COALESCE(data_removal_required_at, ?1)
          WHERE tenant_id = ?2 AND member_id = ?3`,
      ).bind(now, identity.tenantID, memberID),
    );
  }
  statements.push(
    accessAuditStatement(
      env,
      identity.tenantID,
      action === "suspend" ? "member.suspended" :
        action === "reactivate" ? "member.reactivated" : "member.revoked",
      {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: memberID,
      metadata: { previousStatus: target.status, nextStatus },
      createdAt: now,
      },
    ),
  );
  await env.DB.batch(statements);
  return json({ memberID, status: nextStatus });
}

async function secureEmployeeAccessForArchive(
  env: Env,
  identity: DeviceIdentity,
  employeeID: string,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const normalizedEmployeeID = employeeID.trim().toLowerCase();
  if (!normalizedEmployeeID) return json({ error: "invalid_employee" }, 400);
  await expireTenantInvitations(env, identity.tenantID);
  const target = await env.DB.prepare(
    `SELECT id, role, status
       FROM tenant_members
      WHERE tenant_id = ?1 AND lower(employee_id) = ?2
      ORDER BY CASE WHEN status = 'revoked' THEN 1 ELSE 0 END,
               created_at DESC
      LIMIT 1`,
  ).bind(identity.tenantID, normalizedEmployeeID).first<{
    id: string;
    role: TenantRole;
    status: "invited" | "active" | "suspended" | "revoked";
  }>();
  if (!target) return json({ action: "none", membershipStatus: null });
  if (target.id === identity.memberID) {
    return json({ error: "cannot_archive_current_member" }, 409);
  }
  if (!canManageTarget(identity, target.role)) {
    return json({ error: "protected_role" }, 403);
  }

  const now = new Date().toISOString();
  if (target.status === "invited") {
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE enrollment_codes
            SET cancelled_at = ?1, cancelled_by_member_id = ?2
          WHERE tenant_id = ?3 AND member_id = ?4
            AND redeemed_at IS NULL AND cancelled_at IS NULL`,
      ).bind(now, identity.memberID, identity.tenantID, target.id),
      env.DB.prepare(
        `UPDATE tenant_members SET status = 'revoked', revoked_at = ?1
          WHERE tenant_id = ?2 AND id = ?3 AND status = 'invited'`,
      ).bind(now, identity.tenantID, target.id),
      accessAuditStatement(env, identity.tenantID, "invitation.cancelled", {
        actorMemberID: identity.memberID,
        actorDeviceID: identity.deviceID,
        targetMemberID: target.id,
        metadata: { reason: "employeeArchived" },
        createdAt: now,
      }),
    ]);
    return json({ action: "cancelledInvitation", membershipStatus: "revoked" });
  }
  if (target.status === "active") {
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE tenant_members SET status = 'suspended'
          WHERE tenant_id = ?1 AND id = ?2 AND status = 'active'`,
      ).bind(identity.tenantID, target.id),
      accessAuditStatement(env, identity.tenantID, "member.suspended", {
        actorMemberID: identity.memberID,
        actorDeviceID: identity.deviceID,
        targetMemberID: target.id,
        metadata: {
          previousStatus: "active",
          nextStatus: "suspended",
          reason: "employeeArchived",
        },
        createdAt: now,
      }),
    ]);
    return json({ action: "suspendedMembership", membershipStatus: "suspended" });
  }
  return json({ action: "none", membershipStatus: target.status });
}

async function runAccessCleanup(
  env: Env,
  now: Date = new Date(),
): Promise<{ invitationSecretsPurged: number; deviceCredentialsPurged: number }> {
  const invitationCutoff = new Date(
    now.getTime() - 30 * 24 * 60 * 60 * 1000,
  ).toISOString();
  const deviceCutoff = new Date(
    now.getTime() - 90 * 24 * 60 * 60 * 1000,
  ).toISOString();
  await env.DB.prepare(
    `UPDATE tenant_members
        SET status = 'revoked', revoked_at = ?1
      WHERE status = 'invited'
        AND EXISTS (
          SELECT 1 FROM enrollment_codes
           WHERE enrollment_codes.tenant_id = tenant_members.tenant_id
             AND enrollment_codes.member_id = tenant_members.id
             AND enrollment_codes.redeemed_at IS NULL
             AND enrollment_codes.cancelled_at IS NULL
             AND enrollment_codes.expires_at < ?1
        )`,
  ).bind(now.toISOString()).run();
  const invitationResult = await env.DB.prepare(
    `DELETE FROM enrollment_codes
      WHERE COALESCE(redeemed_at, cancelled_at, expires_at) < ?1`,
  ).bind(invitationCutoff).run();
  const deviceResult = await env.DB.prepare(
    `UPDATE devices
        SET token_hash = 'purged:' || tenant_id || ':' || id,
            credentials_purged_at = ?1
      WHERE revoked_at IS NOT NULL AND revoked_at < ?2
        AND data_removal_acknowledged_at IS NOT NULL
        AND credentials_purged_at IS NULL`,
  ).bind(now.toISOString(), deviceCutoff).run();
  return {
    invitationSecretsPurged: invitationResult.meta.changes,
    deviceCredentialsPurged: deviceResult.meta.changes,
  };
}

async function cleanAccessHistory(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  const result = await runAccessCleanup(env);
  await accessAuditStatement(env, identity.tenantID, "access.cleanup", {
    actorMemberID: identity.memberID,
    actorDeviceID: identity.deviceID,
    metadata: {
      invitationSecretsPurged: String(result.invitationSecretsPurged),
      deviceCredentialsPurged: String(result.deviceCredentialsPurged),
    },
  }).run();
  return json(result);
}

async function acceptOperation(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const operation = await request.json<Record<string, unknown>>();
  const id = String(operation.id ?? "");
  const idempotencyKey = String(operation.idempotencyKey ?? "");
  if (!id || !idempotencyKey) return json({ error: "invalid_operation" }, 400);
  const isRecordMutation = String(operation.type ?? "") === "recordMutation";
  const entityType = String(operation.entityType ?? "");
  const entityID = String(operation.entityID ?? "").toLowerCase();
  const metadata = operation.metadata && typeof operation.metadata === "object"
    ? operation.metadata as Record<string, unknown>
    : {};
  if (
    identity.role === "member" &&
    metadata.conflictResolution === "keptLocal"
  ) {
    return json({ error: "conflict_override_requires_manager" }, 403);
  }
  if (isRecordMutation) {
    const allowed = new Set([
      "customer", "site", "lead", "estimate", "job", "assignment",
      "invoice", "employee", "catalog",
    ]);
    if (!allowed.has(entityType) || !entityID) {
      return json({ error: "invalid_record_mutation" }, 400);
    }
    if (
      identity.role === "member" &&
      (entityType === "catalog" ||
        (entityType === "employee" && entityID !== identity.employeeID?.toLowerCase()))
    ) {
      return json({ error: "forbidden" }, 403);
    }
    if (identity.role === "member" && entityType === "employee") {
      const acceptedRecord = await env.DB.prepare(
        `SELECT operation_json AS operationJSON
           FROM synchronized_records
          WHERE tenant_id = ?1 AND entity_type = 'employee' AND entity_id = ?2`,
      ).bind(identity.tenantID, entityID).first<{ operationJSON: string }>();
      const acceptedRoles = acceptedRecord
        ? employeeRolesFromOperation(JSON.parse(acceptedRecord.operationJSON))
        : null;
      const submittedRoles = employeeRolesFromOperation(operation);
      if (
        !acceptedRoles || !submittedRoles ||
        acceptedRoles.join("|") !== submittedRoles.join("|")
      ) {
        return json({ error: "employee_role_change_requires_manager" }, 403);
      }
    }
  }
  const existing = await env.DB.prepare(
    `SELECT revision FROM synchronized_operations
      WHERE tenant_id = ?1 AND idempotency_key = ?2`,
  ).bind(identity.tenantID, idempotencyKey).first<{ revision: string }>();
  if (existing) return json({ revision: existing.revision, duplicate: true });

  const revision = crypto.randomUUID();
  const acceptedAt = new Date().toISOString();
  if (isRecordMutation) {
    const current = await env.DB.prepare(
      `SELECT revision, operation_json AS operationJSON,
              updated_by_device_id AS updatedByDeviceID
         FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
    ).bind(identity.tenantID, entityType, entityID).first<{
      revision: string;
      operationJSON: string;
      updatedByDeviceID: string;
    }>();
    const baseRevision = operation.baseRevision == null
      ? null
      : String(operation.baseRevision);
    if (
      (current && baseRevision !== current.revision &&
        !(baseRevision === null && current.updatedByDeviceID === identity.deviceID)) ||
      (!current && baseRevision !== null)
    ) {
      const conflictID = await recordSynchronizationConflict(
        env, identity, operation, entityType, entityID,
        current?.revision ?? "", JSON.parse(current?.operationJSON ?? "{}"),
      );
      return json({
        error: "record_conflict",
        conflictID,
        currentRevision: current?.revision ?? null,
        currentOperation: current ? JSON.parse(current.operationJSON) : null,
      }, 409);
    }
    const effectiveBaseRevision = baseRevision ?? (
      current?.updatedByDeviceID === identity.deviceID
        ? current.revision
        : null
    );
    if (current) {
      const updated = await env.DB.prepare(
        `UPDATE synchronized_records
            SET revision = ?1, operation_json = ?2,
                updated_by_member_id = ?3, updated_by_device_id = ?4,
                updated_at = ?5
          WHERE tenant_id = ?6 AND entity_type = ?7 AND entity_id = ?8
            AND revision = ?9`,
      ).bind(
        revision, JSON.stringify(operation), identity.memberID,
        identity.deviceID, acceptedAt, identity.tenantID, entityType,
        entityID, effectiveBaseRevision,
      ).run();
      if (updated.meta.changes !== 1) {
        const latest = await env.DB.prepare(
          `SELECT revision, operation_json AS operationJSON
             FROM synchronized_records
            WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
        ).bind(identity.tenantID, entityType, entityID).first<{
          revision: string;
          operationJSON: string;
        }>();
        const conflictID = await recordSynchronizationConflict(
          env, identity, operation, entityType, entityID,
          latest?.revision ?? "", JSON.parse(latest?.operationJSON ?? "{}"),
        );
        return json({
          error: "record_conflict",
          conflictID,
          currentRevision: latest?.revision ?? null,
          currentOperation: latest ? JSON.parse(latest.operationJSON) : null,
        }, 409);
      }
    } else {
      try {
        await env.DB.prepare(
          `INSERT INTO synchronized_records
            (tenant_id, entity_type, entity_id, revision, operation_json,
             updated_by_member_id, updated_by_device_id, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
        ).bind(
          identity.tenantID, entityType, entityID, revision,
          JSON.stringify(operation), identity.memberID, identity.deviceID,
          acceptedAt,
        ).run();
      } catch {
        const latest = await env.DB.prepare(
          `SELECT revision, operation_json AS operationJSON
             FROM synchronized_records
            WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
        ).bind(identity.tenantID, entityType, entityID).first<{
          revision: string;
          operationJSON: string;
        }>();
        const conflictID = await recordSynchronizationConflict(
          env, identity, operation, entityType, entityID,
          latest?.revision ?? "", JSON.parse(latest?.operationJSON ?? "{}"),
        );
        return json({
          error: "record_conflict",
          conflictID,
          currentRevision: latest?.revision ?? null,
          currentOperation: latest ? JSON.parse(latest.operationJSON) : null,
        }, 409);
      }
    }
  }
  await env.DB.prepare(
    `INSERT INTO synchronized_operations
      (id, tenant_id, device_id, idempotency_key, operation_type,
       entity_type, entity_id, action_name, payload_json, created_at,
       accepted_at, revision)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)`,
  ).bind(
    id,
    identity.tenantID,
    identity.deviceID,
    idempotencyKey,
    String(operation.type ?? "custom"),
    String(operation.entityType ?? "custom"),
    operation.entityID ? String(operation.entityID) : null,
    String(operation.actionName ?? "unknown"),
    JSON.stringify(operation),
    String(operation.createdAt ?? acceptedAt),
    acceptedAt,
    revision,
  ).run();
  return json({ revision, duplicate: false }, 201);
}

async function synchronizationChanges(
  url: URL,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const requestedAfter = Number.parseInt(url.searchParams.get("after") ?? "0", 10);
  const after = Number.isFinite(requestedAfter) && requestedAfter >= 0
    ? requestedAfter
    : 0;
  const requestedLimit = Number.parseInt(url.searchParams.get("limit") ?? "200", 10);
  const limit = Math.min(Math.max(requestedLimit || 200, 1), 500);
  const result = await env.DB.prepare(
    `SELECT rowid AS sequence, device_id AS deviceID,
            revision, payload_json AS payloadJSON
       FROM synchronized_operations
      WHERE tenant_id = ?1 AND rowid > ?2
      ORDER BY rowid ASC
      LIMIT ?3`,
  ).bind(identity.tenantID, after, limit).all<{
    sequence: number;
    deviceID: string;
    revision: string;
    payloadJSON: string;
  }>();
  const changes = result.results.map((row) => ({
    sequence: row.sequence,
    sourceDeviceID: row.deviceID,
    revision: row.revision,
    operation: JSON.parse(row.payloadJSON),
  }));
  const cursor = changes.length > 0
    ? changes[changes.length - 1].sequence
    : after;
  return json({ cursor, hasMore: changes.length === limit, changes });
}

function tenantBackupPrefix(tenantID: string): string {
  return `tenants/${tenantID}/backups/`;
}

function tenantSynchronizationSnapshotKey(tenantID: string): string {
  return `tenants/${tenantID}/synchronization/current.pfssarchive`;
}

async function publishSynchronizationSnapshot(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  if (request.headers.get("content-type") !== archiveMediaType) {
    return json({ error: "unsupported_archive_type" }, 415);
  }
  const body = await request.arrayBuffer();
  if (body.byteLength === 0 || body.byteLength > 100 * 1024 * 1024) {
    return json({ error: "invalid_archive_size" }, 413);
  }
  const publishedAt = new Date().toISOString();
  const revision = crypto.randomUUID();
  await env.ARCHIVES.put(
    tenantSynchronizationSnapshotKey(identity.tenantID),
    body,
    {
      httpMetadata: { contentType: archiveMediaType },
      customMetadata: {
        tenantID: identity.tenantID,
        publishedAt,
        revision,
      },
    },
  );
  return json({ publishedAt, revision }, 201);
}

async function synchronizationBootstrap(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const object = await env.ARCHIVES.get(
    tenantSynchronizationSnapshotKey(identity.tenantID),
  );
  if (!object) return json({ error: "synchronization_snapshot_unavailable" }, 404);
  return new Response(object.body, {
    headers: {
      "content-type": archiveMediaType,
      "cache-control": "no-store",
      "x-pfss-snapshot-revision": object.customMetadata?.revision ?? "",
    },
  });
}

async function uploadBackup(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  if (request.headers.get("content-type") !== archiveMediaType) {
    return json({ error: "unsupported_archive_type" }, 415);
  }
  const body = await request.arrayBuffer();
  if (body.byteLength === 0 || body.byteLength > 100 * 1024 * 1024) {
    return json({ error: "invalid_archive_size" }, 413);
  }
  const archiveID = crypto.randomUUID();
  const uploadedAt = new Date().toISOString();
  const key = `${tenantBackupPrefix(identity.tenantID)}${uploadedAt}-${archiveID}.pfssarchive`;
  const object = await env.ARCHIVES.put(key, body, {
    httpMetadata: { contentType: archiveMediaType },
    customMetadata: {
      tenantID: identity.tenantID,
      archiveID,
      uploadedByDeviceID: identity.deviceID,
      uploadedAt,
    },
  });
  return json({ archiveID, uploadedAt, size: object?.size ?? body.byteLength }, 201);
}

async function listBackups(env: Env, identity: DeviceIdentity): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  const result = await env.ARCHIVES.list({
    prefix: tenantBackupPrefix(identity.tenantID),
    limit: 1000,
    include: ["customMetadata"],
  });
  const backups = result.objects
    .sort((left, right) => right.uploaded.getTime() - left.uploaded.getTime())
    .map((object) => ({
      archiveID: object.customMetadata?.archiveID ?? object.key,
      uploadedAt: object.uploaded.toISOString(),
      size: object.size,
      etag: object.etag,
    }));
  return json({ backups });
}

async function latestBackup(env: Env, identity: DeviceIdentity): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "forbidden" }, 403);
  const listed = await env.ARCHIVES.list({
    prefix: tenantBackupPrefix(identity.tenantID),
    limit: 1000,
  });
  const latest = listed.objects.sort(
    (left, right) => right.uploaded.getTime() - left.uploaded.getTime(),
  )[0];
  if (!latest) return json({ error: "no_backup" }, 404);
  const object = await env.ARCHIVES.get(latest.key);
  if (!object?.body) return json({ error: "no_backup" }, 404);
  return new Response(object.body, {
    headers: {
      "content-type": archiveMediaType,
      "etag": object.httpEtag,
      "x-pfss-uploaded-at": object.uploaded.toISOString(),
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ status: "ok" });
      }
      if (request.method === "POST" && url.pathname === "/v1/beta/enroll") {
        return enroll(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/device-removal/acknowledge"
      ) {
        return acknowledgeCompanyDataRemoval(request, env);
      }

      const identity = await authenticate(request, env);
      if (identity instanceof Response) return identity;

      if (request.method === "GET" && url.pathname === "/v1/session") {
        return session(identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/members") {
        return listMembers(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/invitations") {
        return createInvitation(request, env, identity);
      }
      const cancelInvitationMatch = url.pathname.match(
        /^\/v1\/invitations\/([^/]+)\/cancel$/,
      );
      if (request.method === "POST" && cancelInvitationMatch) {
        return cancelInvitation(
          env,
          identity,
          decodeURIComponent(cancelInvitationMatch[1]),
        );
      }
      const memberLifecycleMatch = url.pathname.match(
        /^\/v1\/members\/([^/]+)\/(suspend|reactivate|revoke)$/,
      );
      if (request.method === "POST" && memberLifecycleMatch) {
        return updateMemberLifecycle(
          env,
          identity,
          decodeURIComponent(memberLifecycleMatch[1]),
          memberLifecycleMatch[2] as "suspend" | "reactivate" | "revoke",
        );
      }
      const archiveEmployeeMatch = url.pathname.match(
        /^\/v1\/employees\/([^/]+)\/secure-for-archive$/,
      );
      if (request.method === "POST" && archiveEmployeeMatch) {
        return secureEmployeeAccessForArchive(
          env,
          identity,
          decodeURIComponent(archiveEmployeeMatch[1]),
        );
      }
      if (request.method === "GET" && url.pathname === "/v1/devices") {
        return listDevices(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/access/cleanup") {
        return cleanAccessHistory(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/recovery/audit") {
        return recordRecoveryAudit(request, env, identity);
      }
      const revokeMatch = url.pathname.match(/^\/v1\/devices\/([^/]+)\/revoke$/);
      if (request.method === "POST" && revokeMatch) {
        return revokeDevice(env, identity, decodeURIComponent(revokeMatch[1]));
      }
      if (request.method === "POST" && url.pathname === "/v1/operations") {
        return acceptOperation(request, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/sync/changes") {
        return synchronizationChanges(url, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/sync/conflicts") {
        return listSynchronizationConflicts(env, identity);
      }
      if (
        request.method === "GET" &&
        url.pathname === "/v1/sync/conflict-resolutions"
      ) {
        return listSourceConflictResolutions(env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/sync/conflict-audit") {
        return listConflictAudit(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/sync/conflicts/report") {
        return reportSynchronizationConflict(request, env, identity);
      }
      const conflictResolutionMatch = url.pathname.match(
        /^\/v1\/sync\/conflicts\/([^/]+)\/resolve$/,
      );
      if (request.method === "POST" && conflictResolutionMatch) {
        return resolveSynchronizationConflict(
          request, env, identity,
          decodeURIComponent(conflictResolutionMatch[1]),
        );
      }
      if (request.method === "POST" && url.pathname === "/v1/sync/snapshot") {
        return publishSynchronizationSnapshot(request, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/sync/bootstrap") {
        return synchronizationBootstrap(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/backups") {
        return uploadBackup(request, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/backups") {
        return listBackups(env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/backups/latest") {
        return latestBackup(env, identity);
      }
      return json({ error: "not_found" }, 404);
    } catch {
      return json({ error: "invalid_request" }, 400);
    }
  },

  scheduled(
    _controller: ScheduledController,
    env: Env,
    context: ExecutionContext,
  ): void {
    context.waitUntil(runAccessCleanup(env));
  },
};
