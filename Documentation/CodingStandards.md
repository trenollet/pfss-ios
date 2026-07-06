# PFSS Coding Standards

## Naming

Use names that describe responsibility.

### Views
- Detail screens: `EstimateDetailView`, `JobDetailView`
- Lists: `LineItemListView`, `CustomerListView`
- Rows: `LineItemRowView`, `CustomerRowView`
- Editors: `EditableLineItemView`, `CustomerEditorView`
- Pickers: `ServiceCatalogPickerView`, `CustomerPickerView`

## View Responsibility

A view should have one primary responsibility.

Examples:

- `LineItemListView` displays line items and handles list interactions.
- `LineItemRowView` displays one line item.
- `EditableLineItemView` edits one line item.
- `WorkOrderTotalsView` displays totals.

## Engines

Business logic should live in engines or calculators, not directly inside views.

Examples:

- `PricingCalculator`
- `CatalogRankingEngine`

## Refactoring Rules

- Rename components when their responsibility changes.
- Extract repeated logic into reusable components.
- Avoid premature generalization.
- Use the Rule of Three before building generic abstractions.

## Git Workflow

Use small commits and milestone tags.

Suggested rhythm:

```bash
git status
git add .
git commit -m "Meaningful commit message"
git pull --rebase origin main
git push origin main
```

Milestone tags should represent completed capabilities, not random checkpoints.
