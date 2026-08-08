# PFSS Parking Lot

- Status: Active
- Owner: PFSS Project
- Applies To: Future Work
- Last Updated: 2026-08-08

This document holds approved ideas and important work that are intentionally deferred. Scheduled work belongs in `Roadmap.md`; completed work belongs in release documentation.

## Priority Before v1.0

### OPS-005: Technician Job Decline and Management Review

Technicians may not assign or reassign a Job. Allow the assigned technician to
decline work only after entering a reason. Store the request in PFSS Cloud as a
tenant-scoped, audited review item and notify every active Manager and Owner
device. Show a prominent `Job Review Required` banner on authorized dashboards;
selecting it opens the affected Job and its decline reason. A Manager or Owner
must resolve the request by reassigning, rescheduling, returning, or cancelling
the work. Resolution must clear the shared alert on every device and remain in
Job history. This is the first deliverable of the larger post-v1 workforce and
sales management initiative, but its permission boundary and review workflow
are required before App Store release.

### TAX-001: Catalog Tax Classification UI

Add catalog editor controls for item type and tax treatment. The model foundation exists; this task should not introduce tax calculation.

## Financial and Document Engines

### TAX-002: Tax Engine

Create an engine-based tax system supporting job-site jurisdiction, provider abstraction, rate lookup, manual override, taxable subtotal, included tax, exemptions, and durable transaction snapshots.

### DOC-001: Invoice Engine

Create invoices from estimates and jobs while preserving line items, discounts, tax classification, totals, customer, site, and transaction history.

### DOC-002: Receipt Engine

Create durable receipts from completed payments and preserve the exact pricing and tax snapshot used at payment time.

## UI and Usability

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

### OPS-003: Route Optimization

Use job-site location and technician assignment to organize field routes.

### OPS-004: Weather and Bulk Rescheduling

Support single-job and selected-day rescheduling without displacing unaffected work. Preserve duration, technician, route, service requirements, reason, and history. Changing one occurrence must not alter its recurrence template unless explicitly requested.

## Platform Expansion

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

### Job-Scoped Technician Location Sharing

Treat location as short-lived operational evidence, not continuous employee
surveillance. Report only while the linked employee has an active assignment in
an approved Traveling, On Site, Setup, Working, or Pack Up state, and stop when
work pauses or completes, access is revoked, permission is withdrawn, or the
assignment no longer qualifies. Use a dedicated short-retention PFSS Cloud
location channel with explicit role authorization, tenant isolation, rate
limits, battery-aware updates, offline behavior, and visible Live, Stale, Not
Reporting, and Permission Denied states. This is separate from Phase 18's
foreground map-assisted address selection.

### PFSS for Mac via Mac Catalyst

Create a standalone Mac Catalyst edition of PFSS from the shared iPhone/iPad
codebase. The Mac edition must install and run independently of Xcode, preserve
the same authenticated account and PFSS Cloud synchronization boundaries, and
support normal macOS signing, archiving, updating, and distribution. Complete a
Mac-specific interface pass for window resizing, keyboard and pointer input,
menus, navigation, printing, file sharing, and platform-inappropriate iOS APIs
before treating the Catalyst build as supported. This replaces reliance on the
temporary `My Mac (Designed for iPad)` development runtime; it does not create a
separate product fork or independent data model.

### Track mileage

track technician mileage in the app for job assignments
track adhoc mileage input
downloadable montlhy reimbursment report
IRS mileage in admin settings
allowed to claim option in admin for employees

### REvamp the Dashboard
Use tiles to navigate Operations, Tech My Day, Leads, Customers, Estimates, and Invoices
rename the Page to something else
