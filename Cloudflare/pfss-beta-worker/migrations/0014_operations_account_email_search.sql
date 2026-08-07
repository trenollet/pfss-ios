PRAGMA foreign_keys = ON;

-- Employee contact information is stored inside synchronized record payloads.
-- Materialize only the normalized email needed by the private Operations search
-- surface so account lookup never has to scan or expose full company records.
CREATE TABLE operations_account_email_index (
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    source_kind TEXT NOT NULL
        CHECK (source_kind IN ('employeeRecord')),
    source_id TEXT NOT NULL,
    normalized_email TEXT NOT NULL,
    display_name TEXT,
    role_hint TEXT,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, source_kind, source_id)
);

CREATE INDEX idx_operations_account_email_search
    ON operations_account_email_index(normalized_email, tenant_id);
