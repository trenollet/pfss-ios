# PFSS Changelog

- Status: Active
- Owner: PFSS Project
- Last Updated: 2026-08-14

This file records durable project-level changes. Detailed user-facing notes remain in `../ReleaseNotes/`, and milestone narratives remain in `../ReleaseHistory/`.

## Unreleased

### Phase 19 — Field Intelligence, Workforce Response, and Financial Integrity

- Added opt-in automatic mileage tracking, private multi-device trip backup,
  review, manual entry, correction, reporting, and CSV export.
- Added server-backed Technician decline review with Manager/Owner alerts,
  authorization, audit history, and offline retry.
- Unified Job lifecycle and time-detail presentation, authorized timestamp
  correction, Held Jobs, and recurring-series hold/release behavior.
- Added fractional catalog labor minutes, durable tax classification, verified
  company tax settings, and reusable decimal Tax and Invoice engines.
- Added immutable, idempotent receipt snapshots and durable thermal output from
  accepted payment facts.
- Completed 246 iOS unit tests and 64 Worker tests with no failures or skips,
  plus signed iPhone and iPad field acceptance.
- Closed Phase 19 on build 19.9.1 and transferred the multi-device
  synchronization redesign to Phase 20.

### Roadmap Alignment

- Assigned the server-authoritative multi-device synchronization redesign to
  Phase 20, reserved Phases 21–24 for pre-launch product development, and moved
  App Store deployment and production release intact to Phase 25.
- Moved App Store deployment and production release intact from Phase 19 to
  Phase 20 in the earlier roadmap; this historical transfer is now superseded
  by the Phase 25 alignment above.
- Added the proposed Phase 19 product-development plan for product-owner review
  before implementation begins.
- Approved automatic mileage tracking as the first Phase 19 capability and
  documented battery-aware detection, background permissions, trip review,
  Personal/Business privacy, manual entry, and CSV reporting requirements.
- Renamed the proposed Phase 19 theme to Field Intelligence, Workforce Response,
  and Financial Integrity; moved reimbursement-rate and payroll extensions to
  the parking lot.

### Phase 18 — Operational Expansion and Field Productivity

- Standardized primary navigation, editing, keyboard dismissal, destructive
  actions, list sorting, and Operations entry points across iPhone and iPad.
- Added the Field Pricing Calculator with adjustable Weekly, Bi-Weekly, and
  Monthly percentages.
- Added GPS and map-assisted Lead, Customer, and Site address selection with
  manual correction and standard/satellite map presentation.
- Added role-aware 1, 3, and 5-day Sales follow-up and Technician job calendars.
- Added Recurring Work templates, bounded idempotent occurrence generation,
  skip-and-remove, skip-and-add, pause, resume, stop, and explicit series edits.
- Added Customer Jobs and Invoices histories with customer filtering and
  Date — Earliest First operational sorting.
- Hardened fresh-device cloud bootstrap so incremental changes cannot cause a
  newly signed-in Owner device to retain or publish a partial company snapshot.
- Added collision-safe offline record numbers scoped to the enrolled device so
  disconnected devices cannot overwrite existing Customer, Lead, Estimate,
  Job, Invoice, or Receipt records when they reconnect.
- Made manual synchronization requeue eligible transient failures and resume the
  ordered queue without duplicating successful operations.
- Completed signed-device and automated Phase 18 regression; version 1.0 build
  18.7.8 is the accepted Phase 18 field build.

### Documentation

- Rebuilt the documentation hierarchy around Product, Architecture, Standards, Features, Decisions, Release Notes, and Release History.
- Consolidated duplicate roadmap, backlog, principles, architecture, coding, and developer-note content.
- Added PFSS UI standards and a formal Git/documentation workflow.
- Established GitHub documentation as the permanent system of record.

## v0.9.6

- Added automatic time tracking through the guided job workflow.
- Added a Setup workflow phase.
- Added the Job History Report.
- Strengthened invoice workflow behavior and elapsed-time resilience.

## Earlier Releases

See `../ReleaseNotes/` and `../ReleaseHistory/`.
