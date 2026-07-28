# PFSS Parking Lot

- Status: Active
- Owner: PFSS Project
- Applies To: Future Work
- Last Updated: 2026-07-18

This document holds approved ideas and important work that are intentionally deferred. Scheduled work belongs in `Roadmap.md`; completed work belongs in release documentation.

## Priority Before v1.0

### UI-001: Persistent Save Actions

Every editable screen should expose a consistent Save action in the top-right navigation toolbar. Save should remain visible while forms scroll, be disabled when invalid or unchanged where practical, and participate in consistent unsaved-change handling. Destructive actions must remain visually separate.

### TAX-001: Catalog Tax Classification UI

Add catalog editor controls for item type and tax treatment. The model foundation exists; this task should not introduce tax calculation.

### BUG-005: Invalid Frame Dimension Warning

Identify the exact view and calculation causing `Invalid frame dimension (negative or non-finite)` before changing layout code.

### INFRA-002: Debug-Only Presentation Logging

Limit `PresentationDebug` to Debug builds or an explicit diagnostics setting.

### ARCH-002: Root Environment Injection Cleanup

Verify `AppDataStore` and `BluetoothPrinter` are created once at the application root and remove redundant descendant injections.

## Financial and Document Engines

### TAX-002: Tax Engine

Create an engine-based tax system supporting job-site jurisdiction, provider abstraction, rate lookup, manual override, taxable subtotal, included tax, exemptions, and durable transaction snapshots.

### DOC-001: Invoice Engine

Create invoices from estimates and jobs while preserving line items, discounts, tax classification, totals, customer, site, and transaction history.

### DOC-002: Receipt Engine

Create durable receipts from completed payments and preserve the exact pricing and tax snapshot used at payment time.

## UI and Usability

### UI-002: Design System

Standardize typography, button roles, form spacing, section headers, cards, icons, corner radius, shadows, status indicators, and accessible color usage.

### UI-003: Closed Job Visual Status

Show a derived Closed indicator when a job reaches its final invoiced workflow state. Closed jobs remain searchable and viewable but are immediately distinguishable from active work.

### UI-004: Customer Identity in Detail Screens

Replace customer-number-only labels with useful customer names while retaining record numbers where helpful.

### UI-005: Time Tracking Detail Presentation

Show Setup Started, Completed, and Time on Job in Job Detail. Dedicated timestamps should be authoritative for new records; timeline lookup should remain a migration fallback for older data.

## Catalog and Recommendations

### CAT-001: Catalog Item Editing Review

Ensure existing and archived catalog items preserve and edit item type and tax treatment.

### REC-001: Recommendation Validation

Validate duplicate recommendations, self-recommendation, archived items, and deleted references.

### REC-002: Recommendation Diagnostics

Expose why an item was recommended and which rule or score contributed.

## Operations

### OPS-001: Scheduling and Dispatch

Expand technician assignment, status transitions, calendar presentation, and dispatch workflows.

### OPS-002: Recurring Work

Model recurrence as templates or schedules that generate individual job occurrences.

### OPS-003: Route Optimization

Use job-site location and technician assignment to organize field routes.

### OPS-004: Weather and Bulk Rescheduling

Support single-job and selected-day rescheduling without displacing unaffected work. Preserve duration, technician, route, service requirements, reason, and history. Changing one occurrence must not alter its recurrence template unless explicitly requested.

## Platform Expansion

- Multi-user authentication, roles, permissions, and business isolation
- Cloud persistence with offline-first synchronization and conflict handling
- Web application
- Customer portal
- Photos, documents, attachments, and signatures
- Reporting and dashboards
- Industry packs and configurable workflow terminology

## Architecture Candidates

### INFRA-001: Presentation Coordinator

Evaluate a reusable presentation coordinator after the stable-parent routing pattern has been proven across more screens. It must preserve ADR-001.

### Advanced Time Reporting

Support pause/resume, travel time separate from job labor, per-technician timers, editable corrections, billing use cases, time cards, and performance reporting.


## Post v1.0

### Track mileage

track technician mileage in the app for job assignments
track adhoc mileage input
downloadable montlhy reimbursment report
IRS mileage in admin settings
allowed to claim option in admin for employees

### Operations Page UI clean up

use tiles to work into each section
no more long lists

### REvamp the Dashboard
Use tiles to navigate Operations, Tech My Day, Leads, Customers, Estimates, and Invoices
rename the Page to something else


