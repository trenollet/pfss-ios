ALTER TABLE tenant_members ADD COLUMN operations_archived_at TEXT;
ALTER TABLE tenant_members ADD COLUMN operations_removed_at TEXT;
ALTER TABLE devices ADD COLUMN operations_removed_at TEXT;

CREATE INDEX idx_tenant_members_operations_lifecycle
    ON tenant_members(tenant_id, operations_archived_at, operations_removed_at);
CREATE INDEX idx_devices_operations_removed
    ON devices(tenant_id, operations_removed_at);
