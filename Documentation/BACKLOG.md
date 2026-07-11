# PFSS Backlog

This document tracks work that should be preserved without interrupting the current development focus.

## High Priority

### TAX-001: Catalog Tax Classification UI

Add controls to the catalog editor for:

- Item Type: Service, Material, Fee
- Tax Treatment: Non-Taxable, Taxable, Tax Included, Exempt

The model foundation and backward-compatible decoding are complete. No tax calculation should be introduced in this task.

### TAX-002: Tax Engine

Design and implement tax calculation as an engine rather than view logic.

Required capabilities:

- Job-site tax jurisdiction
- Tax-rate provider abstraction
- Local rate lookup
- Manual rate override
- Taxable subtotal
- Tax amount and total
- Tax-included handling
- Exemption handling and documentation
- Saved transaction snapshot of rate, source, jurisdiction, and effective date

### DOC-001: Invoice Engine

Create invoices from estimates and jobs while preserving line items, discounts, tax classification, totals, customer, site, and transaction history.

### DOC-002: Receipt Engine

Create durable receipts from completed payments. Receipts must retain the exact pricing and tax snapshot used at the time of payment.

## Workflow and Reliability

### BUG-005: Invalid Frame Dimension Warning

Investigate the console warning:

`Invalid frame dimension (negative or non-finite).`

Identify the exact view and calculation before changing layout code.

### INFRA-001: Presentation Coordinator

Evaluate a reusable presentation coordinator after the stable-parent routing pattern has been proven across more screens.

The coordinator must preserve ADR-001: stable parents or coordinators own modal presentation.

### INFRA-002: Debug-Only Presentation Logging

Make `PresentationDebug` active only for Debug builds or through an explicit diagnostics setting.

### ARCH-002: Single Root Environment Injection Cleanup

Verify `AppDataStore` and `BluetoothPrinter` are created once at the app root. Remove redundant child `.environmentObject` calls where inheritance is sufficient.

## UI and Usability

### ENH-UI-001: Button Colors

Define consistent primary, secondary, success, warning, and destructive button treatments. Confirm accessibility in light and dark appearance.

### ENH-UI-002: Design System

Standardize:

- Typography
- Button styles
- Form spacing
- Section headers
- Cards
- Icons
- Corner radius
- Shadows
- Color usage

### ENH-UI-003: Customer Names in Detail Screens

Review saved job and estimate detail screens for remaining customer-number-only labels and display a useful customer name while preserving the record number where helpful.

## Catalog and Recommendation Platform

### CAT-001: Catalog Item Editing Review

Ensure existing catalog items can edit item type and tax treatment and that archived items retain these values.

### REC-001: Recommendation Rule Validation

Add validation for duplicate recommendations, self-recommendation, archived catalog items, and deleted catalog references.

### REC-002: Recommendation Diagnostics

Provide a developer-facing explanation of why an item was recommended and which rule or score contributed.

## Operations

### OPS-001: Scheduling and Dispatch

Expand scheduling, technician assignment, status transitions, calendar presentation, and dispatch workflows.

### OPS-002: Recurring Work

Model recurring jobs as schedules or templates rather than only a Boolean flag.

### OPS-003: Route Optimization

Use job-site locations and technician assignments to organize field routes.

### OPS-004: Weather and Bulk Rescheduling

Build a Job List Route workflow that can reschedule one job or an entire day's jobs because of weather, staffing, equipment failure, customer request, or other disruptions.

Required capabilities:

- Assign an estimated duration to every job so the scheduler can identify valid open time slots.
- Move affected jobs into available openings later in the same week or into the following week.
- Avoid displacing or changing unaffected jobs on other days.
- Support bulk rescheduling for all jobs on a selected day while still allowing individual exceptions.
- Preserve technician, route, customer, site, and service requirements when proposing new openings.
- Warn when no suitable open slot exists rather than silently overbooking the schedule.
- Preserve a rescheduling reason and history for operational review.

Recurring scheduling rule:

- A rescheduled occurrence must not change the underlying recurrence pattern.
- Example: a monthly job scheduled for the 15th that is performed on the 16th because of rain must still generate future occurrences on the 15th.
- Recurrence templates and individual job occurrences must therefore be stored separately. Rescheduling changes only the selected occurrence unless the user explicitly chooses to modify the recurring series.

## Platform Expansion

### PLATFORM-001: Multi-User Roles

Add authentication, users, roles, permissions, and business-level data isolation.

### PLATFORM-002: Cloud and Offline Sync

Introduce cloud persistence with offline-first behavior, conflict resolution, and migration safety.

### PLATFORM-003: Web Application

Provide desktop access to the same business records and engines through a web application.

### PLATFORM-004: Customer Portal

Allow customers to view and approve estimates, review appointments, receive invoices, and access receipts.

### PLATFORM-005: Attachments and Signatures

Support photos, documents, signatures, and durable attachment metadata.

## Completed in v0.7.x

- Configurable recommendation rules and persistence
- Recommendation results in the catalog picker
- Catalog search and ranking
- Reusable catalog and line-item rows
- Root environment injection
- Line-item editing for saved and unsaved jobs and estimates
- Customer names in job and estimate lists
- One-tap Add Line Item presentation
- Stable-parent presentation ownership
- `PresentationDebug`
- Services & Materials terminology
- Centered Add Line Item button content
- Catalog item type and tax-treatment model foundation
- Backward-compatible catalog decoding