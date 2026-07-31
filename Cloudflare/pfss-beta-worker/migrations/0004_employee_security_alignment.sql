ALTER TABLE tenant_members ADD COLUMN employee_id TEXT;

ALTER TABLE devices ADD COLUMN data_removal_required_at TEXT;
ALTER TABLE devices ADD COLUMN data_removal_acknowledged_at TEXT;

UPDATE devices
   SET data_removal_required_at = revoked_at
 WHERE revoked_at IS NOT NULL
   AND credentials_purged_at IS NULL;

CREATE UNIQUE INDEX idx_tenant_members_employee
    ON tenant_members(tenant_id, employee_id)
    WHERE employee_id IS NOT NULL;

CREATE INDEX idx_devices_data_removal
    ON devices(tenant_id, data_removal_required_at,
               data_removal_acknowledged_at);
