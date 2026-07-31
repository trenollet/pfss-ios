ALTER TABLE enrollment_codes ADD COLUMN cancelled_at TEXT;
ALTER TABLE enrollment_codes ADD COLUMN cancelled_by_member_id TEXT
    REFERENCES tenant_members(id);

ALTER TABLE devices ADD COLUMN credentials_purged_at TEXT;

CREATE TABLE access_audit_events (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    actor_member_id TEXT REFERENCES tenant_members(id),
    actor_device_id TEXT,
    event_type TEXT NOT NULL,
    target_member_id TEXT REFERENCES tenant_members(id),
    target_device_id TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL
);

CREATE INDEX idx_enrollment_codes_lifecycle
    ON enrollment_codes(tenant_id, expires_at, redeemed_at, cancelled_at);
CREATE INDEX idx_devices_revocation_cleanup
    ON devices(tenant_id, revoked_at, credentials_purged_at);
CREATE INDEX idx_access_audit_tenant_created
    ON access_audit_events(tenant_id, created_at);
