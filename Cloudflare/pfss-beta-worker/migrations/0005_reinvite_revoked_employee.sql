DROP INDEX idx_tenant_members_employee;

CREATE UNIQUE INDEX idx_tenant_members_employee
    ON tenant_members(tenant_id, employee_id)
    WHERE employee_id IS NOT NULL
      AND status != 'revoked';
