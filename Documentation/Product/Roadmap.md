# PFSS Product Roadmap

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-07-18

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
