CREATE TABLE IF NOT EXISTS synchronization_push_deliveries (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    source_device_id TEXT NOT NULL,
    cursor INTEGER NOT NULL,
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    apns_request_id TEXT NOT NULL,
    apns_response_id TEXT,
    apns_unique_id TEXT,
    requested_at TEXT NOT NULL,
    accepted_at TEXT,
    failure_code TEXT,
    received_at TEXT,
    sync_started_at TEXT,
    sync_completed_at TEXT,
    sync_failed_at TEXT,
    device_reported_cursor INTEGER,
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES devices(tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_push_deliveries_device
    ON synchronization_push_deliveries
        (tenant_id, device_id, requested_at DESC);

