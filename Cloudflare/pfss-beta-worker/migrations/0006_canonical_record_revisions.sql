PRAGMA foreign_keys = ON;

CREATE TABLE synchronized_records (
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    revision TEXT NOT NULL,
    operation_json TEXT NOT NULL,
    updated_by_member_id TEXT NOT NULL,
    updated_by_device_id TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, entity_type, entity_id),
    FOREIGN KEY (tenant_id, updated_by_device_id)
        REFERENCES devices(tenant_id, id)
);

CREATE INDEX idx_synchronized_records_tenant_updated
    ON synchronized_records(tenant_id, updated_at);
