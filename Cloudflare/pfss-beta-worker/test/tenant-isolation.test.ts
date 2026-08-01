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
import { normalizedAppStoreTransaction } from
  "../src/app-store-subscription-provider";

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
  const subjectID = crypto.randomUUID();
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
    env.DB.prepare(
      `INSERT INTO authentication_subjects
        (id, display_name, status, created_at, updated_at)
       VALUES (?1, ?2, 'active', ?3, ?3)`,
    ).bind(subjectID, `${label} Test Authority`, now),
    env.DB.prepare(
      `INSERT INTO plan_allocations
        (id, tenant_id, access_source, plan_code, entitlements_json,
         effective_at, granted_by_subject_id, grant_reason, created_at)
       VALUES (?1, ?2, 'internalTesting', 'test-full', ?3, ?4, ?5,
               'Automated test fixture', ?4)`,
    ).bind(
      crypto.randomUUID(),
      tenantID,
      JSON.stringify({
        userLimit: 25,
        deviceLimit: 40,
        recordLimits: { leads: 1_000, customers: 1_000, jobs: 3_000 },
        modules: ["sales", "service", "dispatch", "reporting"],
      }),
      now,
      subjectID,
    ),
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
      "plan_catalog",
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

    const plans = await env.DB.prepare(
      `SELECT code, user_limit AS userLimit, device_limit AS deviceLimit,
              lead_limit AS leadLimit, customer_limit AS customerLimit,
              job_limit AS jobLimit
         FROM plan_catalog ORDER BY monthly_price_cents`,
    ).all<{
      code: string;
      userLimit: number;
      deviceLimit: number;
      leadLimit: number | null;
      customerLimit: number | null;
      jobLimit: number | null;
    }>();
    expect(plans.results).toContainEqual({
      code: "trial-14-day",
      userLimit: 2,
      deviceLimit: 4,
      leadLimit: 5,
      customerLimit: 5,
      jobLimit: 10,
    });
    expect(plans.results).toContainEqual({
      code: "expert-monthly",
      userLimit: 10,
      deviceLimit: 20,
      leadLimit: 10_000,
      customerLimit: 10_000,
      jobLimit: 50_000,
    });

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
      plan: { accessSource: string; entitlements: { userLimit: number } };
      tokenIssued: boolean;
    }>();
    expect(receipt.registrationAttempt.status).toBe("active");
    expect(receipt.tenant.displayName).toContain("PFSS");
    expect(receipt.owner.role).toBe("owner");
    expect(receipt.plan.accessSource).toBe("betaGrant");
    expect(receipt.plan.entitlements.userLimit).toBe(5);
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
      screenHint: "sign-in",
    });
    const authorizationURL = new URL(session.authorizationURL);
    expect(authorizationURL.origin).toBe("https://api.workos.com");
    expect(authorizationURL.searchParams.get("provider")).toBe("authkit");
    expect(authorizationURL.searchParams.get("code_challenge_method")).toBe("S256");
    expect(authorizationURL.searchParams.get("code_challenge"))
      .toBe(codeChallenge);
    expect(authorizationURL.searchParams.get("screen_hint")).toBe("sign-in");

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
    // A signed-out installation retains its device ID. Model the primary Owner
    // keeping their phone while the signed-out iPad is activated for the
    // invited Owner.
    const deviceID = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO devices
        (id, tenant_id, member_id, display_name, token_hash, created_at,
         last_seen_at)
       VALUES (?1, ?2, ?3, 'Signed-out iPad', ?4, ?5, ?5)`,
    ).bind(
      deviceID, owner.tenantID, owner.memberID,
      createHash("sha256").update(`old_${deviceID}`).digest("hex"),
      now.toISOString(),
    ).run();
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
    expect(accepted.status).toBe(200);
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
    const reassignedDevice = await env.DB.prepare(
      `SELECT member_id AS memberID, revoked_at AS revokedAt
         FROM devices WHERE tenant_id = ?1 AND id = ?2`,
    ).bind(owner.tenantID, deviceID).first<{
      memberID: string;
      revokedAt: string | null;
    }>();
    expect(reassignedDevice).toEqual({
      memberID: invitation.memberID,
      revokedAt: null,
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

  it("reports server-owned entitlement usage and enforces employee limits", async () => {
    const owner = await seedIdentity("Entitlement Limit");
    await env.DB.prepare(
      `UPDATE plan_allocations SET entitlements_json = ?1
        WHERE tenant_id = ?2 AND revoked_at IS NULL`,
    ).bind(JSON.stringify({
      userLimit: 2,
      deviceLimit: 2,
      recordLimits: { leads: 1, customers: 1, jobs: 1 },
      modules: ["service"],
    }), owner.tenantID).run();

    const status = await worker.fetch(
      request(owner, "/v1/account/entitlements"), env,
    );
    expect(status.status).toBe(200);
    expect(await status.json()).toMatchObject({
      planCode: "test-full",
      accessSource: "internalTesting",
      accessMode: "full",
      entitlements: { userLimit: 2, deviceLimit: 2 },
      usage: {
        users: 1, employees: 0, devices: 1, owners: 1,
        leads: 0, customers: 0, jobs: 0,
      },
    });

    const invite = () => worker.fetch(request(owner, "/v1/invitations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ displayName: "Limited Employee", role: "member" }),
    }), env);
    expect((await invite()).status).toBe(201);
    const rejected = await invite();
    expect(rejected.status).toBe(409);
    expect(await rejected.json()).toEqual({
      error: "user_limit_reached",
      upgradeRecommended: true,
    });
  });

  it("rejects unverified App Store evidence without granting client authority", async () => {
    const owner = await seedIdentity("App Store Evidence");
    const signedTransaction = `${"a".repeat(24)}.${"b".repeat(80)}.${"c".repeat(64)}`;
    const submit = () => worker.fetch(request(
      owner,
      "/v1/account/subscriptions/app-store/transactions",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          signedTransaction,
          planCode: "base-monthly",
          productID: "com.patriot.pfss.subscription.base.monthly",
        }),
      },
    ), env);

    const accepted = await submit();
    expect(accepted.status).toBe(400);
    const receipt = await accepted.json<{ evidenceID: string; status: string }>();
    expect(receipt.status).toBe("rejected");

    const duplicate = await submit();
    expect(duplicate.status).toBe(200);
    expect(await duplicate.json()).toEqual(receipt);

    const allocation = await env.DB.prepare(
      `SELECT access_source AS accessSource FROM plan_allocations
        WHERE tenant_id = ?1 AND revoked_at IS NULL`,
    ).bind(owner.tenantID).first<{ accessSource: string }>();
    expect(allocation?.accessSource).toBe("internalTesting");
  });

  it("normalizes only the published PFSS App Store product claims", () => {
    const tenantID = crypto.randomUUID();
    const transaction = normalizedAppStoreTransaction({
      transactionId: "200000000000001",
      originalTransactionId: "200000000000000",
      appAccountToken: tenantID,
      productId: "com.patriot.pfss.subscription.pro.monthly",
      purchaseDate: Date.now(),
      expiresDate: Date.now() + 2_592_000_000,
      environment: "Sandbox",
    });
    expect(transaction.planCode).toBe("pro-monthly");
    expect(transaction.appAccountToken).toBe(tenantID);
    expect(transaction.environment).toBe("sandbox");
  });

  it("limits new records while permitting updates to existing records", async () => {
    const owner = await seedIdentity("Record Limits");
    await env.DB.prepare(
      `UPDATE plan_allocations SET entitlements_json = ?1
        WHERE tenant_id = ?2 AND revoked_at IS NULL`,
    ).bind(JSON.stringify({
      userLimit: 5,
      deviceLimit: 10,
      recordLimits: { leads: 1, customers: 1, jobs: 1 },
      modules: ["sales", "service"],
    }), owner.tenantID).run();
    const operation = (entityID: string, baseRevision?: string) => ({
      id: crypto.randomUUID(),
      idempotencyKey: `lead-${crypto.randomUUID()}`,
      type: "recordMutation",
      entityType: "lead",
      entityID,
      actionName: "upsertRecord",
      baseRevision: baseRevision ?? null,
      payload: { schemaVersion: 1, contentType: "test", body: "e30=" },
      createdAt: new Date().toISOString(),
    });
    const submit = (value: ReturnType<typeof operation>) => worker.fetch(
      request(owner, "/v1/operations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(value),
      }), env,
    );

    const leadID = crypto.randomUUID();
    const created = await submit(operation(leadID));
    expect(created.status).toBe(201);
    const revision = (await created.json<{ revision: string }>()).revision;

    const limited = await submit(operation(crypto.randomUUID()));
    expect(limited.status).toBe(409);
    expect(await limited.json()).toEqual({
      error: "lead_limit_reached",
      limit: 1,
      upgradeRecommended: true,
    });

    expect((await submit(operation(leadID, revision))).status).toBe(201);
  });

  it("keeps past-due paid companies readable while blocking account growth", async () => {
    const owner = await seedIdentity("Past Due");
    const now = new Date().toISOString();
    const subscriptionID = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE plan_allocations SET revoked_at = ?1 WHERE tenant_id = ?2",
      ).bind(now, owner.tenantID),
      env.DB.prepare(
        `INSERT INTO subscription_accounts
          (id, tenant_id, provider_key, provider_customer_reference, status,
           created_at, updated_at)
         VALUES (?1, ?2, 'appStore', ?3, 'pastDue', ?4, ?4)`,
      ).bind(subscriptionID, owner.tenantID, crypto.randomUUID(), now),
      env.DB.prepare(
        `INSERT INTO plan_allocations
          (id, tenant_id, subscription_account_id, access_source,
           source_reference, plan_code, entitlements_json, effective_at,
           created_at)
         VALUES (?1, ?2, ?3, 'appStoreSubscription', ?4, 'team-annual',
                 ?5, ?6, ?6)`,
      ).bind(
        crypto.randomUUID(), owner.tenantID, subscriptionID,
        crypto.randomUUID(), JSON.stringify({
          userLimit: 25,
          deviceLimit: 40,
          recordLimits: { leads: 1_000, customers: 1_000, jobs: 3_000 },
          modules: ["sales", "service", "dispatch", "reporting"],
        }), now,
      ),
    ]);

    const status = await worker.fetch(
      request(owner, "/v1/account/entitlements"), env,
    );
    expect(status.status).toBe(200);
    expect(await status.json()).toMatchObject({
      subscriptionStatus: "pastDue",
      accessMode: "readOnly",
    });
    const invitation = await worker.fetch(request(owner, "/v1/invitations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ displayName: "Blocked Growth", role: "member" }),
    }), env);
    expect(invitation.status).toBe(402);
    expect(await invitation.json()).toEqual({
      error: "account_read_only",
      subscriptionStatus: "pastDue",
    });
  });
});
