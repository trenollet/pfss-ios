CREATE TABLE IF NOT EXISTS synchronization_device_reminder_preferences (
    tenant_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('snoozed', 'disabled')),
    suppressed_until TEXT,
    updated_by_member_id TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, device_id),
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES devices(tenant_id, id) ON DELETE CASCADE,
    FOREIGN KEY (updated_by_member_id)
        REFERENCES tenant_members(id) ON DELETE RESTRICT,
    CHECK (
        (mode = 'snoozed' AND suppressed_until IS NOT NULL) OR
        (mode = 'disabled' AND suppressed_until IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_sync_device_reminder_preferences_tenant
    ON synchronization_device_reminder_preferences (tenant_id, mode, suppressed_until);
