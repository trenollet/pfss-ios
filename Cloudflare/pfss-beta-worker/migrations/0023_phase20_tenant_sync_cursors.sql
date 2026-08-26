-- Phase 20 Step 4: tenant-scoped change feed and durable device cursors.

CREATE TABLE IF NOT EXISTS synchronization_change_log (
    tenant_id TEXT NOT NULL,
    tenant_sequence INTEGER NOT NULL,
    operation_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    revision TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    accepted_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, tenant_sequence),
    UNIQUE (tenant_id, operation_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_change_log_tenant_sequence
    ON synchronization_change_log (tenant_id, tenant_sequence);

CREATE TABLE IF NOT EXISTS synchronization_device_cursors (
    tenant_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    acknowledged_sequence INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, device_id)
);

-- Preserve the existing accepted history. ROW_NUMBER creates an independent,
-- gap-free sequence for every tenant even though the legacy feed used global
-- SQLite rowids.
INSERT OR IGNORE INTO synchronization_change_log
    (tenant_id, tenant_sequence, operation_id, device_id, revision,
     payload_json, accepted_at)
SELECT tenant_id,
       ROW_NUMBER() OVER (
           PARTITION BY tenant_id
           ORDER BY accepted_at ASC, rowid ASC
       ),
       id, device_id, revision, payload_json, accepted_at
  FROM synchronized_operations;
