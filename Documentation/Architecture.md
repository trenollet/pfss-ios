# PFSS Architecture

## Architectural Philosophy

PFSS is a platform of reusable business engines expressed through industry-specific workflows and labels.

The bottom layers should remain stable across industries. The top layer can change terminology, service catalog content, branding, and workflow emphasis.

## Platform Layers

### Industry Layer
Examples: window cleaning, property maintenance, pressure washing, handyman, roofing, HVAC, plumbing, landscaping.

This layer changes labels, catalog items, and industry terminology.

### Business Workflow Layer
Core business objects and flows:

- Leads
- Customers
- Sites
- Estimates
- Jobs
- Invoices
- Payments
- Receipts

### Engine Layer
Reusable logic that should remain independent of industry labels:

- WorkOrder Engine
- Pricing Engine
- Catalog Ranking Engine
- Recommendation Engine
- Scheduling Engine
- Routing Engine
- Workflow Engine

## Current Engines

### WorkOrder Engine
Reusable workflow for records that contain service line items and totals.

Current components:

- WorkOrderEditorView
- LineItemListView
- LineItemRowView
- EditableLineItemView
- WorkOrderTotalsView
- ServiceCatalogPickerView
- CustomLineItemView

### Pricing Engine
Currently implemented as `PricingCalculator`.

Responsibilities:

- Calculate subtotal
- Apply discount
- Calculate total
- Update line totals

Future responsibilities:

- Tax
- Fees
- Deposits
- Balance due
- Payment status

### Catalog Ranking Engine
Implemented as `CatalogRankingEngine`.

Responsibilities:

- Rank catalog search results
- Tokenize human search input
- Support initialism matching
- Score exact, prefix, contains, token, description, usage, and recency signals
- Provide debug ranking output

## Architecture Rules

- Business logic should live outside SwiftUI views.
- Views should compose focused components.
- Engines should be deterministic, explainable, and testable.
- Generalize only after repeated patterns prove the abstraction is needed.
- Reusable components should make future features easier to build.
