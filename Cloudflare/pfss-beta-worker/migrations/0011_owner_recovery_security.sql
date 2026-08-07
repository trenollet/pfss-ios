PRAGMA foreign_keys = ON;

CREATE UNIQUE INDEX idx_active_recovery_code_digest
    ON account_recovery_methods(secret_digest)
    WHERE kind = 'recoveryCode'
      AND secret_digest IS NOT NULL
      AND last_used_at IS NULL
      AND revoked_at IS NULL;

CREATE TABLE owner_recovery_attempts (
    id TEXT PRIMARY KEY,
    recovery_method_id TEXT
        REFERENCES account_recovery_methods(id),
    subject_id TEXT
        REFERENCES authentication_subjects(id),
    device_id TEXT NOT NULL,
    status TEXT NOT NULL
        CHECK (status IN ('succeeded', 'failed')),
    created_at TEXT NOT NULL
);

CREATE INDEX idx_owner_recovery_attempts_subject_created
    ON owner_recovery_attempts(subject_id, created_at DESC);
