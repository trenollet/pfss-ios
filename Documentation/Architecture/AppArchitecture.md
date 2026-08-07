# PFSS Application Architecture

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-07-18

## Architectural Philosophy

PFSS is a platform of reusable business engines expressed through industry-specific workflows, terminology, catalog content, and branding.

## Layers

### Industry Layer

Changes labels, catalog defaults, branding, and industry terminology without redefining the underlying business system.

### Experience Layer

SwiftUI screens, navigation, persona-specific presentation, and workflow orchestration. Views collect input, display results, and raise user intent.

### Business Workflow Layer

Durable records and lifecycle relationships:

- Leads
- Customers
- Sites
- Estimates
- Jobs
- Invoices
- Payments
- Receipts

### Engine Layer

Deterministic, testable, and explainable business logic:

- WorkOrder Engine
- Pricing Engine
- Catalog Ranking Engine
- Recommendation Engine
- Scheduling Engine
- Routing Engine
- Workflow Engine
- Future Tax, Invoice, Payment, and Reporting engines

### Infrastructure Layer

Persistence, migration, presentation coordination, diagnostics, printing, synchronization, and platform services.

## Current Engines

### WorkOrder Engine

Shared editing and display behavior for service line items and totals. Current components include `WorkOrderEditorView`, `LineItemListView`, `LineItemRowView`, `EditableLineItemView`, `WorkOrderTotalsView`, `ServiceCatalogPickerView`, and `CustomLineItemView`.

### Pricing Engine

`PricingCalculator` calculates subtotal, discounts, line totals, and total. Future responsibilities include tax, fees, deposits, balance due, and payment status.

### Catalog Ranking Engine

`CatalogRankingEngine` tokenizes search input, supports initialisms, combines exact, prefix, contains, token, description, usage, and recency signals, and provides debug ranking output.

## Architecture Rules

- Business logic lives outside SwiftUI views.
- Views compose focused components with one primary responsibility.
- Models preserve durable business intent and transaction history.
- Engines are deterministic, explainable, and testable where practical.
- Stable parents or coordinators own modal presentation.
- Application-wide dependencies have one owner at the app root.
- Generalization follows proven repetition rather than speculation.
- New features should strengthen reusable platform layers.

## Related Documents

- `../Product/Vision.md`
- `../Standards/ProjectPrinciples.md`
- `../Standards/CodingStandards.md`
- `../Decisions/ADR-001-Presentation-Ownership.md`
- `ProductionAccountPlatform.md`
