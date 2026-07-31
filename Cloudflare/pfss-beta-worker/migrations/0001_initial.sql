PRAGMA foreign_keys = ON;

CREATE TABLE tenants (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    created_at TEXT NOT NULL
);

CREATE TABLE enrollment_codes (
    code_hash TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL,
    redeemed_at TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE devices (
    id TEXT NOT NULL,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    revoked_at TEXT,
    PRIMARY KEY (tenant_id, id)
);

CREATE TABLE synchronized_operations (
    id TEXT NOT NULL,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    operation_type TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    action_name TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    accepted_at TEXT NOT NULL,
    revision TEXT NOT NULL,
    PRIMARY KEY (tenant_id, id),
    UNIQUE (tenant_id, idempotency_key),
    FOREIGN KEY (tenant_id, device_id) REFERENCES devices(tenant_id, id)
);

CREATE INDEX idx_devices_token_hash ON devices(token_hash);
CREATE INDEX idx_operations_tenant_accepted
    ON synchronized_operations(tenant_id, accepted_at);
