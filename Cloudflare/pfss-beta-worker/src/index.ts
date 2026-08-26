import {
  IdentityConfigurationError,
  IdentityProviderResponseError,
  ManagedIdentityConfigurationBindings,
  ManagedOwnerIdentityProvider,
  WorkOSManagedOwnerIdentityProvider,
  managedIdentityConfigurationFromBindings,
} from "./account-identity-provider";
import { resolveAccountEntitlements } from "./account-entitlements";
import synchronizationPolicyContract from
  "../../../PPS Receipt Printer/SynchronizationPolicyContract.json";

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
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_TOPIC?: string;
  APNS_ENVIRONMENT?: string;
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

const SYNCHRONIZATION_CONFLICT_POLICY_VERSION = 1;
const SYNCHRONIZATION_QUARANTINE_POLICY_VERSION = 1;

function conflictOperationalImpact(entityType: string, fields: string[]): string {
  const names = new Set(fields.map((field) => field.split(".")[0]));
  if ([...names].some((field) => [
    "roles", "role", "isActive", "accessRole", "lifecycleStatus",
  ].includes(field)) && entityType === "employee") {
    return "This decision can change employee access or active workforce status.";
  }
  if ([...names].some((field) => [
    "amountPaid", "balanceDue", "paidDate", "receipts", "total", "tax",
  ].includes(field))) {
    return "This decision can change billing, payment, or receipt records.";
  }
  if ([...names].some((field) => [
    "scheduledDate", "scheduledStart", "scheduledEnd", "scheduling",
    "arrivalWindowEnd", "completionDeadline", "routeSequence",
  ].includes(field))) {
    return "This decision can change when work is scheduled or routed.";
  }
  if ([...names].some((field) => [
    "primaryTechnicianID", "secondaryTechnicianID", "crew", "assignmentPriority",
  ].includes(field))) {
    return "This decision can change who is responsible for the work.";
  }
  if ([...names].some((field) => [
    "status", "workflowState", "lifecycleStatus", "completedDate",
  ].includes(field))) {
    return "This decision can change the record's workflow or lifecycle state.";
  }
  return "This decision changes shared company information on every synchronized device.";
}

function conflictReviewDetails(
  localOperation: Record<string, unknown>,
  cloudOperation: Record<string, unknown>,
  requestedFallback: string[] = [],
): { affectedFields: string[]; operationalImpact: string; policyVersion: number } {
  const envelope = versionedMutationEnvelope(localOperation);
  const base = decodedRecordData(envelope?.baseRecordData);
  const device = recordPayloadFromOperation(localOperation);
  const cloud = recordPayloadFromOperation(cloudOperation);
  let affectedFields: string[] = [];
  if (base && device && cloud) {
    const candidates = envelope?.changedFields?.length
      ? envelope.changedFields
      : topLevelChangedFields(base, device);
    affectedFields = [...new Set(candidates)].filter((field) =>
      !fieldStateEqual(device, base, field) &&
      !fieldStateEqual(cloud, base, field) &&
      !fieldStateEqual(device, cloud, field)
    ).sort();
  } else if (device && cloud) {
    affectedFields = topLevelChangedFields(device, cloud);
  }
  if (affectedFields.length === 0) {
    affectedFields = [...new Set(requestedFallback
      .filter((field) => typeof field === "string" && field.trim())
      .map((field) => field.trim()))].slice(0, 100);
  }
  if (affectedFields.length === 0) affectedFields = ["record"];
  const entityType = String(localOperation.entityType ?? "custom");
  return {
    affectedFields,
    operationalImpact: conflictOperationalImpact(entityType, affectedFields),
    policyVersion: SYNCHRONIZATION_CONFLICT_POLICY_VERSION,
  };
}

const STALE_DEVICE_CONFLICT_WINDOW_MS = 8 * 60 * 60 * 1000;

function cloudRecordClearlyNewer(
  cloudUpdatedAt: string,
  submittedOperation: Record<string, unknown>,
): boolean {
  const cloudTime = Date.parse(cloudUpdatedAt);
  const deviceTime = Date.parse(String(submittedOperation.createdAt ?? ""));
  return Number.isFinite(cloudTime) && Number.isFinite(deviceTime) &&
    cloudTime - deviceTime > STALE_DEVICE_CONFLICT_WINDOW_MS;
}

async function staleDeviceCloudReceipt(
  env: Env,
  identity: DeviceIdentity,
  entityType: string,
  entityID: string,
  revision: string,
  currentOperation: Record<string, unknown>,
): Promise<Response> {
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE synchronization_conflicts
          SET status = 'keptCloud', resolved_at = ?1,
              resolved_by_member_id = ?2, resolved_by_device_id = ?3,
              resolver_role = 'system',
              resolution_reason = 'Cloud record was more than eight hours newer than the stale device change.',
              affected_fields_json = '[]', final_revision = ?4
        WHERE tenant_id = ?5 AND source_device_id = ?3
          AND entity_type = ?6 AND entity_id = ?7 AND status = 'unresolved'`,
    ).bind(
      now, identity.memberID, identity.deviceID, revision,
      identity.tenantID, entityType, entityID,
    ),
    env.DB.prepare(
      `INSERT INTO access_audit_events
        (id, tenant_id, actor_member_id, actor_device_id, event_type,
         metadata_json, created_at)
       VALUES (?1, ?2, ?3, ?4, 'sync.stale_device_change_discarded',
               ?5, ?6)`,
    ).bind(
      crypto.randomUUID(), identity.tenantID, identity.memberID,
      identity.deviceID,
      JSON.stringify({
        entityType, entityID, policyWindowHours: 8,
        retainedRevision: revision,
      }),
      now,
    ),
  ]);
  return json({
    revision,
    duplicate: false,
    supersededByCloud: true,
    currentOperation,
  }, 200);
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
  await retireProvablyObsoleteLegacyConflicts(env, identity);
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
  return json({ conflicts: result.results.map((row) => {
    const localOperation = JSON.parse(row.localOperationJSON) as Record<string, unknown>;
    const cloudOperation = JSON.parse(row.cloudOperationJSON) as Record<string, unknown>;
    return {
      id: row.id,
      entityType: row.entityType,
      entityID: row.entityID,
      sourceMemberID: row.sourceMemberID,
      sourceDeviceID: row.sourceDeviceID,
      localOperation,
      cloudOperation,
      cloudRevision: row.cloudRevision,
      detectedAt: row.detectedAt,
      ...conflictReviewDetails(localOperation, cloudOperation),
    };
  }) });
}

async function retireProvablyObsoleteLegacyConflicts(
  env: Env,
  identity: DeviceIdentity,
): Promise<void> {
  const candidates = await env.DB.prepare(
    `SELECT synchronization_conflicts.id,
            synchronization_conflicts.local_operation_json AS localOperationJSON,
            synchronized_records.operation_json AS currentOperationJSON,
            synchronized_records.revision AS currentRevision
       FROM synchronization_conflicts
       JOIN synchronized_records
         ON synchronized_records.tenant_id = synchronization_conflicts.tenant_id
        AND synchronized_records.entity_type = synchronization_conflicts.entity_type
        AND synchronized_records.entity_id = synchronization_conflicts.entity_id
      WHERE synchronization_conflicts.tenant_id = ?1
        AND synchronization_conflicts.status = 'unresolved'`,
  ).bind(identity.tenantID).all<{
    id: string;
    localOperationJSON: string;
    currentOperationJSON: string;
    currentRevision: string;
  }>();

  for (const candidate of candidates.results) {
    let localOperation: Record<string, unknown>;
    let currentOperation: Record<string, unknown>;
    try {
      localOperation = JSON.parse(candidate.localOperationJSON);
      currentOperation = JSON.parse(candidate.currentOperationJSON);
    } catch {
      continue;
    }
    const envelope = versionedMutationEnvelope(localOperation);
    if ((envelope?.schemaVersion ?? 1) >= 2) continue;

    const localRecord = recordPayloadFromOperation(localOperation);
    const currentRecord = recordPayloadFromOperation(currentOperation);
    const sameOperation = String(localOperation.id ?? "") !== ""
      && String(localOperation.id) === String(currentOperation.id ?? "");
    const sameRecord = localRecord != null && currentRecord != null
      && canonicalJSON(localRecord) === canonicalJSON(currentRecord);
    if (!sameOperation && !sameRecord) continue;

    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE synchronization_conflicts
          SET status = 'keptCloud', resolved_at = ?1,
              resolved_by_member_id = ?2, resolved_by_device_id = ?3,
              resolver_role = ?4,
              resolution_reason = ?5,
              affected_fields_json = '[]', final_revision = ?6
        WHERE tenant_id = ?7 AND id = ?8 AND status = 'unresolved'`,
    ).bind(
      now, identity.memberID, identity.deviceID, identity.role,
      "Automatically retired: cloud already contains the identical legacy mutation.",
      candidate.currentRevision, identity.tenantID, candidate.id,
    ).run();
  }
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
            synchronization_conflicts.policy_version AS policyVersion,
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
    policyVersion: number;
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
    policyVersion: row.policyVersion,
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
  const providedReason = body.reason?.trim().slice(0, 500) ?? "";
  const reason = providedReason || (
    body.resolution === "keptDevice"
      ? "Manager or Owner chose the device version without an additional note."
      : "Manager or Owner chose the cloud version without an additional note."
  );
  const conflict = await env.DB.prepare(
    `SELECT entity_type AS entityType, entity_id AS entityID,
            local_operation_json AS localOperationJSON,
            cloud_operation_json AS cloudOperationJSON,
            cloud_revision AS cloudRevision, status,
            resolved_at AS resolvedAt, final_revision AS finalRevision
       FROM synchronization_conflicts
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, conflictID).first<{
    entityType: string;
    entityID: string;
    localOperationJSON: string;
    cloudOperationJSON: string;
    cloudRevision: string;
    status: string;
    resolvedAt: string | null;
    finalRevision: string | null;
  }>();
  if (!conflict) return json({ error: "conflict_not_found" }, 404);

  if (conflict.status !== "unresolved") {
    return json({
      id: conflictID,
      entityType: conflict.entityType,
      entityID: conflict.entityID,
      resolution: conflict.status,
      resolvedAt: conflict.resolvedAt,
      finalRevision: conflict.finalRevision ?? conflict.cloudRevision,
      duplicate: true,
    });
  }

  const localOperation = JSON.parse(conflict.localOperationJSON) as
    Record<string, unknown>;
  const cloudOperation = JSON.parse(conflict.cloudOperationJSON) as
    Record<string, unknown>;
  const review = conflictReviewDetails(
    localOperation,
    cloudOperation,
    body.affectedFields ?? [],
  );
  const current = await env.DB.prepare(
    `SELECT revision, operation_json AS operationJSON
       FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
  ).bind(
    identity.tenantID, conflict.entityType, conflict.entityID,
  ).first<{ revision: string; operationJSON: string }>();
  if (!current) return json({ error: "conflict_record_not_found" }, 404);
  if (current.revision !== conflict.cloudRevision) {
    await env.DB.prepare(
      `UPDATE synchronization_conflicts
          SET cloud_operation_json = ?1, cloud_revision = ?2
        WHERE tenant_id = ?3 AND id = ?4 AND status = 'unresolved'
          AND cloud_revision = ?5`,
    ).bind(
      current.operationJSON, current.revision, identity.tenantID, conflictID,
      conflict.cloudRevision,
    ).run();
    return json({
      error: "conflict_changed_since_review",
      currentRevision: current.revision,
    }, 409);
  }

  let finalRevision = conflict.cloudRevision;
  const resolutionOperationID = crypto.randomUUID();
  const resolutionKey = `conflict-resolution-${conflictID}`;
  const now = new Date().toISOString();
  let acceptedOperation: Record<string, unknown>;
  if (body.resolution === "keptDevice") {
    let operation = structuredClone(localOperation);
    operation.id = resolutionOperationID;
    operation.idempotencyKey = resolutionKey;
    operation.baseRevision = current.revision;
    operation.metadata = {
      ...(operation.metadata && typeof operation.metadata === "object"
        ? operation.metadata as Record<string, unknown>
        : {}),
      conflictResolution: "keptLocal",
      serverConflictID: conflictID,
      conflictPolicyVersion: String(review.policyVersion),
    };
    const localRecord = recordPayloadFromOperation(operation);
    const currentOperation = JSON.parse(current.operationJSON) as
      Record<string, unknown>;
    const appendOnlyResolution = automaticallyMergeAppendOnlyRecord(
      operation,
      currentOperation,
      current.revision,
    );
    if (appendOnlyResolution) {
      operation = appendOnlyResolution;
    } else if (localRecord) {
      const rebasedOperation = rewriteRecordMutation(
        operation,
        localRecord,
        current.revision,
        {},
      );
      if (!rebasedOperation) {
        return json({ error: "invalid_conflict_operation" }, 400);
      }
      operation = rebasedOperation;
    } else {
      // Legacy schema-1 conflict payloads have no embedded mutation revision.
      // Their single outer revision remains the authoritative rebase target.
      operation.baseRevision = current.revision;
    }
    const envelopeError = validateVersionedMutationEnvelope(operation, identity);
    if (envelopeError) return json({ error: envelopeError }, 400);
    finalRevision = crypto.randomUUID();
    acceptedOperation = operation;
  } else {
    const receipt = structuredClone(cloudOperation);
    receipt.id = resolutionOperationID;
    receipt.idempotencyKey = resolutionKey;
    receipt.metadata = {
      ...(receipt.metadata && typeof receipt.metadata === "object"
        ? receipt.metadata as Record<string, unknown>
        : {}),
      conflictResolution: "keptRemote",
      serverConflictID: conflictID,
      conflictPolicyVersion: String(review.policyVersion),
    };
    acceptedOperation = receipt;
  }

  const acceptedOperationJSON = JSON.stringify(acceptedOperation);
  const statements = [
    env.DB.prepare(
      `UPDATE synchronization_conflicts
          SET status = ?1, resolved_at = ?2,
              resolved_by_member_id = ?3, resolved_by_device_id = ?4,
              resolver_role = ?5, resolution_reason = ?6,
              affected_fields_json = ?7, final_revision = ?8,
              policy_version = ?9
        WHERE tenant_id = ?10 AND id = ?11 AND status = 'unresolved'
          AND cloud_revision = ?12
          AND EXISTS (
            SELECT 1 FROM synchronized_records
             WHERE tenant_id = ?10 AND entity_type = ?13 AND entity_id = ?14
               AND revision = ?12
          )`,
    ).bind(
      body.resolution, now, identity.memberID, identity.deviceID,
      identity.role, reason, JSON.stringify(review.affectedFields),
      finalRevision, review.policyVersion, identity.tenantID, conflictID,
      conflict.cloudRevision, conflict.entityType, conflict.entityID,
    ),
  ];
  if (body.resolution === "keptDevice") {
    statements.push(env.DB.prepare(
      `UPDATE synchronized_records
          SET revision = ?1, operation_json = ?2,
              updated_by_member_id = ?3, updated_by_device_id = ?4,
              updated_at = ?5
        WHERE tenant_id = ?6 AND entity_type = ?7 AND entity_id = ?8
          AND revision = ?9
          AND EXISTS (
            SELECT 1 FROM synchronization_conflicts
             WHERE tenant_id = ?6 AND id = ?10 AND status = 'keptDevice'
               AND final_revision = ?1 AND resolved_at = ?5
          )`,
    ).bind(
      finalRevision, acceptedOperationJSON, identity.memberID,
      identity.deviceID, now, identity.tenantID, conflict.entityType,
      conflict.entityID, conflict.cloudRevision, conflictID,
    ));
    if (conflict.entityType === "employee") {
      statements.push(env.DB.prepare(
        `DELETE FROM operations_account_email_index
          WHERE tenant_id = ?1 AND source_kind = 'employeeRecord'
            AND source_id = ?2
            AND EXISTS (
              SELECT 1 FROM synchronization_conflicts
               WHERE tenant_id = ?1 AND id = ?3 AND status = 'keptDevice'
                 AND final_revision = ?4 AND resolved_at = ?5
            )`,
      ).bind(
        identity.tenantID, conflict.entityID, conflictID, finalRevision, now,
      ));
      const contact = employeeSearchContactFromOperation(acceptedOperation);
      if (contact) {
        statements.push(env.DB.prepare(
          `INSERT INTO operations_account_email_index
            (tenant_id, source_kind, source_id, normalized_email,
             display_name, role_hint, updated_at)
           SELECT ?1, 'employeeRecord', ?2, ?3, ?4, ?5, ?6
            WHERE EXISTS (
              SELECT 1 FROM synchronization_conflicts
               WHERE tenant_id = ?1 AND id = ?7 AND status = 'keptDevice'
                 AND final_revision = ?8 AND resolved_at = ?6
            )`,
        ).bind(
          identity.tenantID, conflict.entityID, contact.normalizedEmail,
          contact.displayName || null, contact.roleHint, now, conflictID,
          finalRevision,
        ));
      }
    }
  }
  statements.push(
    env.DB.prepare(
      `INSERT INTO synchronized_operations
        (id, tenant_id, device_id, idempotency_key, operation_type,
         entity_type, entity_id, action_name, payload_json, created_at,
         accepted_at, revision)
       SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10, ?11
        WHERE EXISTS (
          SELECT 1 FROM synchronization_conflicts
           WHERE tenant_id = ?2 AND id = ?12 AND status = ?13
             AND final_revision = ?11 AND resolved_at = ?10
        )`,
    ).bind(
      resolutionOperationID, identity.tenantID, identity.deviceID,
      resolutionKey, String(acceptedOperation.type ?? "recordMutation"),
      conflict.entityType, conflict.entityID,
      String(acceptedOperation.actionName ?? "upsertRecord"),
      acceptedOperationJSON, now, finalRevision, conflictID, body.resolution,
    ),
    env.DB.prepare(
      `INSERT INTO synchronization_change_log
        (tenant_id, tenant_sequence, operation_id, device_id, revision,
         payload_json, accepted_at)
       SELECT ?1, COALESCE(MAX(tenant_sequence), 0) + 1, ?2, ?3, ?4, ?5, ?6
         FROM synchronization_change_log
        WHERE tenant_id = ?1
          AND EXISTS (
            SELECT 1 FROM synchronization_conflicts
             WHERE tenant_id = ?1 AND id = ?7 AND status = ?8
               AND final_revision = ?4 AND resolved_at = ?6
          )`,
    ).bind(
      identity.tenantID, resolutionOperationID, identity.deviceID,
      finalRevision, acceptedOperationJSON, now, conflictID, body.resolution,
    ),
    env.DB.prepare(
      `INSERT INTO access_audit_events
        (id, tenant_id, actor_member_id, actor_device_id, event_type,
         metadata_json, created_at)
       SELECT ?1, ?2, ?3, ?4, 'sync.conflict_resolved', ?5, ?6
        WHERE EXISTS (
          SELECT 1 FROM synchronization_conflicts
           WHERE tenant_id = ?2 AND id = ?7 AND status = ?8
             AND final_revision = ?9 AND resolved_at = ?6
        )`,
    ).bind(
      crypto.randomUUID(), identity.tenantID, identity.memberID,
      identity.deviceID, JSON.stringify({
        conflictID,
        resolution: body.resolution,
        resolverRole: identity.role,
        affectedFields: JSON.stringify(review.affectedFields),
        finalRevision,
        reason,
        policyVersion: String(review.policyVersion),
      }), now, conflictID, body.resolution, finalRevision,
    ),
  );
  let results: D1Result<unknown>[];
  try {
    results = await env.DB.batch(statements);
  } catch {
    const existing = await env.DB.prepare(
      `SELECT status, resolved_at AS resolvedAt, final_revision AS finalRevision
         FROM synchronization_conflicts
        WHERE tenant_id = ?1 AND id = ?2`,
    ).bind(identity.tenantID, conflictID).first<{
      status: string;
      resolvedAt: string | null;
      finalRevision: string | null;
    }>();
    if (existing && existing.status !== "unresolved") {
      return json({
        id: conflictID,
        entityType: conflict.entityType,
        entityID: conflict.entityID,
        resolution: existing.status,
        resolvedAt: existing.resolvedAt,
        finalRevision: existing.finalRevision ?? conflict.cloudRevision,
        duplicate: true,
      });
    }
    return json({ error: "conflict_resolution_failed" }, 409);
  }
  const recordResultIndex = body.resolution === "keptDevice" ? 1 : null;
  if (results[0].meta.changes !== 1 ||
      (recordResultIndex !== null && results[recordResultIndex].meta.changes !== 1)) {
    return json({ error: "conflict_changed_since_review" }, 409);
  }
  return json({
    id: conflictID,
    entityType: conflict.entityType,
    entityID: conflict.entityID,
    resolution: body.resolution,
    resolvedAt: now,
    finalRevision,
    policyVersion: review.policyVersion,
    affectedFields: review.affectedFields,
  });
}

async function discardRevokedDeviceSynchronizationConflicts(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canResolveConflicts(identity)) return json({ error: "forbidden" }, 403);
  const body = await request.json<{
    sourceDeviceID?: string;
    expectedCount?: number;
    reason?: string;
  }>();
  const sourceDeviceID = body.sourceDeviceID?.trim() ?? "";
  const expectedCount = Number.isInteger(body.expectedCount)
    ? Number(body.expectedCount)
    : 0;
  const reason = body.reason?.trim().slice(0, 500) ?? "";
  if (!sourceDeviceID || expectedCount < 1 || expectedCount > 1_000) {
    return json({ error: "invalid_revoked_device_conflict_scope" }, 400);
  }
  if (reason.length < 10) {
    return json({ error: "conflict_resolution_reason_required" }, 400);
  }
  const sourceDevice = await env.DB.prepare(
    `SELECT revoked_at AS revokedAt FROM devices
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, sourceDeviceID).first<{ revokedAt: string | null }>();
  if (!sourceDevice) return json({ error: "source_device_not_found" }, 404);
  if (!sourceDevice.revokedAt) {
    return json({ error: "source_device_must_be_revoked" }, 409);
  }
  const scope = await env.DB.prepare(
    `SELECT COUNT(*) AS count,
            SUM(CASE WHEN synchronized_records.revision IS NULL THEN 1 ELSE 0 END)
              AS missingRecords
       FROM synchronization_conflicts
       LEFT JOIN synchronized_records
         ON synchronized_records.tenant_id = synchronization_conflicts.tenant_id
        AND synchronized_records.entity_type = synchronization_conflicts.entity_type
        AND synchronized_records.entity_id = synchronization_conflicts.entity_id
      WHERE synchronization_conflicts.tenant_id = ?1
        AND synchronization_conflicts.source_device_id = ?2
        AND synchronization_conflicts.status = 'unresolved'`,
  ).bind(identity.tenantID, sourceDeviceID).first<{
    count: number;
    missingRecords: number;
  }>();
  if (Number(scope?.count ?? 0) !== expectedCount) {
    return json({
      error: "revoked_device_conflict_count_changed",
      currentCount: Number(scope?.count ?? 0),
    }, 409);
  }
  if (Number(scope?.missingRecords ?? 0) !== 0) {
    return json({ error: "conflict_record_not_found" }, 409);
  }

  const now = new Date().toISOString();
  const batchID = crypto.randomUUID();
  const exactScope = `tenant_id = ?1 AND source_device_id = ?2
    AND status = 'unresolved'
    AND (SELECT COUNT(*) FROM synchronization_conflicts
          WHERE tenant_id = ?1 AND source_device_id = ?2
            AND status = 'unresolved') = ?3`;
  const results = await env.DB.batch([
    env.DB.prepare(
      `UPDATE synchronization_conflicts
          SET status = 'keptCloud', resolved_at = ?4,
              resolved_by_member_id = ?5, resolved_by_device_id = ?6,
              resolver_role = ?7, resolution_reason = ?8,
              affected_fields_json = '[]',
              final_revision = (
                SELECT revision FROM synchronized_records
                 WHERE synchronized_records.tenant_id = synchronization_conflicts.tenant_id
                   AND synchronized_records.entity_type = synchronization_conflicts.entity_type
                   AND synchronized_records.entity_id = synchronization_conflicts.entity_id
              ), policy_version = 1
        WHERE ${exactScope}`,
    ).bind(
      identity.tenantID, sourceDeviceID, expectedCount, now,
      identity.memberID, identity.deviceID, identity.role, reason,
    ),
    env.DB.prepare(
      `INSERT INTO synchronized_operations
        (id, tenant_id, device_id, idempotency_key, operation_type,
         entity_type, entity_id, action_name, payload_json, created_at,
         accepted_at, revision)
       SELECT 'conflict-resolution-' || id, tenant_id, ?1,
              'conflict-resolution-' || id,
              COALESCE(json_extract(cloud_operation_json, '$.type'), 'recordMutation'),
              entity_type, entity_id,
              COALESCE(json_extract(cloud_operation_json, '$.actionName'), 'upsertRecord'),
              json_set(cloud_operation_json,
                '$.id', id,
                '$.idempotencyKey', 'conflict-resolution-' || id,
                '$.metadata.conflictResolution', 'keptRemote',
                '$.metadata.serverConflictID', id),
              ?2, ?2, final_revision
         FROM synchronization_conflicts
        WHERE tenant_id = ?3 AND source_device_id = ?4
          AND status = 'keptCloud' AND resolved_at = ?2`,
    ).bind(identity.deviceID, now, identity.tenantID, sourceDeviceID),
    env.DB.prepare(
      `INSERT INTO synchronization_change_log
        (tenant_id, tenant_sequence, operation_id, device_id, revision,
         payload_json, accepted_at)
       SELECT ?1, base.maximumSequence + ranked.position,
              'conflict-resolution-' || ranked.id, ?2,
              ranked.finalRevision, ranked.payloadJSON, ?3
         FROM (
           SELECT id, final_revision AS finalRevision,
                  json_set(cloud_operation_json,
                    '$.id', id,
                    '$.idempotencyKey', 'conflict-resolution-' || id,
                    '$.metadata.conflictResolution', 'keptRemote',
                    '$.metadata.serverConflictID', id) AS payloadJSON,
                  ROW_NUMBER() OVER (ORDER BY detected_at, id) AS position
             FROM synchronization_conflicts
            WHERE tenant_id = ?1 AND source_device_id = ?4
              AND status = 'keptCloud' AND resolved_at = ?3
         ) AS ranked
         CROSS JOIN (
           SELECT COALESCE(MAX(tenant_sequence), 0) AS maximumSequence
             FROM synchronization_change_log WHERE tenant_id = ?1
         ) AS base`,
    ).bind(identity.tenantID, identity.deviceID, now, sourceDeviceID),
    env.DB.prepare(
      `INSERT INTO access_audit_events
        (id, tenant_id, actor_member_id, actor_device_id, event_type,
         metadata_json, created_at)
       SELECT 'conflict-audit-' || id, tenant_id, ?1, ?2,
              'sync.conflict_resolved',
              json_object(
                'conflictID', id, 'resolution', 'keptCloud',
                'resolverRole', ?3, 'affectedFields', '[]',
                'finalRevision', final_revision, 'reason', ?4,
                'policyVersion', '1', 'batchID', ?5,
                'sourceDeviceID', source_device_id), ?6
         FROM synchronization_conflicts
        WHERE tenant_id = ?7 AND source_device_id = ?8
          AND status = 'keptCloud' AND resolved_at = ?6`,
    ).bind(
      identity.memberID, identity.deviceID, identity.role, reason,
      batchID, now, identity.tenantID, sourceDeviceID,
    ),
  ]);
  if (results[0].meta.changes !== expectedCount ||
      results[1].meta.changes !== expectedCount ||
      results[2].meta.changes !== expectedCount ||
      results[3].meta.changes !== expectedCount) {
    return json({ error: "revoked_device_conflict_cleanup_failed" }, 409);
  }
  return json({
    sourceDeviceID,
    resolvedCount: expectedCount,
    resolution: "keptCloud",
    resolvedAt: now,
    batchID,
  });
}

async function revokedDeviceSynchronizationConflictScope(
  url: URL,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canResolveConflicts(identity)) return json({ error: "forbidden" }, 403);
  const sourceDeviceID = url.searchParams.get("sourceDeviceID")?.trim() ?? "";
  if (!sourceDeviceID) {
    return json({ error: "invalid_revoked_device_conflict_scope" }, 400);
  }
  const scope = await env.DB.prepare(
    `SELECT devices.revoked_at AS revokedAt,
            COUNT(synchronization_conflicts.id) AS conflictCount
       FROM devices
       LEFT JOIN synchronization_conflicts
         ON synchronization_conflicts.tenant_id = devices.tenant_id
        AND synchronization_conflicts.source_device_id = devices.id
        AND synchronization_conflicts.status = 'unresolved'
      WHERE devices.tenant_id = ?1 AND devices.id = ?2
      GROUP BY devices.id, devices.revoked_at`,
  ).bind(identity.tenantID, sourceDeviceID).first<{
    revokedAt: string | null;
    conflictCount: number;
  }>();
  if (!scope) return json({ error: "source_device_not_found" }, 404);
  return json({
    sourceDeviceID,
    conflictCount: Number(scope.conflictCount),
    isRevoked: scope.revokedAt != null,
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

function accessRoleFromEmployeeOperation(
  operation: Record<string, unknown>,
): "manager" | "member" | null {
  const roles = employeeRolesFromOperation(operation);
  if (!roles) return null;
  return roles.includes("Manager") ? "manager" : "member";
}

function recordPayloadFromOperation(
  operation: Record<string, unknown>,
): Record<string, unknown> | null {
  try {
    const payload = operation.payload as { body?: string } | undefined;
    const mutation = JSON.parse(atob(payload?.body ?? "")) as {
      recordData?: string;
    };
    return JSON.parse(atob(mutation.recordData ?? "")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

type VersionedMutationEnvelope = {
  schemaVersion?: number;
  operationID?: string;
  tenantID?: string | null;
  deviceID?: string | null;
  entityType?: string;
  recordID?: string;
  baseRevision?: string | null;
  mutationKind?: string;
  changedFields?: string[];
  commandName?: string | null;
  baseRecordData?: string | null;
  recordData?: string | null;
};

function versionedMutationEnvelope(
  operation: Record<string, unknown>,
): VersionedMutationEnvelope | null {
  try {
    const payload = operation.payload as { body?: string } | undefined;
    if (!payload?.body) return null;
    return JSON.parse(atob(payload.body)) as VersionedMutationEnvelope;
  } catch {
    return null;
  }
}

function decodedRecordData(value: string | null | undefined): Record<string, unknown> | null {
  if (!value) return null;
  try {
    const decoded = JSON.parse(atob(value));
    return decoded !== null && typeof decoded === "object" && !Array.isArray(decoded)
      ? decoded as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

const appendOnlyFieldsByEntity: Record<string, Set<string>> = {
  job: new Set(["timelineEvents"]),
  assignment: new Set(["history"]),
  invoice: new Set(["receipts"]),
};

const commandFieldsByEntity: Record<string, Record<string, Set<string>>> =
  Object.fromEntries(
    Object.entries(synchronizationPolicyContract.commandsByEntity).map(
      ([entityType, commands]) => [
        entityType,
        Object.fromEntries(Object.entries(commands).map(
          ([command, fields]) => [command, new Set(fields)],
        )),
      ]),
  );

function fieldsForDomainCommand(
  entityType: string,
  commandName: string,
): Set<string> | undefined {
  return commandFieldsByEntity[entityType]?.[commandName]
    ?? commandFieldsByEntity["*"]?.[commandName];
}

function topLevelChangedFields(
  base: Record<string, unknown>,
  changed: Record<string, unknown>,
): string[] {
  return [...new Set([...Object.keys(base), ...Object.keys(changed)])]
    .filter((field) => canonicalJSON(base[field]) !== canonicalJSON(changed[field]))
    .sort();
}

function validateVersionedMutationEnvelope(
  operation: Record<string, unknown>,
  identity: DeviceIdentity,
): string | null {
  const payload = operation.payload as {
    body?: string;
    contentType?: string;
  } | undefined;
  // Legacy operations either have no encoded mutation body or use a
  // non-JSON transport contract. They remain supported and continue through
  // the existing authorization/conflict rules below.
  if (!payload?.body) return null;
  try {
    const mutation = JSON.parse(atob(payload?.body ?? "")) as VersionedMutationEnvelope;
    // Schema 1 is the supported legacy whole-record payload.
    if ((mutation.schemaVersion ?? 1) < 2) return null;
    if (mutation.schemaVersion !== 2) return "unsupported_mutation_schema";
    if (mutation.operationID?.toLowerCase() !== String(operation.id ?? "").toLowerCase()) {
      return "mutation_operation_mismatch";
    }
    if (mutation.entityType !== String(operation.entityType ?? "")) {
      return "mutation_entity_mismatch";
    }
    if (mutation.recordID?.toLowerCase() !== String(operation.entityID ?? "").toLowerCase()) {
      return "mutation_record_mismatch";
    }
    const outerBase = operation.baseRevision == null
      ? null : String(operation.baseRevision);
    if ((mutation.baseRevision ?? null) !== outerBase) {
      return "mutation_base_revision_mismatch";
    }
    if (mutation.tenantID != null && mutation.tenantID !== identity.tenantID) {
      return "mutation_tenant_mismatch";
    }
    if (
      mutation.deviceID != null &&
      mutation.deviceID.toLowerCase() !== identity.deviceID.toLowerCase()
    ) {
      return "mutation_device_mismatch";
    }
    const allowedKinds = new Set(["wholeRecord", "fieldPatch", "appendFact", "domainCommand"]);
    if (!allowedKinds.has(mutation.mutationKind ?? "")) {
      return "unsupported_mutation_kind";
    }
    if (!mutation.recordData) {
      return "mutation_record_data_required";
    }
    const record = decodedRecordData(mutation.recordData);
    if (!record) return "invalid_mutation_record_data";
    if (mutation.mutationKind !== "wholeRecord") {
      const fields = mutation.changedFields;
      if (!Array.isArray(fields) || fields.length === 0 ||
          fields.some((field) => typeof field !== "string" || !field) ||
          new Set(fields).size !== fields.length) {
        return "mutation_changed_fields_required";
      }
      if (mutation.baseRevision && !decodedRecordData(mutation.baseRecordData)) {
        return "mutation_base_record_required";
      }
      if (mutation.mutationKind === "appendFact") {
        const allowed = appendOnlyFieldsByEntity[mutation.entityType ?? ""] ?? new Set<string>();
        if (fields.some((field) => !allowed.has(field))) {
          return "invalid_append_only_field";
        }
      }
if (mutation.mutationKind === "domainCommand") {
  const commandName = mutation.commandName ?? "";
  const allowed = fieldsForDomainCommand(mutation.entityType ?? "", commandName);
  const assignmentCommandNames = [
    "assignment.assign",
    "assignment.reschedule",
    "assignment.transition",
    "assignment.updateNotes",
  ];
  const assignmentCompatibleFields = new Set<string>(
    assignmentCommandNames.flatMap((name) =>
      Array.from(fieldsForDomainCommand("assignment", name) ?? [])
    )
  );
  const isCompatibleCompositeAssignment =
    assignmentCommandNames.includes(commandName) &&
    fields.every((field) => assignmentCompatibleFields.has(field));

  if (
    !allowed ||
    (fields.some((field) => !allowed.has(field)) &&
      !isCompatibleCompositeAssignment)
  ) {
    return "invalid_domain_command";
  }
}
    }
    return null;
  } catch {
    return payload.contentType === "application/json"
      ? "invalid_mutation_envelope"
      : null;
  }
}

function primaryTechnicianFromRecord(
  entityType: string,
  record: Record<string, unknown> | null,
): string | null {
  if (!record) return null;
  if (entityType === "job") {
    return record.primaryTechnicianID == null
      ? null : String(record.primaryTechnicianID).toLowerCase();
  }
  if (entityType === "assignment") {
    const crew = record.crew as { members?: Array<Record<string, unknown>> } | undefined;
    const primary = (crew?.members ?? []).find((member) =>
      String(member.role ?? "") === "Primary Technician" && member.removedDate == null,
    );
    return primary?.employeeID == null
      ? null : String(primary.employeeID).toLowerCase();
  }
  return null;
}

function preserveCloudAssignmentAuthority(
  submittedOperation: Record<string, unknown>,
  acceptedOperation: Record<string, unknown>,
  entityType: string,
): Record<string, unknown> {
  const submittedRecord = recordPayloadFromOperation(submittedOperation);
  const acceptedRecord = recordPayloadFromOperation(acceptedOperation);
  if (!submittedRecord || !acceptedRecord) return submittedOperation;

  const protectedFields: string[] = [];
  if (entityType === "job") {
    if (Object.prototype.hasOwnProperty.call(acceptedRecord, "primaryTechnicianID")) {
      submittedRecord.primaryTechnicianID = acceptedRecord.primaryTechnicianID;
    } else {
      delete submittedRecord.primaryTechnicianID;
    }
    protectedFields.push("primaryTechnicianID");
  } else if (entityType === "assignment") {
    if (Object.prototype.hasOwnProperty.call(acceptedRecord, "crew")) {
      submittedRecord.crew = acceptedRecord.crew;
    } else {
      delete submittedRecord.crew;
    }
    protectedFields.push("crew");
  } else {
    return submittedOperation;
  }

  try {
    const rewritten = structuredClone(submittedOperation);
    const payload = rewritten.payload as { body?: string } | undefined;
    const mutation = JSON.parse(atob(payload?.body ?? "")) as {
      recordData?: string;
    };
    mutation.recordData = utf8Base64(submittedRecord);
    if (!payload) return submittedOperation;
    payload.body = utf8Base64(mutation);
    rewritten.metadata = {
      ...((rewritten.metadata as Record<string, unknown> | undefined) ?? {}),
      serverProtectedFields: protectedFields,
    };
    return rewritten;
  } catch {
    return submittedOperation;
  }
}

const jobWorkflowMergeFields = new Set([
  "status", "workflowState", "timelineEvents", "setupStartDate",
  "workStartDate", "completedDate",
]);

function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJSON(record[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value) ?? "undefined";
}

function fieldStateEqual(
  lhs: Record<string, unknown>,
  rhs: Record<string, unknown>,
  field: string,
): boolean {
  const lhsHas = Object.prototype.hasOwnProperty.call(lhs, field);
  const rhsHas = Object.prototype.hasOwnProperty.call(rhs, field);
  return lhsHas === rhsHas && (!lhsHas || canonicalJSON(lhs[field]) === canonicalJSON(rhs[field]));
}

function appendFactArray(value: unknown): Array<Record<string, unknown>> | null {
  const candidates = Array.isArray(value)
    ? value
    : value !== null && typeof value === "object" && !Array.isArray(value) &&
        Array.isArray((value as Record<string, unknown>).events)
      ? (value as Record<string, unknown>).events as unknown[]
      : null;
  if (!candidates) return null;
  const facts: Array<Record<string, unknown>> = [];
  for (const candidate of candidates) {
    if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)) return null;
    facts.push(candidate as Record<string, unknown>);
  }
  return facts;
}

function appendFactsByID(value: unknown): Map<string, Record<string, unknown>> | null {
  const facts = appendFactArray(value);
  if (!facts) return null;
  const result = new Map<string, Record<string, unknown>>();
  for (const fact of facts) {
    const id = String(fact.id ?? "").toLowerCase();
    if (!id) return null;
    const existing = result.get(id);
    if (existing && canonicalJSON(existing) !== canonicalJSON(fact)) return null;
    result.set(id, fact);
  }
  return result;
}

function mergeAppendOnlyFacts(
  baseValue: unknown,
  deviceValue: unknown,
  cloudValue: unknown,
): unknown | null {
  const base = appendFactsByID(baseValue ?? []);
  const device = appendFactsByID(deviceValue ?? []);
  const cloud = appendFactsByID(cloudValue ?? []);
  if (!base || !device || !cloud) return null;
  for (const [id, fact] of base) {
    if (canonicalJSON(device.get(id)) !== canonicalJSON(fact) ||
        canonicalJSON(cloud.get(id)) !== canonicalJSON(fact)) return null;
  }
  const merged = new Map(cloud);
  for (const [id, fact] of device) {
    const existing = merged.get(id);
    if (existing && canonicalJSON(existing) !== canonicalJSON(fact)) return null;
    merged.set(id, fact);
  }
  const mergedFacts = [...merged.values()];
  const template = cloudValue ?? deviceValue ?? baseValue;
  if (template !== null && typeof template === "object" && !Array.isArray(template) &&
      Array.isArray((template as Record<string, unknown>).events)) {
    return {
      ...(template as Record<string, unknown>),
      events: mergedFacts,
    };
  }
  return mergedFacts;
}

function withoutJobWorkflowFields(record: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(record).filter(([key]) => !jobWorkflowMergeFields.has(key)),
  );
}

function jobStatusRank(value: unknown): number {
  return ["To Be Scheduled", "Scheduled", "Assigned", "In Progress", "Completed"]
    .indexOf(String(value));
}

function eventTimestamp(event: Record<string, unknown>): number {
  const parsed = Date.parse(String(event.timestamp ?? ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function mergeTimelineEvents(cloudValue: unknown, deviceValue: unknown): Array<Record<string, unknown>> | null {
  if (!Array.isArray(cloudValue) || !Array.isArray(deviceValue)) return null;
  const merged = new Map<string, Record<string, unknown>>();
  for (const candidate of [...cloudValue, ...deviceValue]) {
    if (candidate === null || typeof candidate !== "object") return null;
    const event = candidate as Record<string, unknown>;
    const id = String(event.id ?? "").toLowerCase();
    if (!id) return null;
    const existing = merged.get(id);
    if (existing && canonicalJSON(existing) !== canonicalJSON(event)) return null;
    merged.set(id, event);
  }
  return [...merged.values()].sort((lhs, rhs) => eventTimestamp(lhs) - eventTimestamp(rhs));
}

function rewriteRecordMutation(
  operation: Record<string, unknown>,
  record: Record<string, unknown>,
  baseRevision: string,
  metadata: Record<string, unknown>,
  baseRecord?: Record<string, unknown>,
): Record<string, unknown> | null {
  try {
    const rewritten = structuredClone(operation);
    const payload = rewritten.payload as { body?: string } | undefined;
    if (!payload) return null;
    const mutation = JSON.parse(atob(payload.body ?? "")) as {
      operationID?: string;
      baseRevision?: string | null;
      recordData?: string;
      baseRecordData?: string | null;
    };
    mutation.operationID = String(rewritten.id ?? mutation.operationID ?? "");
    mutation.baseRevision = baseRevision;
    mutation.recordData = utf8Base64(record);
    mutation.baseRecordData = utf8Base64(baseRecord ?? record);
    payload.body = utf8Base64(mutation);
    rewritten.baseRevision = baseRevision;
    rewritten.metadata = {
      ...((rewritten.metadata as Record<string, unknown> | undefined) ?? {}),
      ...metadata,
    };
    return rewritten;
  } catch {
    return null;
  }
}

function verifiedThreeWayMerge(
  submittedOperation: Record<string, unknown>,
  acceptedOperation: Record<string, unknown>,
  currentRevision: string,
): Record<string, unknown> | null {
  const envelope = versionedMutationEnvelope(submittedOperation);
  if (!envelope || (envelope.schemaVersion ?? 1) < 2 ||
      envelope.mutationKind === "wholeRecord") return null;
  const base = decodedRecordData(envelope.baseRecordData);
  const device = decodedRecordData(envelope.recordData);
  const cloud = recordPayloadFromOperation(acceptedOperation);
  const declared = [...new Set(envelope.changedFields ?? [])].sort();
  if (!base || !device || !cloud || declared.length === 0 ||
      canonicalJSON(topLevelChangedFields(base, device)) !== canonicalJSON(declared)) return null;

  const merged = structuredClone(cloud);
  for (const field of declared) {
    if (appendOnlyFieldsByEntity[envelope.entityType ?? ""]?.has(field)) {
      const facts = mergeAppendOnlyFacts(base[field], device[field], cloud[field]);
      if (!facts) return null;
      merged[field] = facts;
      continue;
    }
    if (fieldStateEqual(cloud, base, field)) {
      if (Object.prototype.hasOwnProperty.call(device, field)) merged[field] = device[field];
      else delete merged[field];
    } else if (!fieldStateEqual(cloud, device, field)) {
      return null;
    }
  }
  return rewriteRecordMutation(submittedOperation, merged, currentRevision, {
    verifiedThreeWayMerge: true,
    mergedFields: declared,
  }, cloud);
}

// Compatibility bridge for records written by clients that still submit a
// complete record after appending an immutable fact. Only append-only fields
// may differ, and facts are unioned by their stable IDs. Any simultaneous
// status, scheduling, assignment, archive, or other mutable-field change is
// deliberately left for the normal conflict workflow.
function automaticallyMergeAppendOnlyRecord(
  submittedOperation: Record<string, unknown>,
  acceptedOperation: Record<string, unknown>,
  currentRevision: string,
): Record<string, unknown> | null {
  const entityType = String(submittedOperation.entityType ?? "");
  const appendOnlyFields = appendOnlyFieldsByEntity[entityType];
  if (!appendOnlyFields?.size) return null;

  const device = recordPayloadFromOperation(submittedOperation);
  const cloud = recordPayloadFromOperation(acceptedOperation);
  if (!device || !cloud) return null;

  const differences = topLevelChangedFields(cloud, device);
  if (differences.length === 0 || differences.some((field) => !appendOnlyFields.has(field))) {
    return null;
  }

  const merged = structuredClone(cloud);
  for (const field of differences) {
    const facts = entityType === "job" && field === "timelineEvents"
      ? mergeTimelineEvents(cloud[field] ?? [], device[field] ?? [])
      : mergeAppendOnlyFacts([], device[field], cloud[field]);
    if (!facts) return null;
    merged[field] = facts;
  }

  return rewriteRecordMutation(submittedOperation, merged, currentRevision, {
    serverMergePolicy: "appendOnlyUnionV1",
    serverMergedFields: differences.join(","),
  }, cloud);
}

function automaticallyRebaseSameDeviceSuccessor(
  submittedOperation: Record<string, unknown>,
  acceptedOperation: Record<string, unknown>,
  currentRevision: string,
): Record<string, unknown> | null {
  const submittedSequence = Number(submittedOperation.sequenceNumber);
  const acceptedSequence = Number(acceptedOperation.sequenceNumber);
  if (
    !Number.isSafeInteger(submittedSequence) ||
    !Number.isSafeInteger(acceptedSequence) ||
    submittedSequence <= acceptedSequence
  ) return null;

  const submittedRecord = recordPayloadFromOperation(submittedOperation);
  if (!submittedRecord) return null;
  return rewriteRecordMutation(
    submittedOperation,
    submittedRecord,
    currentRevision,
    {
      serverMergePolicy: "sameDeviceCausalSuccessorV1",
      serverRebasedFromSequence: String(acceptedSequence),
      serverRebasedToSequence: String(submittedSequence),
    },
  );
}

function automaticallyMergeJobWorkflow(
  submittedOperation: Record<string, unknown>,
  acceptedOperation: Record<string, unknown>,
  currentRevision: string,
): Record<string, unknown> | null {
  const device = recordPayloadFromOperation(submittedOperation);
  const cloud = recordPayloadFromOperation(acceptedOperation);
  if (!device || !cloud) return null;
  if (
    canonicalJSON(withoutJobWorkflowFields(device)) !==
      canonicalJSON(withoutJobWorkflowFields(cloud))
  ) return null;
  const timelineEvents = mergeTimelineEvents(cloud.timelineEvents ?? [], device.timelineEvents ?? []);
  if (!timelineEvents) return null;
  const latest = (value: unknown): number => Math.max(
    0,
    ...(Array.isArray(value)
      ? value.map((event) => eventTimestamp(event as Record<string, unknown>))
      : []),
  );
  const merged = structuredClone(cloud);
  merged.timelineEvents = timelineEvents;
  if (jobStatusRank(device.status) > jobStatusRank(cloud.status)) merged.status = device.status;
  if (latest(device.timelineEvents) >= latest(cloud.timelineEvents)) {
    merged.workflowState = device.workflowState;
  }
  for (const field of ["setupStartDate", "workStartDate", "completedDate"]) {
    if (merged[field] == null && device[field] != null) merged[field] = device[field];
  }
  return rewriteRecordMutation(submittedOperation, merged, currentRevision, {
    serverMergePolicy: "jobWorkflowTimelineV1",
    // iOS intentionally models operation metadata as [String: String]. Keep
    // server annotations inside that wire contract so an accepted merge can
    // always be read back through the tenant change feed.
    serverMergedFields: [...jobWorkflowMergeFields].join(","),
  });
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
  let operation = await request.json<Record<string, unknown>>();
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
    const envelopeError = validateVersionedMutationEnvelope(operation, identity);
    if (envelopeError) return json({ error: envelopeError }, 400);
    const allowed = new Set([
      "customer", "site", "lead", "estimate", "job", "assignment",
      "invoice", "employee", "catalog", "recurringWork", "custom",
    ]);
    if (!allowed.has(entityType) || !entityID) {
      return json({ error: "invalid_record_mutation" }, 400);
    }
    if (
      identity.role === "member" &&
      (entityType === "recurringWork" ||
        entityType === "custom" ||
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
    if (entityType === "employee") {
      const linkedMember = await env.DB.prepare(
        `SELECT id, role FROM tenant_members
          WHERE tenant_id = ?1 AND employee_id = ?2 AND status != 'revoked'
          ORDER BY created_at DESC LIMIT 1`,
      ).bind(identity.tenantID, entityID).first<{
        id: string;
        role: TenantRole;
      }>();
      const requestedAccessRole = accessRoleFromEmployeeOperation(operation);
      if (
        linkedMember && linkedMember.role !== "owner" && requestedAccessRole &&
        requestedAccessRole !== linkedMember.role && identity.role !== "owner"
      ) {
        return json({ error: "employee_access_role_change_requires_owner" }, 403);
      }
    }
    if (
      identity.role === "member" &&
      (entityType === "job" || entityType === "assignment")
    ) {
      const acceptedRecord = await env.DB.prepare(
        `SELECT operation_json AS operationJSON
           FROM synchronized_records
          WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
      ).bind(identity.tenantID, entityType, entityID).first<{
        operationJSON: string;
      }>();
      const submittedPrimary = primaryTechnicianFromRecord(
        entityType,
        recordPayloadFromOperation(operation),
      );
      const acceptedPrimary = acceptedRecord
        ? primaryTechnicianFromRecord(
            entityType,
            recordPayloadFromOperation(JSON.parse(acceptedRecord.operationJSON)),
          )
        : null;
      if (submittedPrimary !== acceptedPrimary) {
        // A field device can carry a stale technician/crew snapshot while making
        // an otherwise valid workflow update. Preserve the cloud-authorized
        // assignment instead of rejecting and stalling the entire offline queue.
        // This still prevents the member device from reassigning the work.
        if (!acceptedRecord) {
          const memberEmployeeID = identity.employeeID?.toLowerCase() ?? null;
          if (submittedPrimary !== null && submittedPrimary !== memberEmployeeID) {
            return json({ error: "technician_assignment_change_requires_manager" }, 403);
          }
        } else {
          operation = preserveCloudAssignmentAuthority(
            operation,
            JSON.parse(acceptedRecord.operationJSON),
            entityType,
          );
        }
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
  // Legacy command-shaped mutations remain valid history/feed events, but
  // only a mutation carrying a complete record body may replace canonical
  // recovery authority.
  const isCanonicalRecordMutation = isRecordMutation && (
    String(operation.actionName ?? "") === "upsertRecord" ||
    recordPayloadFromOperation(operation) !== null
  );
  if (isCanonicalRecordMutation) {
    const current = await env.DB.prepare(
      `SELECT revision, operation_json AS operationJSON,
              updated_by_device_id AS updatedByDeviceID,
              updated_at AS updatedAt
         FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
    ).bind(identity.tenantID, entityType, entityID).first<{
      revision: string;
      operationJSON: string;
      updatedByDeviceID: string;
      updatedAt: string;
    }>();
    const baseRevision = operation.baseRevision == null
      ? null
      : String(operation.baseRevision);
    if (
      (current && baseRevision !== current.revision &&
        !(baseRevision === null && current.updatedByDeviceID === identity.deviceID)) ||
      (!current && baseRevision !== null)
    ) {
      const acceptedOperation = current
        ? JSON.parse(current.operationJSON) as Record<string, unknown>
        : null;
      const phase20Envelope = versionedMutationEnvelope(operation);
      const usesPhase20Mutation = (phase20Envelope?.schemaVersion ?? 1) >= 2;
      const verifiedMerge = current && acceptedOperation
        ? verifiedThreeWayMerge(operation, acceptedOperation, current.revision)
        : null;
      const appendOnlyMerge = current && acceptedOperation
        ? automaticallyMergeAppendOnlyRecord(
          operation, acceptedOperation, current.revision,
        )
        : null;
      // A device queue is strictly ordered. If an accepted mutation from this
      // same device has a lower sequence number, the submitted operation is a
      // causal successor rather than an independent concurrent edit. Rebase
      // both revision layers and preserve the newer complete device record.
      // Cross-device and out-of-order mutations continue through conflict
      // detection so this never becomes an unrestricted last-writer-wins rule.
      const automaticallyRebased = !usesPhase20Mutation && current && acceptedOperation &&
          current.updatedByDeviceID === identity.deviceID
        ? automaticallyRebaseSameDeviceSuccessor(
          operation, acceptedOperation, current.revision,
        )
        : null;
      const automaticallyMerged = verifiedMerge ?? appendOnlyMerge ?? automaticallyRebased ?? (
        !usesPhase20Mutation && current && acceptedOperation && entityType === "job"
          ? automaticallyMergeJobWorkflow(
            operation, acceptedOperation, current.revision,
          )
          : null
      );
      if (automaticallyMerged) {
        operation = automaticallyMerged;
      } else {
        if (current && cloudRecordClearlyNewer(current.updatedAt, operation)) {
          return staleDeviceCloudReceipt(
            env, identity, entityType, entityID, current.revision,
            JSON.parse(current.operationJSON),
          );
        }
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
    }
    const rebasedRevision = operation.baseRevision == null
      ? null
      : String(operation.baseRevision);
    const effectiveBaseRevision = rebasedRevision ?? (
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
  if (isCanonicalRecordMutation && entityType === "employee") {
    const contact = employeeSearchContactFromOperation(operation);
    const requestedAccessRole = accessRoleFromEmployeeOperation(operation);
    const linkedMember = await env.DB.prepare(
      `SELECT id, role FROM tenant_members
        WHERE tenant_id = ?1 AND employee_id = ?2 AND status != 'revoked'
        ORDER BY created_at DESC LIMIT 1`,
    ).bind(identity.tenantID, entityID).first<{
      id: string;
      role: TenantRole;
    }>();
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
    if (
      linkedMember && linkedMember.role !== "owner" && requestedAccessRole &&
      linkedMember.role !== requestedAccessRole
    ) {
      statements.push(env.DB.prepare(
        `UPDATE tenant_members SET role = ?1
          WHERE tenant_id = ?2 AND id = ?3 AND role = ?4`,
      ).bind(requestedAccessRole, identity.tenantID, linkedMember.id,
        linkedMember.role));
      statements.push(accessAuditStatement(
        env,
        identity.tenantID,
        requestedAccessRole === "manager"
          ? "member.promoted_to_manager"
          : "member.demoted_to_member",
        {
          actorMemberID: identity.memberID,
          actorDeviceID: identity.deviceID,
          targetMemberID: linkedMember.id,
          metadata: {
            employeeID: entityID,
            previousRole: linkedMember.role,
            newRole: requestedAccessRole,
          },
          createdAt: acceptedAt,
        },
      ));
    }
    await env.DB.batch(statements);
  }
  const acceptedOperationJSON = JSON.stringify(operation);
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
    acceptedOperationJSON,
    String(operation.createdAt ?? acceptedAt),
    acceptedAt,
    revision,
  ).run();
  const changeSequence = await appendSynchronizationChange(
    env, identity.tenantID, id, identity.deviceID, revision,
    acceptedOperationJSON, acceptedAt,
  );
  await dispatchSynchronizationWake(
    env,
    identity.tenantID,
    identity.deviceID,
    changeSequence,
  );
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
  return json({ revision, changeSequence, duplicate: false }, 201);
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
  const changeSequence = await appendSynchronizationChange(
    env, identity.tenantID, operationID, identity.deviceID,
    revision, operationJSON, now,
  );
  await dispatchSynchronizationWake(
    env,
    identity.tenantID,
    identity.deviceID,
    changeSequence,
  );
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
    `SELECT tenant_sequence AS sequence, device_id AS deviceID,
            revision, payload_json AS payloadJSON, accepted_at AS acceptedAt
       FROM synchronization_change_log
      WHERE tenant_id = ?1 AND tenant_sequence > ?2
      ORDER BY tenant_sequence ASC
      LIMIT ?3`,
  ).bind(identity.tenantID, after, limit).all<{
    sequence: number;
    deviceID: string;
    revision: string;
    payloadJSON: string;
    acceptedAt: string;
  }>();
  const changes = result.results.map((row) => {
    const operation = JSON.parse(row.payloadJSON) as Record<string, unknown>;
    const createdAt = typeof operation.createdAt === "string"
      ? operation.createdAt
      : new Date().toISOString();
    const rawMetadata = operation.metadata;
    const metadata = rawMetadata && typeof rawMetadata === "object" &&
        !Array.isArray(rawMetadata)
      ? Object.fromEntries(Object.entries(rawMetadata).map(([key, value]) => {
        if (typeof value === "string") return [key, value];
        if (value == null) return [key, ""];
        if (typeof value === "object") return [key, JSON.stringify(value)];
        return [key, String(value)];
      }))
      : {};
    return {
      sequence: row.sequence,
      sourceDeviceID: row.deviceID,
      revision: row.revision,
      operation: {
        sequenceNumber: 0,
        status: "synchronized",
        retryAttempts: [],
        ...operation,
        metadata,
        updatedAt: row.acceptedAt,
      },
    };
  });
  const cursor = changes.length > 0
    ? changes[changes.length - 1].sequence
    : after;
  const serverCursor = await tenantSynchronizationCursor(env, identity.tenantID);
  return json({
    cursor,
    serverCursor,
    hasMore: cursor < serverCursor,
    changes,
  });
}

async function tenantSynchronizationCursor(
  env: Env,
  tenantID: string,
): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT COALESCE(MAX(tenant_sequence), 0) AS cursor
       FROM synchronization_change_log WHERE tenant_id = ?1`,
  ).bind(tenantID).first<{ cursor: number }>();
  return Number(row?.cursor ?? 0);
}

async function appendSynchronizationChange(
  env: Env,
  tenantID: string,
  operationID: string,
  deviceID: string,
  revision: string,
  payloadJSON: string,
  acceptedAt: string,
): Promise<number> {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const next = (await tenantSynchronizationCursor(env, tenantID)) + 1;
    try {
      await env.DB.prepare(
        `INSERT INTO synchronization_change_log
          (tenant_id, tenant_sequence, operation_id, device_id, revision,
           payload_json, accepted_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
      ).bind(
        tenantID, next, operationID, deviceID, revision, payloadJSON, acceptedAt,
      ).run();
      return next;
    } catch (error) {
      const existing = await env.DB.prepare(
        `SELECT tenant_sequence AS sequence
           FROM synchronization_change_log
          WHERE tenant_id = ?1 AND operation_id = ?2`,
      ).bind(tenantID, operationID).first<{ sequence: number }>();
      if (existing) return existing.sequence;
      if (attempt === 3) throw error;
    }
  }
  throw new Error("change_sequence_allocation_failed");
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64URLJSON(value: unknown): string {
  return base64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function apnsEnvironment(env: Env): "sandbox" | "production" {
  return env.APNS_ENVIRONMENT === "production" ? "production" : "sandbox";
}

async function apnsProviderToken(env: Env): Promise<string | null> {
  const keyID = env.APNS_KEY_ID?.trim();
  const teamID = env.APNS_TEAM_ID?.trim();
  const privateKey = env.APNS_PRIVATE_KEY?.replace(/\\n/g, "\n").trim();
  if (!keyID || !teamID || !privateKey) return null;
  const encodedKey = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(encodedKey), (character) =>
    character.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = base64URLJSON({ alg: "ES256", kid: keyID });
  const claims = base64URLJSON({ iss: teamID, iat: Math.floor(Date.now() / 1000) });
  const signingInput = `${header}.${claims}`;
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  ));
  return `${signingInput}.${base64URL(signature)}`;
}

async function registerSynchronizationPush(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const body = await request.json<{ token?: string; appBuild?: string }>();
  const token = String(body.token ?? "").trim().toLowerCase();
  const appBuild = String(body.appBuild ?? "").trim();
  if (!/^[0-9a-f]{32,200}$/.test(token) ||
      appBuild.length < 1 || appBuild.length > 32) {
    return json({ error: "invalid_push_registration" }, 400);
  }
  const environment = apnsEnvironment(env);
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM synchronization_push_registrations
        WHERE environment = ?1 AND token = ?2
          AND (tenant_id <> ?3 OR device_id <> ?4)`,
    ).bind(environment, token, identity.tenantID, identity.deviceID),
    env.DB.prepare(
      `INSERT INTO synchronization_push_registrations
        (tenant_id, device_id, token, environment, app_build,
         registered_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
       ON CONFLICT (tenant_id, device_id) DO UPDATE SET
         token = excluded.token,
         environment = excluded.environment,
         app_build = excluded.app_build,
         updated_at = excluded.updated_at,
         last_failure_code = NULL`,
    ).bind(identity.tenantID, identity.deviceID, token, environment, appBuild, now),
  ]);
  return json({ registered: true, environment, registeredAt: now });
}

async function unregisterSynchronizationPush(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  await env.DB.prepare(
    `DELETE FROM synchronization_push_registrations
      WHERE tenant_id = ?1 AND device_id = ?2`,
  ).bind(identity.tenantID, identity.deviceID).run();
  return json({ registered: false });
}

async function dispatchSynchronizationWake(
  env: Env,
  tenantID: string,
  sourceDeviceID: string,
  cursor: number,
): Promise<void> {
  const topic = env.APNS_TOPIC?.trim();
  const providerToken = await apnsProviderToken(env);
  if (!topic || !providerToken) return;
  const environment = apnsEnvironment(env);
  const registrations = await env.DB.prepare(
    `SELECT registrations.device_id AS deviceID,
            registrations.token
       FROM synchronization_push_registrations AS registrations
       JOIN devices
         ON devices.tenant_id = registrations.tenant_id
        AND devices.id = registrations.device_id
      WHERE registrations.tenant_id = ?1
        AND registrations.device_id <> ?2
        AND registrations.environment = ?3
        AND devices.revoked_at IS NULL`,
  ).bind(tenantID, sourceDeviceID, environment).all<{
    deviceID: string;
    token: string;
  }>();
  const host = environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  await Promise.all(registrations.results.map(async (registration) => {
    const deliveryID = crypto.randomUUID();
    const apnsRequestID = crypto.randomUUID();
    const requestedAt = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO synchronization_push_deliveries
        (id, tenant_id, device_id, source_device_id, cursor, environment,
         apns_request_id, requested_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
    ).bind(
      deliveryID,
      tenantID,
      registration.deviceID,
      sourceDeviceID,
      cursor,
      environment,
      apnsRequestID,
      requestedAt,
    ).run();
    const payload = JSON.stringify({
      aps: { "content-available": 1 },
      pfss: "syncWake",
      cursor,
      deliveryID,
    });
    try {
      const response = await fetch(`${host}/3/device/${registration.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${providerToken}`,
          "apns-topic": topic,
          "apns-push-type": "background",
          "apns-priority": "5",
          "apns-collapse-id": `pfss-sync-${tenantID}`,
          "apns-id": apnsRequestID,
          "content-type": "application/json",
        },
        body: payload,
      });
      const now = new Date().toISOString();
      if (response.ok) {
        await env.DB.batch([
          env.DB.prepare(
            `UPDATE synchronization_push_registrations
                SET last_notified_at = ?1, last_failure_code = NULL
              WHERE tenant_id = ?2 AND device_id = ?3`,
          ).bind(now, tenantID, registration.deviceID),
          env.DB.prepare(
            `UPDATE synchronization_push_deliveries
                SET accepted_at = ?1, apns_response_id = ?2,
                    apns_unique_id = ?3
              WHERE id = ?4`,
          ).bind(
            now,
            response.headers.get("apns-id"),
            response.headers.get("apns-unique-id"),
            deliveryID,
          ),
        ]);
        return;
      }
      let reason = `http_${response.status}`;
      try {
        const body = await response.json<{ reason?: string }>();
        if (body.reason) reason = body.reason;
      } catch { /* retain the status-only reason */ }
      if (response.status === 400 || response.status === 410) {
        await env.DB.prepare(
          `DELETE FROM synchronization_push_registrations
            WHERE tenant_id = ?1 AND device_id = ?2`,
        ).bind(tenantID, registration.deviceID).run();
      } else {
        await env.DB.prepare(
          `UPDATE synchronization_push_registrations
              SET last_failure_code = ?1, updated_at = ?2
            WHERE tenant_id = ?3 AND device_id = ?4`,
        ).bind(reason, now, tenantID, registration.deviceID).run();
      }
      await env.DB.prepare(
        `UPDATE synchronization_push_deliveries
            SET failure_code = ?1
          WHERE id = ?2`,
      ).bind(reason, deliveryID).run();
    } catch {
      const now = new Date().toISOString();
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE synchronization_push_registrations
              SET last_failure_code = 'transport_error', updated_at = ?1
            WHERE tenant_id = ?2 AND device_id = ?3`,
        ).bind(now, tenantID, registration.deviceID),
        env.DB.prepare(
          `UPDATE synchronization_push_deliveries
              SET failure_code = 'transport_error'
            WHERE id = ?1`,
        ).bind(deliveryID),
      ]);
    }
  }));
}

async function recordSynchronizationPushEvent(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const deliveryID = typeof body.deliveryID === "string"
    ? body.deliveryID.trim()
    : "";
  const event = typeof body.event === "string" ? body.event.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(deliveryID) || ![
    "received", "syncStarted", "syncCompleted", "syncFailed",
  ].includes(event)) {
    return json({ error: "invalid_push_event" }, 400);
  }
  const delivery = await env.DB.prepare(
    `SELECT id FROM synchronization_push_deliveries
      WHERE id = ?1 AND tenant_id = ?2 AND device_id = ?3`,
  ).bind(deliveryID, identity.tenantID, identity.deviceID).first();
  if (!delivery) return json({ error: "push_delivery_not_found" }, 404);

  const column = {
    received: "received_at",
    syncStarted: "sync_started_at",
    syncCompleted: "sync_completed_at",
    syncFailed: "sync_failed_at",
  }[event]!;
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE synchronization_push_deliveries
        SET ${column} = COALESCE(${column}, ?1),
            device_reported_cursor = COALESCE(?2, device_reported_cursor)
      WHERE id = ?3 AND tenant_id = ?4 AND device_id = ?5`,
  ).bind(
    now,
    Number.isSafeInteger(body.cursor) && (body.cursor as number) >= 0
      ? body.cursor as number
      : null,
    deliveryID,
    identity.tenantID,
    identity.deviceID,
  ).run();
  return json({ recorded: true, event, recordedAt: now });
}

type SynchronizationHealthLevel = "healthy" | "delayed" | "actionRequired";

function synchronizationHealthRank(level: SynchronizationHealthLevel): number {
  return level === "actionRequired" ? 2 : level === "delayed" ? 1 : 0;
}

function highestSynchronizationHealthLevel(
  levels: SynchronizationHealthLevel[],
): SynchronizationHealthLevel {
  return levels.reduce((highest, level) =>
    synchronizationHealthRank(level) > synchronizationHealthRank(highest)
      ? level
      : highest, "healthy" as SynchronizationHealthLevel);
}

function ageSeconds(value: string | null, nowMilliseconds: number): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp)
    ? Math.max(0, Math.floor((nowMilliseconds - timestamp) / 1000))
    : null;
}

async function reportSynchronizationDeviceHealth(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  let body: Record<string, unknown>;
  try { body = await request.json<Record<string, unknown>>(); } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const integer = (key: string, maximum = 1_000_000): number | null => {
    const value = body[key];
    return Number.isSafeInteger(value) && (value as number) >= 0 &&
        (value as number) <= maximum ? value as number : null;
  };
  const appBuild = typeof body.appBuild === "string"
    ? body.appBuild.trim().slice(0, 32) : "";
  const oldestQueuedAt = typeof body.oldestQueuedAt === "string" &&
      Number.isFinite(Date.parse(body.oldestQueuedAt))
    ? body.oldestQueuedAt : null;
  const values = ["queueCount", "failedCount", "waitingRetryCount",
    "retryAttempts24h", "blockedDependencyCount", "conflictedCount",
    "quarantinedCount"].map((key) => integer(key));
  if (!appBuild || values.some((value) => value == null)) {
    return json({ error: "invalid_device_health_report" }, 400);
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO synchronization_device_health_reports
      (tenant_id, device_id, app_build, queue_count, oldest_queued_at,
       failed_count, waiting_retry_count, retry_attempts_24h,
       blocked_dependency_count, conflicted_count, quarantined_count,
       reported_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
     ON CONFLICT (tenant_id, device_id) DO UPDATE SET
       app_build = excluded.app_build,
       queue_count = excluded.queue_count,
       oldest_queued_at = excluded.oldest_queued_at,
       failed_count = excluded.failed_count,
       waiting_retry_count = excluded.waiting_retry_count,
       retry_attempts_24h = excluded.retry_attempts_24h,
       blocked_dependency_count = excluded.blocked_dependency_count,
       conflicted_count = excluded.conflicted_count,
       quarantined_count = excluded.quarantined_count,
       reported_at = excluded.reported_at`,
  ).bind(
    identity.tenantID, identity.deviceID, appBuild, values[0], oldestQueuedAt,
    values[1], values[2], values[3], values[4], values[5], values[6], now,
  ).run();
  await evaluateSynchronizationHealthAlerts(env, identity.tenantID);
  return json({ recorded: true, reportedAt: now });
}

interface SynchronizationAlertCandidate {
  fingerprint: string;
  kind: "tenantDivergence" | "stuckDependencies" | "excessiveRetries" |
    "highImpactConflict";
  severity: "warning" | "critical";
  deviceID: string | null;
  title: string;
  detail: string;
  recommendation: string;
  observedValue: number;
  thresholdValue: number;
}

async function evaluateSynchronizationHealthAlerts(
  env: Env,
  tenantID: string,
): Promise<void> {
  const now = new Date();
  const nowISO = now.toISOString();
  const [cursorResult, deviceResult, reportResult, conflictResult] =
    await env.DB.batch([
      env.DB.prepare(
        `SELECT COALESCE(MAX(tenant_sequence), 0) AS serverCursor
           FROM synchronization_change_log WHERE tenant_id = ?1`,
      ).bind(tenantID),
      env.DB.prepare(
        `SELECT devices.id, devices.display_name AS displayName,
                COALESCE(cursors.acknowledged_sequence, 0) AS acknowledgedCursor,
                cursors.updated_at AS cursorUpdatedAt
           FROM devices
           JOIN tenant_members AS members
             ON members.tenant_id = devices.tenant_id
            AND members.id = devices.member_id
           LEFT JOIN synchronization_device_cursors AS cursors
             ON cursors.tenant_id = devices.tenant_id
            AND cursors.device_id = devices.id
          WHERE devices.tenant_id = ?1 AND devices.revoked_at IS NULL
            AND members.status = 'active'`,
      ).bind(tenantID),
      env.DB.prepare(
        `SELECT reports.device_id AS deviceID, devices.display_name AS displayName,
                reports.oldest_queued_at AS oldestQueuedAt,
                reports.retry_attempts_24h AS retryAttempts24h,
                reports.blocked_dependency_count AS blockedDependencyCount
           FROM synchronization_device_health_reports AS reports
           JOIN devices ON devices.tenant_id = reports.tenant_id
             AND devices.id = reports.device_id
          WHERE reports.tenant_id = ?1`,
      ).bind(tenantID),
      env.DB.prepare(
        `SELECT id, entity_type AS entityType, affected_fields_json AS fieldsJSON,
                detected_at AS detectedAt
           FROM synchronization_conflicts
          WHERE tenant_id = ?1 AND status = 'unresolved'`,
      ).bind(tenantID),
    ]);
  const serverCursor = Number(
    (cursorResult.results[0] as { serverCursor?: number } | undefined)
      ?.serverCursor ?? 0,
  );
  const candidates: SynchronizationAlertCandidate[] = [];
  for (const row of deviceResult.results as Array<Record<string, unknown>>) {
    const deviceID = String(row.id);
    const displayName = String(row.displayName);
    const behindBy = Math.max(
      0,
      serverCursor - Number(row.acknowledgedCursor ?? 0),
    );
    const cursorAge = ageSeconds(row.cursorUpdatedAt as string | null, now.getTime());
    if (behindBy >= 50 || (behindBy > 0 && (cursorAge ?? 0) >= 1800)) {
      candidates.push({
        fingerprint: `tenantDivergence:${deviceID}`,
        kind: "tenantDivergence",
        severity: behindBy >= 100 ? "critical" : "warning",
        deviceID,
        title: `${displayName} is behind`,
        detail: `${displayName} is ${behindBy} company changes behind.`,
        recommendation: "Connect the device to the internet, open PFSS, and check Sync Status.",
        observedValue: behindBy,
        thresholdValue: 50,
      });
    }
  }
  for (const row of reportResult.results as Array<Record<string, unknown>>) {
    const deviceID = String(row.deviceID);
    const displayName = String(row.displayName);
    const blocked = Number(row.blockedDependencyCount ?? 0);
    const oldestAge = ageSeconds(row.oldestQueuedAt as string | null, now.getTime());
    if (blocked > 0 && (oldestAge ?? 0) >= 900) {
      candidates.push({
        fingerprint: `stuckDependencies:${deviceID}`,
        kind: "stuckDependencies",
        severity: (oldestAge ?? 0) >= 3600 ? "critical" : "warning",
        deviceID,
        title: `${displayName} has blocked work`,
        detail: `${blocked} queued change${blocked === 1 ? " is" : "s are"} waiting behind another unresolved change.`,
        recommendation: "Open Sync Status on the device and resolve the first failed or conflicting change.",
        observedValue: blocked,
        thresholdValue: 1,
      });
    }
    const retries = Number(row.retryAttempts24h ?? 0);
    if (retries >= 10) {
      candidates.push({
        fingerprint: `excessiveRetries:${deviceID}`,
        kind: "excessiveRetries",
        severity: retries >= 25 ? "critical" : "warning",
        deviceID,
        title: `${displayName} is retrying repeatedly`,
        detail: `${displayName} made ${retries} synchronization retry attempts during the last 24 hours.`,
        recommendation: "Check the device connection and Sync Status. Send diagnostics if retries continue.",
        observedValue: retries,
        thresholdValue: 10,
      });
    }
  }
  for (const row of conflictResult.results as Array<Record<string, unknown>>) {
    let fields: string[] = ["record"];
    try {
      const parsed = JSON.parse(String(row.fieldsJSON ?? "[]"));
      if (Array.isArray(parsed) && parsed.length) fields = parsed.map(String);
    } catch { /* retain record */ }
    const impact = conflictOperationalImpact(String(row.entityType), fields);
    if (!impact.includes("shared company information")) {
      const age = ageSeconds(String(row.detectedAt), now.getTime()) ?? 0;
      candidates.push({
        fingerprint: `highImpactConflict:${String(row.id)}`,
        kind: "highImpactConflict",
        severity: age >= 3600 ? "critical" : "warning",
        deviceID: null,
        title: "An important record decision is waiting",
        detail: impact,
        recommendation: "An Owner or Manager should open Conflict Review and choose the correct version.",
        observedValue: age,
        thresholdValue: 0,
      });
    }
  }

  for (const alert of candidates) {
    await env.DB.prepare(
      `INSERT INTO synchronization_health_alerts
        (id, tenant_id, device_id, fingerprint, kind, severity, status,
         title, detail, recommendation, observed_value, threshold_value,
         opened_at, last_observed_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'active', ?7, ?8, ?9, ?10, ?11, ?12, ?12)
       ON CONFLICT (tenant_id, fingerprint) DO UPDATE SET
         device_id = excluded.device_id, kind = excluded.kind,
         severity = excluded.severity, status = 'active',
         title = excluded.title, detail = excluded.detail,
         recommendation = excluded.recommendation,
         observed_value = excluded.observed_value,
         threshold_value = excluded.threshold_value,
         opened_at = CASE WHEN synchronization_health_alerts.status = 'resolved'
                          THEN excluded.opened_at
                          ELSE synchronization_health_alerts.opened_at END,
         last_observed_at = excluded.last_observed_at, resolved_at = NULL`,
    ).bind(
      crypto.randomUUID(), tenantID, alert.deviceID, alert.fingerprint,
      alert.kind, alert.severity, alert.title, alert.detail,
      alert.recommendation, alert.observedValue, alert.thresholdValue, nowISO,
    ).run();
  }
  const fingerprints = new Set(candidates.map((candidate) => candidate.fingerprint));
  const active = await env.DB.prepare(
    `SELECT id, fingerprint FROM synchronization_health_alerts
      WHERE tenant_id = ?1 AND status = 'active'`,
  ).bind(tenantID).all<{ id: string; fingerprint: string }>();
  for (const alert of active.results) {
    if (fingerprints.has(alert.fingerprint)) continue;
    await env.DB.prepare(
      `UPDATE synchronization_health_alerts
          SET status = 'resolved', resolved_at = ?1, last_observed_at = ?1
        WHERE tenant_id = ?2 AND id = ?3 AND status = 'active'`,
    ).bind(nowISO, tenantID, alert.id).run();
  }
}

async function evaluateAllSynchronizationHealthAlerts(env: Env): Promise<void> {
  const tenants = await env.DB.prepare(
    `SELECT id FROM tenants WHERE status = 'active'`,
  ).all<{ id: string }>();
  for (const tenant of tenants.results) {
    await evaluateSynchronizationHealthAlerts(env, tenant.id);
  }
}

async function synchronizationHealth(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  await evaluateSynchronizationHealthAlerts(env, identity.tenantID);
  const now = new Date();
  const nowMilliseconds = now.getTime();
  const recentCutoff = new Date(nowMilliseconds - 24 * 60 * 60 * 1000)
    .toISOString();
  const trendCutoff = new Date(nowMilliseconds - 7 * 24 * 60 * 60 * 1000)
    .toISOString();

  const [cursorResult, deviceResult, conflictResult, quarantineResult,
    recentConflictResult, recentQuarantineResult, pushResult, alertResult] =
    await env.DB.batch([
    env.DB.prepare(
      `SELECT COALESCE(MAX(tenant_sequence), 0) AS serverCursor
         FROM synchronization_change_log WHERE tenant_id = ?1`,
    ).bind(identity.tenantID),
    env.DB.prepare(
      `SELECT devices.id, devices.display_name AS displayName,
              devices.last_seen_at AS lastSeenAt, members.role,
              COALESCE(cursors.acknowledged_sequence, 0) AS acknowledgedCursor,
              cursors.updated_at AS cursorUpdatedAt,
              registrations.app_build AS appBuild,
              registrations.last_failure_code AS registrationFailure,
              deliveries.requested_at AS pushRequestedAt,
              deliveries.accepted_at AS pushAcceptedAt,
              deliveries.received_at AS pushReceivedAt,
              deliveries.sync_completed_at AS pushCompletedAt,
              deliveries.sync_failed_at AS pushFailedAt,
              deliveries.failure_code AS pushFailure
         FROM devices
         JOIN tenant_members AS members
           ON members.tenant_id = devices.tenant_id
          AND members.id = devices.member_id
         LEFT JOIN synchronization_device_cursors AS cursors
           ON cursors.tenant_id = devices.tenant_id
          AND cursors.device_id = devices.id
         LEFT JOIN synchronization_push_registrations AS registrations
           ON registrations.tenant_id = devices.tenant_id
          AND registrations.device_id = devices.id
         LEFT JOIN synchronization_push_deliveries AS deliveries
           ON deliveries.id = (
             SELECT latest.id FROM synchronization_push_deliveries AS latest
              WHERE latest.tenant_id = devices.tenant_id
                AND latest.device_id = devices.id
              ORDER BY latest.requested_at DESC LIMIT 1
           )
        WHERE devices.tenant_id = ?1
          AND devices.revoked_at IS NULL
          AND members.status = 'active'
        ORDER BY devices.display_name ASC`,
    ).bind(identity.tenantID),
    env.DB.prepare(
      `SELECT id, entity_type AS entityType, affected_fields_json AS fieldsJSON,
              detected_at AS detectedAt
         FROM synchronization_conflicts
        WHERE tenant_id = ?1 AND status = 'unresolved'
        ORDER BY detected_at ASC`,
    ).bind(identity.tenantID),
    env.DB.prepare(
      `SELECT id, entity_type AS entityType, operation_json AS operationJSON,
              failure_json AS failureJSON, detected_at AS detectedAt
         FROM synchronization_quarantines
        WHERE tenant_id = ?1 AND status = 'unresolved'
        ORDER BY detected_at ASC`,
    ).bind(identity.tenantID),
    env.DB.prepare(
      `SELECT entity_type AS entityType, affected_fields_json AS fieldsJSON
         FROM synchronization_conflicts
        WHERE tenant_id = ?1 AND detected_at >= ?2`,
    ).bind(identity.tenantID, trendCutoff),
    env.DB.prepare(
      `SELECT entity_type AS entityType, operation_json AS operationJSON,
              failure_json AS failureJSON
         FROM synchronization_quarantines
        WHERE tenant_id = ?1 AND detected_at >= ?2`,
    ).bind(identity.tenantID, trendCutoff),
    env.DB.prepare(
      `SELECT COUNT(*) AS sent,
              SUM(CASE WHEN accepted_at IS NOT NULL THEN 1 ELSE 0 END) AS accepted,
              SUM(CASE WHEN received_at IS NOT NULL THEN 1 ELSE 0 END) AS received,
              SUM(CASE WHEN sync_completed_at IS NOT NULL THEN 1 ELSE 0 END) AS completed,
              SUM(CASE WHEN failure_code IS NOT NULL OR sync_failed_at IS NOT NULL
                       THEN 1 ELSE 0 END) AS failed,
              SUM(CASE WHEN accepted_at IS NOT NULL AND received_at IS NULL
                         AND requested_at < ?2 THEN 1 ELSE 0 END) AS deferred
         FROM synchronization_push_deliveries
        WHERE tenant_id = ?1 AND requested_at >= ?3`,
    ).bind(
      identity.tenantID,
      new Date(nowMilliseconds - 2 * 60 * 1000).toISOString(),
      recentCutoff,
    ),
    env.DB.prepare(
      `SELECT id, kind, severity, title, detail, recommendation,
              device_id AS deviceID, observed_value AS observedValue,
              threshold_value AS thresholdValue, opened_at AS openedAt,
              last_observed_at AS lastObservedAt
         FROM synchronization_health_alerts
        WHERE tenant_id = ?1 AND status = 'active'
        ORDER BY CASE severity WHEN 'critical' THEN 0 ELSE 1 END,
                 opened_at ASC`,
    ).bind(identity.tenantID),
  ]);

  const serverCursor = Number(
    (cursorResult.results[0] as { serverCursor?: number } | undefined)
      ?.serverCursor ?? 0,
  );
  const devices = (deviceResult.results as Array<Record<string, unknown>>).map(
    (row) => {
      const acknowledgedCursor = Number(row.acknowledgedCursor ?? 0);
      const behindBy = Math.max(0, serverCursor - acknowledgedCursor);
      const cursorAgeSeconds = ageSeconds(
        row.cursorUpdatedAt as string | null,
        nowMilliseconds,
      );
      const pushAgeSeconds = ageSeconds(
        row.pushRequestedAt as string | null,
        nowMilliseconds,
      );
      const reasons: string[] = [];
      let status: SynchronizationHealthLevel = "healthy";
      if (row.registrationFailure || row.pushFailure || row.pushFailedAt) {
        status = "actionRequired";
        reasons.push("The latest background delivery or synchronization failed.");
      }
      if (behindBy >= 50 || (behindBy > 0 && (cursorAgeSeconds ?? 0) >= 1800)) {
        status = "actionRequired";
        reasons.push(`This device is ${behindBy} company changes behind.`);
      } else if (behindBy > 0) {
        status = highestSynchronizationHealthLevel([status, "delayed"]);
        reasons.push(`This device is ${behindBy} company change${behindBy === 1 ? "" : "s"} behind.`);
      }
      if (row.pushAcceptedAt && !row.pushReceivedAt &&
          pushAgeSeconds != null && pushAgeSeconds >= 120) {
        status = highestSynchronizationHealthLevel([status, "delayed"]);
        reasons.push("Apple accepted the latest signal but the device has not reported receipt.");
      }
      if (reasons.length === 0) reasons.push("This device matches the company change feed.");
      return {
        deviceID: row.id,
        displayName: row.displayName,
        role: row.role,
        status,
        reasons,
        acknowledgedCursor,
        serverCursor,
        behindBy,
        cursorAgeSeconds,
        lastSeenAt: row.lastSeenAt,
        cursorUpdatedAt: row.cursorUpdatedAt,
        appBuild: row.appBuild,
        latestPush: row.pushRequestedAt ? {
          requestedAt: row.pushRequestedAt,
          acceptedAt: row.pushAcceptedAt,
          receivedAt: row.pushReceivedAt,
          completedAt: row.pushCompletedAt,
          failedAt: row.pushFailedAt,
          failureCode: row.pushFailure ?? row.registrationFailure,
        } : null,
      };
    },
  );

  const unresolvedConflicts = conflictResult.results as Array<Record<string, unknown>>;
  const unresolvedQuarantines = quarantineResult.results as Array<Record<string, unknown>>;
  const oldestConflictAgeSeconds = ageSeconds(
    unresolvedConflicts[0]?.detectedAt as string | null ?? null,
    nowMilliseconds,
  );
  const oldestQuarantineAgeSeconds = ageSeconds(
    unresolvedQuarantines[0]?.detectedAt as string | null ?? null,
    nowMilliseconds,
  );
  const entityCounts = new Map<string, number>();
  const fieldCounts = new Map<string, number>();
  const failureCounts = new Map<string, number>();
  const countFields = (entityType: string, fields: string[]) => {
    entityCounts.set(entityType, (entityCounts.get(entityType) ?? 0) + 1);
    for (const field of fields) {
      fieldCounts.set(field, (fieldCounts.get(field) ?? 0) + 1);
    }
  };
  for (const row of recentConflictResult.results as Array<Record<string, unknown>>) {
    let fields: string[] = ["record"];
    try {
      const decoded = JSON.parse(String(row.fieldsJSON ?? "[]"));
      if (Array.isArray(decoded) && decoded.length > 0) fields = decoded.map(String);
    } catch { /* retain record-level classification */ }
    countFields(String(row.entityType ?? "unknown"), fields);
  }
  for (const row of recentQuarantineResult.results as Array<Record<string, unknown>>) {
    let operation: Record<string, unknown> = {};
    let reason = "unknown";
    try { operation = JSON.parse(String(row.operationJSON ?? "{}")); } catch { /* empty */ }
    try {
      const failure = JSON.parse(String(row.failureJSON ?? "{}"));
      reason = String(failure.reason ?? "unknown");
    } catch { /* retain unknown */ }
    const fields = quarantineReviewDetails(operation, null).affectedFields;
    countFields(String(row.entityType ?? "unknown"), fields);
    failureCounts.set(reason, (failureCounts.get(reason) ?? 0) + 1);
  }
  const push = (pushResult.results[0] ?? {}) as Record<string, unknown>;
  const pushSummary = {
    sent: Number(push.sent ?? 0),
    accepted: Number(push.accepted ?? 0),
    received: Number(push.received ?? 0),
    completed: Number(push.completed ?? 0),
    failed: Number(push.failed ?? 0),
    deferred: Number(push.deferred ?? 0),
  };
  const queueLevel: SynchronizationHealthLevel =
    unresolvedConflicts.length > 0 || unresolvedQuarantines.length > 0
      ? "actionRequired"
      : "healthy";
  const pushLevel: SynchronizationHealthLevel = pushSummary.failed > 0
    ? "actionRequired"
    : pushSummary.deferred > 0 ? "delayed" : "healthy";
  const status = highestSynchronizationHealthLevel([
    queueLevel,
    pushLevel,
    ...devices.map((device) => device.status),
  ]);
  return json({
    generatedAt: now.toISOString(),
    status,
    statusLabel: status === "healthy" ? "Healthy"
      : status === "delayed" ? "Delayed" : "Action Required",
    serverCursor,
    summary: {
      activeDevices: devices.length,
      healthyDevices: devices.filter((device) => device.status === "healthy").length,
      delayedDevices: devices.filter((device) => device.status === "delayed").length,
      actionRequiredDevices: devices.filter((device) =>
        device.status === "actionRequired").length,
      unresolvedConflicts: unresolvedConflicts.length,
      quarantinedChanges: unresolvedQuarantines.length,
      oldestConflictAgeSeconds,
      oldestQuarantineAgeSeconds,
      pushLast24Hours: pushSummary,
      activeAlerts: alertResult.results.length,
      criticalAlerts: (alertResult.results as Array<Record<string, unknown>>)
        .filter((alert) => alert.severity === "critical").length,
    },
    alerts: alertResult.results,
    devices,
    trendsLast7Days: {
      byEntity: [...entityCounts.entries()].map(([entityType, count]) => ({
        entityType, count,
      })).sort((left, right) => right.count - left.count),
      byField: [...fieldCounts.entries()].map(([field, count]) => ({ field, count }))
        .sort((left, right) => right.count - left.count),
      quarantineReasons: [...failureCounts.entries()].map(([reason, count]) => ({
        reason, count,
      })).sort((left, right) => right.count - left.count),
    },
    thresholds: {
      delayedBehindChanges: 1,
      actionRequiredBehindChanges: 50,
      actionRequiredCursorAgeSeconds: 1800,
      deferredPushAgeSeconds: 120,
    },
  });
}

async function acknowledgeSynchronizationCursor(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const body = await request.json<{ cursor?: number }>();
  const requested = Number(body.cursor ?? -1);
  if (!Number.isInteger(requested) || requested < 0) {
    return json({ error: "invalid_synchronization_cursor" }, 400);
  }
  const serverCursor = await tenantSynchronizationCursor(env, identity.tenantID);
  const cursor = Math.min(requested, serverCursor);
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO synchronization_device_cursors
      (tenant_id, device_id, acknowledged_sequence, updated_at)
     VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT (tenant_id, device_id) DO UPDATE SET
       acknowledged_sequence = MAX(acknowledged_sequence, excluded.acknowledged_sequence),
       updated_at = excluded.updated_at`,
  ).bind(identity.tenantID, identity.deviceID, cursor, now).run();
  return json({ cursor, serverCursor, acknowledgedAt: now });
}

interface MileageTripUpload {
  id?: string;
  originatingDeviceID?: string;
  classification?: string;
  startedAt?: string;
  updatedAt?: string;
  payload?: unknown;
}

interface MileageTripDeletion {
  id?: string;
  deletedAt?: string;
}

function validMileageTimestamp(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

async function synchronizeMileageTrips(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const body = await request.json<{
    cursor?: number;
    trips?: MileageTripUpload[];
    deletions?: MileageTripDeletion[];
  }>();
  const cursor = Number.isInteger(body.cursor) && (body.cursor ?? 0) >= 0
    ? body.cursor ?? 0
    : 0;
  const trips = Array.isArray(body.trips) ? body.trips : [];
  const deletions = Array.isArray(body.deletions) ? body.deletions : [];
  if (trips.length > 100 || deletions.length > 100) {
    return json({ error: "mileage_sync_batch_too_large" }, 413);
  }

  for (const upload of trips) {
    if (!upload.id || !validUUID(upload.id) ||
        !upload.originatingDeviceID || !validUUID(upload.originatingDeviceID) ||
        !["unclassified", "business", "personal"].includes(
          upload.classification ?? "",
        ) || !validMileageTimestamp(upload.startedAt) ||
        !validMileageTimestamp(upload.updatedAt) || upload.payload === undefined) {
      return json({ error: "invalid_mileage_trip" }, 400);
    }
    const payloadJSON = JSON.stringify(upload.payload);
    if (payloadJSON.length > 1_500_000) {
      return json({ error: "mileage_trip_too_large" }, 413);
    }
    const existing = await env.DB.prepare(
      `SELECT updated_at AS updatedAt, deleted_at AS deletedAt
         FROM mileage_trips
        WHERE tenant_id = ?1 AND member_id = ?2 AND id = ?3`,
    ).bind(identity.tenantID, identity.memberID, upload.id).first<{
      updatedAt: string;
      deletedAt: string | null;
    }>();
    const serverChangeAt = existing?.deletedAt ?? existing?.updatedAt;
    if (serverChangeAt && Date.parse(serverChangeAt) >= Date.parse(upload.updatedAt)) {
      continue;
    }
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO mileage_trips
          (id, tenant_id, member_id, originating_device_id, classification,
           started_at, updated_at, payload_json, deleted_at, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, NULL, ?9)
         ON CONFLICT(tenant_id, member_id, id) DO UPDATE SET
           originating_device_id = excluded.originating_device_id,
           classification = excluded.classification,
           started_at = excluded.started_at,
           updated_at = excluded.updated_at,
           payload_json = excluded.payload_json,
           deleted_at = NULL`,
      ).bind(upload.id, identity.tenantID, identity.memberID,
        upload.originatingDeviceID, upload.classification, upload.startedAt,
        upload.updatedAt, payloadJSON, now),
      env.DB.prepare(
        `INSERT INTO mileage_trip_changes
          (tenant_id, member_id, trip_id, change_type, payload_json, changed_at)
         VALUES (?1, ?2, ?3, 'upsert', ?4, ?5)`,
      ).bind(identity.tenantID, identity.memberID, upload.id, payloadJSON,
        upload.updatedAt),
    ]);
  }

  for (const deletion of deletions) {
    if (!deletion.id || !validUUID(deletion.id) ||
        !validMileageTimestamp(deletion.deletedAt)) {
      return json({ error: "invalid_mileage_trip_deletion" }, 400);
    }
    const existing = await env.DB.prepare(
      `SELECT updated_at AS updatedAt, deleted_at AS deletedAt
         FROM mileage_trips
        WHERE tenant_id = ?1 AND member_id = ?2 AND id = ?3`,
    ).bind(identity.tenantID, identity.memberID, deletion.id).first<{
      updatedAt: string;
      deletedAt: string | null;
    }>();
    const serverChangeAt = existing?.deletedAt ?? existing?.updatedAt;
    if (serverChangeAt && Date.parse(serverChangeAt) >= Date.parse(deletion.deletedAt)) {
      continue;
    }
    const placeholderPayload = JSON.stringify({ id: deletion.id });
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO mileage_trips
          (id, tenant_id, member_id, originating_device_id, classification,
           started_at, updated_at, payload_json, deleted_at, created_at)
         VALUES (?1, ?2, ?3, ?4, 'unclassified', ?5, ?5, NULL, ?5, ?5)
         ON CONFLICT(tenant_id, member_id, id) DO UPDATE SET
           updated_at = excluded.updated_at, payload_json = NULL,
           deleted_at = excluded.deleted_at`,
      ).bind(deletion.id, identity.tenantID, identity.memberID,
        identity.deviceID, deletion.deletedAt),
      env.DB.prepare(
        `INSERT INTO mileage_trip_changes
          (tenant_id, member_id, trip_id, change_type, payload_json, changed_at)
         VALUES (?1, ?2, ?3, 'delete', ?4, ?5)`,
      ).bind(identity.tenantID, identity.memberID, deletion.id,
        placeholderPayload, deletion.deletedAt),
    ]);
  }

  const result = await env.DB.prepare(
    `SELECT sequence, trip_id AS tripID, change_type AS changeType,
            payload_json AS payloadJSON, changed_at AS changedAt
       FROM mileage_trip_changes
      WHERE tenant_id = ?1 AND member_id = ?2 AND sequence > ?3
      ORDER BY sequence ASC
      LIMIT 200`,
  ).bind(identity.tenantID, identity.memberID, cursor).all<{
    sequence: number;
    tripID: string;
    changeType: "upsert" | "delete";
    payloadJSON: string | null;
    changedAt: string;
  }>();
  const changes = result.results.map((row) => ({
    sequence: row.sequence,
    tripID: row.tripID,
    type: row.changeType,
    payload: row.changeType === "upsert" && row.payloadJSON
      ? JSON.parse(row.payloadJSON)
      : undefined,
    changedAt: row.changedAt,
  }));
  return json({
    cursor: changes.at(-1)?.sequence ?? cursor,
    hasMore: changes.length === 200,
    changes,
  });
}

async function mileageBusinessSummary(
  url: URL,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const from = url.searchParams.get("from");
  const through = url.searchParams.get("through");
  if (!validMileageTimestamp(from) || !validMileageTimestamp(through)) {
    return json({ error: "invalid_date_range" }, 400);
  }
  const rows = await env.DB.prepare(
    `SELECT member_id AS memberID, payload_json AS payloadJSON
       FROM mileage_trips
      WHERE tenant_id = ?1 AND classification = 'business'
        AND deleted_at IS NULL AND started_at >= ?2 AND started_at <= ?3`,
  ).bind(identity.tenantID, from, through).all<{
    memberID: string;
    payloadJSON: string;
  }>();
  const summaries = rows.results.map((row) => {
    const payload = JSON.parse(row.payloadJSON) as Record<string, unknown>;
    return {
      memberID: row.memberID,
      tripID: payload.id,
      startedAt: payload.startedAt,
      distanceMeters: payload.distanceMeters,
      businessPurpose: payload.businessPurpose,
    };
  });
  return json({ trips: summaries });
}

type JobDeclineReviewRow = {
  id: string;
  assignmentID: string;
  jobID: string;
  jobNumber: string;
  customerNumber: string;
  technicianMemberID: string;
  technicianEmployeeID: string;
  originatingDeviceID: string;
  reason: string;
  status: "pending" | "resolved";
  resolutionAction: string | null;
  resolutionNote: string | null;
  resolvedByMemberID: string | null;
  createdAt: string;
  updatedAt: string;
  resolvedAt: string | null;
};

function jobDeclineReviewJSON(row: JobDeclineReviewRow): Record<string, unknown> {
  return {
    id: row.id,
    assignmentID: row.assignmentID,
    jobID: row.jobID,
    jobNumber: row.jobNumber,
    customerNumber: row.customerNumber,
    technicianMemberID: row.technicianMemberID,
    technicianEmployeeID: row.technicianEmployeeID,
    originatingDeviceID: row.originatingDeviceID,
    reason: row.reason,
    status: row.status,
    resolutionAction: row.resolutionAction,
    resolutionNote: row.resolutionNote,
    resolvedByMemberID: row.resolvedByMemberID,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    resolvedAt: row.resolvedAt,
  };
}

const jobDeclineReviewSelection =
  `SELECT id, assignment_id AS assignmentID, job_id AS jobID,
          job_number AS jobNumber, customer_number AS customerNumber,
          technician_member_id AS technicianMemberID,
          technician_employee_id AS technicianEmployeeID,
          originating_device_id AS originatingDeviceID,
          reason, status, resolution_action AS resolutionAction,
          resolution_note AS resolutionNote,
          resolved_by_member_id AS resolvedByMemberID,
          created_at AS createdAt, updated_at AS updatedAt,
          resolved_at AS resolvedAt
     FROM job_decline_reviews`;

async function synchronizedAssignment(
  env: Env,
  tenantID: string,
  assignmentID: string,
): Promise<Record<string, unknown> | null> {
  const row = await env.DB.prepare(
    `SELECT operation_json AS operationJSON
       FROM synchronized_records
      WHERE tenant_id = ?1 AND entity_type = 'assignment'
        AND entity_id = ?2`,
  ).bind(tenantID, assignmentID.toLowerCase()).first<{ operationJSON: string }>();
  if (!row) return null;
  try {
    const operation = JSON.parse(row.operationJSON) as {
      payload?: { body?: string };
    };
    const mutation = JSON.parse(atob(operation.payload?.body ?? "")) as {
      recordData?: string;
    };
    return JSON.parse(atob(mutation.recordData ?? "")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function submitJobDecline(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!identity.employeeID) return json({ error: "employee_profile_required" }, 403);
  const body = await request.json<{
    assignmentID?: string;
    jobID?: string;
    reason?: string;
    idempotencyKey?: string;
  }>();
  const assignmentID = body.assignmentID?.trim().toLowerCase() ?? "";
  const jobID = body.jobID?.trim().toLowerCase() ?? "";
  const reason = body.reason?.trim() ?? "";
  const idempotencyKey = body.idempotencyKey?.trim() ?? "";
  if (!assignmentID || !jobID || !idempotencyKey || reason.length < 3) {
    return json({ error: "invalid_job_decline" }, 400);
  }
  if (reason.length > 1000) return json({ error: "job_decline_reason_too_long" }, 400);

  const existing = await env.DB.prepare(
    `${jobDeclineReviewSelection}
      WHERE tenant_id = ?1 AND idempotency_key = ?2`,
  ).bind(identity.tenantID, idempotencyKey).first<JobDeclineReviewRow>();
  if (existing) return json({ review: jobDeclineReviewJSON(existing), duplicate: true });

  const assignment = await synchronizedAssignment(env, identity.tenantID, assignmentID);
  if (!assignment) return json({ error: "assignment_not_found" }, 404);
  if (String(assignment.jobID ?? "").toLowerCase() !== jobID) {
    return json({ error: "assignment_job_mismatch" }, 409);
  }
  if (!["Scheduled", "Dispatched"].includes(String(assignment.status ?? ""))) {
    return json({ error: "assignment_already_in_progress" }, 409);
  }
  const crew = assignment.crew as { members?: Array<Record<string, unknown>> } | undefined;
  const isPrimary = (crew?.members ?? []).some((member) =>
    String(member.employeeID ?? "").toLowerCase() === identity.employeeID!.toLowerCase() &&
    String(member.role ?? "") === "Primary Technician" &&
    (member.removedDate == null),
  );
  if (!isPrimary) return json({ error: "assignment_not_owned_by_technician" }, 403);

  const pending = await env.DB.prepare(
    `${jobDeclineReviewSelection}
      WHERE tenant_id = ?1 AND assignment_id = ?2 AND status = 'pending'`,
  ).bind(identity.tenantID, assignmentID).first<JobDeclineReviewRow>();
  if (pending) return json({ review: jobDeclineReviewJSON(pending), duplicate: true });

  const now = new Date().toISOString();
  const id = crypto.randomUUID();
  const eventPayload = { reason, assignmentID, jobID };
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO job_decline_reviews
        (id, tenant_id, assignment_id, job_id, job_number, customer_number,
         technician_member_id, technician_employee_id, originating_device_id,
         idempotency_key, reason, status, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 'pending', ?12, ?12)`,
    ).bind(
      id, identity.tenantID, assignmentID, jobID,
      String(assignment.jobNumber ?? ""), String(assignment.customerNumber ?? ""),
      identity.memberID, identity.employeeID, identity.deviceID,
      idempotencyKey, reason, now,
    ),
    env.DB.prepare(
      `INSERT INTO job_decline_review_events
        (id, review_id, tenant_id, event_type, actor_member_id,
         actor_device_id, payload_json, created_at)
       VALUES (?1, ?2, ?3, 'submitted', ?4, ?5, ?6, ?7)`,
    ).bind(crypto.randomUUID(), id, identity.tenantID, identity.memberID,
      identity.deviceID, JSON.stringify(eventPayload), now),
    accessAuditStatement(env, identity.tenantID, "job.decline_submitted", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      metadata: { reviewID: id, assignmentID, jobID },
      createdAt: now,
    }),
  ]);
  const created = await env.DB.prepare(
    `${jobDeclineReviewSelection} WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, id).first<JobDeclineReviewRow>();
  return json({ review: jobDeclineReviewJSON(created!), duplicate: false }, 201);
}

async function listJobDeclines(
  url: URL,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const requestedStatus = url.searchParams.get("status") ?? "pending";
  if (requestedStatus !== "pending" && requestedStatus !== "resolved") {
    return json({ error: "invalid_job_decline_status" }, 400);
  }
  const manager = canManageMembers(identity);
  const result = manager
    ? await env.DB.prepare(
        `${jobDeclineReviewSelection}
          WHERE tenant_id = ?1 AND status = ?2 ORDER BY created_at ASC`,
      ).bind(identity.tenantID, requestedStatus).all<JobDeclineReviewRow>()
    : await env.DB.prepare(
        `${jobDeclineReviewSelection}
          WHERE tenant_id = ?1 AND technician_member_id = ?2 AND status = ?3
          ORDER BY created_at ASC`,
      ).bind(identity.tenantID, identity.memberID, requestedStatus).all<JobDeclineReviewRow>();
  return json({ reviews: result.results.map(jobDeclineReviewJSON) });
}

async function resolveJobDecline(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
  reviewID: string,
): Promise<Response> {
  if (!canManageMembers(identity)) return json({ error: "forbidden" }, 403);
  const body = await request.json<{ action?: string; note?: string }>();
  const allowed = new Set(["reassigned", "rescheduled", "returned", "cancelled"]);
  const action = body.action?.trim() ?? "";
  const note = body.note?.trim().slice(0, 1000) ?? "";
  if (!allowed.has(action)) return json({ error: "invalid_job_decline_resolution" }, 400);
  const current = await env.DB.prepare(
    `${jobDeclineReviewSelection} WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, reviewID).first<JobDeclineReviewRow>();
  if (!current) return json({ error: "job_decline_not_found" }, 404);
  if (current.status === "resolved") {
    return json({ review: jobDeclineReviewJSON(current), duplicate: true });
  }
  const now = new Date().toISOString();
  const update = await env.DB.prepare(
    `UPDATE job_decline_reviews
        SET status = 'resolved', resolution_action = ?1, resolution_note = ?2,
            resolved_by_member_id = ?3, resolved_by_device_id = ?4,
            resolved_at = ?5, updated_at = ?5
      WHERE tenant_id = ?6 AND id = ?7 AND status = 'pending'`,
  ).bind(action, note, identity.memberID, identity.deviceID, now,
    identity.tenantID, reviewID).run();
  if (update.meta.changes === 0) {
    const raced = await env.DB.prepare(
      `${jobDeclineReviewSelection} WHERE tenant_id = ?1 AND id = ?2`,
    ).bind(identity.tenantID, reviewID).first<JobDeclineReviewRow>();
    return json({ review: jobDeclineReviewJSON(raced!), duplicate: true });
  }
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO job_decline_review_events
        (id, review_id, tenant_id, event_type, actor_member_id,
         actor_device_id, payload_json, created_at)
       VALUES (?1, ?2, ?3, 'resolved', ?4, ?5, ?6, ?7)`,
    ).bind(crypto.randomUUID(), reviewID, identity.tenantID, identity.memberID,
      identity.deviceID, JSON.stringify({ action, note }), now),
    accessAuditStatement(env, identity.tenantID, "job.decline_resolved", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      metadata: { reviewID, action },
      createdAt: now,
    }),
  ]);
  const resolved = await env.DB.prepare(
    `${jobDeclineReviewSelection} WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, reviewID).first<JobDeclineReviewRow>();
  return json({ review: jobDeclineReviewJSON(resolved!), duplicate: false });
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
  const changeCursor = await tenantSynchronizationCursor(
    env, identity.tenantID,
  );
  await env.ARCHIVES.put(
    tenantSynchronizationSnapshotKey(identity.tenantID),
    body,
    {
      httpMetadata: { contentType: archiveMediaType },
      customMetadata: {
        tenantID: identity.tenantID,
        publishedAt,
        revision,
        changeCursor: String(changeCursor),
      },
    },
  );
  return json({ publishedAt, revision, changeCursor }, 201);
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
      "x-pfss-change-cursor": object.customMetadata?.changeCursor ?? "0",
    },
  });
}

async function synchronizationCanonicalBaseline(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const result = await env.DB.prepare(
    `SELECT revision, operation_json AS operationJSON, updated_at AS updatedAt
       FROM synchronized_records
      WHERE tenant_id = ?1
      ORDER BY entity_type ASC, entity_id ASC`,
  ).bind(identity.tenantID).all<{
    revision: string;
    operationJSON: string;
    updatedAt: string;
  }>();
  const records = result.results.map((row) => {
    const operation = JSON.parse(row.operationJSON) as Record<string, unknown>;
    const rawMetadata = operation.metadata;
    const metadata = rawMetadata && typeof rawMetadata === "object" &&
        !Array.isArray(rawMetadata)
      ? Object.fromEntries(Object.entries(rawMetadata).map(([key, value]) => {
        if (typeof value === "string") return [key, value];
        if (value == null) return [key, ""];
        if (typeof value === "object") return [key, JSON.stringify(value)];
        return [key, String(value)];
      }))
      : {};
    return {
      revision: row.revision,
      operation: {
        ...operation,
        metadata,
        sequenceNumber: 0,
        status: "synchronized",
        updatedAt: row.updatedAt,
      },
    };
  });
  return json({
    cursor: await tenantSynchronizationCursor(env, identity.tenantID),
    records,
  });
}


async function reportSynchronizationQuarantine(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const body = await request.json<{
    operation?: Record<string, unknown>;
    reason?: string;
  }>();
  const operation = body.operation;
  const operationID = String(operation?.id ?? "").toLowerCase();
  const entityType = String(operation?.entityType ?? "custom");
  const entityID = operation?.entityID == null
    ? null
    : String(operation.entityID).toLowerCase();
  const reason = body.reason?.trim().slice(0, 1000) ?? "";
  if (!operation || !operationID || reason.length < 3) {
    return json({ error: "invalid_quarantine_report" }, 400);
  }
  let cloudOperationJSON: string | null = null;
  let cloudRevision: string | null = null;
  if (entityID) {
    const current = await env.DB.prepare(
      `SELECT operation_json AS operationJSON, revision
         FROM synchronized_records
        WHERE tenant_id = ?1 AND entity_type = ?2 AND entity_id = ?3`,
    ).bind(identity.tenantID, entityType, entityID).first<{
      operationJSON: string;
      revision: string;
    }>();
    cloudOperationJSON = current?.operationJSON ?? null;
    cloudRevision = current?.revision ?? null;
  }
  const now = new Date().toISOString();
  const existing = await env.DB.prepare(
    `SELECT id FROM synchronization_quarantines
      WHERE tenant_id = ?1 AND source_device_id = ?2 AND operation_id = ?3`,
  ).bind(identity.tenantID, identity.deviceID, operationID)
    .first<{ id: string }>();
  const quarantineID = existing?.id ?? crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO synchronization_quarantines
      (id, tenant_id, operation_id, entity_type, entity_id, source_member_id,
       source_device_id, operation_json, cloud_operation_json, cloud_revision,
       failure_json, status, policy_version, detected_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 'unresolved',
             ?12, ?13)
     ON CONFLICT(tenant_id, source_device_id, operation_id) DO UPDATE SET
       operation_json = excluded.operation_json,
       cloud_operation_json = excluded.cloud_operation_json,
       cloud_revision = excluded.cloud_revision,
       failure_json = excluded.failure_json,
       status = 'unresolved',
       resolution_action = NULL,
       resolution_reason = NULL,
       resolved_by_member_id = NULL,
       resolved_by_device_id = NULL,
       resolver_role = NULL,
       replacement_operation_id = NULL,
       detected_at = excluded.detected_at,
       resolved_at = NULL`,
  ).bind(
    quarantineID, identity.tenantID, operationID, entityType, entityID,
    identity.memberID, identity.deviceID, JSON.stringify(operation),
    cloudOperationJSON, cloudRevision, JSON.stringify({ reason }),
    SYNCHRONIZATION_QUARANTINE_POLICY_VERSION, now,
  ).run();
  return json({ quarantineID }, existing ? 200 : 201);
}

function quarantineReviewDetails(
  operation: Record<string, unknown>,
  cloudOperation: Record<string, unknown> | null,
): { affectedFields: string[]; operationalImpact: string } {
  if (cloudOperation) return conflictReviewDetails(operation, cloudOperation);
  const envelope = versionedMutationEnvelope(operation);
  const affectedFields = envelope?.changedFields?.filter((field) => field.trim())
    ?? ["record"];
  return {
    affectedFields: affectedFields.length > 0 ? affectedFields : ["record"],
    operationalImpact: conflictOperationalImpact(
      String(operation.entityType ?? "custom"),
      affectedFields,
    ),
  };
}

async function listSynchronizationQuarantines(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (!canResolveConflicts(identity)) return json({ error: "forbidden" }, 403);
  const result = await env.DB.prepare(
    `SELECT id, operation_id AS operationID, entity_type AS entityType,
            entity_id AS entityID, source_member_id AS sourceMemberID,
            source_device_id AS sourceDeviceID,
            operation_json AS operationJSON,
            cloud_operation_json AS cloudOperationJSON,
            cloud_revision AS cloudRevision, failure_json AS failureJSON,
            policy_version AS policyVersion, detected_at AS detectedAt
       FROM synchronization_quarantines
      WHERE tenant_id = ?1 AND status = 'unresolved'
      ORDER BY detected_at ASC`,
  ).bind(identity.tenantID).all<{
    id: string; operationID: string; entityType: string; entityID: string | null;
    sourceMemberID: string; sourceDeviceID: string; operationJSON: string;
    cloudOperationJSON: string | null; cloudRevision: string | null;
    failureJSON: string; policyVersion: number; detectedAt: string;
  }>();
  return json({ quarantines: result.results.map((row) => {
    const operation = JSON.parse(row.operationJSON) as Record<string, unknown>;
    const cloudOperation = row.cloudOperationJSON
      ? JSON.parse(row.cloudOperationJSON) as Record<string, unknown>
      : null;
    return {
      id: row.id,
      operationID: row.operationID,
      entityType: row.entityType,
      entityID: row.entityID,
      sourceMemberID: row.sourceMemberID,
      sourceDeviceID: row.sourceDeviceID,
      operation,
      cloudOperation,
      cloudRevision: row.cloudRevision,
      failure: JSON.parse(row.failureJSON),
      policyVersion: row.policyVersion,
      detectedAt: row.detectedAt,
      ...quarantineReviewDetails(operation, cloudOperation),
    };
  }) });
}

async function resolveSynchronizationQuarantine(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
  quarantineID: string,
): Promise<Response> {
  if (!canResolveConflicts(identity)) return json({ error: "forbidden" }, 403);
  const body = await request.json<{
    action?: string; reason?: string; replacementOperationID?: string;
  }>();
  if (
    body.action !== "discard" && body.action !== "retry" &&
    body.action !== "repair"
  ) {
    return json({ error: "invalid_quarantine_resolution" }, 400);
  }
  const providedReason = body.reason?.trim().slice(0, 500) ?? "";
  const actionDescription = body.action === "discard"
    ? "discarded the device change"
    : body.action === "retry"
      ? "retried the device change"
      : "repaired and approved the device change";
  const reason = providedReason ||
    `Manager or Owner ${actionDescription} without an additional note.`;
  if (body.action === "repair" && !body.replacementOperationID?.trim()) {
    return json({ error: "repair_replacement_required" }, 400);
  }
  const existing = await env.DB.prepare(
    `SELECT operation_id AS operationID, status, resolution_action AS action,
            resolved_at AS resolvedAt
       FROM synchronization_quarantines
      WHERE tenant_id = ?1 AND id = ?2`,
  ).bind(identity.tenantID, quarantineID).first<{
    operationID: string; status: string; action: string | null;
    resolvedAt: string | null;
  }>();
  if (!existing) return json({ error: "quarantine_not_found" }, 404);
  if (existing.status === "resolved") {
    return json({
      id: quarantineID, operationID: existing.operationID,
      action: existing.action, resolvedAt: existing.resolvedAt, duplicate: true,
    });
  }
  if (body.action === "repair") {
    const replacement = await env.DB.prepare(
      `SELECT synchronized_operations.id
         FROM synchronized_operations
         JOIN synchronization_quarantines
           ON synchronization_quarantines.tenant_id = synchronized_operations.tenant_id
          AND synchronization_quarantines.id = ?1
          AND synchronization_quarantines.entity_type = synchronized_operations.entity_type
          AND COALESCE(synchronization_quarantines.entity_id, '') =
              COALESCE(synchronized_operations.entity_id, '')
        WHERE synchronized_operations.tenant_id = ?2
          AND synchronized_operations.id = ?3
          AND synchronized_operations.device_id = ?4`,
    ).bind(
      quarantineID, identity.tenantID,
      body.replacementOperationID!.trim(), identity.deviceID,
    ).first<{ id: string }>();
    if (!replacement) {
      return json({ error: "repair_replacement_not_accepted" }, 409);
    }
  }
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE synchronization_quarantines
          SET status = 'resolved', resolution_action = ?1,
              resolution_reason = ?2, resolved_by_member_id = ?3,
              resolved_by_device_id = ?4, resolver_role = ?5, resolved_at = ?6,
              replacement_operation_id = ?9
        WHERE tenant_id = ?7 AND id = ?8 AND status = 'unresolved'`,
    ).bind(
      body.action, reason, identity.memberID, identity.deviceID, identity.role,
      now, identity.tenantID, quarantineID,
      body.replacementOperationID?.trim() ?? null,
    ),
    env.DB.prepare(
      `INSERT INTO access_audit_events
        (id, tenant_id, actor_member_id, actor_device_id, event_type,
         metadata_json, created_at)
       SELECT ?1, ?2, ?3, ?4, 'sync.quarantine_resolved', ?5, ?6
        WHERE EXISTS (
          SELECT 1 FROM synchronization_quarantines
           WHERE tenant_id = ?2 AND id = ?7 AND status = 'resolved'
             AND resolved_at = ?6
        )`,
    ).bind(
      crypto.randomUUID(), identity.tenantID, identity.memberID,
      identity.deviceID, JSON.stringify({
        quarantineID, operationID: existing.operationID,
        action: body.action, reason,
        replacementOperationID: body.replacementOperationID ?? null,
        policyVersion: SYNCHRONIZATION_QUARANTINE_POLICY_VERSION,
      }), now, quarantineID,
    ),
  ]);
  return json({
    id: quarantineID, operationID: existing.operationID,
    action: body.action, resolvedAt: now, duplicate: false,
  });
}

async function listSourceQuarantineResolutions(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const result = await env.DB.prepare(
    `SELECT id, operation_id AS operationID, resolution_action AS action,
            resolution_reason AS reason, resolved_at AS resolvedAt
       FROM synchronization_quarantines
      WHERE tenant_id = ?1
        AND (source_device_id = ?2 OR source_member_id = ?3)
        AND status = 'resolved'
      ORDER BY resolved_at ASC`,
  ).bind(identity.tenantID, identity.deviceID, identity.memberID).all<{
    id: string; operationID: string; action: "discard" | "retry" | "repair";
    reason: string; resolvedAt: string;
  }>();
  return json({ resolutions: result.results });
}

const synchronizationDiagnosticMediaType =
  "application/vnd.pfss.sync-diagnostics+json";
const synchronizationDiagnosticMaximumBytes = 256 * 1024;
const synchronizationDiagnosticRetentionMilliseconds = 30 * 24 * 60 * 60 * 1000;

function diagnosticRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function diagnosticString(value: unknown, maximum = 200): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= maximum ? trimmed : null;
}

function sanitizeSynchronizationDiagnostic(body: Record<string, unknown>) {
  const app = diagnosticRecord(body.app);
  const device = diagnosticRecord(body.device);
  const synchronization = diagnosticRecord(body.synchronization);
  const inventory = diagnosticRecord(body.inventory);
  const recovery = diagnosticRecord(synchronization.latestRecovery);
  const operations = Array.isArray(body.operations) ? body.operations.slice(0, 100) : [];
  return {
    schemaVersion: 1,
    generatedAt: diagnosticString(body.generatedAt, 40),
    app: {
      version: diagnosticString(app.version, 40),
      build: diagnosticString(app.build, 40),
    },
    device: {
      model: diagnosticString(device.model, 100),
      systemName: diagnosticString(device.systemName, 40),
      systemVersion: diagnosticString(device.systemVersion, 40),
    },
    synchronization: {
      cursor: Number.isSafeInteger(synchronization.cursor)
        ? synchronization.cursor : null,
      connectivity: diagnosticString(synchronization.connectivity, 40),
      cloudAccessStatus: diagnosticString(synchronization.cloudAccessStatus, 80),
      queuePersistenceError: diagnosticString(
        synchronization.queuePersistenceError, 300,
      ),
      latestRecovery: Object.keys(recovery).length === 0 ? null : {
        startedAt: diagnosticString(recovery.startedAt, 40),
        completedAt: diagnosticString(recovery.completedAt, 40),
        startingCursor: Number.isSafeInteger(recovery.startingCursor)
          ? recovery.startingCursor : null,
        endingCursor: Number.isSafeInteger(recovery.endingCursor)
          ? recovery.endingCursor : null,
        pulledChanges: Number.isSafeInteger(recovery.pulledChanges)
          ? recovery.pulledChanges : null,
        alreadyReflected: Number.isSafeInteger(recovery.alreadyReflected)
          ? recovery.alreadyReflected : null,
        supersededDeviceChanges: Number.isSafeInteger(recovery.supersededDeviceChanges)
          ? recovery.supersededDeviceChanges : null,
        requiringReview: Number.isSafeInteger(recovery.requiringReview)
          ? recovery.requiringReview : null,
      },
    },
    inventory: {
      customers: Number.isSafeInteger(inventory.customers) ? inventory.customers : null,
      sites: Number.isSafeInteger(inventory.sites) ? inventory.sites : null,
      leads: Number.isSafeInteger(inventory.leads) ? inventory.leads : null,
      estimates: Number.isSafeInteger(inventory.estimates) ? inventory.estimates : null,
      jobs: Number.isSafeInteger(inventory.jobs) ? inventory.jobs : null,
      invoices: Number.isSafeInteger(inventory.invoices) ? inventory.invoices : null,
      employees: Number.isSafeInteger(inventory.employees) ? inventory.employees : null,
      catalogItems: Number.isSafeInteger(inventory.catalogItems) ? inventory.catalogItems : null,
      recurringWorkTemplates: Number.isSafeInteger(inventory.recurringWorkTemplates)
        ? inventory.recurringWorkTemplates : null,
      assignments: Number.isSafeInteger(inventory.assignments) ? inventory.assignments : null,
    },
    operations: operations.map((raw) => {
      const operation = diagnosticRecord(raw);
      const failure = diagnosticRecord(operation.failure);
      const conflict = diagnosticRecord(operation.conflict);
      const metadata = diagnosticRecord(operation.metadata);
      const retries = Array.isArray(operation.retries)
        ? operation.retries.slice(-10).map((rawRetry) => {
          const retry = diagnosticRecord(rawRetry);
          return {
            attemptNumber: Number.isSafeInteger(retry.attemptNumber)
              ? retry.attemptNumber : null,
            startedAt: diagnosticString(retry.startedAt, 40),
            completedAt: diagnosticString(retry.completedAt, 40),
            outcome: diagnosticString(retry.outcome, 40),
            failureCode: diagnosticString(retry.failureCode, 120),
          };
        }) : [];
      const allowedMetadata = [
        "serverQuarantineID", "serverQuarantineStatus", "serverConflictID",
        "sourceOperationID", "mutationEnvelopeVersion", "mutationKind",
        "commandName", "changedFields", "quarantineDeliveryStatus",
        "conflictDeliveryStatus", "appliedQuarantineResolutionID",
        "quarantineResolution", "recoveryClassification", "remoteRevision",
      ];
      return {
        operationID: diagnosticString(operation.operationID, 80),
        idempotencyKey: diagnosticString(operation.idempotencyKey, 160),
        sequenceNumber: Number.isSafeInteger(operation.sequenceNumber)
          ? operation.sequenceNumber : null,
        entityType: diagnosticString(operation.entityType, 60),
        recordID: diagnosticString(operation.recordID, 80),
        actionName: diagnosticString(operation.actionName, 100),
        status: diagnosticString(operation.status, 40),
        createdAt: diagnosticString(operation.createdAt, 40),
        updatedAt: diagnosticString(operation.updatedAt, 40),
        nextRetryAt: diagnosticString(operation.nextRetryAt, 40),
        failure: Object.keys(failure).length === 0 ? null : {
          category: diagnosticString(failure.category, 60),
          code: diagnosticString(failure.code, 120),
          isRetryable: typeof failure.isRetryable === "boolean"
            ? failure.isRetryable : null,
          occurredAt: diagnosticString(failure.occurredAt, 40),
        },
        conflict: Object.keys(conflict).length === 0 ? null : {
          kind: diagnosticString(conflict.kind, 60),
          detectedAt: diagnosticString(conflict.detectedAt, 40),
          resolution: diagnosticString(conflict.resolution, 60),
        },
        metadata: Object.fromEntries(allowedMetadata.flatMap((key) => {
          const value = diagnosticString(metadata[key], 300);
          return value === null ? [] : [[key, value]];
        })),
        retries,
      };
    }),
  };
}

function synchronizationDiagnosticCaseCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const token = Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
  return `PFSS-${token.slice(0, 4)}-${token.slice(4)}`;
}

async function submitSynchronizationDiagnostic(
  request: Request,
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  if (request.headers.get("content-type") !== synchronizationDiagnosticMediaType) {
    return json({ error: "unsupported_diagnostic_type" }, 415);
  }
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > synchronizationDiagnosticMaximumBytes) {
    return json({ error: "diagnostic_too_large" }, 413);
  }
  const body = await request.json<Record<string, unknown>>();
  const description = body.description == null
    ? null : diagnosticString(body.description, 500);
  if (body.description != null && description === null) {
    return json({ error: "invalid_diagnostic_description" }, 400);
  }
  const sanitized = sanitizeSynchronizationDiagnostic(body);
  if (!sanitized.generatedAt || !sanitized.app.version || !sanitized.app.build ||
      !sanitized.device.model || !sanitized.device.systemVersion) {
    return json({ error: "invalid_diagnostic_bundle" }, 400);
  }
  const recent = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM synchronization_diagnostics
      WHERE tenant_id = ?1 AND source_device_id = ?2 AND submitted_at >= ?3`,
  ).bind(
    identity.tenantID, identity.deviceID,
    new Date(Date.now() - 60 * 60 * 1000).toISOString(),
  ).first<{ count: number }>();
  if (Number(recent?.count ?? 0) >= 5) {
    return json({ error: "diagnostic_rate_limited" }, 429);
  }

  const id = crypto.randomUUID();
  const caseCode = synchronizationDiagnosticCaseCode();
  const submittedAt = new Date();
  const expiresAt = new Date(
    submittedAt.getTime() + synchronizationDiagnosticRetentionMilliseconds,
  );
  const objectKey = `support-diagnostics/${identity.tenantID}/${id}.json`;
  const stored = {
    header: {
      caseCode,
      tenantID: identity.tenantID,
      tenantName: identity.tenantName,
      sourceMemberID: identity.memberID,
      sourceMemberName: identity.memberName,
      sourceRole: identity.role,
      sourceDeviceID: identity.deviceID,
      sourceDeviceName: identity.deviceName,
      submittedAt: submittedAt.toISOString(),
      expiresAt: expiresAt.toISOString(),
    },
    description,
    diagnostic: sanitized,
  };
  const data = new TextEncoder().encode(JSON.stringify(stored));
  if (data.byteLength > synchronizationDiagnosticMaximumBytes) {
    return json({ error: "diagnostic_too_large" }, 413);
  }
  await env.ARCHIVES.put(objectKey, data, {
    httpMetadata: { contentType: synchronizationDiagnosticMediaType },
    customMetadata: {
      caseCode, tenantID: identity.tenantID, sourceDeviceID: identity.deviceID,
      submittedAt: submittedAt.toISOString(), expiresAt: expiresAt.toISOString(),
    },
  });
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO synchronization_diagnostics
          (id, case_code, tenant_id, source_member_id, source_device_id,
           source_role, description, object_key, byte_size, app_version,
           build_number, system_version, device_model, submitted_at, expires_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)`,
      ).bind(
        id, caseCode, identity.tenantID, identity.memberID, identity.deviceID,
        identity.role, description, objectKey, data.byteLength,
        sanitized.app.version, sanitized.app.build,
        sanitized.device.systemVersion, sanitized.device.model,
        submittedAt.toISOString(), expiresAt.toISOString(),
      ),
      accessAuditStatement(env, identity.tenantID, "support.sync_diagnostics_submitted", {
        actorMemberID: identity.memberID,
        actorDeviceID: identity.deviceID,
        metadata: {
          caseCode,
          byteSize: String(data.byteLength),
          expiresAt: expiresAt.toISOString(),
        },
        createdAt: submittedAt.toISOString(),
      }),
    ]);
  } catch (error) {
    await env.ARCHIVES.delete(objectKey);
    throw error;
  }
  return json({ caseCode, submittedAt, expiresAt }, 201);
}

async function listSynchronizationDiagnostics(
  env: Env,
  identity: DeviceIdentity,
): Promise<Response> {
  const managerScope = identity.role === "owner" || identity.role === "manager";
  const result = await env.DB.prepare(
    `SELECT case_code AS caseCode, source_member_id AS sourceMemberID,
            source_device_id AS sourceDeviceID, source_role AS sourceRole,
            description, byte_size AS byteSize, app_version AS appVersion,
            build_number AS buildNumber, system_version AS systemVersion,
            device_model AS deviceModel, submitted_at AS submittedAt,
            expires_at AS expiresAt
       FROM synchronization_diagnostics
      WHERE tenant_id = ?1 AND deleted_at IS NULL
        AND (?2 = 1 OR source_member_id = ?3)
      ORDER BY submitted_at DESC LIMIT 100`,
  ).bind(identity.tenantID, managerScope ? 1 : 0, identity.memberID).all();
  return json({ diagnostics: result.results });
}

async function getSynchronizationDiagnostic(
  env: Env,
  identity: DeviceIdentity,
  caseCode: string,
): Promise<Response> {
  const row = await env.DB.prepare(
    `SELECT source_member_id AS sourceMemberID, object_key AS objectKey
       FROM synchronization_diagnostics
      WHERE tenant_id = ?1 AND case_code = ?2 AND deleted_at IS NULL`,
  ).bind(identity.tenantID, caseCode.toUpperCase()).first<{
    sourceMemberID: string; objectKey: string;
  }>();
  if (!row) return json({ error: "diagnostic_not_found" }, 404);
  if (identity.role === "member" && row.sourceMemberID !== identity.memberID) {
    return json({ error: "forbidden" }, 403);
  }
  const object = await env.ARCHIVES.get(row.objectKey);
  if (!object) return json({ error: "diagnostic_content_missing" }, 404);
  await accessAuditStatement(env, identity.tenantID, "support.sync_diagnostics_accessed", {
    actorMemberID: identity.memberID,
    actorDeviceID: identity.deviceID,
    metadata: { caseCode: caseCode.toUpperCase() },
  }).run();
  return new Response(object.body, {
    headers: { "content-type": synchronizationDiagnosticMediaType },
  });
}

async function deleteSynchronizationDiagnostic(
  env: Env,
  identity: DeviceIdentity,
  caseCode: string,
): Promise<Response> {
  if (identity.role === "member") return json({ error: "forbidden" }, 403);
  const normalized = caseCode.toUpperCase();
  const row = await env.DB.prepare(
    `SELECT object_key AS objectKey FROM synchronization_diagnostics
      WHERE tenant_id = ?1 AND case_code = ?2 AND deleted_at IS NULL`,
  ).bind(identity.tenantID, normalized).first<{ objectKey: string }>();
  if (!row) return json({ error: "diagnostic_not_found" }, 404);
  await env.ARCHIVES.delete(row.objectKey);
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE synchronization_diagnostics
          SET deleted_at = ?1, deleted_by_member_id = ?2
        WHERE tenant_id = ?3 AND case_code = ?4 AND deleted_at IS NULL`,
    ).bind(now, identity.memberID, identity.tenantID, normalized),
    accessAuditStatement(env, identity.tenantID, "support.sync_diagnostics_deleted", {
      actorMemberID: identity.memberID,
      actorDeviceID: identity.deviceID,
      metadata: { caseCode: normalized },
      createdAt: now,
    }),
  ]);
  return json({ caseCode: normalized, deletedAt: now });
}

async function cleanupExpiredSynchronizationDiagnostics(
  env: Env,
  now: Date = new Date(),
): Promise<number> {
  const expired = await env.DB.prepare(
    `SELECT id, object_key AS objectKey FROM synchronization_diagnostics
      WHERE expires_at <= ?1 LIMIT 1000`,
  ).bind(now.toISOString()).all<{ id: string; objectKey: string }>();
  for (const row of expired.results) await env.ARCHIVES.delete(row.objectKey);
  if (expired.results.length > 0) {
    await env.DB.batch(expired.results.map((row) => env.DB.prepare(
      "DELETE FROM synchronization_diagnostics WHERE id = ?1",
    ).bind(row.id)));
  }
  return expired.results.length;
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
      if (request.method === "POST" && url.pathname === "/v1/sync/cursor") {
        return acknowledgeSynchronizationCursor(request, env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/sync/push") {
        return registerSynchronizationPush(request, env, identity);
      }
      if (request.method === "DELETE" && url.pathname === "/v1/sync/push") {
        return unregisterSynchronizationPush(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/sync/push-events") {
        return recordSynchronizationPushEvent(request, env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/sync/device-health") {
        return reportSynchronizationDeviceHealth(request, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/sync/health") {
        return synchronizationHealth(env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/mileage/sync") {
        return synchronizeMileageTrips(request, env, identity);
      }
      if (
        request.method === "GET" &&
        url.pathname === "/v1/mileage/business-summary"
      ) {
        return mileageBusinessSummary(url, env, identity);
      }
      if (request.method === "POST" && url.pathname === "/v1/job-declines") {
        return submitJobDecline(request, env, identity);
      }
      if (request.method === "GET" && url.pathname === "/v1/job-declines") {
        return listJobDeclines(url, env, identity);
      }
      const jobDeclineResolutionMatch = url.pathname.match(
        /^\/v1\/job-declines\/([^/]+)\/resolve$/,
      );
      if (request.method === "POST" && jobDeclineResolutionMatch) {
        return resolveJobDecline(
          request,
          env,
          identity,
          decodeURIComponent(jobDeclineResolutionMatch[1]),
        );
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
      if (request.method === "GET" && url.pathname === "/v1/sync/quarantines") {
        return listSynchronizationQuarantines(env, identity);
      }
      if (
        request.method === "GET" &&
        url.pathname === "/v1/sync/quarantine-resolutions"
      ) {
        return listSourceQuarantineResolutions(env, identity);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/sync/quarantines/report"
      ) {
        return reportSynchronizationQuarantine(request, env, identity);
      }
      const quarantineResolutionMatch = url.pathname.match(
        /^\/v1\/sync\/quarantines\/([^/]+)\/resolve$/,
      );
      if (request.method === "POST" && quarantineResolutionMatch) {
        return resolveSynchronizationQuarantine(
          request, env, identity,
          decodeURIComponent(quarantineResolutionMatch[1]),
        );
      }
      if (request.method === "POST" && url.pathname === "/v1/sync/conflicts/report") {
        return reportSynchronizationConflict(request, env, identity);
      }
      if (
        request.method === "GET" &&
        url.pathname === "/v1/sync/conflicts/revoked-device-scope"
      ) {
        return revokedDeviceSynchronizationConflictScope(url, env, identity);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/sync/conflicts/discard-revoked-device"
      ) {
        return discardRevokedDeviceSynchronizationConflicts(
          request, env, identity,
        );
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
      if (
        request.method === "GET" &&
        url.pathname === "/v1/sync/baseline-records"
      ) {
        return synchronizationCanonicalBaseline(env, identity);
      }
      if (
        request.method === "POST" &&
        url.pathname === "/v1/support/sync-diagnostics"
      ) {
        return submitSynchronizationDiagnostic(request, env, identity);
      }
      if (
        request.method === "GET" &&
        url.pathname === "/v1/support/sync-diagnostics"
      ) {
        return listSynchronizationDiagnostics(env, identity);
      }
      const synchronizationDiagnosticMatch = url.pathname.match(
        /^\/v1\/support\/sync-diagnostics\/([^/]+)$/,
      );
      if (synchronizationDiagnosticMatch && request.method === "GET") {
        return getSynchronizationDiagnostic(
          env, identity, decodeURIComponent(synchronizationDiagnosticMatch[1]),
        );
      }
      if (synchronizationDiagnosticMatch && request.method === "DELETE") {
        return deleteSynchronizationDiagnostic(
          env, identity, decodeURIComponent(synchronizationDiagnosticMatch[1]),
        );
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
    context.waitUntil(Promise.all([
      runAccessCleanup(env),
      cleanupExpiredSynchronizationDiagnostics(env),
      evaluateAllSynchronizationHealthAlerts(env),
    ]));
  },
};
