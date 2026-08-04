PRAGMA foreign_keys = ON;

-- Immutable administrative entitlement ledger. Superseding an override sets
-- revoked_at on the old row; the original plan, limits, reason, and actor are
-- never rewritten or deleted.
CREATE TABLE operations_plan_overrides (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
    administrator_id TEXT NOT NULL
        REFERENCES operations_administrators(id) ON DELETE RESTRICT,
    plan_code TEXT NOT NULL
        CHECK (plan_code IN ('beta', 'trial', 'base', 'pro', 'expert')),
    access_source TEXT NOT NULL
        CHECK (access_source IN ('betaGrant', 'planOverride')),
    entitlements_json TEXT NOT NULL,
    reason TEXT NOT NULL CHECK (length(trim(reason)) >= 10),
    effective_at TEXT NOT NULL,
    expires_at TEXT,
    revoked_at TEXT,
    revoked_by_administrator_id TEXT
        REFERENCES operations_administrators(id) ON DELETE RESTRICT,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_operations_plan_overrides_active
    ON operations_plan_overrides(tenant_id, effective_at DESC, expires_at);
