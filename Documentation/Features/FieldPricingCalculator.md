# PFSS Field Pricing Calculator

- Status: Initial calculator implemented in Phase 18
- Owner: PFSS Project
- Last Updated: 2026-08-07

## User Goal

A field user enters one base price and quickly creates consistent service-price
options for different frequencies without mental calculations or retyping them
into a Lead or Estimate.

## Workflow

1. Open Pricing Calculator from the Sales page.
2. Enter a base price.
3. Select Calculate Pricing.
4. Review the Weekly, Bi-Weekly, and Monthly prices together.

## Behavior

- Weekly is 20% of the base price.
- Bi-Weekly is 35% of the base price.
- Monthly is 55% of the base price.
- The initial calculator does not save or alter a Lead or Estimate.
- Invalid input explains the correction without dismissing the calculator.
- Taxes and discounts are not calculated here.

## Offline and Sync

The initial calculator is local and deterministic, so it works without a
network connection and creates no synchronization records.

## Completion Criteria

- Engine tests verify the three approved percentages, currency rounding, and
  invalid input.
- The Sales page opens the calculator directly.
- Signed iPhone and iPad field tests confirm readable results and keyboard
  behavior.

## Related Documents

- `../Architecture/FieldPricingEngine.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
