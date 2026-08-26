-- Phase 20: tenant-scoped quarantine review and durable source-device receipts.

CREATE TABLE IF NOT EXISTS synchronization_quarantines (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    operation_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    source_member_id TEXT NOT NULL,
    source_device_id TEXT NOT NULL,
    operation_json TEXT NOT NULL,
    cloud_operation_json TEXT,
    cloud_revision TEXT,
    failure_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unresolved',
    resolution_action TEXT,
    resolution_reason TEXT,
    resolved_by_member_id TEXT,
    resolved_by_device_id TEXT,
    resolver_role TEXT,
    policy_version INTEGER NOT NULL DEFAULT 1,
    detected_at TEXT NOT NULL,
    resolved_at TEXT,
    UNIQUE (tenant_id, source_device_id, operation_id),
    FOREIGN KEY (tenant_id, source_device_id)
        REFERENCES devices(tenant_id, id)
);

CREATE INDEX IF NOT EXISTS idx_sync_quarantines_tenant_status
    ON synchronization_quarantines (tenant_id, status, detected_at);

CREATE INDEX IF NOT EXISTS idx_sync_quarantines_source
    ON synchronization_quarantines (tenant_id, source_device_id, resolved_at);
