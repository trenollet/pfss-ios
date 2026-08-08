# PFSS Field Pricing Engine Architecture

- Status: Initial engine implemented in Phase 18
- Owner: PFSS Project
- Applies To: Phase 18+
- Last Updated: 2026-08-07

## Responsibility

The Field Pricing Engine converts a currency base price into the three approved
routine-service prices. It does not own SwiftUI, taxes, discounts, persistence,
subscription billing, or invoice balances.

## Boundary

```text
Lead / Estimate / Calculator UI
              ↓ input and intent
       FieldPricingEngine
              ↓ immutable results
       Decimal Currency Values
```

## Core Concepts

- `FieldPricingBreakdown`: base, weekly, bi-weekly, and monthly currency values.
- `FieldPricingEngine`: deterministic calculation boundary.
- Approved rates: Weekly 20%, Bi-Weekly 35%, and Monthly 55%.

## Rules

- Use decimal currency arithmetic and one documented rounding policy.
- Reject zero, negative, unsupported, or structurally invalid inputs.
- Return results without mutating Leads, Estimates, Jobs, or settings.
- Keep tax and discount calculation outside this engine.

## Persistence and Synchronization

The initial engine has no persistence or synchronization dependency. Future
transfer into Leads or Estimates must save the selected price as a durable
business snapshot rather than silently recalculating an existing record.

## Testing

Cover every approved frequency, currency rounding, and zero or negative input.

## Related Documents

- `AppArchitecture.md`
- `../Features/FieldPricingCalculator.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
