CREATE TABLE IF NOT EXISTS job_decline_reviews (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    assignment_id TEXT NOT NULL,
    job_id TEXT NOT NULL,
    job_number TEXT NOT NULL,
    customer_number TEXT NOT NULL,
    technician_member_id TEXT NOT NULL,
    technician_employee_id TEXT NOT NULL,
    originating_device_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'resolved')),
    resolution_action TEXT CHECK (
        resolution_action IS NULL OR resolution_action IN (
            'reassigned', 'rescheduled', 'returned', 'cancelled'
        )
    ),
    resolution_note TEXT,
    resolved_by_member_id TEXT,
    resolved_by_device_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    resolved_at TEXT,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE (tenant_id, idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_job_decline_one_pending_assignment
    ON job_decline_reviews(tenant_id, assignment_id)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_job_decline_pending_tenant
    ON job_decline_reviews(tenant_id, status, created_at);

CREATE INDEX IF NOT EXISTS idx_job_decline_technician
    ON job_decline_reviews(tenant_id, technician_member_id, status, created_at);

CREATE TABLE IF NOT EXISTS job_decline_review_events (
    id TEXT PRIMARY KEY,
    review_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('submitted', 'resolved')),
    actor_member_id TEXT NOT NULL,
    actor_device_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (review_id) REFERENCES job_decline_reviews(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_job_decline_events_review
    ON job_decline_review_events(review_id, created_at);
