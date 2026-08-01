PRAGMA foreign_keys = ON;

ALTER TABLE subscription_accounts ADD COLUMN product_id TEXT;
ALTER TABLE subscription_accounts ADD COLUMN original_transaction_id TEXT;
ALTER TABLE subscription_accounts ADD COLUMN app_store_environment TEXT
    CHECK (app_store_environment IN ('sandbox', 'production'));
ALTER TABLE subscription_accounts ADD COLUMN current_period_expires_at TEXT;

CREATE UNIQUE INDEX idx_subscription_app_store_original_transaction
    ON subscription_accounts(app_store_environment, original_transaction_id)
    WHERE provider_key = 'appStore';

CREATE TABLE app_store_notification_events (
    notification_uuid TEXT PRIMARY KEY,
    notification_type TEXT NOT NULL,
    subtype TEXT,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    original_transaction_id TEXT NOT NULL,
    signed_payload_sha256 TEXT NOT NULL,
    signed_at TEXT NOT NULL,
    processed_at TEXT NOT NULL
);

CREATE INDEX idx_app_store_notifications_tenant_processed
    ON app_store_notification_events(tenant_id, processed_at DESC);
