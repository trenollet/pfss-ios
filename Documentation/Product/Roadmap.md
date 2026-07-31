# PFSS Product Roadmap

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-07-31

## Current Foundation

PFSS currently includes customers, sites, leads, estimates, jobs, invoices, a service and material catalog, local persistence, archiving, reusable WorkOrder components, pricing calculations, catalog ranking, recommendation rules, guided job workflow, workforce and scheduling foundations, route planning foundations, and automatic job time tracking.

## v0.9.6 — Brick 9: Automatic Time Tracking

**Status:** Completed

Delivered:

- Setup phase in the guided workflow
- Automatic time tracking from existing workflow actions
- Job History Report
- Invoice workflow regression fixes
- Resilient elapsed-time calculation for older records

## Brick 10 — Editing and UI Consistency

**Status:** Planned / Deferred

This brick remains approved but is not the active implementation focus.

Goals:

- Persistent top-right Save action on editable screens
- Shared edit-screen behavior
- Dirty-state tracking where practical
- Consistent handling of unsaved changes
- Standard button roles and treatments
- Consistent form spacing, sections, icons, and status presentation
- Review saved job and estimate detail screens for clear customer identity

References:

- `../Standards/UIStandards.md`
- `../Decisions/ADR-003-Editing-Experience.md` when adopted

## Brick 11 — Scheduling Engine

**Status:** Active

Goal:

Establish one reusable and explainable source of truth for scheduling validation, technician availability, capacity, and candidate openings.

Deliverables:

- Scheduling interval and normalized assignment value types
- Deterministic overlap and availability validation
- Structured scheduling conflicts and explanations
- Daily technician capacity calculation
- Non-mutating candidate-opening generation
- Multi-technician availability evaluation
- Unit tests for time boundaries, overlap, capacity, and candidate generation
- Integration with existing job, employee, and schedule data

Out of scope for the first Scheduling Engine brick:

- Automatic dispatch
- Route optimization
- Recurring occurrence generation
- Weather-driven bulk rescheduling
- Travel-time prediction
- Cloud synchronization conflicts

References:

- `../Features/Scheduling.md`
- `../Architecture/SchedulingEngine.md`
- `../Decisions/ADR-002-Scheduling-Source-of-Truth.md`

## Persona Engine

**Status:** Planned

Goals:

- Distinguish roles from personas
- Technician, Sales, Office, and Owner experiences
- Persona-specific dashboards and action emphasis
- Shared business data beneath adaptive presentation

## Product Readiness

Goals:

- Catalog controls for item type and tax treatment
- Debug-only presentation diagnostics
- Isolate and fix invalid-frame warnings
- Strengthen saved-record detail presentation
- Formalize release notes and milestone checkpoints
- Continue scheduling, dispatch, recurring-work, and route workflows

## Production Account Platform

**Status:** Planned after the current development phase

PFSS Cloud production onboarding and support must replace beta enrollment with
a durable identity, tenant-provisioning, and recovery system.

### First-Run Company Registration

- Extend the existing unauthenticated `Device Activation` screen into the
  shared account entry point. It must clearly offer both `Activate Employee
  Device` for an invitation code and `Create New Company` for a first Owner.
  Do not ship a nonfunctional signup placeholder before registration is ready.
- Present a guided first-run choice to create a company or sign in to an
  existing company.
- Verify the initial Owner's email and establish password and/or passkey
  authentication with multi-factor recovery methods.
- Collect the minimum company profile, legal consent, time zone, plan, and
  billing information required for service activation.
- Atomically create the authentication subject, tenant, Owner membership,
  subscription allocation, first device session, and immutable audit event.
- Provision the tenant's PFSS Cloud database/storage boundary without exposing
  infrastructure addresses or tenant identifiers to the client.
- Seed an initial recoverable company snapshot and verify synchronization before
  declaring setup complete.
- Roll back incomplete registration so PFSS never leaves an ownerless tenant,
  orphaned subscription, or partially provisioned database.

### Durable Sign-In and Owner Recovery

- Treat Keychain credentials as revocable per-device sessions, never as the
  Owner's only durable identity.
- Support new-device sign-in using verified username/email plus password or
  passkey, followed by MFA where required.
- Issue a new device credential only after authentication and register it in the
  tenant's device inventory.
- Restore a replacement device from the current PFSS Cloud snapshot and resume
  queued synchronization safely.
- Provide verified account recovery and single-use recovery codes without using
  employee invitation codes as permanent credentials.
- Support more than one Owner so one lost device or inaccessible account cannot
  permanently lock a company out.
- Allow an authenticated Owner to revoke a lost device, triggering mandatory
  company-data removal if that device contacts PFSS again.

### Developer Support and Database Operations Console

- Build a separate developer-only operations tool for customer support,
  provisioning diagnostics, migration status, backup verification, tenant
  health, and disaster recovery.
- Require phishing-resistant MFA, least-privilege roles, short-lived access,
  approved devices, and just-in-time elevation for support operators.
- Do not create a universal customer password, permanent tenant credential, or
  undocumented master-key path.
- Require an explicit support case and customer authorization for access to
  customer data whenever practical; visibly identify any support session.
- Log every tenant lookup, data view, export, recovery, credential action,
  migration, and administrative mutation in an immutable audit trail.
- Separate routine support metadata from sensitive business content and redact
  secrets, payment data, authentication material, and unnecessary personal
  information by default.
- Make break-glass access exceptional, time-limited, independently alerted, and
  subject to post-event review.
- Provide safe tenant backup, point-in-time recovery, schema migration,
  quarantine, and integrity-check workflows with confirmation and rollback.
- Test the console and production provisioning process in a non-production
  environment before granting access to live customer tenants.

### Job-Scoped Technician Location Sharing

- Treat location as short-lived operational evidence, not continuous employee
  surveillance or a permanent part of the employee record.
- Report a device location only while the linked employee has an active
  assignment in an approved workflow state, initially Traveling, On Site,
  Setup, Working, or Pack Up.
- Stop reporting automatically when work is paused or completed, the employee
  is off duty, the assignment is cancelled, access is revoked, or the app no
  longer has the required location authorization.
- Clearly disclose when job-scoped location sharing is active and explain its
  business purpose during permission onboarding.
- Send the tenant, employee, device, assignment, coordinates, accuracy,
  timestamp, and workflow state through a dedicated PFSS Cloud location
  channel rather than the durable business-record change feed.
- Show Managers and Owners only the latest authorized observation needed for
  dispatch and Live Map decisions, with visible Live, Stale, Not Reporting,
  and Permission Denied states; never fabricate a missing location.
- Use configurable freshness and retention limits so precise coordinates expire
  quickly after their operational purpose has ended.
- Allow location evidence to support review of a requested time correction,
  while never changing time records automatically or treating GPS alone as
  proof of work performed.
- Preserve the original time entry, proposed correction, reviewer, reason, and
  decision in the audit trail; record only the minimum location evidence needed
  to explain that decision.
- Add explicit role authorization, tenant isolation, rate limits, battery-aware
  update intervals, offline behavior, consent withdrawal, and revoked-device
  tests before production use.

### Beta-to-Production Cloud Infrastructure

- Treat the current `pfss-beta-api` Worker, beta D1 database, and beta R2 archive
  bucket as trial infrastructure only; do not promote them in place for live
  customer use.
- Create separately named and independently secured production Cloudflare
  Workers, D1 databases, R2 buckets, queues, secrets, service bindings, and
  operational accounts.
- Replace the beta `workers.dev` address with a stable PFSS-owned production
  domain and ship that endpoint through release-specific app configuration.
- Keep Development, Beta/Staging, and Production environments isolated so test
  tenants, credentials, archives, logs, and migrations cannot cross boundaries.
- Establish version-controlled production provisioning and migration procedures
  with preflight validation, backups, rollback plans, and post-deployment
  integrity checks.
- Configure production monitoring, alerting, rate limits, abuse protection,
  retention rules, disaster recovery, and cost controls before onboarding live
  customers.
- Perform load, tenant-isolation, authentication, recovery, revoked-device, and
  failure-injection testing against the staging-equivalent environment before
  every production cutover.
- Define an explicit beta-customer migration process that verifies ownership,
  moves or intentionally resets approved tenant data, rotates credentials, and
  records customer acceptance without silently copying trial data.
- Remove the beta endpoint from production builds and prevent production
  credentials from authenticating against beta infrastructure.

These capabilities are production requirements, but implementation begins only
after the current development phase is completed and accepted.

## Final Pre-Launch UI Consistency Pass

**Status:** Required before v1.0 production release; deferred from Phase 16

- Replace the adaptive system `TabView` presentation with a PFSS-owned primary
  navigation bar that remains at the bottom on both iPhone and iPad.
- Preserve Dashboard, Sales, My Day, Service, and Settings destinations,
  selection state, role-based visibility, accessibility labels, safe-area
  behavior, and deep-navigation behavior.
- Verify the unified navigation in portrait and landscape, light and dark
  appearance, larger Dynamic Type sizes, and supported iPhone and iPad layouts.
- Complete this as part of the final UI improvements and enhancements pass
  before PFSS goes live, not as an expansion of Phase 16.

## v1.0 — First Production Release

**Status:** Planned

Required capabilities:

- Stable mobile field workflow
- Customers, sites, leads, estimates, and jobs
- Invoices, payments, and receipts
- Bluetooth receipt printing
- Service Catalog and WorkOrder Engine
- Technician Action Hub
- Basic roles and personas
- Reliable local persistence and migration safety
- Consistent editing and navigation experience

## Post-v1.0 Platform Direction

- Advanced technician time tracking, including pause, travel time, labor time, per-worker time, and correction workflows
- Tax Engine and tax-rate provider abstraction
- Scheduling and dispatch expansion
- Recurring work templates and occurrences
- Route optimization and bulk rescheduling
- Multi-user roles and permissions
- Cloud and offline synchronization
- Web application
- Customer portal
- Photos, attachments, and signatures
- Reporting and dashboards
- Industry packs and configurable workflows
- AI-assisted recommendations

Detailed deferred items belong in `ParkingLot.md`; completed release details belong in release notes and release history.
