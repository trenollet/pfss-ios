# Synchronization Operations Health

Phase 20 exposes `GET /v1/sync/health` to authenticated Owner and Manager
devices. Employees cannot read tenant-wide operational health.

The endpoint is tenant scoped and returns operational metadata only. It never
returns synchronization payloads, record bodies, customer data, job data, or
conflict versions.

## Health levels

- `healthy`: the device matches the tenant change feed and no unresolved review
  or recent delivery failure requires attention.
- `delayed`: the device is behind or Apple accepted a background signal that the
  device has not acknowledged within two minutes.
- `actionRequired`: a device is at least 50 changes behind, remains behind for
  at least 30 minutes, the latest delivery failed, or an unresolved conflict or
  quarantined change requires authorized review.

The response includes the tenant server cursor, each active device's acknowledged
cursor and plain-language reasons, unresolved queue counts and oldest age, push
delivery totals for the last 24 hours, and seven-day conflict/quarantine trends
by entity, affected field, and quarantine reason.

Quarantined changes are the server's dead-letter equivalent. Schema and policy
failures remain visible through the aggregated quarantine-reason trend without
exposing the rejected operation. Push delivery data distinguishes provider
failure, Apple deferral, device receipt, and completed or failed synchronization.

Build 20.7.8 adds the client-facing Synchronization Health screen under Settings
> App Information for Owner and Manager devices. It preserves the endpoint's
plain-language classifications, provides recommended actions for delayed or
behind devices, and summarizes review queues, background delivery, and recent
problem trends. Employee devices do not receive the navigation link, and the
server independently denies employee access.

## Proactive operational alerts

Build 20.7.12 adds durable, tenant-scoped alerts for four conditions:

- tenant divergence when a device is at least 50 changes behind or remains
  behind for 30 minutes;
- stuck dependencies when queued work remains blocked for at least 15 minutes;
- excessive retries when a device reports at least 10 retries in 24 hours; and
- unresolved high-impact conflicts affecting operationally important fields.

Devices report payload-free queue health after synchronization. Reports contain
only counts, timestamps, app build, and retry/dependency totals; record content
is never uploaded. The Worker evaluates these reports and authoritative server
state, creates or reactivates one durable alert per condition, and automatically
resolves an alert after the condition clears. Critical thresholds identify more
severe or longer-lived conditions.

Active alerts appear at the top of the Owner/Manager Synchronization Health
screen with a plain-language explanation, recommended action, severity, and
first-observed time. Employee devices contribute their own health report but
cannot read tenant-wide health or alerts.

Signed-device acceptance on build 20.7.12 covered excessive retries, stuck
dependencies, tenant divergence, and an isolated test-only high-impact
conflict. Each condition appeared on an Owner iPhone17e and automatically
resolved after the employee iPad Pro mini's test condition was restored. Final
server verification showed all four durable alert records resolved, no active
alerts, and no unresolved conflicts.

Build 20.7.14 adds proactive discovery on the main Dashboard. Owner and Manager
devices check health when the Dashboard opens or the app becomes active. A
non-dismissible orange warning or red critical banner appears only while active
alerts exist, shows the number of issues in plain language, and opens
Synchronization Health directly. Refreshes from the health screen are shared
back to the Dashboard so the banner disappears immediately after the issue is
corrected. The client confirms its server role before requesting tenant health,
so employee devices neither fetch nor display the banner.

Signed build 20.7.14 acceptance confirmed the warning banner and direct health
navigation on an Owner iPhone17e, immediate removal after a Healthy refresh,
and no banner on an employee iPad Pro mini while the tenant alert was active.
The test-only conflict was removed afterward, with zero active alerts and zero
unresolved conflicts confirmed on the server.
