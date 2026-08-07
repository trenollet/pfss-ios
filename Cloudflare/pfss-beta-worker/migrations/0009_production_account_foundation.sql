PRAGMA foreign_keys = ON;

CREATE TABLE authentication_subjects (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('pending', 'active', 'locked', 'disabled')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE authentication_identities (
    id TEXT PRIMARY KEY,
    subject_id TEXT NOT NULL
        REFERENCES authentication_subjects(id) ON DELETE CASCADE,
    provider_key TEXT NOT NULL,
    provider_subject TEXT NOT NULL,
    method TEXT NOT NULL
        CHECK (method IN ('password', 'passkey', 'signInWithApple', 'federated')),
    created_at TEXT NOT NULL,
    last_authenticated_at TEXT,
    UNIQUE (provider_key, provider_subject)
);

CREATE TABLE verified_contact_addresses (
    id TEXT PRIMARY KEY,
    subject_id TEXT NOT NULL
        REFERENCES authentication_subjects(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('email', 'phone')),
    normalized_value TEXT NOT NULL,
    verified_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE (kind, normalized_value)
);

CREATE TABLE account_recovery_methods (
    id TEXT PRIMARY KEY,
    subject_id TEXT NOT NULL
        REFERENCES authentication_subjects(id) ON DELETE CASCADE,
    kind TEXT NOT NULL
        CHECK (kind IN ('verifiedEmail', 'verifiedPhone', 'recoveryCode')),
    secret_digest TEXT,
    created_at TEXT NOT NULL,
    last_used_at TEXT,
    revoked_at TEXT
);

CREATE TABLE account_registration_attempts (
    id TEXT PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    request_fingerprint TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'started'
        CHECK (status IN (
            'started', 'identityVerified', 'profileComplete',
            'planAuthorized', 'provisioning', 'active', 'expired',
            'cancelled', 'failedRolledBack'
        )),
    normalized_email TEXT NOT NULL,
    owner_display_name TEXT NOT NULL,
    company_display_name TEXT NOT NULL,
    normalized_company_name TEXT NOT NULL,
    time_zone_id TEXT NOT NULL,
    requested_plan_code TEXT NOT NULL,
    identity_assertion_digest TEXT NOT NULL,
    registration_token_digest TEXT NOT NULL,
    authentication_method TEXT NOT NULL
        CHECK (authentication_method IN (
            'password', 'passkey', 'signInWithApple', 'federated'
        )),
    device_id TEXT NOT NULL,
    device_display_name TEXT NOT NULL,
    subject_id TEXT REFERENCES authentication_subjects(id),
    tenant_id TEXT REFERENCES tenants(id),
    expires_at TEXT NOT NULL,
    completed_at TEXT,
    cancelled_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE legal_consents (
    id TEXT PRIMARY KEY,
    subject_id TEXT REFERENCES authentication_subjects(id),
    registration_attempt_id TEXT NOT NULL
        REFERENCES account_registration_attempts(id) ON DELETE CASCADE,
    terms_version TEXT NOT NULL,
    privacy_version TEXT NOT NULL,
    accepted_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE subscription_accounts (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL UNIQUE
        REFERENCES tenants(id) ON DELETE CASCADE,
    provider_key TEXT,
    provider_customer_reference TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending', 'trialing', 'active', 'pastDue', 'suspended',
            'cancelled'
        )),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (provider_key, provider_customer_reference)
);

CREATE TABLE plan_allocations (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    subscription_account_id TEXT
        REFERENCES subscription_accounts(id) ON DELETE CASCADE,
    access_source TEXT NOT NULL
        CHECK (access_source IN (
            'appStoreSubscription', 'betaGrant', 'internalTesting',
            'internalBusinessGrant', 'promotionalGrant'
        )),
    source_reference TEXT,
    plan_code TEXT NOT NULL,
    entitlements_json TEXT NOT NULL DEFAULT '{}',
    effective_at TEXT NOT NULL,
    expires_at TEXT,
    granted_by_subject_id TEXT REFERENCES authentication_subjects(id),
    grant_reason TEXT,
    revoked_at TEXT,
    revoked_by_subject_id TEXT REFERENCES authentication_subjects(id),
    created_at TEXT NOT NULL,
    CHECK (
        (access_source = 'appStoreSubscription'
            AND subscription_account_id IS NOT NULL
            AND granted_by_subject_id IS NULL
            AND grant_reason IS NULL)
        OR
        (access_source != 'appStoreSubscription'
            AND subscription_account_id IS NULL
            AND granted_by_subject_id IS NOT NULL
            AND length(trim(grant_reason)) > 0)
    )
);

ALTER TABLE tenant_members ADD COLUMN authentication_subject_id TEXT
    REFERENCES authentication_subjects(id);

CREATE INDEX idx_auth_identities_subject
    ON authentication_identities(subject_id);
CREATE INDEX idx_verified_contacts_subject
    ON verified_contact_addresses(subject_id);
CREATE INDEX idx_recovery_methods_subject_active
    ON account_recovery_methods(subject_id, revoked_at);
CREATE INDEX idx_registration_status_expiry
    ON account_registration_attempts(status, expires_at);
CREATE INDEX idx_registration_email_created
    ON account_registration_attempts(normalized_email, created_at);
CREATE INDEX idx_registration_company_created
    ON account_registration_attempts(normalized_company_name, created_at);
CREATE INDEX idx_members_authentication_subject
    ON tenant_members(authentication_subject_id);
CREATE INDEX idx_plan_allocations_account_effective
    ON plan_allocations(subscription_account_id, effective_at DESC);
CREATE INDEX idx_plan_allocations_tenant_effective
    ON plan_allocations(tenant_id, effective_at DESC);
CREATE UNIQUE INDEX idx_plan_allocations_active_internal_business
    ON plan_allocations(tenant_id)
    WHERE access_source = 'internalBusinessGrant' AND revoked_at IS NULL;
