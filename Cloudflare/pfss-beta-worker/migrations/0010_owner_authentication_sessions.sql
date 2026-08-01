PRAGMA foreign_keys = ON;

CREATE TABLE owner_authorization_attempts (
    id TEXT PRIMARY KEY,
    state_digest TEXT NOT NULL UNIQUE,
    code_challenge TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    email_hint TEXT,
    status TEXT NOT NULL DEFAULT 'started'
        CHECK (status IN ('started', 'verified', 'consumed', 'expired', 'failed')),
    subject_id TEXT REFERENCES authentication_subjects(id),
    subject_was_created INTEGER NOT NULL DEFAULT 0
        CHECK (subject_was_created IN (0, 1)),
    identity_assertion_digest TEXT UNIQUE,
    provider_method TEXT,
    expires_at TEXT NOT NULL,
    verified_at TEXT,
    consumed_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

ALTER TABLE account_registration_attempts
    ADD COLUMN owner_authorization_attempt_id TEXT
        REFERENCES owner_authorization_attempts(id);

CREATE INDEX idx_owner_authorization_expiry
    ON owner_authorization_attempts(status, expires_at);

CREATE UNIQUE INDEX idx_registration_owner_authorization
    ON account_registration_attempts(owner_authorization_attempt_id)
    WHERE owner_authorization_attempt_id IS NOT NULL;
