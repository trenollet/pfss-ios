CREATE TABLE tenant_members (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'member')),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('invited', 'active', 'suspended', 'revoked')),
    created_at TEXT NOT NULL,
    activated_at TEXT,
    revoked_at TEXT,
    UNIQUE (tenant_id, id)
);

ALTER TABLE devices ADD COLUMN member_id TEXT REFERENCES tenant_members(id);
ALTER TABLE enrollment_codes ADD COLUMN member_id TEXT REFERENCES tenant_members(id);

INSERT INTO tenant_members
    (id, tenant_id, display_name, role, status, created_at, activated_at)
SELECT id || ':owner', id, display_name || ' Owner', 'owner', 'active',
       created_at, created_at
  FROM tenants;

UPDATE devices
   SET member_id = tenant_id || ':owner'
 WHERE member_id IS NULL;

UPDATE enrollment_codes
   SET member_id = tenant_id || ':owner'
 WHERE member_id IS NULL;

CREATE INDEX idx_tenant_members_tenant_status
    ON tenant_members(tenant_id, status);
CREATE INDEX idx_devices_tenant_member
    ON devices(tenant_id, member_id);
