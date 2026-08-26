CREATE TABLE IF NOT EXISTS synchronization_push_registrations (
    tenant_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL,
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    app_build TEXT NOT NULL,
    registered_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    last_notified_at TEXT,
    last_failure_code TEXT,
    PRIMARY KEY (tenant_id, device_id),
    UNIQUE (environment, token),
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES devices(tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_push_tenant
    ON synchronization_push_registrations (tenant_id, environment);
