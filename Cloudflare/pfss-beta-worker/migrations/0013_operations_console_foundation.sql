PRAGMA foreign_keys = ON;

-- PFSS Operations is a separate privileged control plane. Administrators are
-- invited out-of-band and claim their record only after WorkOS verifies the
-- exact email address. No customer membership or device credential grants
-- Operations access.
CREATE TABLE operations_administrators (
    id TEXT PRIMARY KEY,
    normalized_email TEXT NOT NULL UNIQUE,
    provider_subject TEXT UNIQUE,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL
        CHECK (role IN (
            'platformOwner', 'supportAdministrator',
            'billingAdministrator', 'readOnlyAuditor'
        )),
    status TEXT NOT NULL DEFAULT 'invited'
        CHECK (status IN ('invited', 'active', 'suspended', 'revoked')),
    created_at TEXT NOT NULL,
    activated_at TEXT,
    updated_at TEXT NOT NULL,
    revoked_at TEXT
);

CREATE TABLE operations_authorization_attempts (
    id TEXT PRIMARY KEY,
    state_digest TEXT NOT NULL UNIQUE,
    code_challenge TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'started'
        CHECK (status IN ('started', 'consumed', 'expired', 'failed')),
    expires_at TEXT NOT NULL,
    consumed_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE operations_sessions (
    id TEXT PRIMARY KEY,
    administrator_id TEXT NOT NULL
        REFERENCES operations_administrators(id) ON DELETE CASCADE,
    token_digest TEXT NOT NULL UNIQUE,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    UNIQUE (administrator_id, device_id)
);

CREATE TABLE operations_audit_events (
    id TEXT PRIMARY KEY,
    administrator_id TEXT
        REFERENCES operations_administrators(id),
    event_type TEXT NOT NULL,
    target_tenant_id TEXT REFERENCES tenants(id),
    target_member_id TEXT REFERENCES tenant_members(id),
    outcome TEXT NOT NULL CHECK (outcome IN ('succeeded', 'rejected', 'failed')),
    reason TEXT,
    request_id TEXT NOT NULL,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL
);

-- This control record extends the original active/suspended tenant state
-- without weakening the existing synchronization authorization checks.
CREATE TABLE platform_account_controls (
    tenant_id TEXT PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    lifecycle_status TEXT NOT NULL DEFAULT 'active'
        CHECK (lifecycle_status IN (
            'active', 'billingHold', 'securityHold', 'supportHold',
            'archived', 'deletionPending'
        )),
    reason TEXT,
    hold_expires_at TEXT,
    archived_at TEXT,
    deletion_scheduled_at TEXT,
    updated_by_administrator_id TEXT
        REFERENCES operations_administrators(id),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_operations_admin_status
    ON operations_administrators(status, role);
CREATE INDEX idx_operations_authorization_expiry
    ON operations_authorization_attempts(status, expires_at);
CREATE INDEX idx_operations_sessions_token
    ON operations_sessions(token_digest, expires_at, revoked_at);
CREATE INDEX idx_operations_audit_created
    ON operations_audit_events(created_at DESC);
CREATE INDEX idx_operations_audit_target
    ON operations_audit_events(target_tenant_id, created_at DESC);
CREATE INDEX idx_platform_account_lifecycle
    ON platform_account_controls(lifecycle_status, updated_at DESC);
