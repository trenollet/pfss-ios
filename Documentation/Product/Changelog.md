# PFSS Changelog

- Status: Active
- Owner: PFSS Project
- Last Updated: 2026-08-08

This file records durable project-level changes. Detailed user-facing notes remain in `../ReleaseNotes/`, and milestone narratives remain in `../ReleaseHistory/`.

## Unreleased

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
