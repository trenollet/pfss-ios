PRAGMA foreign_keys = ON;

CREATE TABLE synchronization_conflicts (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    source_member_id TEXT NOT NULL,
    source_device_id TEXT NOT NULL,
    local_operation_json TEXT NOT NULL,
    cloud_operation_json TEXT NOT NULL,
    cloud_revision TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unresolved'
        CHECK (status IN ('unresolved', 'keptCloud', 'keptDevice')),
    detected_at TEXT NOT NULL,
    resolved_at TEXT,
    resolved_by_member_id TEXT,
    resolved_by_device_id TEXT
);

CREATE INDEX idx_sync_conflicts_tenant_status_detected
    ON synchronization_conflicts(tenant_id, status, detected_at);

CREATE UNIQUE INDEX idx_sync_conflicts_one_unresolved_source_record
    ON synchronization_conflicts(
        tenant_id, source_device_id, entity_type, entity_id
    )
    WHERE status = 'unresolved';
