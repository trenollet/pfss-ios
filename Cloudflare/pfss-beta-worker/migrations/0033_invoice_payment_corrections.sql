CREATE TABLE invoice_payment_corrections (
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    request_id TEXT NOT NULL,
    root_invoice_id TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    result_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, request_id)
);
CREATE TABLE invoice_payment_correction_guards (
    tenant_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    revision_guard INTEGER NOT NULL CHECK (revision_guard = 1),
    PRIMARY KEY (tenant_id, request_id, entity_type, entity_id),
    FOREIGN KEY (tenant_id, request_id)
        REFERENCES invoice_payment_corrections(tenant_id, request_id) ON DELETE CASCADE
);
