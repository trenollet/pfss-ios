PRAGMA foreign_keys = ON;

CREATE TABLE owner_account_invitations (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    member_id TEXT NOT NULL REFERENCES tenant_members(id) ON DELETE CASCADE,
    invited_email TEXT NOT NULL,
    invitation_digest TEXT NOT NULL UNIQUE,
    created_by_member_id TEXT NOT NULL REFERENCES tenant_members(id),
    expires_at TEXT NOT NULL,
    accepted_at TEXT,
    cancelled_at TEXT,
    created_at TEXT NOT NULL,
    CHECK (accepted_at IS NULL OR cancelled_at IS NULL)
);

CREATE UNIQUE INDEX idx_pending_owner_invitation_email
    ON owner_account_invitations(tenant_id, invited_email)
    WHERE accepted_at IS NULL AND cancelled_at IS NULL;

CREATE INDEX idx_owner_invitation_lifecycle
    ON owner_account_invitations(tenant_id, expires_at, accepted_at, cancelled_at);
