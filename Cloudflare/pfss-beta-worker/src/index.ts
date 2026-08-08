import {
  IdentityConfigurationError,
  IdentityProviderResponseError,
  ManagedIdentityConfigurationBindings,
  ManagedOwnerIdentityProvider,
  WorkOSManagedOwnerIdentityProvider,
  managedIdentityConfigurationFromBindings,
} from "./account-identity-provider";
import { resolveAccountEntitlements } from "./account-entitlements";

interface Env extends ManagedIdentityConfigurationBindings {
  DB: D1Database;
  ARCHIVES: R2Bucket;
  WORKOS_OPERATIONS_CLIENT_ID?: string;
  WORKOS_OPERATIONS_API_KEY?: string;
  WORKOS_OPERATIONS_REDIRECT_URIS?: string;
  CLOUDFLARE_WORKERS_DAILY_REQUEST_LIMIT?: string;
  CLOUDFLARE_R2_STORAGE_LIMIT_BYTES?: string;
  WORKOS_AUTHKIT_MONTHLY_ACTIVE_USER_LIMIT?: string;
  CLOUDFLARE_ANALYTICS_API_TOKEN?: string;
  CLOUDFLARE_ACCOUNT_ID?: string;
  CLOUDFLARE_D1_DATABASE_ID?: string;
  CLOUDFLARE_WORKER_SCRIPT_NAME?: string;
}

type TenantRole = "owner" | "manager" | "member";

type AccountRegistrationStatus =
  | "started"
  | "identityVerified"
  | "profileComplete"
  | "planAuthorized"
  | "provisioning"
  | "active"
  | "expired"
  | "cancelled"
  | "failedRolledBack";

type AccountAuthenticationMethod =
  | "password"
  | "passkey"
  | "signInWithApple"
  | "federated";

type AccountAccessSource =
  | "appStoreSubscription"
  | "betaGrant"
  | "internalTesting"
  | "internalBusinessGrant"
  | "promotionalGrant";

interface ValidatedAccountRegistration {
  idempotencyKey: string;
  identityAssertion: string;
  authenticationMethod: AccountAuthenticationMethod;
  owner: { displayName: string; email: string };
  company: { displayName: string; normalizedName: string; timeZoneID: string };
  requestedPlanCode: string;
  consent: {
    termsVersion: string;
    privacyVersion: string;
    acceptedAt: string;
  };
  device: { id: string; displayName: string };
}

interface AccountRegistrationAttemptRow {
  id: string;
  requestFingerprint: string;
  status: AccountRegistrationStatus;
  expiresAt: string;
  createdAt: string;
  updatedAt: string;
  cancelledAt: string | null;
}

interface ProvisioningRegistrationAttemptRow extends AccountRegistrationAttemptRow {
  ownerDisplayName: string;
  companyDisplayName: string;
  timeZoneID: string;
  requestedPlanCode: string;
  deviceID: string;
  deviceDisplayName: string;
  subjectID: string;
  tenantID: string | null;
}

interface OwnerAuthorizationAttemptRow {
  id: string;
  codeChallenge: string;
  redirectURI: string;
  status: "started" | "verified" | "consumed" | "expired" | "failed";
  expiresAt: string;
}

interface DeviceIdentity {
  tenantID: string;
  tenantName: string;
  memberID: string;
  employeeID: string | null;
  memberName: string;
  memberEmail: string | null;
  role: TenantRole;
  memberStatus: "invited" | "active" | "suspended" | "revoked";
  deviceID: string;
  deviceName: string;
  revokedAt: string | null;
  dataRemovalRequiredAt: string | null;
  dataRemovalAcknowledgedAt: string | null;
  tenantStatus: string;
  lifecycleStatus: string;
  holdExpiresAt: string | null;
}

type OperationsAdministratorRole =
  | "platformOwner"
  | "supportAdministrator"
  | "billingAdministrator"
  | "readOnlyAuditor";

interface OperationsIdentity {
  administratorID: string;
  displayName: string;
  email: string;
  role: OperationsAdministratorRole;
  sessionID: string;
  deviceID: string;
  deviceName: string;
  expiresAt: string;
}

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };
const archiveMediaType = "application/vnd.pfss.archive+json";

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: jsonHeaders });
}

function utf8Base64(value: unknown): string {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
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

async function sha256Base64URL(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  const encoded = btoa(String.fromCharCode(...new Uint8Array(digest)));
  return encoded.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function bearer(request: Request): string | null {
  const authorization = request.headers.get("authorization") ?? "";
  return authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : null;
}

const forbiddenRegistrationKeys = new Set([
  "tenantid", "tenant", "role", "ownerrole", "price", "amount",
  "entitlements", "limits", "databaseid", "databasename", "bucketname",
  "storagepath", "infrastructureendpoint", "workerurl", "accesssource",
  "allocationsource", "granttype", "complimentaryaccess",
]);

function normalizedFieldKey(value: string): string {
  return value.replace(/[_-]/g, "").toLowerCase();
}

function forbiddenRegistrationField(
  value: unknown,
  path = "",
): string | null {
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const found = forbiddenRegistrationField(value[index], `${path}[${index}]`);
      if (found) return found;
    }
    return null;
  }
  if (value === null || typeof value !== "object") return null;
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    const childPath = path ? `${path}.${key}` : key;
    if (forbiddenRegistrationKeys.has(normalizedFieldKey(key))) return childPath;
    const found = forbiddenRegistrationField(child, childPath);
    if (found) return found;
  }
  return null;
}

function nonemptyString(
  value: unknown,
  minimum: number,
  maximum: number,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length >= minimum && normalized.length <= maximum
    ? normalized
    : null;
}

function validEmail(value: string): boolean {
  if (value.length > 254 || /\s/.test(value)) return false;
  const parts = value.split("@");
  return parts.length === 2 && parts[0].length > 0 && parts[0].length <= 64 &&
    parts[1].includes(".") && !parts[1].startsWith(".") &&
    !parts[1].endsWith(".");
}

function managedOwnerIdentityProvider(env: Env): ManagedOwnerIdentityProvider {
  return new WorkOSManagedOwnerIdentityProvider(
    managedIdentityConfigurationFromBindings(env),
  );
}

function managedOperationsIdentityProvider(
  env: Env,
): ManagedOwnerIdentityProvider {
  return new WorkOSManagedOwnerIdentityProvider(
    managedIdentityConfigurationFromBindings({
      PFSS_ENVIRONMENT: env.PFSS_ENVIRONMENT,
      WORKOS_ENVIRONMENT: env.WORKOS_ENVIRONMENT,
      WORKOS_CLIENT_ID: env.WORKOS_OPERATIONS_CLIENT_ID,
      WORKOS_API_KEY: env.WORKOS_OPERATIONS_API_KEY,
      WORKOS_API_BASE_URL: env.WORKOS_API_BASE_URL,
      WORKOS_ISSUER: env.WORKOS_ISSUER,
      WORKOS_REDIRECT_URIS: env.WORKOS_OPERATIONS_REDIRECT_URIS,
    }),
  );
}

function accountAuthenticationMethod(providerMethod: string):
AccountAuthenticationMethod {
  switch (providerMethod) {
  case "Password": return "password";
  case "Passkey": return "passkey";
  case "AppleOAuth": return "signInWithApple";
  default: return "federated";
  }
}

function operationsCanViewAccounts(_identity: OperationsIdentity): boolean {
  return true;
}

function operationsCanOverridePlans(identity: OperationsIdentity): boolean {
  return identity.role === "platformOwner" ||
    identity.role === "billingAdministrator";
}

function operationsCanManageRecovery(identity: OperationsIdentity): boolean {
  return identity.role === "platformOwner" ||
    identity.role === "supportAdministrator";
}

function operationsCanManageMemberAccess(identity: OperationsIdentity): boolean {
  return identity.role === "platformOwner" ||
    identity.role === "supportAdministrator";
}

type OperationsMemberAction =
  "suspend" | "reactivate" | "revoke" | "archive" | "remove";

async function manageOperationsMember(
  request: Request, env: Env, identity: OperationsIdentity,
  tenantID: string, memberID: string, action: OperationsMemberAction,
): Promise<Response> {
  if (!operationsCanManageMemberAccess(identity)) {
    return json({ error: "operations_member_access_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_member_access_action" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) {
    return json({ error: "invalid_member_access_action" }, 400);
  }
  const target = await env.DB.prepare(
    `SELECT role, status, operations_archived_at AS archivedAt,
            operations_removed_at AS removedAt
       FROM tenant_members WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(tenantID, memberID).first<{
    role: TenantRole; status: string; archivedAt: string | null;
    removedAt: string | null;
  }>();
  if (!target) return json({ error: "not_found" }, 404);
  if (target.removedAt) return json({ error: "member_already_removed" }, 409);
  if (target.role === "owner" && action !== "reactivate") {
    const owners = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM tenant_members
        WHERE tenant_id = ?1 AND role = 'owner' AND status = 'active'
          AND operations_archived_at IS NULL AND operations_removed_at IS NULL`,
    ).bind(tenantID).first<{ count: number }>();
    if (target.status === "active" && Number(owners?.count ?? 0) <= 1) {
      return json({ error: "cannot_remove_final_active_owner" }, 409);
    }
  }
  const allowed =
    (action === "suspend" && target.status === "active" && !target.archivedAt) ||
    (action === "reactivate" && target.status === "suspended" && !target.archivedAt) ||
    (action === "revoke" && ["active", "suspended"].includes(target.status) &&
      !target.archivedAt) ||
    (action === "archive" && target.status === "revoked" && !target.archivedAt) ||
    (action === "remove" && target.status === "revoked" && !!target.archivedAt);
  if (!allowed) return json({ error: "invalid_member_access_transition" }, 409);

  if (action === "remove") {
    const pending = await env.DB.prepare(
      `SELECT COUNT(*) AS count FROM devices
        WHERE tenant_id = ?1 AND member_id = ?2
          AND data_removal_required_at IS NOT NULL
          AND data_removal_acknowledged_at IS NULL`,
    ).bind(tenantID, memberID).first<{ count: number }>();
    if (Number(pending?.count ?? 0) > 0) {
      return json({ error: "device_data_removal_pending" }, 409);
    }
  }

  const now = new Date().toISOString();
  const statements: D1PreparedStatement[] = [];
  if (action === "suspend" || action === "reactivate") {
    statements.push(env.DB.prepare(
      `UPDATE tenant_members SET status = ?1
        WHERE tenant_id = ?2 AND id = ?3`,
    ).bind(action === "suspend" ? "suspended" : "active", tenantID, memberID));
  } else if (action === "revoke") {
    statements.push(
      env.DB.prepare(
        `UPDATE tenant_members SET status = 'revoked', revoked_at = ?1
          WHERE tenant_id = ?2 AND id = ?3`,
      ).bind(now, tenantID, memberID),
      env.DB.prepare(
        `UPDATE devices SET revoked_at = COALESCE(revoked_at, ?1),
                data_removal_required_at = COALESCE(data_removal_required_at, ?1)
          WHERE tenant_id = ?2 AND member_id = ?3`,
      ).bind(now, tenantID, memberID),
    );
  } else if (action === "archive") {
    statements.push(env.DB.prepare(
      `UPDATE tenant_members SET operations_archived_at = ?1
        WHERE tenant_id = ?2 AND id = ?3`,
    ).bind(now, tenantID, memberID));
  } else {
    statements.push(
      env.DB.prepare(
        `UPDATE tenant_members
            SET display_name = 'Removed User', employee_id = NULL,
                authentication_subject_id = NULL, operations_removed_at = ?1
          WHERE tenant_id = ?2 AND id = ?3`,
      ).bind(now, tenantID, memberID),
      env.DB.prepare(
        `UPDATE devices SET display_name = 'Removed Device',
                token_hash = 'removed:' || tenant_id || ':' || id,
                credentials_purged_at = COALESCE(credentials_purged_at, ?1),
                operations_removed_at = ?1
          WHERE tenant_id = ?2 AND member_id = ?3`,
      ).bind(now, tenantID, memberID),
    );
  }
  statements.push(operationsAuditStatement(env, `operations.member.${action}`, {
    administratorID: identity.administratorID, targetTenantID: tenantID,
    targetMemberID: memberID, reason,
    metadata: { previousStatus: target.archivedAt ? "archived" : target.status,
      nextStatus: action }, createdAt: now,
  }));
  await env.DB.batch(statements);
  return json({ memberID, status: action, effectiveAt: now });
}

async function manageOperationsDevice(
  request: Request, env: Env, identity: OperationsIdentity,
  tenantID: string, deviceID: string, action: "revoke" | "remove",
): Promise<Response> {
  if (!operationsCanManageMemberAccess(identity)) {
    return json({ error: "operations_member_access_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_device_access_action" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) return json({ error: "invalid_device_access_action" }, 400);
  const target = await env.DB.prepare(
    `SELECT member_id AS memberID, revoked_at AS revokedAt,
            data_removal_required_at AS requiredAt,
            data_removal_acknowledged_at AS acknowledgedAt,
            operations_removed_at AS removedAt
       FROM devices WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(tenantID, deviceID).first<{
    memberID: string; revokedAt: string | null; requiredAt: string | null;
    acknowledgedAt: string | null; removedAt: string | null;
  }>();
  if (!target) return json({ error: "not_found" }, 404);
  if (target.removedAt) return json({ error: "device_already_removed" }, 409);
  if (action === "revoke" && target.revokedAt) {
    return json({ error: "invalid_device_access_transition" }, 409);
  }
  if (action === "remove" && (!target.revokedAt ||
      (target.requiredAt && !target.acknowledgedAt))) {
    return json({ error: "device_data_removal_pending" }, 409);
  }
  const now = new Date().toISOString();
  const update = action === "revoke"
    ? env.DB.prepare(
      `UPDATE devices SET revoked_at = ?1, data_removal_required_at = ?1
        WHERE tenant_id = ?2 AND id = ?3`,
    ).bind(now, tenantID, deviceID)
    : env.DB.prepare(
      `UPDATE devices SET display_name = 'Removed Device',
              token_hash = 'removed:' || tenant_id || ':' || id,
              credentials_purged_at = COALESCE(credentials_purged_at, ?1),
              operations_removed_at = ?1
        WHERE tenant_id = ?2 AND id = ?3`,
    ).bind(now, tenantID, deviceID);
  await env.DB.batch([
    update,
    operationsAuditStatement(env, `operations.device.${action}`, {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      targetMemberID: target.memberID, reason, metadata: { deviceID },
      createdAt: now,
    }),
  ]);
  return json({ deviceID, status: action, effectiveAt: now });
}

async function operationsRecoveryTarget(
  env: Env, tenantID: string, memberID: string,
): Promise<{ email: string; workOSUserID: string } | null> {
  return env.DB.prepare(
    `SELECT contacts.normalized_value AS email,
            identities.provider_subject AS workOSUserID
       FROM tenant_members AS members
       JOIN authentication_identities AS identities
         ON identities.subject_id = members.authentication_subject_id
        AND identities.provider_key = 'workos'
       JOIN verified_contact_addresses AS contacts
         ON contacts.subject_id = members.authentication_subject_id
        AND contacts.kind = 'email'
      WHERE members.tenant_id = ?1 AND members.id = ?2
      ORDER BY contacts.verified_at DESC LIMIT 1`,
  ).bind(tenantID, memberID).first<{ email: string; workOSUserID: string }>();
}

function workOSManagementConfiguration(env: Env):
{ apiKey: string; baseURL: string } | null {
  const apiKey = env.WORKOS_API_KEY ?? "";
  const baseURL = env.WORKOS_API_BASE_URL ?? "";
  try {
    if (!apiKey.startsWith("sk_") || new URL(baseURL).protocol !== "https:") {
      return null;
    }
  } catch { return null; }
  return { apiKey, baseURL };
}

async function sendOperationsPasswordReset(
  request: Request, env: Env, identity: OperationsIdentity,
  tenantID: string, memberID: string,
): Promise<Response> {
  if (!operationsCanManageRecovery(identity)) {
    return json({ error: "operations_recovery_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_recovery_assistance" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) {
    return json({ error: "invalid_recovery_assistance" }, 400);
  }
  const target = await operationsRecoveryTarget(env, tenantID, memberID);
  if (!target) return json({ error: "managed_identity_not_found" }, 404);
  const configuration = workOSManagementConfiguration(env);
  if (!configuration) return json({ error: "identity_provider_unavailable" }, 503);
  const response = await fetch(new URL(
    "/user_management/password_reset", configuration.baseURL,
  ), {
    method: "POST",
    headers: {
      authorization: `Bearer ${configuration.apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email: target.email }),
  });
  if (!response.ok) return json({ error: "identity_provider_unavailable" }, 503);
  const now = new Date().toISOString();
  await operationsAuditStatement(env, "operations.recovery_email.sent", {
    administratorID: identity.administratorID, targetTenantID: tenantID,
    targetMemberID: memberID, reason,
    metadata: { email: target.email }, createdAt: now,
  }).run();
  return json({ status: "sent", email: target.email, effectiveAt: now });
}

async function revokeOperationsUserSessions(
  request: Request, env: Env, identity: OperationsIdentity,
  tenantID: string, memberID: string,
): Promise<Response> {
  if (!operationsCanManageRecovery(identity)) {
    return json({ error: "operations_recovery_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_session_revocation" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) return json({ error: "invalid_session_revocation" }, 400);
  const target = await operationsRecoveryTarget(env, tenantID, memberID);
  if (!target) return json({ error: "managed_identity_not_found" }, 404);
  const configuration = workOSManagementConfiguration(env);
  if (!configuration) return json({ error: "identity_provider_unavailable" }, 503);
  const sessionsResponse = await fetch(new URL(
    `/user_management/users/${encodeURIComponent(target.workOSUserID)}/sessions`,
    configuration.baseURL,
  ), { headers: { authorization: `Bearer ${configuration.apiKey}` } });
  if (!sessionsResponse.ok) {
    return json({ error: "identity_provider_unavailable" }, 503);
  }
  const sessionsBody = await sessionsResponse.json<{
    data?: Array<{ id?: unknown }>;
  }>();
  const sessionIDs = (sessionsBody.data ?? []).flatMap((session) =>
    typeof session.id === "string" ? [session.id] : []
  );
  for (const sessionID of sessionIDs) {
    const revokeResponse = await fetch(new URL(
      "/user_management/sessions/revoke", configuration.baseURL,
    ), {
      method: "POST",
      headers: {
        authorization: `Bearer ${configuration.apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ session_id: sessionID }),
    });
    if (!revokeResponse.ok) {
      return json({ error: "identity_provider_unavailable" }, 503);
    }
  }
  const now = new Date().toISOString();
  const devices = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM devices
      WHERE tenant_id = ?1 AND member_id = ?2 AND revoked_at IS NULL`,
  ).bind(tenantID, memberID).first<{ count: number }>();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE devices SET revoked_at = ?3, data_removal_required_at = ?3
        WHERE tenant_id = ?1 AND member_id = ?2 AND revoked_at IS NULL`,
    ).bind(tenantID, memberID, now),
    operationsAuditStatement(env, "operations.sessions.revoked", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      targetMemberID: memberID, reason,
      metadata: { workOSSessions: String(sessionIDs.length),
        pfssDevices: String(Number(devices?.count ?? 0)) }, createdAt: now,
    }),
  ]);
  return json({ status: "revoked", workOSSessions: sessionIDs.length,
    pfssDevices: Number(devices?.count ?? 0), effectiveAt: now });
}

type OperationsHoldStatus = "billingHold" | "securityHold" | "supportHold";

function operationsCanManageHold(
  identity: OperationsIdentity, status: OperationsHoldStatus,
): boolean {
  if (identity.role === "platformOwner") return true;
  if (status === "billingHold") return identity.role === "billingAdministrator";
  return identity.role === "supportAdministrator";
}

async function setOperationsAccountHold(
  request: Request, env: Env, identity: OperationsIdentity, tenantID: string,
): Promise<Response> {
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_account_hold" }, 400); }
  const status = typeof body.status === "string" ? body.status : "";
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  const permanent = body.permanent === true;
  const expiresAt = typeof body.expiresAt === "string" ? body.expiresAt : null;
  if (!["billingHold", "securityHold", "supportHold"].includes(status) ||
      reason.length < 10 ||
      (!permanent && (!expiresAt || !Number.isFinite(Date.parse(expiresAt)))) ||
      (expiresAt && Date.parse(expiresAt) <= Date.now())) {
    return json({ error: "invalid_account_hold" }, 400);
  }
  const holdStatus = status as OperationsHoldStatus;
  if (!operationsCanManageHold(identity, holdStatus)) {
    await operationsAuditStatement(env, "operations.account_hold.rejected", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      outcome: "rejected", reason: "insufficient_role",
      metadata: { requestedStatus: holdStatus },
    }).run();
    return json({ error: "operations_account_hold_forbidden" }, 403);
  }
  const current = await env.DB.prepare(
    `SELECT COALESCE(lifecycle_status, 'active') AS status
       FROM tenants LEFT JOIN platform_account_controls
         ON platform_account_controls.tenant_id = tenants.id
      WHERE tenants.id = ?1`,
  ).bind(tenantID).first<{ status: string }>();
  if (!current) return json({ error: "account_not_found" }, 404);
  const now = new Date().toISOString();
  const eventID = crypto.randomUUID();
  const effectiveExpiry = permanent ? null : expiresAt;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO platform_account_controls
        (tenant_id, lifecycle_status, reason, hold_expires_at,
         updated_by_administrator_id, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
       ON CONFLICT(tenant_id) DO UPDATE SET
         lifecycle_status = excluded.lifecycle_status,
         reason = excluded.reason, hold_expires_at = excluded.hold_expires_at,
         updated_by_administrator_id = excluded.updated_by_administrator_id,
         updated_at = excluded.updated_at`,
    ).bind(tenantID, holdStatus, reason, effectiveExpiry,
      identity.administratorID, now),
    env.DB.prepare(
      `INSERT INTO operations_account_lifecycle_events
        (id, tenant_id, administrator_id, action, from_status, to_status,
         reason, hold_expires_at, created_at)
       VALUES (?1, ?2, ?3, 'hold', ?4, ?5, ?6, ?7, ?8)`,
    ).bind(eventID, tenantID, identity.administratorID, current.status,
      holdStatus, reason, effectiveExpiry, now),
    operationsAuditStatement(env, "operations.account_hold.applied", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      reason, requestID: eventID,
      metadata: { status: holdStatus,
        expiresAt: effectiveExpiry ?? "permanent" }, createdAt: now,
    }),
  ]);
  return json({ status: holdStatus, reason, holdExpiresAt: effectiveExpiry,
    effectiveAt: now });
}

async function reactivateOperationsAccount(
  request: Request, env: Env, identity: OperationsIdentity, tenantID: string,
): Promise<Response> {
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_account_reactivation" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) return json({ error: "invalid_account_reactivation" }, 400);
  const current = await env.DB.prepare(
    `SELECT lifecycle_status AS status FROM platform_account_controls
      WHERE tenant_id = ?1`,
  ).bind(tenantID).first<{ status: string }>();
  if (!current) return json({ error: "account_not_found" }, 404);
  if (!["billingHold", "securityHold", "supportHold"].includes(current.status)) {
    return json({ error: "account_not_on_hold" }, 409);
  }
  if (!operationsCanManageHold(identity, current.status as OperationsHoldStatus)) {
    return json({ error: "operations_account_hold_forbidden" }, 403);
  }
  const now = new Date().toISOString();
  const eventID = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE platform_account_controls
          SET lifecycle_status = 'active', reason = ?2, hold_expires_at = NULL,
              updated_by_administrator_id = ?3, updated_at = ?4
        WHERE tenant_id = ?1`,
    ).bind(tenantID, reason, identity.administratorID, now),
    env.DB.prepare(
      `INSERT INTO operations_account_lifecycle_events
        (id, tenant_id, administrator_id, action, from_status, to_status,
         reason, created_at)
       VALUES (?1, ?2, ?3, 'reactivate', ?4, 'active', ?5, ?6)`,
    ).bind(eventID, tenantID, identity.administratorID, current.status, reason, now),
    operationsAuditStatement(env, "operations.account_hold.reactivated", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      reason, requestID: eventID,
      metadata: { previousStatus: current.status }, createdAt: now,
    }),
  ]);
  return json({ status: "active", reason, effectiveAt: now });
}

type OperationsAccountArchiveAction =
  "archive" | "restore" | "schedule-deletion" | "cancel-deletion";

async function manageOperationsAccountArchive(
  request: Request, env: Env, identity: OperationsIdentity,
  tenantID: string, action: OperationsAccountArchiveAction,
): Promise<Response> {
  if (identity.role !== "platformOwner") {
    return json({ error: "operations_account_archive_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_account_archive_action" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) {
    return json({ error: "invalid_account_archive_action" }, 400);
  }
  const account = await env.DB.prepare(
    `SELECT tenants.display_name AS displayName,
            COALESCE(controls.lifecycle_status, 'active') AS status,
            controls.deletion_scheduled_at AS deletionScheduledAt
       FROM tenants LEFT JOIN platform_account_controls AS controls
         ON controls.tenant_id = tenants.id WHERE tenants.id = ?1`,
  ).bind(tenantID).first<{
    displayName: string; status: string; deletionScheduledAt: string | null;
  }>();
  if (!account) return json({ error: "account_not_found" }, 404);
  const confirmation = typeof body.confirmation === "string"
    ? body.confirmation.trim() : "";
  if ((action === "archive" || action === "schedule-deletion") &&
      confirmation !== account.displayName) {
    return json({ error: "account_name_confirmation_mismatch" }, 409);
  }
  const allowed =
    (action === "archive" && !["archived", "deletionPending"].includes(account.status)) ||
    (action === "restore" && account.status === "archived") ||
    (action === "schedule-deletion" && account.status === "archived") ||
    (action === "cancel-deletion" && account.status === "deletionPending");
  if (!allowed) return json({ error: "invalid_account_archive_transition" }, 409);

  if (action === "schedule-deletion") {
    const [pendingDevices, archive] = await Promise.all([
      env.DB.prepare(
        `SELECT COUNT(*) AS count FROM devices WHERE tenant_id = ?1
          AND data_removal_required_at IS NOT NULL
          AND data_removal_acknowledged_at IS NULL`,
      ).bind(tenantID).first<{ count: number }>(),
      env.ARCHIVES.list({ prefix: tenantBackupPrefix(tenantID), limit: 1 }),
    ]);
    if (Number(pendingDevices?.count ?? 0) > 0) {
      return json({ error: "account_device_cleanup_pending" }, 409);
    }
    if (archive.objects.length === 0) {
      return json({ error: "account_archive_backup_required" }, 409);
    }
  }

  const now = new Date().toISOString();
  const deletionScheduledAt = action === "schedule-deletion"
    ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() : null;
  const nextStatus = action === "archive" || action === "cancel-deletion"
    ? "archived" : action === "restore" ? "active" : "deletionPending";
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `INSERT INTO platform_account_controls
        (tenant_id, lifecycle_status, reason, archived_at,
         deletion_scheduled_at, updated_by_administrator_id, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
       ON CONFLICT(tenant_id) DO UPDATE SET
         lifecycle_status = excluded.lifecycle_status,
         reason = excluded.reason,
         archived_at = CASE WHEN excluded.lifecycle_status = 'active'
           THEN NULL ELSE COALESCE(platform_account_controls.archived_at, excluded.archived_at) END,
         deletion_scheduled_at = excluded.deletion_scheduled_at,
         hold_expires_at = NULL,
         updated_by_administrator_id = excluded.updated_by_administrator_id,
         updated_at = excluded.updated_at`,
    ).bind(tenantID, nextStatus, reason,
      nextStatus === "active" ? null : now, deletionScheduledAt,
      identity.administratorID, now),
  ];
  if (action === "archive") {
    statements.push(env.DB.prepare(
      `UPDATE devices SET revoked_at = COALESCE(revoked_at, ?1),
              data_removal_required_at = COALESCE(data_removal_required_at, ?1)
        WHERE tenant_id = ?2`,
    ).bind(now, tenantID));
  }
  const eventID = crypto.randomUUID();
  statements.push(operationsAuditStatement(env,
    `operations.account.${action.replace("-", "_")}`, {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      reason, requestID: eventID,
      metadata: { previousStatus: account.status, nextStatus,
        deletionScheduledAt: deletionScheduledAt ?? "none" }, createdAt: now,
    }));
  await env.DB.batch(statements);
  return json({ status: nextStatus, reason, effectiveAt: now,
    deletionScheduledAt });
}

async function operationsDeletionReadiness(
  env: Env, identity: OperationsIdentity, tenantID: string,
): Promise<Response> {
  if (identity.role !== "platformOwner") {
    return json({ error: "operations_account_archive_forbidden" }, 403);
  }
  const account = await env.DB.prepare(
    "SELECT id FROM tenants WHERE id = ?1",
  ).bind(tenantID).first();
  if (!account) return json({ error: "account_not_found" }, 404);
  const pending = await env.DB.prepare(
    `SELECT devices.id, devices.display_name AS displayName,
            members.display_name AS memberName,
            devices.last_seen_at AS lastSeenAt
       FROM devices JOIN tenant_members AS members
         ON members.id = devices.member_id AND members.tenant_id = devices.tenant_id
      WHERE devices.tenant_id = ?1
        AND devices.data_removal_required_at IS NOT NULL
        AND devices.data_removal_acknowledged_at IS NULL
      ORDER BY devices.last_seen_at DESC`,
  ).bind(tenantID).all();
  const [backups, snapshot] = await Promise.all([
    env.ARCHIVES.list({ prefix: tenantBackupPrefix(tenantID), limit: 1000 }),
    env.ARCHIVES.head(tenantSynchronizationSnapshotKey(tenantID)),
  ]);
  const latest = backups.objects.sort(
    (left, right) => right.uploaded.getTime() - left.uploaded.getTime(),
  )[0];
  return json({
    ready: pending.results.length === 0 && Boolean(latest),
    pendingDevices: pending.results,
    latestBackupAt: latest?.uploaded.toISOString() ?? null,
    synchronizationSnapshotAvailable: Boolean(snapshot),
  });
}

async function confirmOperationsDeviceCleanup(
  request: Request, env: Env, identity: OperationsIdentity, tenantID: string,
): Promise<Response> {
  if (identity.role !== "platformOwner") {
    return json({ error: "operations_account_archive_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_deletion_readiness_action" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  const confirmation = typeof body.confirmation === "string"
    ? body.confirmation.trim() : "";
  const account = await env.DB.prepare(
    `SELECT tenants.display_name AS displayName,
            COALESCE(controls.lifecycle_status, 'active') AS status
       FROM tenants LEFT JOIN platform_account_controls AS controls
         ON controls.tenant_id = tenants.id WHERE tenants.id = ?1`,
  ).bind(tenantID).first<{ displayName: string; status: string }>();
  if (!account) return json({ error: "account_not_found" }, 404);
  if (account.status !== "archived" || reason.length < 10) {
    return json({ error: "invalid_deletion_readiness_action" }, 400);
  }
  if (confirmation !== account.displayName) {
    return json({ error: "account_name_confirmation_mismatch" }, 409);
  }
  const now = new Date().toISOString();
  const pending = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM devices WHERE tenant_id = ?1
      AND data_removal_required_at IS NOT NULL
      AND data_removal_acknowledged_at IS NULL`,
  ).bind(tenantID).first<{ count: number }>();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE devices SET data_removal_acknowledged_at = ?1
        WHERE tenant_id = ?2 AND data_removal_required_at IS NOT NULL
          AND data_removal_acknowledged_at IS NULL`,
    ).bind(now, tenantID),
    operationsAuditStatement(env, "operations.account.device_cleanup_confirmed", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      reason, requestID: crypto.randomUUID(),
      metadata: { manuallyConfirmedDevices: String(pending?.count ?? 0) },
      createdAt: now,
    }),
  ]);
  return json({ status: "confirmed", confirmedAt: now,
    confirmedDevices: Number(pending?.count ?? 0) });
}

async function createOperationsRecoveryArchive(
  request: Request, env: Env, identity: OperationsIdentity, tenantID: string,
): Promise<Response> {
  if (identity.role !== "platformOwner") {
    return json({ error: "operations_account_archive_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_deletion_readiness_action" }, 400); }
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 10) {
    return json({ error: "invalid_deletion_readiness_action" }, 400);
  }
  const account = await env.DB.prepare(
    `SELECT COALESCE(controls.lifecycle_status, 'active') AS status
       FROM tenants LEFT JOIN platform_account_controls AS controls
         ON controls.tenant_id = tenants.id WHERE tenants.id = ?1`,
  ).bind(tenantID).first<{ status: string }>();
  if (!account) return json({ error: "account_not_found" }, 404);
  if (account.status !== "archived") {
    return json({ error: "invalid_deletion_readiness_action" }, 400);
  }
  const snapshot = await env.ARCHIVES.get(tenantSynchronizationSnapshotKey(tenantID));
  if (!snapshot?.body) {
    return json({ error: "synchronization_snapshot_unavailable" }, 409);
  }
  const archiveID = crypto.randomUUID();
  const uploadedAt = new Date().toISOString();
  const key = `${tenantBackupPrefix(tenantID)}${uploadedAt}-${archiveID}.pfssarchive`;
  await env.ARCHIVES.put(key, snapshot.body, {
    httpMetadata: { contentType: archiveMediaType },
    customMetadata: { tenantID, archiveID, uploadedAt,
      createdByOperationsAdministratorID: identity.administratorID },
  });
  await operationsAuditStatement(env, "operations.account.recovery_archive_created", {
    administratorID: identity.administratorID, targetTenantID: tenantID,
    reason, requestID: crypto.randomUUID(), metadata: { archiveID },
    createdAt: uploadedAt,
  }).run();
  return json({ status: "created", archiveID, uploadedAt }, 201);
}

const operationsPlanEntitlements: Record<string, Record<string, number>> = {
  beta: { userLimit: 5, deviceLimit: 10, leadLimit: 1000,
    customerLimit: 1000, jobLimit: 3000 },
  trial: { userLimit: 2, deviceLimit: 4, leadLimit: 5,
    customerLimit: 5, jobLimit: 10 },
  base: { userLimit: 3, deviceLimit: 6, leadLimit: 1000,
    customerLimit: 1000, jobLimit: 3000 },
  pro: { userLimit: 5, deviceLimit: 10, leadLimit: 3000,
    customerLimit: 3000, jobLimit: 9000 },
  expert: { userLimit: 10, deviceLimit: 20, leadLimit: 10000,
    customerLimit: 10000, jobLimit: 50000 },
};

async function activeTenantEntitlements(
  env: Env, tenantID: string,
): Promise<Record<string, number>> {
  const now = new Date().toISOString();
  const override = await env.DB.prepare(
    `SELECT entitlements_json AS value FROM operations_plan_overrides
      WHERE tenant_id = ?1 AND revoked_at IS NULL AND effective_at <= ?2
        AND (expires_at IS NULL OR expires_at > ?2)
      ORDER BY effective_at DESC LIMIT 1`,
  ).bind(tenantID, now).first<{ value: string }>();
  const allocation = override ?? await env.DB.prepare(
    `SELECT entitlements_json AS value FROM plan_allocations
      WHERE tenant_id = ?1 AND revoked_at IS NULL AND effective_at <= ?2
        AND (expires_at IS NULL OR expires_at > ?2)
      ORDER BY effective_at DESC LIMIT 1`,
  ).bind(tenantID, now).first<{ value: string }>();
  if (!allocation) return {};
  try { return JSON.parse(allocation.value) as Record<string, number>; }
  catch { return {}; }
}

async function enforceNewRecordLimit(
  env: Env, tenantID: string, entityType: string,
): Promise<Response | null> {
  const keys: Record<string, string> = {
    lead: "leadLimit", customer: "customerLimit", job: "jobLimit",
  };
  const limitKey = keys[entityType];
  if (!limitKey) return null;
  const entitlements = await activeTenantEntitlements(env, tenantID);
  const limit = entitlements[limitKey];
  if (!Number.isFinite(limit)) return null;
  const count = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = ?2`,
  ).bind(tenantID, entityType).first<{ count: number }>();
  if ((count?.count ?? 0) < limit) return null;
  return json({ error: "plan_record_limit_reached", entityType, limit }, 409);
}

async function accountResourceCount(
  env: Env,
  tenantID: string,
  resource: "devices" | "users" | "employees" | "owners",
): Promise<number> {
  const sql = resource === "devices"
    ? `SELECT COUNT(*) AS count FROM devices
        WHERE tenant_id = ?1 AND revoked_at IS NULL`
    : resource === "users"
    ? `SELECT COUNT(*) AS count FROM tenant_members
        WHERE tenant_id = ?1
          AND status IN ('invited', 'active', 'suspended')`
    : resource === "owners"
    ? `SELECT COUNT(*) AS count FROM tenant_members
        WHERE tenant_id = ?1 AND role = 'owner'
          AND status IN ('invited', 'active', 'suspended')`
    : `SELECT COUNT(*) AS count FROM tenant_members
        WHERE tenant_id = ?1 AND role != 'owner'
          AND status IN ('invited', 'active', 'suspended')`;
  const row = await env.DB.prepare(sql).bind(tenantID)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function accountRecordCount(
  env: Env,
  tenantID: string,
  entityType: "lead" | "customer" | "job",
): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = ?2`,
  ).bind(tenantID, entityType).first<{ count: number }>();
  return row?.count ?? 0;
}

async function accountEntitlementStatus(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "owner_required" }, 403);
  const snapshot = await resolveAccountEntitlements(env.DB, identity.tenantID);
  if (!snapshot) {
    return json({ error: "account_entitlements_unavailable" }, 404);
  }
  const [users, employees, devices, owners, leads, customers, jobs] =
    await Promise.all([
      accountResourceCount(env, identity.tenantID, "users"),
      accountResourceCount(env, identity.tenantID, "employees"),
      accountResourceCount(env, identity.tenantID, "devices"),
      accountResourceCount(env, identity.tenantID, "owners"),
      accountRecordCount(env, identity.tenantID, "lead"),
      accountRecordCount(env, identity.tenantID, "customer"),
      accountRecordCount(env, identity.tenantID, "job"),
    ]);
  return json({
    ...snapshot,
    // The tenant UUID is the stable, server-authoritative StoreKit account token.
    appAccountToken: identity.tenantID.toLowerCase(),
    usage: { users, employees, devices, owners, leads, customers, jobs },
  });
}

async function createOperationsPlanOverride(
  request: Request, env: Env, identity: OperationsIdentity, tenantID: string,
): Promise<Response> {
  if (!operationsCanOverridePlans(identity)) {
    await operationsAuditStatement(env, "operations.plan_override.rejected", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      outcome: "rejected", reason: "insufficient_role",
    }).run();
    return json({ error: "operations_plan_override_forbidden" }, 403);
  }
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); }
  catch { return json({ error: "invalid_plan_override" }, 400); }
  const planCode = typeof body.planCode === "string" ? body.planCode.trim() : "";
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  const expiresAt = typeof body.expiresAt === "string" ? body.expiresAt : null;
  const permanent = body.permanent === true;
  const entitlements = operationsPlanEntitlements[planCode];
  if (!entitlements || reason.length < 10 ||
      (!permanent && (!expiresAt || !Number.isFinite(Date.parse(expiresAt)))) ||
      (expiresAt && Date.parse(expiresAt) <= Date.now())) {
    return json({ error: "invalid_plan_override" }, 400);
  }
  const tenant = await env.DB.prepare("SELECT id FROM tenants WHERE id = ?1")
    .bind(tenantID).first();
  if (!tenant) return json({ error: "account_not_found" }, 404);
  const now = new Date().toISOString();
  const id = crypto.randomUUID();
  const effectiveExpiry = permanent ? null : expiresAt;
  const source = planCode === "beta" ? "betaGrant" : "planOverride";
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE operations_plan_overrides
          SET revoked_at = ?2, revoked_by_administrator_id = ?3
        WHERE tenant_id = ?1 AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > ?2)`,
    ).bind(tenantID, now, identity.administratorID),
    env.DB.prepare(
      `INSERT INTO operations_plan_overrides
        (id, tenant_id, administrator_id, plan_code, access_source,
         entitlements_json, reason, effective_at, expires_at, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?8)`,
    ).bind(id, tenantID, identity.administratorID, planCode, source,
      JSON.stringify(entitlements), reason, now, effectiveExpiry),
    operationsAuditStatement(env, "operations.plan_override.granted", {
      administratorID: identity.administratorID, targetTenantID: tenantID,
      reason, requestID: id,
      metadata: { planCode, accessSource: source,
        expiresAt: effectiveExpiry ?? "permanent" }, createdAt: now,
    }),
  ]);
  return json({ id, planCode, accessSource: source, entitlements,
    effectiveAt: now, expiresAt: effectiveExpiry, reason }, 201);
}

function operationsAuditStatement(
  env: Env,
  eventType: string,
  options: {
    administratorID?: string | null;
    targetTenantID?: string | null;
    targetMemberID?: string | null;
    outcome?: "succeeded" | "rejected" | "failed";
    reason?: string | null;
    requestID?: string;
    metadata?: Record<string, string>;
    createdAt?: string;
  } = {},
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO operations_audit_events
      (id, administrator_id, event_type, target_tenant_id, target_member_id,
       outcome, reason, request_id, metadata_json, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)`,
  ).bind(
    crypto.randomUUID(), options.administratorID ?? null, eventType,
    options.targetTenantID ?? null, options.targetMemberID ?? null,
    options.outcome ?? "succeeded", options.reason ?? null,
    options.requestID ?? crypto.randomUUID(),
    JSON.stringify(options.metadata ?? {}),
    options.createdAt ?? new Date().toISOString(),
  );
}

export async function startOperationsAuthorization(
  request: Request,
  env: Env,
  provider: ManagedOwnerIdentityProvider = managedOperationsIdentityProvider(env),
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_operations_authorization_request" }, 400);
  }
  const state = nonemptyString(body.state, 43, 128);
  const codeChallenge = nonemptyString(body.codeChallenge, 43, 128);
  const redirectURI = nonemptyString(body.redirectURI, 8, 2048);
  if (!state || !codeChallenge || !redirectURI) {
    return json({ error: "invalid_operations_authorization_request" }, 400);
  }
  try {
    const session = await provider.startAuthorization({
      state, codeChallenge, redirectURI, screenHint: "sign-in",
    });
    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO operations_authorization_attempts
        (id, state_digest, code_challenge, redirect_uri, status, expires_at,
         created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, 'started', ?5, ?6, ?6)`,
    ).bind(
      crypto.randomUUID(), await sha256(state), codeChallenge, redirectURI,
      session.expiresAt, now,
    ).run();
    return json(session, 201);
  } catch (error) {
    if (error instanceof IdentityConfigurationError) {
      return json({ error: "invalid_operations_authorization_request" }, 400);
    }
    return json({ error: "identity_provider_unavailable" }, 503);
  }
}

export async function completeOperationsAuthorization(
  request: Request,
  env: Env,
  provider: ManagedOwnerIdentityProvider = managedOperationsIdentityProvider(env),
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_operations_authorization_callback" }, 400);
  }
  const state = nonemptyString(body.state, 43, 128);
  const code = nonemptyString(body.code, 20, 512);
  const codeVerifier = nonemptyString(body.codeVerifier, 43, 128);
  const redirectURI = nonemptyString(body.redirectURI, 8, 2048);
  const deviceID = nonemptyString(body.deviceID, 36, 36);
  const deviceName = nonemptyString(body.deviceName, 1, 120);
  if (!state || !code || !codeVerifier || !redirectURI ||
      !deviceID || !deviceName) {
    return json({ error: "invalid_operations_authorization_callback" }, 400);
  }
  const attempt = await env.DB.prepare(
    `SELECT id, code_challenge AS codeChallenge, redirect_uri AS redirectURI,
            status, expires_at AS expiresAt
       FROM operations_authorization_attempts WHERE state_digest = ?1`,
  ).bind(await sha256(state)).first<OwnerAuthorizationAttemptRow>();
  if (!attempt) return json({ error: "authorization_not_found" }, 404);
  if (attempt.status !== "started") {
    return json({ error: "authorization_already_used" }, 409);
  }
  const now = new Date().toISOString();
  if (Date.parse(attempt.expiresAt) <= Date.now()) {
    await env.DB.prepare(
      `UPDATE operations_authorization_attempts
          SET status = 'expired', updated_at = ?2
        WHERE id = ?1 AND status = 'started'`,
    ).bind(attempt.id, now).run();
    return json({ error: "authorization_expired" }, 410);
  }
  if (attempt.redirectURI !== redirectURI ||
      await sha256Base64URL(codeVerifier) !== attempt.codeChallenge) {
    return json({ error: "invalid_operations_authorization_callback" }, 400);
  }
  try {
    const verified = await provider.exchangeAuthorizationCode(
      code, codeVerifier, redirectURI,
    );
    const administrator = await env.DB.prepare(
      `SELECT id, normalized_email AS email, display_name AS displayName,
              provider_subject AS providerSubject, role, status
         FROM operations_administrators
        WHERE normalized_email = ?1 OR provider_subject = ?2
        LIMIT 1`,
    ).bind(verified.verifiedEmail, verified.providerSubject).first<{
      id: string;
      email: string;
      displayName: string;
      providerSubject: string | null;
      role: OperationsAdministratorRole;
      status: "invited" | "active" | "suspended" | "revoked";
    }>();
    if (!administrator || !["invited", "active"].includes(administrator.status)) {
      await operationsAuditStatement(env, "operations.sign_in_rejected", {
        outcome: "rejected", reason: "administrator_not_authorized",
        metadata: { verifiedEmail: verified.verifiedEmail }, createdAt: now,
      }).run();
      return json({ error: "operations_access_not_authorized" }, 403);
    }
    if (administrator.providerSubject &&
        administrator.providerSubject !== verified.providerSubject) {
      return json({ error: "operations_identity_mismatch" }, 403);
    }
    const sessionToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
    const sessionID = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE operations_administrators
            SET provider_subject = COALESCE(provider_subject, ?2),
                display_name = ?3, status = 'active',
                activated_at = COALESCE(activated_at, ?4), updated_at = ?4
          WHERE id = ?1 AND status IN ('invited', 'active')`,
      ).bind(administrator.id, verified.providerSubject,
        verified.displayName, now),
      env.DB.prepare(
        `INSERT INTO operations_sessions
          (id, administrator_id, token_digest, device_id, device_name,
           created_at, last_seen_at, expires_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7)
         ON CONFLICT(administrator_id, device_id) DO UPDATE SET
           id = excluded.id, token_digest = excluded.token_digest,
           device_name = excluded.device_name, created_at = excluded.created_at,
           last_seen_at = excluded.last_seen_at, expires_at = excluded.expires_at,
           revoked_at = NULL`,
      ).bind(sessionID, administrator.id, await sha256(sessionToken),
        deviceID, deviceName, now, expiresAt),
      env.DB.prepare(
        `UPDATE operations_authorization_attempts
            SET status = 'consumed', consumed_at = ?2, updated_at = ?2
          WHERE id = ?1 AND status = 'started'`,
      ).bind(attempt.id, now),
      operationsAuditStatement(env, "operations.signed_in", {
        administratorID: administrator.id, requestID: sessionID,
        metadata: { deviceID, authenticationMethod: verified.authenticationMethod },
        createdAt: now,
      }),
    ]);
    return json({
      sessionToken,
      expiresAt,
      administrator: {
        id: administrator.id,
        displayName: verified.displayName,
        email: verified.verifiedEmail,
        role: administrator.role,
      },
    });
  } catch (error) {
    if (error instanceof IdentityProviderResponseError) {
      return json({ error: "identity_verification_failed" }, 401);
    }
    if (error instanceof IdentityConfigurationError) {
      return json({ error: "invalid_operations_authorization_callback" }, 400);
    }
    return json({ error: "identity_provider_unavailable" }, 503);
  }
}

async function authenticateOperations(
  request: Request,
  env: Env,
): Promise<OperationsIdentity | Response> {
  const token = bearer(request);
  if (!token) return json({ error: "unauthorized" }, 401);
  const identity = await env.DB.prepare(
    `SELECT administrators.id AS administratorID,
            administrators.display_name AS displayName,
            administrators.normalized_email AS email,
            administrators.role AS role, sessions.id AS sessionID,
            sessions.device_id AS deviceID, sessions.device_name AS deviceName,
            sessions.expires_at AS expiresAt
       FROM operations_sessions AS sessions
       JOIN operations_administrators AS administrators
         ON administrators.id = sessions.administrator_id
      WHERE sessions.token_digest = ?1 AND sessions.revoked_at IS NULL
        AND sessions.expires_at > ?2 AND administrators.status = 'active'`,
  ).bind(await sha256(token), new Date().toISOString())
    .first<OperationsIdentity>();
  if (!identity) return json({ error: "unauthorized" }, 401);
  await env.DB.prepare(
    "UPDATE operations_sessions SET last_seen_at = ?2 WHERE id = ?1",
  ).bind(identity.sessionID, new Date().toISOString()).run();
  return identity;
}

function operationsSession(identity: OperationsIdentity): Response {
  return json({
    administrator: {
      id: identity.administratorID,
      displayName: identity.displayName,
      email: identity.email,
      role: identity.role,
    },
    device: { id: identity.deviceID, displayName: identity.deviceName },
    expiresAt: identity.expiresAt,
  });
}

async function operationsSummary(
  env: Env,
  identity: OperationsIdentity,
): Promise<Response> {
  if (!operationsCanViewAccounts(identity)) return json({ error: "forbidden" }, 403);
  const [accounts, members, devices, unresolvedConflicts, pendingRemoval,
    failedRegistrations] = await env.DB.batch([
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM tenants`,
    ),
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM tenant_members WHERE status = 'active'`,
    ),
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM devices WHERE revoked_at IS NULL`,
    ),
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM synchronization_conflicts
        WHERE status = 'unresolved'`,
    ),
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM devices
        WHERE data_removal_required_at IS NOT NULL
          AND data_removal_acknowledged_at IS NULL`,
    ),
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM account_registration_attempts
        WHERE status = 'failedRolledBack'`,
    ),
  ]);
  const count = (result: D1Result<unknown>) =>
    Number((result.results[0] as { count?: number } | undefined)?.count ?? 0);
  return json({
    accounts: { total: count(accounts) },
    users: { active: count(members) },
    devices: { active: count(devices), pendingDataRemoval: count(pendingRemoval) },
    errors: {
      unresolvedSynchronizationConflicts: count(unresolvedConflicts),
      failedRegistrations: count(failedRegistrations),
    },
    generatedAt: new Date().toISOString(),
  });
}

async function operationsMonitoring(
  env: Env,
  identity: OperationsIdentity,
): Promise<Response> {
  if (!operationsCanViewAccounts(identity)) return json({ error: "forbidden" }, 403);
  const now = new Date();
  const monthStart = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), 1,
  )).toISOString();
  const [workOSMAU, unresolvedConflicts, failedRegistrations, pendingRemovals,
    accountRows] = await env.DB.batch([
    env.DB.prepare(
      `SELECT COUNT(DISTINCT subject_id) AS count
         FROM owner_authorization_attempts
        WHERE subject_id IS NOT NULL AND created_at >= ?1`,
    ).bind(monthStart),
    env.DB.prepare(
      `SELECT conflicts.id, conflicts.tenant_id AS tenantID,
              tenants.display_name AS accountName,
              conflicts.entity_type AS entityType,
              conflicts.detected_at AS occurredAt
         FROM synchronization_conflicts AS conflicts
         JOIN tenants ON tenants.id = conflicts.tenant_id
        WHERE conflicts.status = 'unresolved'
        ORDER BY conflicts.detected_at DESC LIMIT 50`,
    ),
    env.DB.prepare(
      `SELECT attempts.id, attempts.tenant_id AS tenantID,
              COALESCE(tenants.display_name, attempts.company_display_name)
                AS accountName,
              attempts.normalized_email AS email,
              attempts.updated_at AS occurredAt
         FROM account_registration_attempts AS attempts
         LEFT JOIN tenants ON tenants.id = attempts.tenant_id
        WHERE attempts.status = 'failedRolledBack'
        ORDER BY attempts.updated_at DESC LIMIT 50`,
    ),
    env.DB.prepare(
      `SELECT devices.id, devices.tenant_id AS tenantID,
              tenants.display_name AS accountName,
              devices.display_name AS deviceName,
              devices.data_removal_required_at AS occurredAt
         FROM devices JOIN tenants ON tenants.id = devices.tenant_id
        WHERE devices.data_removal_required_at IS NOT NULL
          AND devices.data_removal_acknowledged_at IS NULL
        ORDER BY devices.data_removal_required_at DESC LIMIT 50`,
    ),
    env.DB.prepare(
      `SELECT tenants.id AS tenantID, tenants.display_name AS accountName,
              (SELECT COUNT(*) FROM tenant_members
                WHERE tenant_id = tenants.id
                  AND status IN ('invited', 'active', 'suspended')) AS users,
              (SELECT COUNT(*) FROM synchronized_records
                WHERE tenant_id = tenants.id AND entity_type = 'lead') AS leads,
              (SELECT COUNT(*) FROM synchronized_records
                WHERE tenant_id = tenants.id AND entity_type = 'customer') AS customers,
              (SELECT COUNT(*) FROM synchronized_records
                WHERE tenant_id = tenants.id AND entity_type = 'job') AS jobs,
              COALESCE(
                (SELECT entitlements_json FROM operations_plan_overrides
                  WHERE tenant_id = tenants.id AND revoked_at IS NULL
                    AND effective_at <= ?1
                    AND (expires_at IS NULL OR expires_at > ?1)
                  ORDER BY effective_at DESC LIMIT 1),
                (SELECT entitlements_json FROM plan_allocations
                  WHERE tenant_id = tenants.id AND revoked_at IS NULL
                    AND effective_at <= ?1
                    AND (expires_at IS NULL OR expires_at > ?1)
                  ORDER BY effective_at DESC LIMIT 1)
              ) AS entitlementsJSON
         FROM tenants ORDER BY tenants.display_name COLLATE NOCASE`,
    ).bind(now.toISOString()),
  ]);

  let r2Bytes = 0;
  let r2Objects = 0;
  let cursor: string | undefined;
  do {
    const page = await env.ARCHIVES.list({ limit: 1000, cursor });
    r2Bytes += page.objects.reduce((sum, object) => sum + object.size, 0);
    r2Objects += page.objects.length;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);

  const numberValue = (value: string | undefined, fallback: number) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
  };
  const r2Limit = numberValue(env.CLOUDFLARE_R2_STORAGE_LIMIT_BYTES,
    10 * 1024 * 1024 * 1024);
  const workersLimit = numberValue(env.CLOUDFLARE_WORKERS_DAILY_REQUEST_LIMIT,
    100_000);
  const workOSLimit = numberValue(env.WORKOS_AUTHKIT_MONTHLY_ACTIVE_USER_LIMIT,
    1_000_000);
  const observedMAU = Number(
    (workOSMAU.results[0] as { count?: number } | undefined)?.count ?? 0,
  );
  let cloudflareUsage: {
    workerRequests: number; d1RowsRead: number; d1RowsWritten: number;
  } | null = null;
  let cloudflareTelemetrySource = "Provider telemetry unavailable";
  if (env.CLOUDFLARE_ANALYTICS_API_TOKEN && env.CLOUDFLARE_ACCOUNT_ID &&
      env.CLOUDFLARE_D1_DATABASE_ID && env.CLOUDFLARE_WORKER_SCRIPT_NAME) {
    try {
      const today = now.toISOString().slice(0, 10);
      const datetimeStart = `${today}T00:00:00.000Z`;
      const response = await fetch("https://api.cloudflare.com/client/v4/graphql", {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.CLOUDFLARE_ANALYTICS_API_TOKEN
          .replace(/[^A-Za-z0-9_-]/g, "")}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        query: `query PFSSUsage($accountTag: string, $datetimeStart: string,
          $datetimeEnd: string, $scriptName: string, $date: Date,
          $databaseId: string) {
          viewer { accounts(filter: {accountTag: $accountTag}) {
            workersInvocationsAdaptive(limit: 10000, filter: {
              scriptName: $scriptName, datetime_geq: $datetimeStart,
              datetime_leq: $datetimeEnd }) { sum { requests } }
            d1AnalyticsAdaptiveGroups(limit: 10000, filter: {
              date_geq: $date, date_leq: $date, databaseId: $databaseId }) {
              sum { rowsRead rowsWritten }
            }
          } }
        }`,
        variables: {
          accountTag: env.CLOUDFLARE_ACCOUNT_ID,
          datetimeStart, datetimeEnd: now.toISOString(), date: today,
          scriptName: env.CLOUDFLARE_WORKER_SCRIPT_NAME,
          databaseId: env.CLOUDFLARE_D1_DATABASE_ID,
        },
      }),
      });
      if (response.ok) {
        const payload = await response.json<{
        data?: { viewer?: { accounts?: Array<{
          workersInvocationsAdaptive?: Array<{ sum?: { requests?: number } }>;
          d1AnalyticsAdaptiveGroups?: Array<{
            sum?: { rowsRead?: number; rowsWritten?: number };
          }>;
        }> } };
        errors?: unknown[];
        }>();
        const account = payload.data?.viewer?.accounts?.[0];
        if (account && !payload.errors?.length) {
          cloudflareUsage = {
          workerRequests: (account.workersInvocationsAdaptive ?? [])
            .reduce((sum, row) => sum + Number(row.sum?.requests ?? 0), 0),
          d1RowsRead: (account.d1AnalyticsAdaptiveGroups ?? [])
            .reduce((sum, row) => sum + Number(row.sum?.rowsRead ?? 0), 0),
          d1RowsWritten: (account.d1AnalyticsAdaptiveGroups ?? [])
            .reduce((sum, row) => sum + Number(row.sum?.rowsWritten ?? 0), 0),
          };
          cloudflareTelemetrySource = "Cloudflare Analytics API";
        } else if (payload.errors?.length) {
          const first = payload.errors[0] as { message?: unknown };
          cloudflareTelemetrySource = typeof first?.message === "string"
            ? `Cloudflare API: ${first.message.slice(0, 160)}`
            : "Cloudflare Analytics API returned an error";
        }
      } else {
        const detail = (await response.text())
          .replace(/[\r\n\t]+/g, " ")
          .replace(/\s{2,}/g, " ")
          .slice(0, 220);
        cloudflareTelemetrySource = detail
          ? `Cloudflare API HTTP ${response.status}: ${detail}`
          : `Cloudflare Analytics API HTTP ${response.status}`;
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown provider error";
      cloudflareTelemetrySource = `Cloudflare telemetry unavailable: ${message.slice(0, 140)}`;
    }
  }
  const metric = (provider: string, name: string, used: number | null,
    limit: number | null, unit: string, source: string) => ({
      provider, name, used, limit, unit, source,
      utilization: used !== null && limit ? used / limit : null,
      status: used === null || !limit ? "unavailable"
        : used >= limit ? "critical" : used >= limit * 0.8 ? "warning" : "normal",
    });
  const providerMetrics = [
    metric("Cloudflare", "Workers requests today",
      cloudflareUsage?.workerRequests ?? null, workersLimit, "requests",
      cloudflareTelemetrySource),
    metric("Cloudflare", "D1 rows read today",
      cloudflareUsage?.d1RowsRead ?? null, 5_000_000, "rows",
      cloudflareTelemetrySource),
    metric("Cloudflare", "D1 rows written today",
      cloudflareUsage?.d1RowsWritten ?? null, 100_000, "rows",
      cloudflareTelemetrySource),
    metric("Cloudflare", "R2 archive storage", r2Bytes, r2Limit, "bytes",
      "Measured from PFSS archive bucket"),
    metric("WorkOS", "AuthKit monthly active users", observedMAU, workOSLimit, "users",
      "PFSS-observed authentications; verify provider dashboard for billing"),
  ];

  const accountAlerts: Record<string, unknown>[] = [];
  for (const raw of accountRows.results as Record<string, unknown>[]) {
    let limits: Record<string, number | null> = {};
    if (typeof raw.entitlementsJSON === "string") {
      try { limits = JSON.parse(raw.entitlementsJSON) as Record<string, number | null>; }
      catch { limits = {}; }
    }
    for (const [resource, limitKey] of [
      ["users", "userLimit"], ["leads", "leadLimit"],
      ["customers", "customerLimit"], ["jobs", "jobLimit"],
    ] as const) {
      const used = Number(raw[resource] ?? 0);
      const limit = limits[limitKey];
      if (typeof limit !== "number" || limit <= 0 || used < limit * 0.8) continue;
      accountAlerts.push({
        tenantID: raw.tenantID, accountName: raw.accountName, resource,
        used, limit, utilization: used / limit,
        severity: used >= limit ? "critical" : "warning",
      });
    }
  }
  accountAlerts.sort((left, right) =>
    Number(right.utilization) - Number(left.utilization));
  const errors: Record<string, unknown>[] = [
    ...(unresolvedConflicts.results as Record<string, unknown>[]).map((item) => ({
      ...item, category: "synchronizationConflict", severity: "warning",
      summary: `Unresolved ${String(item.entityType ?? "record")} conflict`,
    })),
    ...(failedRegistrations.results as Record<string, unknown>[]).map((item) => ({
      ...item, category: "failedRegistration", severity: "critical",
      summary: "Account registration failed and rolled back",
    })),
    ...(pendingRemovals.results as Record<string, unknown>[]).map((item) => ({
      ...item, category: "pendingDataRemoval", severity: "warning",
      summary: `Company-data removal pending on ${String(item.deviceName ?? "device")}`,
    })),
  ];
  errors.sort((left, right) =>
    String(right.occurredAt).localeCompare(String(left.occurredAt)));
  return json({ providerMetrics, accountAlerts, errors,
    archiveObjects: r2Objects, generatedAt: now.toISOString() });
}

async function listOperationsAccounts(
  url: URL,
  env: Env,
  identity: OperationsIdentity,
): Promise<Response> {
  if (!operationsCanViewAccounts(identity)) return json({ error: "forbidden" }, 403);
  const search = (url.searchParams.get("search") ?? "").trim().slice(0, 160);
  const lifecycle = (url.searchParams.get("status") ?? "all").trim();
  const allowedStatuses = new Set([
    "all", "active", "billingHold", "securityHold", "supportHold",
    "archived", "deletionPending",
  ]);
  if (!allowedStatuses.has(lifecycle)) {
    return json({ error: "invalid_status_filter" }, 400);
  }
  const requestedLimit = Number.parseInt(url.searchParams.get("limit") ?? "50", 10);
  const limit = Math.min(Math.max(requestedLimit || 50, 1), 100);
  const requestedOffset = Number.parseInt(url.searchParams.get("offset") ?? "0", 10);
  const offset = Math.max(requestedOffset || 0, 0);
  const result = await env.DB.prepare(
    `SELECT tenants.id, tenants.display_name AS displayName,
            tenants.created_at AS createdAt,
            CASE
              WHEN controls.lifecycle_status IN
                ('billingHold', 'securityHold', 'supportHold')
               AND controls.hold_expires_at IS NOT NULL
               AND controls.hold_expires_at <= ?1 THEN 'active'
              ELSE COALESCE(controls.lifecycle_status, 'active')
            END AS lifecycleStatus,
            subscriptions.status AS subscriptionStatus,
            COALESCE(
              (SELECT plan_code FROM operations_plan_overrides
                WHERE tenant_id = tenants.id AND revoked_at IS NULL
                  AND effective_at <= ?1
                  AND (expires_at IS NULL OR expires_at > ?1)
                ORDER BY effective_at DESC LIMIT 1),
              (SELECT plan_code FROM plan_allocations
                WHERE tenant_id = tenants.id AND revoked_at IS NULL
                  AND effective_at <= ?1
                  AND (expires_at IS NULL OR expires_at > ?1)
                ORDER BY effective_at DESC LIMIT 1)
            ) AS planCode,
            COALESCE(
              (SELECT access_source FROM operations_plan_overrides
                WHERE tenant_id = tenants.id AND revoked_at IS NULL
                  AND effective_at <= ?1
                  AND (expires_at IS NULL OR expires_at > ?1)
                ORDER BY effective_at DESC LIMIT 1),
              (SELECT access_source FROM plan_allocations
                WHERE tenant_id = tenants.id AND revoked_at IS NULL
                  AND effective_at <= ?1
                  AND (expires_at IS NULL OR expires_at > ?1)
                ORDER BY effective_at DESC LIMIT 1)
            ) AS accessSource,
            (SELECT COUNT(*) FROM tenant_members
              WHERE tenant_id = tenants.id AND status = 'active') AS activeUsers,
            (SELECT COUNT(*) FROM devices
              WHERE tenant_id = tenants.id AND revoked_at IS NULL) AS activeDevices,
            (SELECT MAX(last_seen_at) FROM devices
              WHERE tenant_id = tenants.id) AS lastActivityAt
       FROM tenants
       LEFT JOIN platform_account_controls AS controls
         ON controls.tenant_id = tenants.id
       LEFT JOIN subscription_accounts AS subscriptions
         ON subscriptions.tenant_id = tenants.id
      WHERE (?2 = '' OR lower(tenants.display_name) LIKE '%' || lower(?2) || '%'
             OR lower(tenants.id) = lower(?2)
             OR EXISTS (
               SELECT 1 FROM tenant_members AS searchable_members
               JOIN verified_contact_addresses AS searchable_contacts
                 ON searchable_contacts.subject_id =
                    searchable_members.authentication_subject_id
                AND searchable_contacts.kind = 'email'
              WHERE searchable_members.tenant_id = tenants.id
                AND lower(searchable_contacts.normalized_value)
                    LIKE '%' || lower(?2) || '%'
             )
             OR EXISTS (
               SELECT 1 FROM owner_account_invitations AS owner_invitations
                WHERE owner_invitations.tenant_id = tenants.id
                  AND lower(owner_invitations.invited_email)
                      LIKE '%' || lower(?2) || '%'
             )
             OR EXISTS (
               SELECT 1 FROM account_registration_attempts AS registrations
                WHERE registrations.tenant_id = tenants.id
                  AND lower(registrations.normalized_email)
                      LIKE '%' || lower(?2) || '%'
             )
             OR EXISTS (
               SELECT 1 FROM operations_account_email_index AS indexed_emails
                WHERE indexed_emails.tenant_id = tenants.id
                  AND lower(indexed_emails.normalized_email)
                      LIKE '%' || lower(?2) || '%'
             ))
        AND (?3 = 'all' OR (CASE
              WHEN controls.lifecycle_status IN
                ('billingHold', 'securityHold', 'supportHold')
               AND controls.hold_expires_at IS NOT NULL
               AND controls.hold_expires_at <= ?1 THEN 'active'
              ELSE COALESCE(controls.lifecycle_status, 'active')
            END) = ?3)
      ORDER BY tenants.display_name COLLATE NOCASE ASC
      LIMIT ?4 OFFSET ?5`,
  ).bind(new Date().toISOString(), search, lifecycle, limit + 1, offset).all();
  const hasMore = result.results.length > limit;
  return json({
    accounts: result.results.slice(0, limit),
    page: { offset, limit, hasMore, nextOffset: hasMore ? offset + limit : null },
  });
}

async function operationsAccountDetail(
  env: Env,
  identity: OperationsIdentity,
  tenantID: string,
): Promise<Response> {
  if (!operationsCanViewAccounts(identity)) return json({ error: "forbidden" }, 403);
  const account = await env.DB.prepare(
    `SELECT tenants.id, tenants.display_name AS displayName,
            tenants.created_at AS createdAt,
            CASE
              WHEN controls.lifecycle_status IN
                ('billingHold', 'securityHold', 'supportHold')
               AND controls.hold_expires_at IS NOT NULL
               AND controls.hold_expires_at <= ?2 THEN 'active'
              ELSE COALESCE(controls.lifecycle_status, 'active')
            END AS lifecycleStatus,
            controls.reason AS lifecycleReason,
            controls.hold_expires_at AS holdExpiresAt,
            controls.archived_at AS archivedAt,
            controls.deletion_scheduled_at AS deletionScheduledAt,
            subscriptions.status AS subscriptionStatus,
            allocations.plan_code AS planCode,
            allocations.access_source AS accessSource,
            allocations.entitlements_json AS entitlementsJSON,
            allocations.effective_at AS planEffectiveAt,
            allocations.expires_at AS planExpiresAt
       FROM tenants
       LEFT JOIN platform_account_controls AS controls
         ON controls.tenant_id = tenants.id
       LEFT JOIN subscription_accounts AS subscriptions
         ON subscriptions.tenant_id = tenants.id
       LEFT JOIN plan_allocations AS allocations ON allocations.id = (
         SELECT id FROM plan_allocations
          WHERE tenant_id = tenants.id AND revoked_at IS NULL
            AND effective_at <= ?2 AND (expires_at IS NULL OR expires_at > ?2)
          ORDER BY effective_at DESC LIMIT 1
       )
      WHERE tenants.id = ?1`,
  ).bind(tenantID, new Date().toISOString()).first<Record<string, unknown>>();
  if (!account) return json({ error: "account_not_found" }, 404);
  const activeOverride = await env.DB.prepare(
    `SELECT plan_code AS planCode, access_source AS accessSource,
            entitlements_json AS entitlementsJSON,
            effective_at AS planEffectiveAt, expires_at AS planExpiresAt,
            reason AS overrideReason
       FROM operations_plan_overrides
      WHERE tenant_id = ?1 AND revoked_at IS NULL AND effective_at <= ?2
        AND (expires_at IS NULL OR expires_at > ?2)
      ORDER BY effective_at DESC LIMIT 1`,
  ).bind(tenantID, new Date().toISOString()).first<Record<string, unknown>>();
  if (activeOverride) Object.assign(account, activeOverride);
  const [members, devices, usage, conflicts, recentAudit] = await env.DB.batch([
    env.DB.prepare(
      `SELECT members.id, members.display_name AS displayName,
              members.role, members.status, members.employee_id AS employeeID,
              CASE WHEN members.authentication_subject_id IS NULL
                   THEN 0 ELSE 1 END AS recoveryAvailable,
              COALESCE(
                (SELECT contacts.normalized_value
                   FROM verified_contact_addresses AS contacts
                  WHERE contacts.subject_id = members.authentication_subject_id
                    AND contacts.kind = 'email'
                  ORDER BY contacts.verified_at DESC LIMIT 1),
                (SELECT indexed.normalized_email
                   FROM operations_account_email_index AS indexed
                  WHERE indexed.tenant_id = members.tenant_id
                    AND indexed.source_kind = 'employeeRecord'
                    AND indexed.source_id = lower(members.employee_id)
                  LIMIT 1)
              ) AS email,
              members.created_at AS createdAt,
              members.activated_at AS activatedAt,
              members.revoked_at AS revokedAt,
              members.operations_archived_at AS archivedAt,
              members.operations_removed_at AS removedAt
         FROM tenant_members AS members
        WHERE members.tenant_id = ?1 ORDER BY members.created_at ASC`,
    ).bind(tenantID),
    env.DB.prepare(
      `SELECT devices.id, devices.member_id AS memberID,
              devices.display_name AS displayName,
              members.display_name AS memberName,
              COALESCE(
                (SELECT contacts.normalized_value
                   FROM verified_contact_addresses AS contacts
                  WHERE contacts.subject_id = members.authentication_subject_id
                    AND contacts.kind = 'email'
                  ORDER BY contacts.verified_at DESC LIMIT 1),
                (SELECT indexed.normalized_email
                   FROM operations_account_email_index AS indexed
                  WHERE indexed.tenant_id = members.tenant_id
                    AND indexed.source_kind = 'employeeRecord'
                    AND indexed.source_id = lower(members.employee_id)
                  LIMIT 1)
              ) AS memberEmail,
              CASE WHEN devices.revoked_at IS NULL
                   THEN 'active' ELSE 'revoked' END AS status,
              devices.created_at AS createdAt,
              devices.last_seen_at AS lastSeenAt,
              devices.revoked_at AS revokedAt,
              devices.data_removal_required_at AS dataRemovalRequiredAt,
              devices.data_removal_acknowledged_at AS dataRemovalAcknowledgedAt,
              devices.operations_removed_at AS removedAt
         FROM devices
         JOIN tenant_members AS members
           ON members.id = devices.member_id
          AND members.tenant_id = devices.tenant_id
        WHERE devices.tenant_id = ?1 ORDER BY devices.last_seen_at DESC`,
    ).bind(tenantID),
    env.DB.prepare(
      `SELECT entity_type AS entityType, COUNT(*) AS count
         FROM synchronized_records WHERE tenant_id = ?1
        GROUP BY entity_type ORDER BY entity_type`,
    ).bind(tenantID),
    env.DB.prepare(
      `SELECT COUNT(*) AS count FROM synchronization_conflicts
        WHERE tenant_id = ?1 AND status = 'unresolved'`,
    ).bind(tenantID),
    env.DB.prepare(
      `SELECT event_type AS eventType, created_at AS createdAt,
              metadata_json AS metadataJSON
         FROM access_audit_events WHERE tenant_id = ?1
        ORDER BY created_at DESC LIMIT 25`,
    ).bind(tenantID),
  ]);
  const entitlementsJSON = account.entitlementsJSON;
  const entitlements = typeof entitlementsJSON === "string"
    ? JSON.parse(entitlementsJSON) as unknown
    : {};
  delete account.entitlementsJSON;
  return json({
    account: { ...account, entitlements },
    members: members.results,
    devices: devices.results,
    usage: usage.results,
    errors: {
      unresolvedSynchronizationConflicts:
        Number((conflicts.results[0] as { count?: number } | undefined)?.count ?? 0),
    },
    recentAudit: recentAudit.results.map((event) => {
      const row = event as { eventType: string; createdAt: string; metadataJSON: string };
      return {
        eventType: row.eventType,
        createdAt: row.createdAt,
        metadata: JSON.parse(row.metadataJSON),
      };
    }),
  });
}

export async function startOwnerAuthorization(
  request: Request,
  env: Env,
  provider: ManagedOwnerIdentityProvider = managedOwnerIdentityProvider(env),
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_authorization_request" }, 400);
  }
  const state = nonemptyString(body.state, 43, 128);
  const codeChallenge = nonemptyString(body.codeChallenge, 43, 128);
  const redirectURI = nonemptyString(body.redirectURI, 8, 2048);
  const rawEmailHint = body.emailHint === undefined
    ? null
    : nonemptyString(body.emailHint, 3, 254)?.toLowerCase() ?? null;
  if (!state || !codeChallenge || !redirectURI ||
      (rawEmailHint !== null && !validEmail(rawEmailHint))) {
    return json({ error: "invalid_authorization_request" }, 400);
  }
  try {
    const session = await provider.startAuthorization({
      state,
      codeChallenge,
      redirectURI,
      emailHint: rawEmailHint ?? undefined,
    });
    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO owner_authorization_attempts
        (id, state_digest, code_challenge, redirect_uri, email_hint, status,
         expires_at, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, 'started', ?6, ?7, ?7)`,
    ).bind(
      crypto.randomUUID(), await sha256(state), codeChallenge, redirectURI,
      rawEmailHint, session.expiresAt, now,
    ).run();
    return json(session, 201);
  } catch (error) {
    if (error instanceof IdentityConfigurationError) {
      return json({ error: "invalid_authorization_request" }, 400);
    }
    return json({ error: "identity_provider_unavailable" }, 503);
  }
}

async function persistVerifiedOwnerIdentity(
  env: Env,
  identity: Awaited<ReturnType<ManagedOwnerIdentityProvider["exchangeAuthorizationCode"]>>,
): Promise<{ subjectID: string; wasCreated: boolean } | Response> {
  const existingIdentity = await env.DB.prepare(
    `SELECT subject_id AS subjectID
       FROM authentication_identities
      WHERE provider_key = ?1 AND provider_subject = ?2`,
  ).bind(identity.providerKey, identity.providerSubject)
    .first<{ subjectID: string }>();
  const existingContact = await env.DB.prepare(
    `SELECT subject_id AS subjectID
       FROM verified_contact_addresses
      WHERE kind = 'email' AND normalized_value = ?1`,
  ).bind(identity.verifiedEmail).first<{ subjectID: string }>();
  if (existingIdentity && existingContact &&
      existingIdentity.subjectID !== existingContact.subjectID) {
    return json({ error: "identity_linking_required" }, 409);
  }
  if (!existingIdentity && existingContact) {
    return json({ error: "identity_linking_required" }, 409);
  }
  const subjectID = existingIdentity?.subjectID ?? crypto.randomUUID();
  const now = new Date().toISOString();
  const statements = existingIdentity
    ? [
        env.DB.prepare(
          `UPDATE authentication_subjects
              SET display_name = ?2, status = 'active', updated_at = ?3
            WHERE id = ?1`,
        ).bind(subjectID, identity.displayName, now),
        env.DB.prepare(
          `UPDATE authentication_identities
              SET last_authenticated_at = ?3
            WHERE provider_key = ?1 AND provider_subject = ?2`,
        ).bind(identity.providerKey, identity.providerSubject, now),
      ]
    : [
        env.DB.prepare(
          `INSERT INTO authentication_subjects
            (id, display_name, status, created_at, updated_at)
           VALUES (?1, ?2, 'active', ?3, ?3)`,
        ).bind(subjectID, identity.displayName, now),
        env.DB.prepare(
          `INSERT INTO authentication_identities
            (id, subject_id, provider_key, provider_subject, method,
             created_at, last_authenticated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
        ).bind(
          crypto.randomUUID(), subjectID, identity.providerKey,
          identity.providerSubject,
          accountAuthenticationMethod(identity.authenticationMethod), now,
        ),
      ];
  if (!existingContact) {
    statements.push(env.DB.prepare(
      `INSERT INTO verified_contact_addresses
        (id, subject_id, kind, normalized_value, verified_at, created_at)
       VALUES (?1, ?2, 'email', ?3, ?4, ?4)`,
    ).bind(crypto.randomUUID(), subjectID, identity.verifiedEmail, now));
  }
  await env.DB.batch(statements);
  return { subjectID, wasCreated: !existingIdentity };
}

export async function completeOwnerAuthorization(
  request: Request,
  env: Env,
  provider: ManagedOwnerIdentityProvider = managedOwnerIdentityProvider(env),
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_authorization_callback" }, 400);
  }
  const state = nonemptyString(body.state, 43, 128);
  const code = nonemptyString(body.code, 20, 512);
  const codeVerifier = nonemptyString(body.codeVerifier, 43, 128);
  const redirectURI = nonemptyString(body.redirectURI, 8, 2048);
  if (!state || !code || !codeVerifier || !redirectURI) {
    return json({ error: "invalid_authorization_callback" }, 400);
  }
  const attempt = await env.DB.prepare(
    `SELECT id, code_challenge AS codeChallenge, redirect_uri AS redirectURI,
            status, expires_at AS expiresAt
       FROM owner_authorization_attempts WHERE state_digest = ?1`,
  ).bind(await sha256(state)).first<OwnerAuthorizationAttemptRow>();
  if (!attempt) return json({ error: "authorization_not_found" }, 404);
  if (attempt.status !== "started") {
    return json({ error: "authorization_already_used" }, 409);
  }
  if (Date.parse(attempt.expiresAt) <= Date.now()) {
    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE owner_authorization_attempts
          SET status = 'expired', updated_at = ?2
        WHERE id = ?1 AND status = 'started'`,
    ).bind(attempt.id, now).run();
    return json({ error: "authorization_expired" }, 410);
  }
  if (attempt.redirectURI !== redirectURI ||
      await sha256Base64URL(codeVerifier) !== attempt.codeChallenge) {
    return json({ error: "invalid_authorization_callback" }, 400);
  }
  try {
    const identity = await provider.exchangeAuthorizationCode(
      code, codeVerifier, redirectURI,
    );
    const persistedIdentity = await persistVerifiedOwnerIdentity(env, identity);
    if (persistedIdentity instanceof Response) return persistedIdentity;
    const identityAssertion = `pfss_owner_${crypto.randomUUID()}${crypto.randomUUID()}`;
    const method = accountAuthenticationMethod(identity.authenticationMethod);
    const now = new Date().toISOString();
    const updated = await env.DB.prepare(
      `UPDATE owner_authorization_attempts
          SET status = 'verified', subject_id = ?2,
              subject_was_created = ?3, identity_assertion_digest = ?4,
              provider_method = ?5, verified_at = ?6, updated_at = ?6
        WHERE id = ?1 AND status = 'started'`,
    ).bind(
      attempt.id, persistedIdentity.subjectID,
      persistedIdentity.wasCreated ? 1 : 0,
      await sha256(identityAssertion), method, now,
    ).run();
    if (updated.meta.changes !== 1) {
      return json({ error: "authorization_already_used" }, 409);
    }
    return json({
      identityAssertion,
      authenticationMethod: method,
      owner: {
        displayName: identity.displayName,
        email: identity.verifiedEmail,
      },
    });
  } catch (error) {
    if (error instanceof IdentityConfigurationError) {
      return json({ error: "invalid_authorization_callback" }, 400);
    }
    if (error instanceof IdentityProviderResponseError) {
      return json({ error: "identity_verification_failed" }, 401);
    }
    console.error("Owner authorization callback failed", error instanceof Error
      ? { name: error.name, message: error.message }
      : { name: "UnknownError" });
    return json({ error: "identity_provider_unavailable" }, 503);
  }
}

async function signInExistingOwner(
  request: Request,
  env: Env,
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_owner_sign_in" }, 400);
  }
  const identityAssertion = nonemptyString(body.identityAssertion, 20, 4096);
  const deviceID = nonemptyString(body.deviceID, 36, 36);
  const deviceName = nonemptyString(body.deviceName, 1, 120);
  if (!identityAssertion || !deviceID || !deviceName) {
    return json({ error: "invalid_owner_sign_in" }, 400);
  }
  const assertionDigest = await sha256(identityAssertion);
  const now = new Date().toISOString();
  const authorization = await env.DB.prepare(
    `SELECT id, subject_id AS subjectID
       FROM owner_authorization_attempts
      WHERE identity_assertion_digest = ?1 AND status = 'verified'
        AND expires_at > ?2`,
  ).bind(assertionDigest, now).first<{ id: string; subjectID: string }>();
  if (!authorization?.subjectID) {
    return json({ error: "identity_verification_required" }, 401);
  }
  const memberships = await env.DB.prepare(
    `SELECT members.id AS memberID, members.tenant_id AS tenantID,
            tenants.display_name AS tenantName
       FROM tenant_members AS members
       JOIN tenants ON tenants.id = members.tenant_id
      WHERE members.authentication_subject_id = ?1
        AND members.role = 'owner' AND members.status = 'active'
        AND tenants.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM platform_account_controls AS controls
           WHERE controls.tenant_id = tenants.id
             AND (
               controls.lifecycle_status IN ('archived', 'deletionPending')
               OR (
                 controls.lifecycle_status IN
                   ('billingHold', 'securityHold', 'supportHold')
                 AND (controls.hold_expires_at IS NULL OR controls.hold_expires_at > ?2)
               )
             )
        )`,
  ).bind(authorization.subjectID, now).all<{
    memberID: string;
    tenantID: string;
    tenantName: string;
  }>();
  if (memberships.results.length === 0) {
    return json({ error: "owner_company_not_found" }, 404);
  }
  if (memberships.results.length > 1) {
    return json({ error: "owner_company_selection_required" }, 409);
  }
  const membership = memberships.results[0];
  const deviceToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const tokenDigest = await sha256(deviceToken);
  const existingDevice = await env.DB.prepare(
    `SELECT member_id AS memberID FROM devices
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(membership.tenantID, deviceID).first<{ memberID: string }>();
  if (!existingDevice) {
    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM devices WHERE tenant_id = ?1 AND revoked_at IS NULL",
    ).bind(membership.tenantID).first<{ count: number }>();
    if ((count?.count ?? 0) >= stagingRegistrationEntitlements.deviceLimit) {
      return json({ error: "device_limit_reached" }, 409);
    }
  }
  await env.DB.batch([
    existingDevice
      ? env.DB.prepare(
        `UPDATE devices
            SET member_id = ?1, display_name = ?2, token_hash = ?3,
                last_seen_at = ?4, revoked_at = NULL,
                data_removal_required_at = NULL,
                data_removal_acknowledged_at = NULL,
                credentials_purged_at = NULL
          WHERE tenant_id = ?5 AND id = ?6`,
      ).bind(membership.memberID, deviceName, tokenDigest, now,
        membership.tenantID, deviceID)
      : env.DB.prepare(
        `INSERT INTO devices
          (id, tenant_id, member_id, display_name, token_hash, created_at,
           last_seen_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
      ).bind(deviceID, membership.tenantID, membership.memberID, deviceName,
        tokenDigest, now),
    env.DB.prepare(
      `UPDATE owner_authorization_attempts
          SET status = 'consumed', consumed_at = ?2, updated_at = ?2
        WHERE id = ?1 AND status = 'verified'`,
    ).bind(authorization.id, now),
    accessAuditStatement(env, membership.tenantID, "account.owner_signed_in", {
      actorMemberID: membership.memberID,
      actorDeviceID: deviceID,
      targetMemberID: membership.memberID,
      targetDeviceID: deviceID,
      metadata: { existingDevice: existingDevice ? "true" : "false" },
      createdAt: now,
    }),
  ]);
  return json({
    tenant: { id: membership.tenantID, displayName: membership.tenantName },
    owner: { memberID: membership.memberID },
    device: { id: deviceID, deviceToken },
    tokenIssued: true,
  }, existingDevice ? 200 : 201);
}

function recoveryCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(15));
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const encoded = [...bytes].map((byte) => alphabet[byte % alphabet.length]);
  return `PFSS-${encoded.slice(0, 5).join("")}-${encoded.slice(5, 10).join("")}-${encoded.slice(10).join("")}`;
}

async function replaceOwnerRecoveryCodes(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "owner_required" }, 403);
  const subject = await env.DB.prepare(
    `SELECT authentication_subject_id AS subjectID
       FROM tenant_members
      WHERE tenant_id = ?1 AND id = ?2 AND role = 'owner'
        AND status = 'active'`,
  ).bind(identity.tenantID, identity.memberID).first<{ subjectID: string | null }>();
  if (!subject?.subjectID) {
    return json({ error: "owner_identity_not_linked" }, 409);
  }
  const codes = Array.from({ length: 8 }, () => recoveryCode());
  const now = new Date().toISOString();
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `UPDATE account_recovery_methods
          SET revoked_at = ?1
        WHERE subject_id = ?2 AND kind = 'recoveryCode'
          AND revoked_at IS NULL AND last_used_at IS NULL`,
    ).bind(now, subject.subjectID),
  ];
  for (const code of codes) {
    statements.push(env.DB.prepare(
      `INSERT INTO account_recovery_methods
        (id, subject_id, kind, secret_digest, created_at)
       VALUES (?1, ?2, 'recoveryCode', ?3, ?4)`,
    ).bind(crypto.randomUUID(), subject.subjectID, await sha256(code), now));
  }
  statements.push(accessAuditStatement(
    env, identity.tenantID, "account.recovery_codes_replaced", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: identity.memberID,
      metadata: { codeCount: String(codes.length) },
      createdAt: now,
    },
  ));
  await env.DB.batch(statements);
  return json({ recoveryCodes: codes, createdAt: now }, 201);
}

async function createOwnerInvitation(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "owner_required" }, 403);
  const body = await request.json<Record<string, unknown>>();
  const displayName = nonemptyString(body.displayName, 1, 100);
  const email = nonemptyString(body.email, 3, 320)?.trim().toLowerCase();
  if (!displayName || !email || !email.includes("@")) {
    return json({ error: "invalid_owner_invitation" }, 400);
  }
  const existing = await env.DB.prepare(
    `SELECT 1 FROM tenant_members AS members
       JOIN verified_contact_addresses AS contact
         ON contact.subject_id = members.authentication_subject_id
        AND contact.kind = 'email'
      WHERE members.tenant_id = ?1 AND members.role = 'owner'
        AND members.status IN ('invited', 'active')
        AND contact.normalized_value = ?2`,
  ).bind(identity.tenantID, email).first();
  if (existing) return json({ error: "owner_already_exists" }, 409);
  const pending = await env.DB.prepare(
    `SELECT 1 FROM owner_account_invitations
      WHERE tenant_id = ?1 AND invited_email = ?2
        AND accepted_at IS NULL AND cancelled_at IS NULL
        AND expires_at > ?3`,
  ).bind(identity.tenantID, email, new Date().toISOString()).first();
  if (pending) return json({ error: "owner_invitation_already_pending" }, 409);
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  const memberID = crypto.randomUUID();
  const invitationID = crypto.randomUUID();
  const invitationCode = `PFSS-OWNER-${crypto.randomUUID()}${crypto.randomUUID()}`;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO tenant_members
        (id, tenant_id, display_name, role, status, created_at)
       VALUES (?1, ?2, ?3, 'owner', 'invited', ?4)`,
    ).bind(memberID, identity.tenantID, displayName, now.toISOString()),
    env.DB.prepare(
      `INSERT INTO owner_account_invitations
        (id, tenant_id, member_id, invited_email, invitation_digest,
         created_by_member_id, expires_at, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
    ).bind(invitationID, identity.tenantID, memberID, email,
      await sha256(invitationCode), identity.memberID,
      expiresAt.toISOString(), now.toISOString()),
    accessAuditStatement(env, identity.tenantID, "owner.invitation_created", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: memberID,
      metadata: { invitedEmail: email },
      createdAt: now.toISOString(),
    }),
  ]);
  return json({
    invitationID,
    memberID,
    displayName,
    email,
    invitationCode,
    expiresAt: expiresAt.toISOString(),
  }, 201);
}

async function acceptOwnerInvitation(
  request: Request,
  env: Env,
): Promise<Response> {
  const body = await request.json<Record<string, unknown>>();
  const invitationCode = nonemptyString(body.invitationCode, 40, 200);
  const identityAssertion = nonemptyString(body.identityAssertion, 20, 4096);
  const deviceID = nonemptyString(body.deviceID, 36, 36);
  const deviceName = nonemptyString(body.deviceName, 1, 120);
  if (!invitationCode || !identityAssertion || !deviceID || !deviceName ||
      !validUUID(deviceID)) {
    return json({ error: "invalid_owner_invitation_acceptance" }, 400);
  }
  const now = new Date().toISOString();
  const invitation = await env.DB.prepare(
    `SELECT invitations.id AS invitationID,
            invitations.tenant_id AS tenantID,
            invitations.member_id AS memberID,
            invitations.invited_email AS invitedEmail,
            tenants.display_name AS tenantName
       FROM owner_account_invitations AS invitations
       JOIN tenants ON tenants.id = invitations.tenant_id
      WHERE invitations.invitation_digest = ?1
        AND invitations.accepted_at IS NULL
        AND invitations.cancelled_at IS NULL
        AND invitations.expires_at > ?2
        AND tenants.status = 'active'`,
  ).bind(await sha256(invitationCode), now).first<{
    invitationID: string;
    tenantID: string;
    memberID: string;
    invitedEmail: string;
    tenantName: string;
  }>();
  if (!invitation) return json({ error: "invalid_or_expired_owner_invitation" }, 401);
  const authorization = await env.DB.prepare(
    `SELECT authorization.id, authorization.subject_id AS subjectID,
            contact.normalized_value AS verifiedEmail
       FROM owner_authorization_attempts AS authorization
       JOIN verified_contact_addresses AS contact
         ON contact.subject_id = authorization.subject_id
        AND contact.kind = 'email'
      WHERE authorization.identity_assertion_digest = ?1
        AND authorization.status = 'verified'
        AND authorization.expires_at > ?2`,
  ).bind(await sha256(identityAssertion), now).first<{
    id: string;
    subjectID: string;
    verifiedEmail: string;
  }>();
  if (!authorization || authorization.verifiedEmail !== invitation.invitedEmail) {
    return json({ error: "owner_invitation_identity_mismatch" }, 403);
  }
  const existingMembership = await env.DB.prepare(
    `SELECT 1 FROM tenant_members
      WHERE tenant_id = ?1 AND authentication_subject_id = ?2
        AND status != 'revoked'`,
  ).bind(invitation.tenantID, authorization.subjectID).first();
  if (existingMembership) return json({ error: "owner_already_exists" }, 409);
  const count = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM devices WHERE tenant_id = ?1 AND revoked_at IS NULL",
  ).bind(invitation.tenantID).first<{ count: number }>();
  if ((count?.count ?? 0) >= stagingRegistrationEntitlements.deviceLimit) {
    return json({ error: "device_limit_reached" }, 409);
  }
  const deviceToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const tokenDigest = await sha256(deviceToken);
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE owner_account_invitations SET accepted_at = ?1
        WHERE id = ?2 AND accepted_at IS NULL AND cancelled_at IS NULL`,
    ).bind(now, invitation.invitationID),
    env.DB.prepare(
      `UPDATE tenant_members
          SET authentication_subject_id = ?1, status = 'active', activated_at = ?2
        WHERE tenant_id = ?3 AND id = ?4 AND role = 'owner' AND status = 'invited'`,
    ).bind(authorization.subjectID, now, invitation.tenantID, invitation.memberID),
    env.DB.prepare(
      `INSERT INTO devices
        (id, tenant_id, member_id, display_name, token_hash, created_at, last_seen_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
    ).bind(deviceID, invitation.tenantID, invitation.memberID, deviceName,
      tokenDigest, now),
    env.DB.prepare(
      `UPDATE owner_authorization_attempts SET status = 'consumed',
              consumed_at = ?1, updated_at = ?1
        WHERE id = ?2 AND status = 'verified'`,
    ).bind(now, authorization.id),
    accessAuditStatement(env, invitation.tenantID, "owner.invitation_accepted", {
      actorMemberID: invitation.memberID,
      actorDeviceID: deviceID,
      targetMemberID: invitation.memberID,
      targetDeviceID: deviceID,
      metadata: { verifiedEmail: authorization.verifiedEmail },
      createdAt: now,
    }),
  ]);
  return json({
    tenant: { id: invitation.tenantID, displayName: invitation.tenantName },
    owner: { memberID: invitation.memberID },
    device: { id: deviceID, deviceToken },
    tokenIssued: true,
  }, 201);
}

async function revokeOwnerMember(
  env: Env,
  identity: DeviceIdentity,
  memberID: string,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "owner_required" }, 403);
  if (memberID === identity.memberID) {
    return json({ error: "cannot_modify_current_member" }, 409);
  }
  const target = await env.DB.prepare(
    `SELECT role, status FROM tenant_members
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, memberID).first<{ role: TenantRole; status: string }>();
  if (!target || target.role !== "owner") return json({ error: "not_found" }, 404);
  if (target.status === "invited") {
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE owner_account_invitations SET cancelled_at = ?1
          WHERE tenant_id = ?2 AND member_id = ?3
            AND accepted_at IS NULL AND cancelled_at IS NULL`,
      ).bind(now, identity.tenantID, memberID),
      env.DB.prepare(
        `UPDATE tenant_members SET status = 'revoked', revoked_at = ?1
          WHERE tenant_id = ?2 AND id = ?3 AND status = 'invited'`,
      ).bind(now, identity.tenantID, memberID),
      accessAuditStatement(env, identity.tenantID, "owner.invitation_cancelled", {
        actorMemberID: identity.memberID,
        actorDeviceID: identity.deviceID,
        targetMemberID: memberID,
        createdAt: now,
      }),
    ]);
    return json({ memberID, status: "revoked" });
  }
  if (target.status !== "active") return json({ error: "invalid_member_transition" }, 409);
  const activeOwners = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM tenant_members
      WHERE tenant_id = ?1 AND role = 'owner' AND status = 'active'`,
  ).bind(identity.tenantID).first<{ count: number }>();
  if ((activeOwners?.count ?? 0) <= 1) {
    return json({ error: "final_active_owner_protected" }, 409);
  }
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE tenant_members SET status = 'revoked', revoked_at = ?1
        WHERE tenant_id = ?2 AND id = ?3 AND role = 'owner' AND status = 'active'`,
    ).bind(now, identity.tenantID, memberID),
    env.DB.prepare(
      `UPDATE devices SET revoked_at = COALESCE(revoked_at, ?1),
              data_removal_required_at = COALESCE(data_removal_required_at, ?1)
        WHERE tenant_id = ?2 AND member_id = ?3`,
    ).bind(now, identity.tenantID, memberID),
    accessAuditStatement(env, identity.tenantID, "owner.revoked", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: memberID,
      metadata: { activeOwnersBefore: String(activeOwners?.count ?? 0) },
      createdAt: now,
    }),
  ]);
  return json({ memberID, status: "revoked" });
}

async function ownerRecoveryStatus(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "owner_required" }, 403);
  const status = await env.DB.prepare(
    `SELECT COUNT(*) AS availableCodes, MAX(methods.created_at) AS createdAt
       FROM account_recovery_methods AS methods
       JOIN tenant_members AS members
         ON members.authentication_subject_id = methods.subject_id
      WHERE members.tenant_id = ?1 AND members.id = ?2
        AND methods.kind = 'recoveryCode'
        AND methods.last_used_at IS NULL AND methods.revoked_at IS NULL`,
  ).bind(identity.tenantID, identity.memberID).first<{
    availableCodes: number;
    createdAt: string | null;
  }>();
  return json({
    availableCodes: status?.availableCodes ?? 0,
    createdAt: status?.createdAt ?? null,
  });
}

async function redeemOwnerRecoveryCode(
  request: Request,
  env: Env,
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_recovery_request" }, 400);
  }
  const code = nonemptyString(body.recoveryCode, 20, 64)?.toUpperCase();
  const deviceID = nonemptyString(body.deviceID, 36, 36);
  const deviceName = nonemptyString(body.deviceName, 1, 120);
  if (!code || !deviceID || !deviceName || !validUUID(deviceID)) {
    return json({ error: "invalid_recovery_request" }, 400);
  }
  const digest = await sha256(code);
  const now = new Date().toISOString();
  const method = await env.DB.prepare(
    `SELECT methods.id AS methodID, methods.subject_id AS subjectID,
            members.id AS memberID, members.tenant_id AS tenantID,
            tenants.display_name AS tenantName
       FROM account_recovery_methods AS methods
       JOIN tenant_members AS members
         ON members.authentication_subject_id = methods.subject_id
        AND members.role = 'owner' AND members.status = 'active'
       JOIN tenants ON tenants.id = members.tenant_id AND tenants.status = 'active'
      WHERE methods.kind = 'recoveryCode' AND methods.secret_digest = ?1
        AND methods.last_used_at IS NULL AND methods.revoked_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM platform_account_controls AS controls
           WHERE controls.tenant_id = tenants.id
             AND (
               controls.lifecycle_status IN ('archived', 'deletionPending')
               OR (
                 controls.lifecycle_status IN
                   ('billingHold', 'securityHold', 'supportHold')
                 AND (controls.hold_expires_at IS NULL OR controls.hold_expires_at > ?2)
               )
             )
        )`,
  ).bind(digest, now).first<{
    methodID: string;
    subjectID: string;
    memberID: string;
    tenantID: string;
    tenantName: string;
  }>();
  if (!method) return json({ error: "invalid_or_used_recovery_code" }, 401);
  const existing = await env.DB.prepare(
    "SELECT member_id AS memberID FROM devices WHERE tenant_id = ?1 AND id = ?2",
  ).bind(method.tenantID, deviceID).first<{ memberID: string }>();
  if (!existing) {
    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM devices WHERE tenant_id = ?1 AND revoked_at IS NULL",
    ).bind(method.tenantID).first<{ count: number }>();
    if ((count?.count ?? 0) >= stagingRegistrationEntitlements.deviceLimit) {
      return json({ error: "device_limit_reached" }, 409);
    }
  }
  const token = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const tokenDigest = await sha256(token);
  const attemptID = crypto.randomUUID();
  const [claimed] = await env.DB.batch([
    env.DB.prepare(
      `UPDATE account_recovery_methods SET last_used_at = ?1
        WHERE id = ?2 AND last_used_at IS NULL AND revoked_at IS NULL`,
    ).bind(now, method.methodID),
    existing
      ? env.DB.prepare(
        `UPDATE devices SET member_id = ?1, display_name = ?2, token_hash = ?3,
                last_seen_at = ?4, revoked_at = NULL,
                data_removal_required_at = NULL,
                data_removal_acknowledged_at = NULL,
                credentials_purged_at = NULL
          WHERE tenant_id = ?5 AND id = ?6`,
      ).bind(method.memberID, deviceName, tokenDigest, now, method.tenantID, deviceID)
      : env.DB.prepare(
        `INSERT INTO devices
          (id, tenant_id, member_id, display_name, token_hash, created_at, last_seen_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)`,
      ).bind(deviceID, method.tenantID, method.memberID, deviceName, tokenDigest, now),
    env.DB.prepare(
      `INSERT INTO owner_recovery_attempts
        (id, recovery_method_id, subject_id, device_id, status, created_at)
       VALUES (?1, ?2, ?3, ?4, 'succeeded', ?5)`,
    ).bind(attemptID, method.methodID, method.subjectID, deviceID, now),
    accessAuditStatement(env, method.tenantID, "account.recovered", {
      actorMemberID: method.memberID,
      actorDeviceID: deviceID,
      targetMemberID: method.memberID,
      targetDeviceID: deviceID,
      metadata: { method: "recoveryCode", existingDevice: existing ? "true" : "false" },
      createdAt: now,
    }),
  ]);
  if (claimed.meta.changes !== 1) {
    return json({ error: "invalid_or_used_recovery_code" }, 401);
  }
  return json({
    tenant: { id: method.tenantID, displayName: method.tenantName },
    owner: { memberID: method.memberID },
    device: { id: deviceID, deviceToken: token },
    tokenIssued: true,
  }, existing ? 200 : 201);
}

function validTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

function validUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

async function parseAccountRegistration(
  request: Request,
): Promise<ValidatedAccountRegistration | Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_registration_request" }, 400);
  }
  const forbiddenField = forbiddenRegistrationField(body);
  if (forbiddenField) {
    return json({
      error: "forbidden_registration_field",
      field: forbiddenField,
    }, 400);
  }

  const owner = body.owner as Record<string, unknown> | undefined;
  const company = body.company as Record<string, unknown> | undefined;
  const consent = body.consent as Record<string, unknown> | undefined;
  const device = body.device as Record<string, unknown> | undefined;
  const ownerName = nonemptyString(owner?.displayName, 2, 120);
  const email = nonemptyString(owner?.email, 3, 254)?.toLowerCase() ?? null;
  const companyName = nonemptyString(company?.displayName, 2, 160);
  const timeZoneID = nonemptyString(company?.timeZoneID, 1, 80);
  const identityAssertion = nonemptyString(body.identityAssertion, 20, 4096);
  const authenticationMethod = body.authenticationMethod as
    | AccountAuthenticationMethod
    | undefined;
  const supportedMethods: AccountAuthenticationMethod[] = [
    "password", "passkey", "signInWithApple", "federated",
  ];
  const planCode = nonemptyString(body.requestedPlanCode, 1, 64)?.toLowerCase();
  const termsVersion = nonemptyString(consent?.termsVersion, 1, 80);
  const privacyVersion = nonemptyString(consent?.privacyVersion, 1, 80);
  const acceptedAt = typeof consent?.acceptedAt === "string"
    ? new Date(consent.acceptedAt)
    : null;
  const now = Date.now();
  const consentTime = acceptedAt?.getTime() ?? Number.NaN;
  const deviceName = nonemptyString(device?.displayName, 1, 120);

  if (!validUUID(body.idempotencyKey) || !ownerName || !email ||
      !validEmail(email) || !companyName || !timeZoneID ||
      !validTimeZone(timeZoneID) || !identityAssertion ||
      !authenticationMethod || !supportedMethods.includes(authenticationMethod) ||
      !planCode || !/^[a-z0-9](?:[a-z0-9_-]{0,62}[a-z0-9])?$/.test(planCode) ||
      !termsVersion || !privacyVersion || !Number.isFinite(consentTime) ||
      consentTime < now - 86_400_000 || consentTime > now + 300_000 ||
      !validUUID(device?.id) || !deviceName) {
    return json({ error: "invalid_registration_request" }, 400);
  }

  return {
    idempotencyKey: body.idempotencyKey,
    identityAssertion,
    authenticationMethod,
    owner: { displayName: ownerName, email },
    company: {
      displayName: companyName,
      normalizedName: companyName.replace(/\s+/g, " ").toLowerCase(),
      timeZoneID,
    },
    requestedPlanCode: planCode,
    consent: {
      termsVersion,
      privacyVersion,
      acceptedAt: acceptedAt!.toISOString(),
    },
    device: { id: device!.id, displayName: deviceName },
  };
}

async function validateAccountRegistration(request: Request): Promise<Response> {
  const registration = await parseAccountRegistration(request);
  if (registration instanceof Response) return registration;
  const { identityAssertion: _, ...publicRegistration } = registration;
  const { normalizedName: __, ...publicCompany } = publicRegistration.company;
  return json({
    valid: true,
    status: "started" satisfies AccountRegistrationStatus,
    registration: { ...publicRegistration, company: publicCompany },
  });
}

function registrationReceipt(
  attempt: AccountRegistrationAttemptRow,
  registrationToken: string | null,
): Response {
  return json({
    registrationAttempt: {
      id: attempt.id,
      status: attempt.status,
      expiresAt: attempt.expiresAt,
      createdAt: attempt.createdAt,
      updatedAt: attempt.updatedAt,
      cancelledAt: attempt.cancelledAt,
    },
    registrationToken,
    tokenIssued: registrationToken !== null,
  }, registrationToken === null ? 200 : 201);
}

async function registrationFingerprint(
  registration: ValidatedAccountRegistration,
): Promise<{ fingerprint: string; assertionDigest: string }> {
  const assertionDigest = await sha256(registration.identityAssertion);
  const fingerprint = await sha256(JSON.stringify({
    ...registration,
    identityAssertion: assertionDigest,
  }));
  return { fingerprint, assertionDigest };
}

async function expireRegistrationAttempt(
  env: Env,
  attempt: AccountRegistrationAttemptRow,
): Promise<AccountRegistrationAttemptRow> {
  if (["started", "identityVerified", "profileComplete", "planAuthorized"]
      .includes(attempt.status) && Date.parse(attempt.expiresAt) <= Date.now()) {
    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE account_registration_attempts
          SET status = 'expired', updated_at = ?2
        WHERE id = ?1 AND status = ?3`,
    ).bind(attempt.id, now, attempt.status).run();
    return { ...attempt, status: "expired", updatedAt: now };
  }
  return attempt;
}

async function startAccountRegistration(
  request: Request,
  env: Env,
): Promise<Response> {
  const registration = await parseAccountRegistration(request);
  if (registration instanceof Response) return registration;
  const { fingerprint, assertionDigest } =
    await registrationFingerprint(registration);
  const existing = await env.DB.prepare(
    `SELECT id, request_fingerprint AS requestFingerprint, status,
            expires_at AS expiresAt, created_at AS createdAt,
            updated_at AS updatedAt, cancelled_at AS cancelledAt
       FROM account_registration_attempts WHERE idempotency_key = ?1`,
  ).bind(registration.idempotencyKey).first<AccountRegistrationAttemptRow>();
  if (existing) {
    if (existing.requestFingerprint !== fingerprint) {
      return json({ error: "idempotency_key_reused" }, 409);
    }
    return registrationReceipt(
      await expireRegistrationAttempt(env, existing),
      null,
    );
  }

  const verifiedAuthorization = await env.DB.prepare(
    `SELECT authorization.id, authorization.subject_id AS subjectID,
            authorization.provider_method AS providerMethod,
            authorization.subject_was_created AS subjectWasCreated
       FROM owner_authorization_attempts AS authorization
       JOIN verified_contact_addresses AS contact
         ON contact.subject_id = authorization.subject_id
        AND contact.kind = 'email'
      WHERE authorization.identity_assertion_digest = ?1
        AND authorization.status = 'verified'
        AND authorization.expires_at > ?2
        AND contact.normalized_value = ?3`,
  ).bind(
    assertionDigest, new Date().toISOString(), registration.owner.email,
  ).first<{
    id: string;
    subjectID: string;
    providerMethod: string;
    subjectWasCreated: number;
  }>();
  if (!verifiedAuthorization ||
      verifiedAuthorization.providerMethod !== registration.authenticationMethod) {
    return json({ error: "identity_verification_required" }, 401);
  }
  if (verifiedAuthorization.subjectWasCreated !== 1) {
    return json({ error: "account_or_company_requires_sign_in" }, 409);
  }

  const duplicate = await env.DB.prepare(
    `SELECT 1 AS found
       FROM verified_contact_addresses
      WHERE kind = 'email' AND normalized_value = ?1 AND subject_id != ?4
      UNION ALL
     SELECT 1 AS found
       FROM account_registration_attempts
      WHERE (
        status IN ('provisioning', 'active') OR
        (status IN (
          'started', 'identityVerified', 'profileComplete', 'planAuthorized'
        ) AND expires_at > ?3)
      )
        AND (normalized_email = ?1 OR normalized_company_name = ?2)
      LIMIT 1`,
  ).bind(
    registration.owner.email,
    registration.company.normalizedName,
    new Date().toISOString(),
    verifiedAuthorization.subjectID,
  ).first<{ found: number }>();
  if (duplicate) {
    return json({ error: "account_or_company_requires_sign_in" }, 409);
  }

  const id = crypto.randomUUID();
  const registrationToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const tokenDigest = await sha256(registrationToken);
  const now = new Date();
  const createdAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + 30 * 60_000).toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO account_registration_attempts
        (id, idempotency_key, request_fingerprint, status,
         normalized_email, owner_display_name, company_display_name,
         normalized_company_name, time_zone_id, requested_plan_code,
         identity_assertion_digest, registration_token_digest,
         authentication_method, device_id, device_display_name,
         subject_id, owner_authorization_attempt_id, expires_at, created_at,
         updated_at)
       VALUES (?1, ?2, ?3, 'started', ?4, ?5, ?6, ?7, ?8, ?9,
               ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?18)`,
    ).bind(
      id, registration.idempotencyKey, fingerprint,
      registration.owner.email, registration.owner.displayName,
      registration.company.displayName, registration.company.normalizedName,
      registration.company.timeZoneID, registration.requestedPlanCode,
      assertionDigest, tokenDigest, registration.authenticationMethod,
      registration.device.id, registration.device.displayName,
      verifiedAuthorization.subjectID, verifiedAuthorization.id, expiresAt,
      createdAt,
    ),
    env.DB.prepare(
      `INSERT INTO legal_consents
        (id, subject_id, registration_attempt_id, terms_version,
         privacy_version, accepted_at, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
    ).bind(
      crypto.randomUUID(), verifiedAuthorization.subjectID, id,
      registration.consent.termsVersion,
      registration.consent.privacyVersion,
      registration.consent.acceptedAt, createdAt,
    ),
    env.DB.prepare(
      `UPDATE owner_authorization_attempts
          SET status = 'consumed', consumed_at = ?2, updated_at = ?2
        WHERE id = ?1 AND status = 'verified'`,
    ).bind(verifiedAuthorization.id, createdAt),
  ]);
  return registrationReceipt({
    id,
    requestFingerprint: fingerprint,
    status: "started",
    expiresAt,
    createdAt,
    updatedAt: createdAt,
    cancelledAt: null,
  }, registrationToken);
}

const stagingRegistrationEntitlements = {
  userLimit: 5,
  deviceLimit: 10,
  leadLimit: 1_000,
  customerLimit: 1_000,
  jobLimit: 3_000,
  modules: ["sales", "service", "dispatch", "reporting"],
};

async function completeAccountRegistration(
  request: Request,
  env: Env,
  id: string,
): Promise<Response> {
  const authenticated = await authenticatedRegistrationAttempt(request, env, id);
  if (authenticated instanceof Response) return authenticated;
  if (authenticated.status === "active") {
    return json({
      registrationAttempt: {
        id: authenticated.id,
        status: authenticated.status,
        expiresAt: authenticated.expiresAt,
        createdAt: authenticated.createdAt,
        updatedAt: authenticated.updatedAt,
      },
      deviceToken: null,
      tokenIssued: false,
    });
  }
  if (authenticated.status !== "started") {
    return json({ error: "registration_not_ready" }, 409);
  }
  if (env.PFSS_ENVIRONMENT !== "staging") {
    return json({ error: "plan_authorization_required" }, 409);
  }

  const attempt = await env.DB.prepare(
    `SELECT registration.id,
            registration.request_fingerprint AS requestFingerprint,
            registration.status,
            registration.owner_display_name AS ownerDisplayName,
            registration.company_display_name AS companyDisplayName,
            registration.time_zone_id AS timeZoneID,
            registration.requested_plan_code AS requestedPlanCode,
            registration.device_id AS deviceID,
            registration.device_display_name AS deviceDisplayName,
            COALESCE(registration.subject_id, authorization.subject_id) AS subjectID,
            registration.tenant_id AS tenantID,
            registration.expires_at AS expiresAt,
            registration.created_at AS createdAt,
            registration.updated_at AS updatedAt,
            registration.cancelled_at AS cancelledAt
       FROM account_registration_attempts AS registration
       JOIN owner_authorization_attempts AS authorization
         ON authorization.id = registration.owner_authorization_attempt_id
      WHERE registration.id = ?1`,
  ).bind(id).first<ProvisioningRegistrationAttemptRow>();
  if (!attempt?.subjectID) return json({ error: "identity_verification_required" }, 401);

  const tenantID = crypto.randomUUID();
  const memberID = crypto.randomUUID();
  const subscriptionID = crypto.randomUUID();
  const allocationID = crypto.randomUUID();
  const deviceToken = `${crypto.randomUUID()}${crypto.randomUUID()}`;
  const deviceTokenDigest = await sha256(deviceToken);
  const now = new Date().toISOString();
  const entitlementsJSON = JSON.stringify(stagingRegistrationEntitlements);
  let results: D1Result<unknown>[];
  try {
    results = await env.DB.batch([
    env.DB.prepare(
      `UPDATE account_registration_attempts
          SET status = 'provisioning', subject_id = ?2, updated_at = ?3
        WHERE id = ?1 AND status = 'started' AND expires_at > ?3`,
    ).bind(id, attempt.subjectID, now),
    env.DB.prepare(
      `INSERT INTO tenants (id, display_name, status, created_at)
       SELECT ?2, company_display_name, 'active', ?3
         FROM account_registration_attempts
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id IS NULL`,
    ).bind(id, tenantID, now),
    env.DB.prepare(
      `UPDATE account_registration_attempts
          SET tenant_id = ?2, updated_at = ?3
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id IS NULL
          AND EXISTS (SELECT 1 FROM tenants WHERE id = ?2)`,
    ).bind(id, tenantID, now),
    env.DB.prepare(
      `INSERT INTO tenant_members
        (id, tenant_id, display_name, role, status, created_at, activated_at,
         authentication_subject_id)
       SELECT ?2, ?3, owner_display_name, 'owner', 'active', ?4, ?4, subject_id
         FROM account_registration_attempts
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id = ?3`,
    ).bind(id, memberID, tenantID, now),
    env.DB.prepare(
      `INSERT INTO subscription_accounts
        (id, tenant_id, status, created_at, updated_at)
       SELECT ?2, ?3, 'trialing', ?4, ?4
         FROM account_registration_attempts
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id = ?3`,
    ).bind(id, subscriptionID, tenantID, now),
    env.DB.prepare(
      `INSERT INTO plan_allocations
        (id, tenant_id, access_source, source_reference, plan_code,
         entitlements_json, effective_at, expires_at, granted_by_subject_id,
         grant_reason, created_at)
       SELECT ?2, ?3, 'betaGrant', ?1, 'beta', ?4, ?5, ?6,
              subject_id, 'Phase 17 staging registration', ?5
         FROM account_registration_attempts
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id = ?3`,
    ).bind(
      id, allocationID, tenantID, entitlementsJSON, now,
      new Date(Date.now() + 90 * 24 * 60 * 60_000).toISOString(),
    ),
    env.DB.prepare(
      `INSERT INTO devices
        (id, tenant_id, member_id, display_name, token_hash, created_at,
         last_seen_at)
       SELECT device_id, ?2, ?3, device_display_name, ?4, ?5, ?5
         FROM account_registration_attempts
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id = ?2`,
    ).bind(id, tenantID, memberID, deviceTokenDigest, now),
    env.DB.prepare(
      `UPDATE legal_consents
          SET subject_id = ?2
        WHERE registration_attempt_id = ?1 AND subject_id IS NULL`,
    ).bind(id, attempt.subjectID),
    env.DB.prepare(
      `INSERT INTO access_audit_events
        (id, tenant_id, actor_member_id, actor_device_id, event_type,
         target_member_id, target_device_id, metadata_json, created_at)
       SELECT ?2, ?3, ?4, device_id, 'account.registration_completed',
              ?4, device_id, ?5, ?6
         FROM account_registration_attempts
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id = ?3`,
    ).bind(
      id, crypto.randomUUID(), tenantID, memberID,
      JSON.stringify({
        registrationAttemptID: id,
        planCode: "beta",
        accessSource: "betaGrant",
      }),
      now,
    ),
    env.DB.prepare(
      `UPDATE account_registration_attempts
          SET status = 'active', completed_at = ?3, updated_at = ?3
        WHERE id = ?1 AND status = 'provisioning' AND tenant_id = ?2
          AND EXISTS (
            SELECT 1 FROM devices
             WHERE tenant_id = ?2 AND id = account_registration_attempts.device_id
          )`,
    ).bind(id, tenantID, now),
    ]);
  } catch {
    return json({ error: "registration_provisioning_failed" }, 503);
  }
  if (results[0].meta.changes !== 1 ||
      results[results.length - 1].meta.changes !== 1) {
    const current = await env.DB.prepare(
      `SELECT status, tenant_id AS tenantID
         FROM account_registration_attempts WHERE id = ?1`,
    ).bind(id).first<{ status: string; tenantID: string | null }>();
    if (current?.status === "active") {
      return json({
        registrationAttempt: { id, status: "active" },
        tenant: current.tenantID ? { id: current.tenantID } : null,
        deviceToken: null,
        tokenIssued: false,
      });
    }
    return json({ error: "registration_provisioning_failed" }, 503);
  }
  return json({
    registrationAttempt: { id, status: "active", completedAt: now },
    tenant: {
      id: tenantID,
      displayName: attempt.companyDisplayName,
      timeZoneID: attempt.timeZoneID,
    },
    owner: { memberID, role: "owner" },
    device: {
      id: attempt.deviceID,
      displayName: attempt.deviceDisplayName,
      deviceToken,
      enrolledAt: now,
    },
    plan: {
      code: "beta",
      accessSource: "betaGrant",
      entitlements: stagingRegistrationEntitlements,
    },
    initialSynchronizationCursor: now,
    tokenIssued: true,
  }, 201);
}

async function authenticatedRegistrationAttempt(
  request: Request,
  env: Env,
  id: string,
): Promise<AccountRegistrationAttemptRow | Response> {
  const token = request.headers.get("x-pfss-registration-token")?.trim();
  if (!token) return json({ error: "registration_authentication_required" }, 401);
  const tokenDigest = await sha256(token);
  const attempt = await env.DB.prepare(
    `SELECT id, request_fingerprint AS requestFingerprint, status,
            expires_at AS expiresAt, created_at AS createdAt,
            updated_at AS updatedAt, cancelled_at AS cancelledAt
       FROM account_registration_attempts
      WHERE id = ?1 AND registration_token_digest = ?2`,
  ).bind(id, tokenDigest).first<AccountRegistrationAttemptRow>();
  if (!attempt) return json({ error: "registration_not_found" }, 404);
  return expireRegistrationAttempt(env, attempt);
}

async function getAccountRegistrationAttempt(
  request: Request,
  env: Env,
  id: string,
): Promise<Response> {
  const attempt = await authenticatedRegistrationAttempt(request, env, id);
  if (attempt instanceof Response) return attempt;
  return registrationReceipt(attempt, null);
}

async function cancelAccountRegistrationAttempt(
  request: Request,
  env: Env,
  id: string,
): Promise<Response> {
  let attempt = await authenticatedRegistrationAttempt(request, env, id);
  if (attempt instanceof Response) return attempt;
  if (attempt.status === "cancelled") return registrationReceipt(attempt, null);
  if (attempt.status === "expired") return registrationReceipt(attempt, null);
  if (["provisioning", "active"].includes(attempt.status)) {
    return json({ error: "registration_cannot_be_cancelled" }, 409);
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE account_registration_attempts
        SET status = 'cancelled', cancelled_at = ?2, updated_at = ?2
      WHERE id = ?1`,
  ).bind(id, now).run();
  attempt = { ...attempt, status: "cancelled", cancelledAt: now, updatedAt: now };
  return registrationReceipt(attempt, null);
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
    `SELECT id, entity_type AS entityType, entity_id AS entityID,
            status AS resolution, resolved_at AS resolvedAt,
            final_revision AS finalRevision
       FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND source_device_id = ?2
        AND status IN ('keptCloud', 'keptDevice')
      ORDER BY resolved_at ASC`,
  ).bind(identity.tenantID, identity.deviceID).all<{
    id: string;
    entityType: string;
    entityID: string;
    resolution: "keptCloud" | "keptDevice";
    resolvedAt: string;
    finalRevision: string;
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
    `SELECT entity_type AS entityType, entity_id AS entityID,
            local_operation_json AS localOperationJSON,
            cloud_operation_json AS cloudOperationJSON,
            cloud_revision AS cloudRevision
       FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND id = ?2 AND status = 'unresolved'`,
  ).bind(identity.tenantID, conflictID).first<{
    entityType: string;
    entityID: string;
    localOperationJSON: string;
    cloudOperationJSON: string;
    cloudRevision: string;
  }>();
  if (!conflict) return json({ error: "conflict_not_found" }, 404);

  let finalRevision = conflict.cloudRevision;
  if (body.resolution === "keptDevice") {
    const operation = JSON.parse(conflict.localOperationJSON) as
      Record<string, unknown>;
    const current = await env.DB.prepare(
      `SELECT revision
         FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
    ).bind(
      identity.tenantID, conflict.entityType, conflict.entityID,
    ).first<{ revision: string }>();
    if (!current) return json({ error: "conflict_record_not_found" }, 404);
    operation.id = crypto.randomUUID();
    operation.idempotencyKey = `conflict-resolution-${conflictID}`;
    operation.baseRevision = current.revision;
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
  return json({
    id: conflictID,
    entityType: conflict.entityType,
    entityID: conflict.entityID,
    resolution: body.resolution,
    resolvedAt: now,
    finalRevision,
  });
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
            (SELECT normalized_value
               FROM verified_contact_addresses
              WHERE subject_id = tenant_members.authentication_subject_id
                AND kind = 'email'
              ORDER BY verified_at DESC
              LIMIT 1) AS memberEmail,
            tenant_members.role AS role,
            tenant_members.status AS memberStatus,
            devices.id AS deviceID,
            devices.display_name AS deviceName,
            devices.revoked_at AS revokedAt,
            devices.data_removal_required_at AS dataRemovalRequiredAt,
            devices.data_removal_acknowledged_at AS dataRemovalAcknowledgedAt,
            tenants.status AS tenantStatus,
            COALESCE(controls.lifecycle_status, 'active') AS lifecycleStatus,
            controls.hold_expires_at AS holdExpiresAt
       FROM devices
       JOIN tenants ON tenants.id = devices.tenant_id
       LEFT JOIN platform_account_controls AS controls
         ON controls.tenant_id = tenants.id
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
  const activeHold = ["billingHold", "securityHold", "supportHold"]
    .includes(device.lifecycleStatus) &&
    (!device.holdExpiresAt || Date.parse(device.holdExpiresAt) > Date.now());
  if (activeHold) {
    return json({
      error: "account_access_on_hold",
      hold: {
        type: device.lifecycleStatus,
        expiresAt: device.holdExpiresAt,
      },
    }, 403);
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
      email: identity.memberEmail,
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

async function createDeviceInvitation(
  env: Env,
  identity: DeviceIdentity,
  memberID: string,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const target = await env.DB.prepare(
    `SELECT employee_id AS employeeID, display_name AS displayName, role, status
       FROM tenant_members
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, memberID).first<{
    employeeID: string | null;
    displayName: string;
    role: TenantRole;
    status: string;
  }>();
  if (!target) return json({ error: "not_found" }, 404);
  if (!canManageTarget(identity, target.role)) {
    return json({ error: "protected_role" }, 403);
  }
  if (target.status !== "active") {
    return json({ error: "member_not_active" }, 409);
  }

  const now = new Date();
  const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  const enrollmentCode = `PFSS-${crypto.randomUUID()}${crypto.randomUUID()}`;
  const codeHash = await sha256(enrollmentCode);
  await env.DB.batch([
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
    accessAuditStatement(env, identity.tenantID, "device.invitation_created", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: memberID,
      metadata: target.employeeID ? { employeeID: target.employeeID } : {},
      createdAt: now.toISOString(),
    }),
  ]);
  return json({
    memberID,
    employeeID: target.employeeID,
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

type CatalogRecordPayload = {
  id?: string;
  itemName?: string;
  itemDescription?: string;
  defaultQuantity?: number;
  defaultPrice?: number;
  estimatedMinutesPerUnit?: number;
  itemType?: string;
  taxTreatment?: string;
  usageCount?: number;
  lastUsedDate?: string | null;
  lifecycleStatus?: string;
};

function catalogRecordFromOperation(
  operation: Record<string, unknown>,
): CatalogRecordPayload | null {
  try {
    const payload = operation.payload as { body?: string } | undefined;
    const mutation = JSON.parse(atob(payload?.body ?? "")) as {
      recordData?: string;
    };
    return JSON.parse(atob(mutation.recordData ?? "")) as CatalogRecordPayload;
  } catch {
    return null;
  }
}

function isAuthorizedCatalogUsageUpdate(
  submittedOperation: Record<string, unknown>,
  acceptedOperation: Record<string, unknown>,
  entityID: string,
): boolean {
  const submitted = catalogRecordFromOperation(submittedOperation);
  const accepted = catalogRecordFromOperation(acceptedOperation);
  if (!submitted || !accepted) return false;

  const submittedID = (submitted.id ?? "").toLowerCase();
  const acceptedID = (accepted.id ?? "").toLowerCase();
  const businessFieldsMatch =
    submittedID === entityID && acceptedID === entityID &&
    submitted.itemName === accepted.itemName &&
    submitted.itemDescription === accepted.itemDescription &&
    submitted.defaultQuantity === accepted.defaultQuantity &&
    submitted.defaultPrice === accepted.defaultPrice &&
    submitted.estimatedMinutesPerUnit === accepted.estimatedMinutesPerUnit &&
    submitted.itemType === accepted.itemType &&
    submitted.taxTreatment === accepted.taxTreatment &&
    submitted.lifecycleStatus === accepted.lifecycleStatus;
  if (!businessFieldsMatch) return false;

  const submittedUsage = submitted.usageCount ?? 0;
  const acceptedUsage = accepted.usageCount ?? 0;
  if (submittedUsage < acceptedUsage) return false;

  const submittedLastUsed = submitted.lastUsedDate == null
    ? null
    : Date.parse(submitted.lastUsedDate);
  const acceptedLastUsed = accepted.lastUsedDate == null
    ? null
    : Date.parse(accepted.lastUsedDate);
  if (submittedLastUsed === null || Number.isNaN(submittedLastUsed)) return false;
  if (
    acceptedLastUsed !== null && !Number.isNaN(acceptedLastUsed) &&
    submittedLastUsed < acceptedLastUsed
  ) return false;

  return submittedUsage > acceptedUsage || submittedLastUsed !== acceptedLastUsed;
}

function employeeSearchContactFromOperation(
  operation: Record<string, unknown>,
): {
  normalizedEmail: string;
  displayName: string;
  roleHint: string | null;
} | null {
  try {
    const payload = operation.payload as { body?: string } | undefined;
    const mutation = JSON.parse(atob(payload?.body ?? "")) as {
      recordData?: string;
    };
    const employee = JSON.parse(atob(mutation.recordData ?? "")) as {
      firstName?: string;
      lastName?: string;
      email?: string;
      role?: string;
      roles?: string[];
    };
    const normalizedEmail = (employee.email ?? "").trim().toLowerCase();
    if (
      normalizedEmail.length < 3 || normalizedEmail.length > 320 ||
      !normalizedEmail.includes("@")
    ) return null;
    const displayName = [employee.firstName, employee.lastName]
      .map((value) => value?.trim() ?? "")
      .filter(Boolean)
      .join(" ");
    const roleHint = employee.roles?.join(", ") ?? employee.role ?? null;
    return { normalizedEmail, displayName, roleHint };
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
      "invoice", "employee", "catalog", "recurringWork",
    ]);
    if (!allowed.has(entityType) || !entityID) {
      return json({ error: "invalid_record_mutation" }, 400);
    }
    if (
      identity.role === "member" &&
      (entityType === "recurringWork" ||
        (entityType === "employee" && entityID !== identity.employeeID?.toLowerCase()))
    ) {
      return json({ error: "forbidden" }, 403);
    }
    if (identity.role === "member" && entityType === "catalog") {
      const acceptedRecord = await env.DB.prepare(
        `SELECT operation_json AS operationJSON
           FROM synchronized_records
          WHERE tenant_id = ?1 AND entity_type = 'catalog' AND entity_id = ?2`,
      ).bind(identity.tenantID, entityID).first<{ operationJSON: string }>();
      if (
        !acceptedRecord ||
        !isAuthorizedCatalogUsageUpdate(
          operation,
          JSON.parse(acceptedRecord.operationJSON),
          entityID,
        )
      ) {
        return json({ error: "catalog_change_requires_manager" }, 403);
      }
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
      const limitResponse = await enforceNewRecordLimit(
        env, identity.tenantID, entityType,
      );
      if (limitResponse) return limitResponse;
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
  if (isRecordMutation && entityType === "employee") {
    const contact = employeeSearchContactFromOperation(operation);
    const statements = [
      env.DB.prepare(
        `DELETE FROM operations_account_email_index
          WHERE tenant_id = ?1 AND source_kind = 'employeeRecord'
            AND source_id = ?2`,
      ).bind(identity.tenantID, entityID),
    ];
    if (contact) {
      statements.push(env.DB.prepare(
        `INSERT INTO operations_account_email_index
          (tenant_id, source_kind, source_id, normalized_email,
           display_name, role_hint, updated_at)
         VALUES (?1, 'employeeRecord', ?2, ?3, ?4, ?5, ?6)`,
      ).bind(identity.tenantID, entityID, contact.normalizedEmail,
        contact.displayName || null, contact.roleHint, acceptedAt));
    }
    await env.DB.batch(statements);
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
  const automaticallyResolvedConflictID = typeof metadata
      .automaticallyResolvedConflictID === "string"
    ? metadata.automaticallyResolvedConflictID
    : null;
  if (automaticallyResolvedConflictID) {
    await env.DB.prepare(
      `UPDATE synchronization_conflicts
          SET status = 'keptDevice', resolved_at = ?1,
              resolved_by_member_id = ?2, resolved_by_device_id = ?3,
              resolver_role = ?4,
              resolution_reason = 'Automatically merged catalog usage statistics.',
              affected_fields_json = '["usageCount","lastUsedDate"]',
              final_revision = ?5
        WHERE tenant_id = ?6 AND id = ?7 AND status = 'unresolved'`,
    ).bind(
      acceptedAt, identity.memberID, identity.deviceID, identity.role,
      revision, identity.tenantID, automaticallyResolvedConflictID,
    ).run();
  }
  return json({ revision, duplicate: false }, 201);
}

async function configureOwnerWorkProfile(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (identity.role !== "owner") return json({ error: "owner_required" }, 403);
  const body = await request.json<Record<string, unknown>>();
  const requested = Array.isArray(body.roles) ? body.roles : [];
  const allowed = new Map([
    ["salesperson", "Salesperson"],
    ["technician", "Technician"],
  ]);
  const roles = [...new Set(requested.map((value) =>
    typeof value === "string" ? allowed.get(value) : undefined,
  ).filter((value): value is string => Boolean(value)))];
  if (roles.length === 0 || roles.length !== requested.length) {
    return json({ error: "invalid_owner_work_roles" }, 400);
  }

  const member = await env.DB.prepare(
    `SELECT employee_id AS employeeID, display_name AS displayName
       FROM tenant_members
      WHERE tenant_id = ?1 AND id = ?2 AND status = 'active'`,
  ).bind(identity.tenantID, identity.memberID).first<{
    employeeID: string | null;
    displayName: string;
  }>();
  if (!member) return json({ error: "member_not_found" }, 404);

  const employeeID = member.employeeID ?? crypto.randomUUID();
  const words = member.displayName.trim().split(/\s+/);
  const firstName = words.shift() ?? "Owner";
  const lastName = words.join(" ");
  const now = new Date().toISOString();
  const revision = crypto.randomUUID();
  const operationID = crypto.randomUUID();
  const recordData = utf8Base64({
    id: employeeID,
    firstName,
    lastName,
    role: roles[0],
    roles,
    isActive: true,
    lifecycleStatus: "Active",
    createdDate: now,
  });
  const mutation = utf8Base64({
    entityType: "employee",
    entityID: employeeID,
    recordData,
    modifiedAt: now,
  });
  const operation = {
    id: operationID,
    idempotencyKey: `owner-work-profile-${identity.memberID}-${revision}`,
    sequenceNumber: 0,
    type: "recordMutation",
    entityType: "employee",
    entityID: employeeID,
    actionName: "upsertRecord",
    payload: {
      schemaVersion: 1,
      contentType: "application/vnd.pfss.record-mutation+json",
      body: mutation,
    },
    status: "synchronized",
    createdAt: now,
    updatedAt: now,
    retryAttempts: [],
    metadata: { source: "ownerWorkProfile" },
  };
  const operationJSON = JSON.stringify(operation);
  const current = await env.DB.prepare(
    `SELECT revision FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = 'employee' AND entity_id = ?2`,
  ).bind(identity.tenantID, employeeID).first<{ revision: string }>();

  const statements = [
    current
      ? env.DB.prepare(
        `UPDATE synchronized_records
            SET revision = ?1, operation_json = ?2,
                updated_by_member_id = ?3, updated_by_device_id = ?4,
                updated_at = ?5
          WHERE tenant_id = ?6 AND entity_type = 'employee' AND entity_id = ?7`,
      ).bind(revision, operationJSON, identity.memberID, identity.deviceID,
        now, identity.tenantID, employeeID)
      : env.DB.prepare(
        `INSERT INTO synchronized_records
          (tenant_id, entity_type, entity_id, revision, operation_json,
           updated_by_member_id, updated_by_device_id, updated_at)
         VALUES (?1, 'employee', ?2, ?3, ?4, ?5, ?6, ?7)`,
      ).bind(identity.tenantID, employeeID, revision, operationJSON,
        identity.memberID, identity.deviceID, now),
    env.DB.prepare(
      `INSERT INTO synchronized_operations
        (id, tenant_id, device_id, idempotency_key, operation_type,
         entity_type, entity_id, action_name, payload_json, created_at,
         accepted_at, revision)
       VALUES (?1, ?2, ?3, ?4, 'recordMutation', 'employee', ?5,
               'upsertRecord', ?6, ?7, ?7, ?8)`,
    ).bind(operationID, identity.tenantID, identity.deviceID,
      operation.idempotencyKey, employeeID, operationJSON, now, revision),
    env.DB.prepare(
      `UPDATE tenant_members SET employee_id = ?1
        WHERE tenant_id = ?2 AND id = ?3 AND role = 'owner'`,
    ).bind(employeeID, identity.tenantID, identity.memberID),
    accessAuditStatement(env, identity.tenantID, "owner.work_profile_updated", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      targetMemberID: identity.memberID,
      metadata: { employeeID, roles: roles.join(",") },
      createdAt: now,
    }),
  ];
  await env.DB.batch(statements);
  return json({ employeeID, roles, revision }, current ? 200 : 201);
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
  const changes = result.results.map((row) => {
    const operation = JSON.parse(row.payloadJSON) as Record<string, unknown>;
    const createdAt = typeof operation.createdAt === "string"
      ? operation.createdAt
      : new Date().toISOString();
    return {
      sequence: row.sequence,
      sourceDeviceID: row.deviceID,
      revision: row.revision,
      operation: {
        sequenceNumber: 0,
        status: "synchronized",
        updatedAt: createdAt,
        retryAttempts: [],
        metadata: {},
        ...operation,
      },
    };
  });
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
      if (
        request.method === "POST" &&
        url.pathname === "/v1/operations-auth/authorize"
      ) {
        return startOperationsAuthorization(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/operations-auth/callback"
      ) {
        return completeOperationsAuthorization(request, env);
      }
      if (url.pathname === "/v1/operations/session" ||
          url.pathname === "/v1/operations/summary" ||
          url.pathname === "/v1/operations/monitoring" ||
          url.pathname === "/v1/operations/accounts" ||
          url.pathname.startsWith("/v1/operations/accounts/")) {
        const operationsIdentity = await authenticateOperations(request, env);
        if (operationsIdentity instanceof Response) return operationsIdentity;
        if (request.method === "GET" && url.pathname === "/v1/operations/session") {
          return operationsSession(operationsIdentity);
        }
        if (request.method === "GET" && url.pathname === "/v1/operations/summary") {
          return operationsSummary(env, operationsIdentity);
        }
        if (request.method === "GET" && url.pathname === "/v1/operations/monitoring") {
          return operationsMonitoring(env, operationsIdentity);
        }
        if (request.method === "GET" && url.pathname === "/v1/operations/accounts") {
          return listOperationsAccounts(url, env, operationsIdentity);
        }
        const operationsPlanOverrideMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/plan-override$/,
        );
        if (request.method === "POST" && operationsPlanOverrideMatch) {
          return createOperationsPlanOverride(request, env, operationsIdentity,
            decodeURIComponent(operationsPlanOverrideMatch[1]));
        }
        const operationsHoldMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/hold$/,
        );
        if (request.method === "POST" && operationsHoldMatch) {
          return setOperationsAccountHold(request, env, operationsIdentity,
            decodeURIComponent(operationsHoldMatch[1]));
        }
        const operationsReactivateMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/reactivate$/,
        );
        if (request.method === "POST" && operationsReactivateMatch) {
          return reactivateOperationsAccount(request, env, operationsIdentity,
            decodeURIComponent(operationsReactivateMatch[1]));
        }
        const operationsAccountArchiveMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/(archive|restore|schedule-deletion|cancel-deletion)$/,
        );
        if (request.method === "POST" && operationsAccountArchiveMatch) {
          return manageOperationsAccountArchive(request, env, operationsIdentity,
            decodeURIComponent(operationsAccountArchiveMatch[1]),
            operationsAccountArchiveMatch[2] as OperationsAccountArchiveAction);
        }
        const operationsDeletionReadinessMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/deletion-readiness$/,
        );
        if (request.method === "GET" && operationsDeletionReadinessMatch) {
          return operationsDeletionReadiness(env, operationsIdentity,
            decodeURIComponent(operationsDeletionReadinessMatch[1]));
        }
        const operationsCleanupConfirmationMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/confirm-device-cleanup$/,
        );
        if (request.method === "POST" && operationsCleanupConfirmationMatch) {
          return confirmOperationsDeviceCleanup(request, env, operationsIdentity,
            decodeURIComponent(operationsCleanupConfirmationMatch[1]));
        }
        const operationsRecoveryArchiveMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/create-recovery-archive$/,
        );
        if (request.method === "POST" && operationsRecoveryArchiveMatch) {
          return createOperationsRecoveryArchive(request, env, operationsIdentity,
            decodeURIComponent(operationsRecoveryArchiveMatch[1]));
        }
        const operationsRecoveryMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/members\/([^/]+)\/password-reset$/,
        );
        if (request.method === "POST" && operationsRecoveryMatch) {
          return sendOperationsPasswordReset(
            request, env, operationsIdentity,
            decodeURIComponent(operationsRecoveryMatch[1]),
            decodeURIComponent(operationsRecoveryMatch[2]),
          );
        }
        const operationsSessionRevocationMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/members\/([^/]+)\/revoke-sessions$/,
        );
        if (request.method === "POST" && operationsSessionRevocationMatch) {
          return revokeOperationsUserSessions(
            request, env, operationsIdentity,
            decodeURIComponent(operationsSessionRevocationMatch[1]),
            decodeURIComponent(operationsSessionRevocationMatch[2]),
          );
        }
        const operationsMemberAccessMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/members\/([^/]+)\/(suspend|reactivate|revoke|archive|remove)$/,
        );
        if (request.method === "POST" && operationsMemberAccessMatch) {
          return manageOperationsMember(request, env, operationsIdentity,
            decodeURIComponent(operationsMemberAccessMatch[1]),
            decodeURIComponent(operationsMemberAccessMatch[2]),
            operationsMemberAccessMatch[3] as OperationsMemberAction);
        }
        const operationsDeviceAccessMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)\/devices\/([^/]+)\/(revoke|remove)$/,
        );
        if (request.method === "POST" && operationsDeviceAccessMatch) {
          return manageOperationsDevice(request, env, operationsIdentity,
            decodeURIComponent(operationsDeviceAccessMatch[1]),
            decodeURIComponent(operationsDeviceAccessMatch[2]),
            operationsDeviceAccessMatch[3] as "revoke" | "remove");
        }
        const operationsAccountMatch = url.pathname.match(
          /^\/v1\/operations\/accounts\/([^/]+)$/,
        );
        if (request.method === "GET" && operationsAccountMatch) {
          return operationsAccountDetail(
            env, operationsIdentity,
            decodeURIComponent(operationsAccountMatch[1]),
          );
        }
        return json({ error: "not_found" }, 404);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/owner-auth/authorize"
      ) {
        return startOwnerAuthorization(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/owner-auth/callback"
      ) {
        return completeOwnerAuthorization(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/owner-auth/sign-in"
      ) {
        return signInExistingOwner(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/account-recovery/redeem"
      ) {
        return redeemOwnerRecoveryCode(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/owner-invitations/accept"
      ) {
        return acceptOwnerInvitation(request, env);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/account-registration/validate"
      ) {
        return validateAccountRegistration(request);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/account-registration/attempts"
      ) {
        return startAccountRegistration(request, env);
      }
      const registrationAttemptMatch = url.pathname.match(
        /^\/v1\/account-registration\/attempts\/([^/]+)(\/(cancel|complete))?$/,
      );
      if (registrationAttemptMatch) {
        const attemptID = decodeURIComponent(registrationAttemptMatch[1]);
        if (request.method === "GET" && !registrationAttemptMatch[2]) {
          return getAccountRegistrationAttempt(request, env, attemptID);
        }
        if (request.method === "POST" && registrationAttemptMatch[3] === "cancel") {
          return cancelAccountRegistrationAttempt(request, env, attemptID);
        }
        if (request.method === "POST" && registrationAttemptMatch[3] === "complete") {
          return completeAccountRegistration(request, env, attemptID);
        }
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
      if (
        request.method === "GET" &&
        url.pathname === "/v1/account/entitlements"
      ) {
        return accountEntitlementStatus(env, identity);
      }
      if (
        request.method === "GET" &&
        url.pathname === "/v1/account-recovery/codes"
      ) {
        return ownerRecoveryStatus(env, identity);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/account-recovery/codes"
      ) {
        return replaceOwnerRecoveryCodes(env, identity);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/owner-invitations"
      ) {
        return createOwnerInvitation(request, env, identity);
      }
      const ownerMemberMatch = url.pathname.match(
        /^\/v1\/owner-members\/([^/]+)\/revoke$/,
      );
      if (request.method === "POST" && ownerMemberMatch) {
        return revokeOwnerMember(
          env, identity, decodeURIComponent(ownerMemberMatch[1]),
        );
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/account/owner-work-profile"
      ) {
        return configureOwnerWorkProfile(request, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/members") {
        return listMembers(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/invitations") {
        return createInvitation(request, env, identity);
      }
      const deviceInvitationMatch = url.pathname.match(
        /^\/v1\/members\/([^/]+)\/device-invitations$/,
      );
      if (request.method === "POST" && deviceInvitationMatch) {
        return createDeviceInvitation(
          env,
          identity,
          decodeURIComponent(deviceInvitationMatch[1]),
        );
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
