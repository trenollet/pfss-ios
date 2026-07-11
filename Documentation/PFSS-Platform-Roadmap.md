# PFSS Platform Roadmap

## Mission

PFSS is a mobile-first field-service platform for creating affordable, industry-specific customer sales and service management applications. The phone is the primary workplace, with future desktop access through a web application.

The platform adapts behavior using workflow, persona, context, action, industry, and role.

## Current Foundation

### Core Records

- Customers
- Customer sites
- Leads
- Estimates
- Jobs
- Service and material catalog
- Record lifecycle and archiving
- Local persistence

### Working Engines and Infrastructure

- Pricing calculations
- Catalog search and ranking
- Configurable recommendation rules
- Recommendation presentation in the work-order workflow
- Root environment injection
- Stable-parent modal presentation
- Presentation diagnostics
- Backward-compatible catalog model evolution

## Near-Term: Workflow and Product Readiness

- Add catalog editor controls for item type and tax treatment
- Continue UI consistency and button styling
- Isolate the invalid-frame console warning
- Expand diagnostic tooling while keeping it Debug-only
- Improve saved-record detail presentation
- Formalize release notes and version checkpoints

## Tax Engine Foundation

The catalog now supports business intent for:

- Item type: Service, Material, Fee
- Tax treatment: Non-Taxable, Taxable, Tax Included, Exempt

Future Tax Engine work will include:

- `TaxCalculationEngine`
- `TaxRateProvider` protocol
- Job-site jurisdiction and address sourcing
- Local rate lookup
- Manual rate override
- Taxable subtotal calculation
- Estimate, invoice, and receipt tax snapshots
- Exemption documentation
- Audit-safe preservation of the rate and source used at transaction time

Tax behavior must remain configurable because jurisdictions treat services, materials, fees, bundled transactions, and contractor purchases differently.

## Document and Financial Engines

- Invoice Engine
- Receipt Engine
- Payment Engine
- Deposits and partial payments
- Balance tracking
- Tax summaries
- Printable and shareable documents
- Bluetooth thermal-printer workflows

## Operations Engines

- Scheduling
- Dispatch
- Recurring work
- Technician assignments
- Route optimization
- GPS and service-area context
- Notifications and reminders

## Platform Expansion

- Multi-user accounts and permissions
- Cloud sync
- Offline-first synchronization
- Web application
- Customer portal
- Photos, attachments, and signatures
- Reporting and dashboards
- Industry packs
- Configurable workflows, personas, roles, and actions
- AI-assisted workflow recommendations

## Architecture Direction

PFSS should continue evolving through reusable layers:

1. Models store durable business data.
2. Engines interpret and manipulate that data.
3. Infrastructure provides persistence, presentation, diagnostics, sync, and platform services.
4. Views collect input and present results.

New features should strengthen this separation rather than place business logic directly in screens.
