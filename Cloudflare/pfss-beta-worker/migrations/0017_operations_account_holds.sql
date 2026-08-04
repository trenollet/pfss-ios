PRAGMA foreign_keys = ON;

CREATE TABLE operations_account_lifecycle_events (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    administrator_id TEXT NOT NULL
        REFERENCES operations_administrators(id) ON DELETE RESTRICT,
    action TEXT NOT NULL CHECK (action IN ('hold', 'reactivate')),
    from_status TEXT NOT NULL,
    to_status TEXT NOT NULL,
    reason TEXT NOT NULL CHECK (length(trim(reason)) >= 10),
    hold_expires_at TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_operations_account_lifecycle_events
    ON operations_account_lifecycle_events(tenant_id, created_at DESC);
