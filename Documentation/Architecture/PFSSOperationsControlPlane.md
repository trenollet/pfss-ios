# PFSS Operations Control Plane

- Status: Phase 17 Step 8b complete
- Client: Private iPhone/iPad application
- Server boundary: `/v1/operations-*`
- Public distribution: Prohibited

## Purpose

PFSS Operations is the private control plane for platform support, complimentary
access, account lifecycle, usage visibility, and incident response. It is a
separate application and authorization domain from customer PFSS devices.

## Security Invariants

- Customer Owner, Manager, employee, and device credentials never authorize an
  Operations endpoint.
- WorkOS verifies the administrator, but PFSS separately requires an active
  allow-listed `operations_administrators` record.
- The app stores only a revocable, eight-hour Operations session in
  this-device-only Keychain storage.
- WorkOS API keys, Cloudflare tokens, database credentials, and entitlement
  authority never enter the app bundle.
- Every privileged mutation must create an `operations_audit_events` record
  with actor, target, reason, outcome, request ID, and timestamp.
- Permanent deletion will require a staged workflow and cannot be exposed as a
  single immediate action.
- Privileged mutations require role authorization, a recorded reason, explicit
  confirmation where destructive, and immutable audit data.

## Administrator Roles

- `platformOwner`: all control-plane authority, including future destructive
  workflows requiring reauthentication.
- `supportAdministrator`: account recovery and diagnostics without billing or
  permanent deletion authority.
- `billingAdministrator`: plan and entitlement management without customer-data
  access.
- `readOnlyAuditor`: account, usage, error, and audit visibility only.

## Foundation Delivered

- Migration `0013_operations_console_foundation.sql` adds administrators,
  authorization attempts, sessions, immutable audit events, and account
  lifecycle controls.
- Migrations `0014` through `0017` add cross-account email discovery,
  member/device lifecycle controls, immutable plan overrides, and account
  hold/reactivation history.
- WorkOS authorization uses a separate client ID, secret, and callback allowlist.
- Endpoints expose session, platform monitoring, a searchable/filterable account
  directory, tenant-scoped account detail, audited plan/hold/recovery/access
  controls, and protected account archival/deletion scheduling.
- The private SwiftUI project is located at
  `PFSS Operations/PFSS Operations.xcodeproj` and supports iPhone and iPad.

## Deployment Requirements

1. Create a dedicated WorkOS staging application for PFSS Operations.
2. Register `https://auth-staging.patriot-ok.com/operations-callback/`.
3. Store its API key as `WORKOS_OPERATIONS_API_KEY` in the Worker secret store.
4. Configure `WORKOS_OPERATIONS_CLIENT_ID` as a non-secret Worker value.
5. Apply D1 migration `0013`.
6. Insert the first invited administrator by normalized email; the verified
   WorkOS subject claims that record during first sign-in.
7. Deploy the updated callback site and Worker.
8. Build and sign the private app using bundle ID
   `com.patriot.PFSS-Operations`.

## Delivered Operations Sequence

1. Temporary and permanent beta/plan grants with expiration and reason.
2. Billing, security, and support holds plus safe reactivation.
3. WorkOS-backed recovery initiation and session revocation.
4. User/device suspension, revocation, archive, and protected removal.
5. Account archive, deletion-pending, cooling-off, and cancellation.
6. Provider and account usage monitoring, threshold alerts, and summary errors.

The Overview stays intentionally compact as the platform grows. Provider usage
uses adaptive fuel-gauge cards. Accounts and summary errors each open a
dedicated searchable page with ascending/descending date ordering; Accounts
also retain lifecycle-status filtering.

Provider metrics clearly identify their source. R2 storage is measured directly;
WorkOS monthly activity is PFSS-observed; Cloudflare Worker-request and D1
read/write counters come from its GraphQL Analytics API using a Worker-secret,
Account Analytics read-only token. Configured staging reference limits are
100,000 Worker requests/day, 5 million D1 rows read/day, 100,000 D1 rows
written/day, 10 GB R2 storage/month, and 1,000,000 WorkOS AuthKit monthly
active users.
