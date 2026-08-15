-- Phase 19: user-private mileage backup and same-user device synchronization.

CREATE TABLE mileage_trips (
    id TEXT NOT NULL,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    member_id TEXT NOT NULL,
    originating_device_id TEXT NOT NULL,
    classification TEXT NOT NULL
        CHECK (classification IN ('unclassified', 'business', 'personal')),
    started_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    payload_json TEXT,
    deleted_at TEXT,
    created_at TEXT NOT NULL,
    PRIMARY KEY (tenant_id, member_id, id),
    FOREIGN KEY (tenant_id, member_id)
        REFERENCES tenant_members(tenant_id, id)
);

CREATE INDEX idx_mileage_trips_user_started
    ON mileage_trips(tenant_id, member_id, started_at DESC);

CREATE TABLE mileage_trip_changes (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    trip_id TEXT NOT NULL,
    change_type TEXT NOT NULL CHECK (change_type IN ('upsert', 'delete')),
    payload_json TEXT,
    changed_at TEXT NOT NULL,
    FOREIGN KEY (tenant_id, member_id, trip_id)
        REFERENCES mileage_trips(tenant_id, member_id, id)
);

CREATE INDEX idx_mileage_trip_changes_user_sequence
    ON mileage_trip_changes(tenant_id, member_id, sequence);
