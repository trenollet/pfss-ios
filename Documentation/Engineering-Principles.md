# PFSS Engineering Principles

These principles guide implementation decisions across PFSS and future industry-specific applications built from the platform.

## EP-001: Preserve Existing Data

Existing customer data must continue to load after every model evolution.

When adding model properties:

- Provide a safe default.
- Use backward-compatible decoding when older saved data may omit the new field.
- Verify existing customers, sites, leads, estimates, jobs, catalog items, and rules still load after a full app restart.
- Do not treat a clean compile as proof of migration safety.

## EP-002: Stable Parents Own Presentation

Modal presentation belongs to stable parent views or coordinators.

- Child views render content and raise user intent through callbacks.
- Do not attach sheet presentation to transient rows or list-backed `Section` views.
- Prefer one active presentation route per screen.

See `ADR-001-Presentation-Ownership.md`.

## EP-003: Business Logic Lives Outside Views

Views collect input and present output. Engines perform business logic. Models store durable data.

Examples include:

- `PricingCalculator`
- Recommendation and ranking engines
- Future tax, invoice, reporting, scheduling, and payment engines

Avoid embedding pricing, recommendation, tax, or workflow rules directly in SwiftUI view bodies.

## EP-004: Store Business Intent Before Automating It

Capture the business classification before implementing automation.

For example, PFSS stores:

- Catalog item type: Service, Material, or Fee
- Tax treatment: Non-Taxable, Taxable, Tax Included, or Exempt

The future Tax Engine can use these values without forcing premature tax-provider or jurisdiction logic into the current release.

## EP-005: One Logical Change, Then Build

Use the following cadence:

1. Make one logical change.
2. Build.
3. Test the affected workflow.
4. Commit when the feature or fix is complete.
5. Push at a stable checkpoint.

This keeps regressions easy to isolate.

## EP-006: Fix Root Causes

Do not preserve a known architectural defect with timing delays, duplicate state, or repeated workarounds.

Temporary instrumentation is encouraged when it produces evidence. Permanent solutions should remove the underlying source of failure.

## EP-007: Design for the Platform

Names and models should remain meaningful across multiple field-service industries.

Before adopting a term or workflow, ask whether it would still make sense for HVAC, electrical, pest control, landscaping, commercial cleaning, roofing, or another service business.

## EP-008: Global State Has One Owner

Application-wide dependencies such as `AppDataStore` and `BluetoothPrinter` are created once at the application root and injected into descendants.

Child views must not create duplicate global stores.
