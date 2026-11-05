-- One tenant-scoped commit owns all superseded bills and receipt events.
-- CHECK guards make stale-source failures abort the entire D1 batch.
CREATE TABLE invoice_combination_commits (
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    request_id TEXT NOT NULL,
    invoice_id TEXT NOT NULL,
    invoice_number TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    result_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, request_id),
    UNIQUE (tenant_id, invoice_id),
    UNIQUE (tenant_id, invoice_number)
);
CREATE TABLE invoice_combination_sources (
    tenant_id TEXT NOT NULL,
    source_invoice_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    revision_guard INTEGER NOT NULL CHECK (revision_guard = 1),
    PRIMARY KEY (tenant_id, source_invoice_id),
    FOREIGN KEY (tenant_id, request_id)
        REFERENCES invoice_combination_commits(tenant_id, request_id) ON DELETE CASCADE
);
CREATE TABLE invoice_combination_payment_events (
    tenant_id TEXT NOT NULL,
    payment_event_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    PRIMARY KEY (tenant_id, payment_event_id),
    FOREIGN KEY (tenant_id, request_id)
        REFERENCES invoice_combination_commits(tenant_id, request_id) ON DELETE CASCADE
);
