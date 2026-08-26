import { env } from "cloudflare:workers";
import { applyD1Migrations } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const TENANT_ALPHA = "migration-tenant-alpha";
const TENANT_BETA = "migration-tenant-beta";
const MEMBER_ALPHA = "migration-member-alpha";
const MEMBER_BETA = "migration-member-beta";
const DEVICE_ALPHA = "migration-device-alpha";
const DEVICE_BETA = "migration-device-beta";

function migrationNumber(migration: D1Migration): number {
  return Number.parseInt(migration.name.slice(0, 4), 10);
}

async function seedPrePhase20Fixture(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO tenants (id, display_name, status, created_at)
       VALUES (?1, ?2, 'active', ?3)`,
    ).bind(TENANT_ALPHA, "Migration Alpha", "2026-07-01T00:00:00.000Z"),
    env.DB.prepare(
      `INSERT INTO tenants (id, display_name, status, created_at)
       VALUES (?1, ?2, 'active', ?3)`,
    ).bind(TENANT_BETA, "Migration Beta", "2026-07-02T00:00:00.000Z"),
    env.DB.prepare(
      `INSERT INTO tenant_members
         (id, tenant_id, display_name, role, status, created_at, activated_at)
       VALUES (?1, ?2, ?3, 'owner', 'active', ?4, ?4)`,
    ).bind(MEMBER_ALPHA, TENANT_ALPHA, "Alpha Owner", "2026-07-01T00:00:00.000Z"),
    env.DB.prepare(
      `INSERT INTO tenant_members
         (id, tenant_id, display_name, role, status, created_at, activated_at)
       VALUES (?1, ?2, ?3, 'owner', 'active', ?4, ?4)`,
    ).bind(MEMBER_BETA, TENANT_BETA, "Beta Owner", "2026-07-02T00:00:00.000Z"),
    env.DB.prepare(
      `INSERT INTO devices
         (id, tenant_id, display_name, token_hash, created_at, last_seen_at,
          member_id)
       VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)`,
    ).bind(
      DEVICE_ALPHA, TENANT_ALPHA, "Alpha iPad", "migration-token-alpha",
      "2026-07-01T00:00:00.000Z", MEMBER_ALPHA,
    ),
    env.DB.prepare(
      `INSERT INTO devices
         (id, tenant_id, display_name, token_hash, created_at, last_seen_at,
          member_id)
       VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)`,
    ).bind(
      DEVICE_BETA, TENANT_BETA, "Beta iPhone", "migration-token-beta",
      "2026-07-02T00:00:00.000Z", MEMBER_BETA,
    ),
  ]);

  const operation = (
    id: string,
    tenantID: string,
    deviceID: string,
    operationType: string,
    entityType: string,
    entityID: string,
    acceptedAt: string,
    revision: string,
  ) => env.DB.prepare(
    `INSERT INTO synchronized_operations
       (id, tenant_id, device_id, idempotency_key, operation_type,
        entity_type, entity_id, action_name, payload_json, created_at,
        accepted_at, revision)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'migrationFixture', ?8, ?9, ?9, ?10)`,
  ).bind(
    id, tenantID, deviceID, `key-${id}`, operationType, entityType, entityID,
    JSON.stringify({ id, operationType, entityType, entityID, revision }),
    acceptedAt, revision,
  );

  // Insert deliberately out of timestamp order. Migration 0023 must produce a
  // stable, gap-free sequence independently for each tenant.
  await env.DB.batch([
    operation(
      "alpha-op-2", TENANT_ALPHA, DEVICE_ALPHA, "upsertRecord", "job",
      "alpha-job-live", "2026-07-10T09:00:00.000Z", "alpha-r2",
    ),
    operation(
      "alpha-op-1", TENANT_ALPHA, DEVICE_ALPHA, "upsertRecord", "customer",
      "alpha-customer", "2026-07-10T08:00:00.000Z", "alpha-r1",
    ),
    operation(
      "alpha-op-3", TENANT_ALPHA, DEVICE_ALPHA, "deleteRecord", "job",
      "alpha-job-deleted", "2026-07-10T09:00:00.000Z", "alpha-r3",
    ),
    operation(
      "beta-op-2", TENANT_BETA, DEVICE_BETA, "deleteRecord", "customer",
      "beta-customer-deleted", "2026-07-11T10:00:00.000Z", "beta-r2",
    ),
    operation(
      "beta-op-1", TENANT_BETA, DEVICE_BETA, "upsertRecord", "job",
      "beta-job-live", "2026-07-11T07:00:00.000Z", "beta-r1",
    ),
  ]);

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO synchronized_records
         (tenant_id, entity_type, entity_id, revision, operation_json,
          updated_by_member_id, updated_by_device_id, updated_at)
       VALUES (?1, 'job', 'alpha-job-live', 'alpha-r2', ?2, ?3, ?4, ?5)`,
    ).bind(
      TENANT_ALPHA,
      JSON.stringify({ recordState: "live", jobNumber: "MIGRATION-LIVE" }),
      MEMBER_ALPHA, DEVICE_ALPHA, "2026-07-10T09:00:00.000Z",
    ),
    env.DB.prepare(
      `INSERT INTO synchronized_records
         (tenant_id, entity_type, entity_id, revision, operation_json,
          updated_by_member_id, updated_by_device_id, updated_at)
       VALUES (?1, 'job', 'alpha-job-deleted', 'alpha-r3', ?2, ?3, ?4, ?5)`,
    ).bind(
      TENANT_ALPHA,
      JSON.stringify({ recordState: "tombstone", deletedAt: "2026-07-10T09:00:00.000Z" }),
      MEMBER_ALPHA, DEVICE_ALPHA, "2026-07-10T09:00:00.000Z",
    ),
    env.DB.prepare(
      `INSERT INTO synchronization_conflicts
         (id, tenant_id, entity_type, entity_id, source_member_id,
          source_device_id, local_operation_json, cloud_operation_json,
          cloud_revision, status, detected_at, affected_fields_json)
       VALUES ('migration-conflict', ?1, 'job', 'alpha-job-live', ?2, ?3,
               ?4, ?5, 'alpha-r2', 'unresolved', ?6, '["scheduledDate"]')`,
    ).bind(
      TENANT_ALPHA, MEMBER_ALPHA, DEVICE_ALPHA,
      JSON.stringify({ version: "device", scheduledDate: "2026-07-12" }),
      JSON.stringify({ version: "cloud", scheduledDate: "2026-07-13" }),
      "2026-07-10T10:00:00.000Z",
    ),
    env.DB.prepare(
      `INSERT INTO mileage_trips
         (id, tenant_id, member_id, originating_device_id, classification,
          started_at, updated_at, payload_json, deleted_at, created_at)
       VALUES ('migration-mileage-tombstone', ?1, ?2, ?3, 'business', ?4,
               ?5, NULL, ?5, ?4)`,
    ).bind(
      TENANT_ALPHA, MEMBER_ALPHA, DEVICE_ALPHA,
      "2026-07-08T08:00:00.000Z", "2026-07-08T09:00:00.000Z",
    ),
    env.DB.prepare(
      `INSERT INTO job_decline_reviews
         (id, tenant_id, assignment_id, job_id, job_number, customer_number,
          technician_member_id, technician_employee_id, originating_device_id,
          idempotency_key, reason, status, created_at, updated_at)
       VALUES ('migration-pending-review', ?1, 'assignment-1', 'job-1',
               'MIG-1', 'CUSTOMER-1', ?2, 'employee-1', ?3, 'decline-key-1',
               'Schedule conflict', 'pending', ?4, ?4)`,
    ).bind(
      TENANT_ALPHA, MEMBER_ALPHA, DEVICE_ALPHA, "2026-07-10T11:00:00.000Z",
    ),
  ]);
}

async function rows(sql: string, ...bindings: unknown[]): Promise<unknown[]> {
  const result = await env.DB.prepare(sql).bind(...bindings).all();
  return result.results;
}

describe("Phase 20 migration safety", () => {
  it("preserves legacy tenant state and backfills ordered tenant feeds", async () => {
    const prePhase20 = env.TEST_MIGRATIONS.filter(
      (migration) => migrationNumber(migration) <= 22,
    );
    const phase20 = env.TEST_MIGRATIONS.filter(
      (migration) => migrationNumber(migration) >= 23,
    );
    expect(prePhase20).toHaveLength(22);
    expect(phase20.map((migration) => migrationNumber(migration))).toEqual([
      23, 24, 25, 26, 27, 28, 29, 30,
    ]);

    await applyD1Migrations(env.DB, prePhase20);
    await seedPrePhase20Fixture();

    const acceptedBefore = await rows(
      `SELECT tenant_id, id, operation_type, entity_type, entity_id,
              payload_json, accepted_at, revision
         FROM synchronized_operations
        ORDER BY tenant_id, accepted_at, rowid`,
    );
    const recordsBefore = await rows(
      `SELECT tenant_id, entity_type, entity_id, revision, operation_json,
              updated_by_member_id, updated_by_device_id, updated_at
         FROM synchronized_records ORDER BY tenant_id, entity_type, entity_id`,
    );
    const conflictsBefore = await rows(
      `SELECT id, tenant_id, entity_type, entity_id, source_member_id,
              source_device_id, local_operation_json, cloud_operation_json,
              cloud_revision, status, detected_at, affected_fields_json
         FROM synchronization_conflicts ORDER BY id`,
    );
    const tombstonesBefore = await rows(
      `SELECT id, tenant_id, member_id, classification, payload_json, deleted_at
         FROM mileage_trips WHERE deleted_at IS NOT NULL ORDER BY id`,
    );
    const pendingReviewsBefore = await rows(
      `SELECT id, tenant_id, assignment_id, job_id, idempotency_key, reason,
              status, created_at, updated_at
         FROM job_decline_reviews WHERE status = 'pending' ORDER BY id`,
    );

    await applyD1Migrations(env.DB, phase20);

    expect(await rows(
      `SELECT tenant_id, id, operation_type, entity_type, entity_id,
              payload_json, accepted_at, revision
         FROM synchronized_operations
        ORDER BY tenant_id, accepted_at, rowid`,
    )).toEqual(acceptedBefore);
    expect(await rows(
      `SELECT tenant_id, entity_type, entity_id, revision, operation_json,
              updated_by_member_id, updated_by_device_id, updated_at
         FROM synchronized_records ORDER BY tenant_id, entity_type, entity_id`,
    )).toEqual(recordsBefore);
    expect(await rows(
      `SELECT id, tenant_id, entity_type, entity_id, source_member_id,
              source_device_id, local_operation_json, cloud_operation_json,
              cloud_revision, status, detected_at, affected_fields_json
         FROM synchronization_conflicts ORDER BY id`,
    )).toEqual(conflictsBefore);
    expect(await rows(
      `SELECT id, tenant_id, member_id, classification, payload_json, deleted_at
         FROM mileage_trips WHERE deleted_at IS NOT NULL ORDER BY id`,
    )).toEqual(tombstonesBefore);
    expect(await rows(
      `SELECT id, tenant_id, assignment_id, job_id, idempotency_key, reason,
              status, created_at, updated_at
         FROM job_decline_reviews WHERE status = 'pending' ORDER BY id`,
    )).toEqual(pendingReviewsBefore);

    expect(await rows(
      `SELECT tenant_id, tenant_sequence, operation_id, revision, payload_json
         FROM synchronization_change_log
        ORDER BY tenant_id, tenant_sequence`,
    )).toEqual([
      expect.objectContaining({ tenant_id: TENANT_ALPHA, tenant_sequence: 1, operation_id: "alpha-op-1", revision: "alpha-r1" }),
      expect.objectContaining({ tenant_id: TENANT_ALPHA, tenant_sequence: 2, operation_id: "alpha-op-2", revision: "alpha-r2" }),
      expect.objectContaining({ tenant_id: TENANT_ALPHA, tenant_sequence: 3, operation_id: "alpha-op-3", revision: "alpha-r3" }),
      expect.objectContaining({ tenant_id: TENANT_BETA, tenant_sequence: 1, operation_id: "beta-op-1", revision: "beta-r1" }),
      expect.objectContaining({ tenant_id: TENANT_BETA, tenant_sequence: 2, operation_id: "beta-op-2", revision: "beta-r2" }),
    ]);

    const feedCounts = await rows(
      `SELECT tenant_id, COUNT(*) AS count, MIN(tenant_sequence) AS minimum,
              MAX(tenant_sequence) AS maximum,
              COUNT(DISTINCT operation_id) AS distinct_operations
         FROM synchronization_change_log
        GROUP BY tenant_id ORDER BY tenant_id`,
    );
    expect(feedCounts).toEqual([
      { tenant_id: TENANT_ALPHA, count: 3, minimum: 1, maximum: 3, distinct_operations: 3 },
      { tenant_id: TENANT_BETA, count: 2, minimum: 1, maximum: 2, distinct_operations: 2 },
    ]);

    expect(await rows("PRAGMA foreign_key_check")).toEqual([]);
    expect(await rows(
      `SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN (
          'synchronization_device_cursors',
          'synchronization_quarantines',
          'synchronization_diagnostics',
          'synchronization_push_registrations',
          'synchronization_push_deliveries',
          'synchronization_device_health_reports',
          'synchronization_health_alerts'
        ) ORDER BY name`,
    )).toEqual([
      { name: "synchronization_device_cursors" },
      { name: "synchronization_device_health_reports" },
      { name: "synchronization_diagnostics" },
      { name: "synchronization_health_alerts" },
      { name: "synchronization_push_deliveries" },
      { name: "synchronization_push_registrations" },
      { name: "synchronization_quarantines" },
    ]);
  });
});
