# Pro Field Sales & Service (PFSS) Product Blueprint

## Product Identity

**Product Name:** Pro Field Sales & Service  
**Short Name:** PFSS  
**Working Tagline:** Less Clicking. More Working.

PFSS is a field service management platform designed to manage the complete customer lifecycle from first contact through final payment while minimizing repetitive data entry, reducing unnecessary taps, and keeping technicians focused on completing work.

## Vision

PFSS exists to help professional field service companies manage sales, service, scheduling, billing, and field operations in one clean workflow. The product should feel like it was designed by someone who has actually run and worked inside a field service business.

The guiding question for every screen is:

> What does the user need to do next?

## Guiding Principles

### Workflow First

The app should follow the way people actually work. Users should not have to hunt through menus to complete common tasks.

### One Source of Truth

Customer data, site data, service catalog items, pricing rules, and work records should each live in one reliable place and be reused across the system.

### Default, Never Restrict

The Service Catalog should provide defaults for item name, description, quantity, and price, but users must be able to adjust pricing, quantities, descriptions, and custom items in the field.

### Touches Matter

Every extra tap matters. PFSS should reduce clicks wherever possible, especially for technicians in the field.

### Technician Simplicity

Technicians should see the work they need to perform and the actions needed to complete that work. They should not be forced into office-style data management workflows.

### Office Power

Office users, managers, and admins need stronger tools for leads, customers, sites, estimates, jobs, invoices, payments, reporting, and configuration.

### Clean Reusable Architecture

If the same logic is needed in more than one place, it should become a reusable component or service. Shared line items, pricing, printing, catalog search, and workflows should be centralized.

## User Roles

### Admin

Full access to all records, settings, users, reports, service catalog, printers, archive/restore, and system configuration.

### Manager

Broad operational access, including archive/restore, team visibility, scheduling, sales, service, and reporting. May not have every system-level configuration permission.

### Office Staff

Lead management, customer management, site management, estimates, scheduling, invoices, payments, customer communication, and general office workflows.

### Sales

Sales-related workflows such as leads, estimates, customer creation, site creation, follow-up, and sales performance visibility limited to assigned or generated records.

### Technician

Assigned jobs, navigation, call customer, start job, add work, photos, payment, receipt printing, and completion workflow. Technician view should be simple and action-driven.

### Sales/Tech

Combined sales and technician permissions for employees who both sell and perform work.

## Core Business Workflow

```text
Lead
  ↓
Customer
  ↓
Site
  ↓
Estimate
  ↓
Approved
  ↓
Job
  ↓
Invoice
  ↓
Payment
  ↓
Receipt
```

Every major module should support this flow and avoid creating disconnected duplicate workflows.

## Field / Technician Workflow

```text
Today's Jobs
  ↓
Navigate
  ↓
Start Job
  ↓
Perform Work
  ↓
Add Work / Line Items
  ↓
Before Photos
  ↓
After Photos
  ↓
Customer Signature
  ↓
Payment
  ↓
Print Receipt
  ↓
Complete Job
```

The technician experience should become an Action Hub, not a traditional admin form.

Example future job card actions:

```text
Navigate
Call Customer
Start Job
Add Work
Before Photos
After Photos
Collect Payment
Print Receipt
Complete Job
```

## Core Data Objects

- Lead
- Customer
- Site
- Estimate
- Job
- Invoice
- Payment
- Receipt
- Service Catalog Item
- Service Line Item
- Employee / User
- Printer
- Photo / Attachment

## Current Architectural Pillars

### WorkOrder Protocol

Shared abstraction for records that contain line items and pricing.

Used by:

- Estimates
- Jobs
- Future invoices
- Future receipts

### ServiceLineItem

Reusable line item model for services, add-ons, and custom field work.

Core fields:

- Catalog item reference (optional)
- Description
- Quantity
- Unit price
- Line total

### PricingCalculator

Single source of pricing math.

Responsibilities:

- Calculate subtotal
- Apply discounts
- Calculate totals
- Update line item totals

Future responsibilities:

- Tax
- Fees
- Deposits
- Balance due
- Customer-specific pricing

### LineItemEditorView

Reusable line item entry and editing component.

Used by:

- Estimates
- Jobs
- Future invoices
- Future receipts

### Service Catalog

Saved service defaults used to quickly create line items.

Current catalog fields:

- Item Name
- Item Description
- Default Quantity
- Default Price
- Usage Count
- Last Used Date
- Lifecycle Status

The catalog provides defaults but does not restrict field edits.

## Service Catalog Philosophy

The Service Catalog should make estimates, jobs, invoices, and receipts faster to build.

Catalog items are not rigid price locks. They are smart defaults.

Users must be able to:

- Search catalog items
- Add catalog items to estimates/jobs/invoices
- Adjust quantity
- Adjust price
- Adjust description
- Create one-off custom items
- Create new catalog items from the field when needed

## Catalog Ranking and Search

Service Catalog ordering should be usage-driven, not manually ordered.

Ranking should consider:

1. Exact search match
2. Usage count
3. Recent usage
4. Context of the current workflow
5. Customer history
6. Job type
7. Frequently used together

Contextual search examples:

- Window cleaning estimate should favor window-related services.
- Pressure washing job should favor pressure washing services.
- Technician field work should favor recently used job items.
- Commercial customers may surface different defaults than residential customers.

Future recommendation engine:

```text
Frequently quoted together
Frequently sold together
Frequently added in the field
```

## Navigation Philosophy

The app should eventually move away from too many bottom tabs.

Future high-level layout:

```text
Dashboard
Sales
Operations
Administration / Settings
```

Printing should not be its own primary tab long term. Printing should be contextual:

- Estimate Detail → Print Estimate
- Job Detail → Print Work Order / Receipt
- Invoice Detail → Print Invoice
- Payment Detail → Print Receipt

## UI / UX Direction

List screens should prioritize records and search/filter controls. Creation forms should eventually move behind clear buttons or sheets.

Future pattern:

```text
Search
Filter
+ New Record
Record List
```

Instead of showing a large empty creation form above the list by default.

Action styling should be consistent:

- Primary actions: prominent button
- Secondary actions: standard button
- Destructive actions: red/destructive
- Archive/restore: Admin/Manager only

Known UI polish items:

- Reduce nested navigation and double back buttons
- Standardize action button styling
- Move create forms behind Add New buttons
- Add search and filters to list screens
- Fix keyboard Done behavior in reusable line item editor
- Clean up Bluetooth printer selection

## Archive / Restore Philosophy

Records should not be hard-deleted during normal use.

Lifecycle:

```text
Active
  ↓
Archived
  ↓
Restored
```

Archive/restore should eventually be restricted to Admin and Manager roles.

## Job Creation Paths

Jobs should support both planned and impromptu work.

```text
Approved Estimate → Create Job
Site Detail → Create Job
```

Estimate number should remain optional on the job so impromptu work can exist without an estimate.

Job statuses:

- To Be Scheduled
- Scheduled
- Assigned
- In Progress
- Completed
- Cancelled

Jobs should support:

- Primary technician
- Secondary technician
- Future crew support
- Recurring flag
- Line items
- Discount
- Work notes
- Scheduled and completed dates

## Technician Action Hub

Technician job cards should support fast actions:

- Navigate
- Call customer
- Start job
- Add work
- Take photos
- Collect payment
- Print receipt
- Complete job

Navigation should open maps directly to the job site. Google Maps support is desired, with Apple Maps fallback or user preference later.

## Printing Philosophy

Printing should be part of the workflow, not a separate destination.

Thermal printing should support:

- Estimates
- Work orders
- Invoices
- Receipts
- Line item details
- Totals
- Discounts
- Payment status
- Feed lines for tear-off

Bluetooth printer selection should eventually move to Settings and remember the preferred printer.

## Future Invoices and Payments

Invoice flow should build from completed jobs.

```text
Completed Job
  ↓
Create Invoice
  ↓
Record Payment
  ↓
Print Receipt
```

Payments should eventually support:

- Cash
- Check
- Card
- External payment reference
- Partial payments
- Balance due
- Paid/unpaid status

## Future Photos and Signatures

Technician workflow should eventually support:

- Before photos
- After photos
- Customer signature
- Attachments to job/customer/site
- Photo history by customer/site/job

## Future Reporting

Reporting should support:

- Sales pipeline
- Estimate conversion rate
- Revenue by service type
- Technician productivity
- Jobs completed
- Outstanding invoices
- Recurring service schedule
- Catalog item usage

## Success Metrics

PFSS should be measured by how quickly common tasks can be completed.

Target examples:

- Create an estimate: under 60 seconds
- Add field work: under 10 seconds
- Create job from estimate: one tap
- Print receipt: under 5 seconds once printer is configured
- Technician starts navigation: one tap from job card

## Parking Lot

Current known roadmap items:

- Rename app/project from receipt-printer origin to PFSS
- Rename GitHub repository
- Service Catalog integration into line item editor
- Contextual catalog search
- Create customer/site directly from Estimate and Job screens
- Move printing into estimate/job/invoice/payment detail screens
- Technician Action Hub
- Google Maps navigation from technician job cards
- Navigation redesign
- Search and filters on list pages
- Bluetooth printer cleanup
- User roles and permissions
- Invoices
- Payments
- Receipt printing from jobs/payments
- Photos before/after
- Customer signature
- Recurring services
- Route planning
- Cloudflare backend and multi-user sync
- Branding, icons, and color theme

## Decision Rule for New Features

Before adding a feature, answer:

1. Who benefits?
2. How often will it be used?
3. Does it reduce work or add work?
4. Does it fit the core workflow?
5. Can it reuse existing architecture?

If the answer is unclear, the feature stays in the parking lot until the workflow is better understood.
