# PFSS Coding Standards

- Status: Active
- Owner: PFSS Project
- Applies To: Swift and SwiftUI Code
- Last Updated: 2026-07-18

## Naming

Names describe responsibility.

- Detail screens: `EstimateDetailView`, `JobDetailView`
- Lists: `LineItemListView`, `CustomerListView`
- Rows: `LineItemRowView`, `CustomerRowView`
- Editors: `EditableLineItemView`, `CustomerEditorView`
- Pickers: `ServiceCatalogPickerView`, `CustomerPickerView`
- Engines and calculators: names describe the business decision performed

## View Responsibility

A view should have one primary responsibility. Reusable children render content and raise intent; stable parents own navigation and modal presentation.

## Business Logic

Business logic belongs in engines or calculators, not view bodies. Examples include `PricingCalculator` and `CatalogRankingEngine`.

## State Ownership

State belongs to the nearest stable owner capable of coordinating the workflow. Application-wide dependencies are created once at the application root.

## Model Evolution

- Provide safe defaults for new properties.
- Use backward-compatible decoding when older data may omit fields.
- Test existing saved data after a full restart.
- Preserve transaction snapshots when later configuration changes must not alter historical records.

## Refactoring

- Rename components when responsibility changes.
- Extract repeated logic into focused reusable components.
- Apply the Rule of Three before introducing broad abstractions.
- Fix root causes rather than layering permanent workarounds.
- Keep one logical change buildable and testable before beginning the next.

## Diagnostics

Debug instrumentation should be explicit, useful, and excluded from production behavior unless it serves an intentional user-facing diagnostics feature.

## Related Documents

- `ProjectPrinciples.md`
- `GitWorkflow.md`
- `UIStandards.md`
- `../Architecture/AppArchitecture.md`