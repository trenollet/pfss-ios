# PFSS Product Roadmap

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-08-14

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

**Status:** Active — Phase 18 Step 2

This work is incorporated into the Phase 18 UI and technical cleanup step.

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
- A dedicated editing-experience ADR if Phase 18 introduces a new architectural
  decision beyond the existing UI standard

## Brick 11 — Scheduling Engine

**Status:** Foundation Completed — expanding in Phase 18

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

Phase 18 consumers of the completed foundation:

- Role-aware 1, 3, and 5-day Operations calendar
- Recurring Work occurrence validation and conflict reporting

Still deferred:

- Automatic dispatch
- Route optimization
- Weather-driven bulk rescheduling
- Travel-time prediction

References:

- `../Features/Scheduling.md`
- `../Architecture/SchedulingEngine.md`
- `../Decisions/ADR-002-Scheduling-Source-of-Truth.md`

## Persona Engine

**Status:** Foundation Completed — role-aware presentation continues

Goals:

- Distinguish roles from personas
- Technician, Sales, Office, and Owner experiences
- Persona-specific dashboards and action emphasis
- Shared business data beneath adaptive presentation

Phase 16 established server-approved roles, device-linked employees, and
role-aware destinations. Phase 18 extends those boundaries into Operations and
the multi-day calendar without allowing role or employee impersonation.

## Product Readiness

**Status:** Active — Phase 18 Steps 1 and 2

Goals:

- Catalog controls for item type and tax treatment
- Debug-only presentation diagnostics
- Isolate and fix invalid-frame warnings
- Strengthen saved-record detail presentation
- Formalize release notes and milestone checkpoints
- Continue scheduling, calendar, dispatch, and Recurring Work workflows

## Production Account Platform

**Status:** Completed — Phase 17

PFSS Cloud production onboarding and support must replace beta enrollment with
a durable identity, tenant-provisioning, and recovery system.

### Delivered Account Capabilities

- Verified first-Owner company registration and atomic tenant provisioning
- Existing-Owner sign-in, logout, replacement devices, and cloud restoration
- Employee invitation activation and device-linked employee identity
- Multiple Owners, recovery codes, lost-device revocation, and final-Owner safety
- Server-owned plans, limits, lifecycle enforcement, and audit history
- Offline-first tenant synchronization and centralized conflict resolution

### Developer Support and Database Operations Console

**Status:** Foundation Completed — Phase 17 Step 8b

- Maintain the separate developer-only Operations tool for customer support,
  provisioning diagnostics, migration status, tenant health, and safe account
  administration.
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

These capabilities remain production requirements and are assigned to Phase 25
rather than expanding the completed Phase 17 account-platform scope.

Phase 17 implementation and acceptance are closed in
`../Phase Development/Phase_17_Project_Workbook.md`. The durable identity and
registration boundary is defined in
`../Architecture/ProductionAccountPlatform.md`.

## Phase 18 — Operational Expansion and Field Productivity

**Status:** Completed

Committed scope:

- Roadmap and architecture cleanup
- Navigation, design, editing, saving, diagnostics, and Operations landing-page
  consistency
- Field Pricing Calculator for approved Weekly, Bi-Weekly, and Monthly routine
  service percentages
- GPS and map-assisted Lead, Customer, and Site address entry
- Role-aware 1, 3, and 5-day calendar for Managers, Salespeople, and Technicians
- Recurring Work templates and idempotent occurrence generation
- Full automated regression, signed iPhone/iPad acceptance, documentation, and
  GitHub closeout

Planning and acceptance are tracked in
`../Phase Development/Phase_18_Project_Workbook.md`.

## Phase 19 — Field Intelligence, Workforce Response, and Financial Integrity

**Status:** Completed — 2026-08-14

Delivered scope:

- Automatic, battery-aware mileage tracking with background trip detection
- Unclassified trip queue with one-tap Personal or Business classification
- Route review, manual trip entry, trip history, and CSV mileage reporting
- Technician Job Decline with a server-backed Manager/Owner review inbox
- Shared Job Review Required alerts and audited resolution
- Closed Job and time-detail presentation consistency
- Catalog tax classification
- Reusable Tax, Invoice, and Receipt engines
- Full automated regression, signed iPhone/iPad acceptance, documentation, and
  GitHub closeout

Planning and acceptance are tracked in
`../Phase Development/Phase_19_Project_Workbook.md`.

## Phase 20 — Multi-Device Synchronization Architecture

**Status:** Next — architecture and implementation planning

Phase 20 replaces broad whole-record conflict handling with a server-
authoritative, versioned, field-aware synchronization architecture. It adds
versioned intent and patches, three-way merge, domain-specific conflict policy,
dependency-aware queues, poison-operation quarantine, durable server change
cursors, stale-device pull/rebase recovery, focused human review, tombstones,
push hints, and synchronization observability.

Planning and acceptance are tracked in
`../Phase Development/Phase_20_Project_Workbook.md`.

## Phases 21–24 — Pre-Launch Product Development

**Status:** Reserved — scope to be defined after Phase 20

These phases remain available for operational expansion, product stabilization,
security hardening, performance, and other field priorities discovered before
the public release candidate is frozen. Each phase will receive its own approved
workbook and acceptance gate before implementation begins.

## Phase 25 — App Store Deployment and Production Release

**Status:** Planned

Phase 25 owns the public app name and identity, permanent production domain and
infrastructure, launch legal and commercial policies, App Store Connect,
subscription products, TestFlight, sandbox billing verification, review
materials, and production-release acceptance. The launch scope is transferred
intact; only its schedule changes.

Planning and acceptance are tracked in
`../Phase Development/Phase_25_Project_Workbook.md`.

## Phase 18 Navigation and UI Consistency

**Status:** Completed — Phase 18

- Replace the adaptive system `TabView` presentation with a PFSS-owned primary
  navigation bar that remains at the bottom on both iPhone and iPad.
- Preserve Dashboard, Sales, My Day, Service, and Settings destinations,
  selection state, role-based visibility, accessibility labels, safe-area
  behavior, and deep-navigation behavior.
- Verify the unified navigation in portrait and landscape, light and dark
  appearance, larger Dynamic Type sizes, and supported iPhone and iPad layouts.
- Complete this as part of Phase 18 before PFSS goes live.
- Standardize Leads, Estimates, and Jobs on **Date — Earliest First** as their
  default list ordering.
- Add Customer-detail shortcuts for filtered Jobs and Invoices histories, also
  defaulted to **Date — Earliest First**.

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
- Route optimization and bulk rescheduling
- Web application
- Customer portal
- Photos, attachments, and signatures
- Reporting and dashboards
- Industry packs and configurable workflows
- AI-assisted recommendations
- New My Day screen for both Sales and Tech.  - Shows # of sales follow up and / or services and click the card shows the activity (sales or service) list for the day.
- iPhone Widget for My Day

Detailed deferred items belong in `ParkingLot.md`; completed release details belong in release notes and release history.
