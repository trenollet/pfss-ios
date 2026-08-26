CREATE TABLE IF NOT EXISTS synchronization_device_health_reports (
    tenant_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    app_build TEXT NOT NULL,
    queue_count INTEGER NOT NULL,
    oldest_queued_at TEXT,
    failed_count INTEGER NOT NULL,
    waiting_retry_count INTEGER NOT NULL,
    retry_attempts_24h INTEGER NOT NULL,
    blocked_dependency_count INTEGER NOT NULL,
    conflicted_count INTEGER NOT NULL,
    quarantined_count INTEGER NOT NULL,
    reported_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, device_id),
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES devices(tenant_id, id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS synchronization_health_alerts (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id TEXT,
    fingerprint TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (
        'tenantDivergence', 'stuckDependencies', 'excessiveRetries',
        'highImpactConflict'
    )),
    severity TEXT NOT NULL CHECK (severity IN ('warning', 'critical')),
    status TEXT NOT NULL CHECK (status IN ('active', 'resolved')),
    title TEXT NOT NULL,
    detail TEXT NOT NULL,
    recommendation TEXT NOT NULL,
    observed_value INTEGER NOT NULL,
    threshold_value INTEGER NOT NULL,
    opened_at TEXT NOT NULL,
    last_observed_at TEXT NOT NULL,
    resolved_at TEXT,
    UNIQUE (tenant_id, fingerprint),
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES devices(tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_health_alerts_tenant_status
    ON synchronization_health_alerts (tenant_id, status, severity, opened_at);

