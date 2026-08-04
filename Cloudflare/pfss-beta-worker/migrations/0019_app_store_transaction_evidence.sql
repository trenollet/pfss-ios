PRAGMA foreign_keys = ON;

-- StoreKit sends Apple-signed JWS evidence to this inbox. Evidence alone never
-- grants access; a server verifier must validate it before changing an
-- App Store subscription account or plan allocation.
CREATE TABLE app_store_transaction_evidence (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    submitted_by_member_id TEXT NOT NULL REFERENCES tenant_members(id),
    submitted_by_device_id TEXT NOT NULL,
    plan_code TEXT NOT NULL REFERENCES plan_catalog(code),
    product_id TEXT NOT NULL,
    signed_transaction TEXT NOT NULL,
    signed_transaction_sha256 TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'pendingVerification'
        CHECK (status IN ('pendingVerification', 'verified', 'rejected')),
    submitted_at TEXT NOT NULL,
    verified_at TEXT,
    rejection_reason TEXT,
    FOREIGN KEY (tenant_id, submitted_by_device_id)
        REFERENCES devices(tenant_id, id)
);

CREATE INDEX idx_app_store_evidence_tenant_status
    ON app_store_transaction_evidence(tenant_id, status, submitted_at DESC);
