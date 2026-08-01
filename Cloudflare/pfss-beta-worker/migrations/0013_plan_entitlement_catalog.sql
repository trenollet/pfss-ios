PRAGMA foreign_keys = ON;

CREATE TABLE plan_catalog (
    code TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    billing_mode TEXT NOT NULL
        CHECK (billing_mode IN ('complimentary', 'appStore', 'directEnterprise')),
    duration_days INTEGER CHECK (duration_days IS NULL OR duration_days > 0),
    monthly_price_cents INTEGER
        CHECK (monthly_price_cents IS NULL OR monthly_price_cents >= 0),
    user_limit INTEGER CHECK (user_limit IS NULL OR user_limit > 0),
    device_limit INTEGER CHECK (device_limit IS NULL OR device_limit > 0),
    lead_limit INTEGER CHECK (lead_limit IS NULL OR lead_limit > 0),
    customer_limit INTEGER CHECK (customer_limit IS NULL OR customer_limit > 0),
    job_limit INTEGER CHECK (job_limit IS NULL OR job_limit > 0),
    modules_json TEXT NOT NULL,
    catalog_version INTEGER NOT NULL,
    is_public INTEGER NOT NULL DEFAULT 1 CHECK (is_public IN (0, 1)),
    created_at TEXT NOT NULL,
    CHECK (
        billing_mode = 'directEnterprise'
        OR (user_limit IS NOT NULL AND device_limit IS NOT NULL)
    )
);

INSERT INTO plan_catalog
    (code, display_name, billing_mode, duration_days, monthly_price_cents,
     user_limit, device_limit, lead_limit, customer_limit, job_limit,
     modules_json, catalog_version, is_public, created_at)
VALUES
    ('beta-90-day', 'Beta Test', 'complimentary', 90, NULL,
     5, 10, 1000, 1000, 3000,
     '["sales","service","dispatch","reporting"]', 1, 0,
     '2026-08-01T00:00:00.000Z'),
    ('trial-14-day', 'Trial', 'appStore', 14, 0,
     2, 4, 5, 5, 10,
     '["sales","service","dispatch","reporting"]', 1, 1,
     '2026-08-01T00:00:00.000Z'),
    ('base-monthly', 'Base', 'appStore', NULL, 799,
     3, 6, 1000, 1000, 3000,
     '["sales","service","dispatch","reporting"]', 1, 1,
     '2026-08-01T00:00:00.000Z'),
    ('pro-monthly', 'Pro', 'appStore', NULL, 1499,
     5, 10, 3000, 3000, 9000,
     '["sales","service","dispatch","reporting"]', 1, 1,
     '2026-08-01T00:00:00.000Z'),
    ('expert-monthly', 'Expert', 'appStore', NULL, 2999,
     10, 20, 10000, 10000, 50000,
     '["sales","service","dispatch","reporting"]', 1, 1,
     '2026-08-01T00:00:00.000Z'),
    ('enterprise-custom', 'Enterprise / Custom', 'directEnterprise', NULL, NULL,
     NULL, NULL, NULL, NULL, NULL,
     '["sales","service","dispatch","reporting"]', 1, 0,
     '2026-08-01T00:00:00.000Z');

-- Existing Phase 17 staging companies receive the approved Beta Test limits.
UPDATE plan_allocations
   SET plan_code = 'beta-90-day',
       entitlements_json = '{"userLimit":5,"deviceLimit":10,"recordLimits":{"leads":1000,"customers":1000,"jobs":3000},"modules":["sales","service","dispatch","reporting"]}'
 WHERE access_source = 'betaGrant'
   AND revoked_at IS NULL;

CREATE INDEX idx_plan_catalog_public
    ON plan_catalog(is_public, monthly_price_cents);
