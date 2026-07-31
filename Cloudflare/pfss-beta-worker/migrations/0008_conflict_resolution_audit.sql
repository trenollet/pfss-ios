ALTER TABLE synchronization_conflicts ADD COLUMN resolver_role TEXT;
ALTER TABLE synchronization_conflicts ADD COLUMN resolution_reason TEXT;
ALTER TABLE synchronization_conflicts ADD COLUMN affected_fields_json TEXT
    NOT NULL DEFAULT '[]';
ALTER TABLE synchronization_conflicts ADD COLUMN final_revision TEXT;

CREATE INDEX idx_sync_conflicts_tenant_resolved
    ON synchronization_conflicts(tenant_id, resolved_at DESC);
