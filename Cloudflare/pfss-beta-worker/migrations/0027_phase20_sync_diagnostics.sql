CREATE TABLE synchronization_diagnostics (
    id TEXT PRIMARY KEY,
    case_code TEXT NOT NULL UNIQUE,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    source_member_id TEXT NOT NULL REFERENCES tenant_members(id),
    source_device_id TEXT NOT NULL,
    source_role TEXT NOT NULL CHECK (source_role IN ('owner', 'manager', 'member')),
    description TEXT,
    object_key TEXT NOT NULL UNIQUE,
    byte_size INTEGER NOT NULL CHECK (byte_size > 0 AND byte_size <= 262144),
    app_version TEXT NOT NULL,
    build_number TEXT NOT NULL,
    system_version TEXT NOT NULL,
    device_model TEXT NOT NULL,
    submitted_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    deleted_at TEXT,
    deleted_by_member_id TEXT REFERENCES tenant_members(id),
    FOREIGN KEY (tenant_id, source_device_id)
        REFERENCES devices(tenant_id, id)
);

CREATE INDEX idx_sync_diagnostics_tenant_submitted
    ON synchronization_diagnostics(tenant_id, submitted_at DESC);

CREATE INDEX idx_sync_diagnostics_source
    ON synchronization_diagnostics(
        tenant_id, source_member_id, source_device_id, submitted_at DESC
    );

CREATE INDEX idx_sync_diagnostics_expiration
    ON synchronization_diagnostics(expires_at, deleted_at);
