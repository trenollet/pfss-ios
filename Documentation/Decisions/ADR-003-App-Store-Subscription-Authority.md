# ADR-003: App Store Subscription Authority

- Status: Accepted
- Date: 2026-07-31
- Last Reviewed: 2026-07-31

## Context

PFSS needs paid production subscriptions while preserving free development,
TestFlight, invited-beta, internal-testing, and PFSS internal-business access.
Maintaining separate free and paid applications would fragment customers,
testing, releases, security fixes, and company data.

## Decision

PFSS will ship one application and use Apple auto-renewable subscriptions as
the initial production payment authority.

- The iOS application uses StoreKit 2 for product presentation and purchase.
- The PFSS server verifies signed transactions through the App Store Server API
  and receives App Store Server Notifications V2.
- The entitlement engine, not the device, decides the effective plan.
- Sandbox and production transaction identities remain isolated.
- Xcode and TestFlight purchases never create production entitlements.
- The server supports audited `betaGrant`, `internalTesting`,
  `internalBusinessGrant`, and future `promotionalGrant` allocations without
  creating another application edition.
- No customer-facing or locally stored switch can disable payment enforcement.

## Consequences

### Positive

- Apple manages collection, renewal, storefront currency, and subscription UI.
- TestFlight and sandbox testing incur no customer charge.
- One app and one entitlement engine cover paid and complimentary access.
- Server verification survives reinstall, replacement device, and missed local
  transaction updates.
- A later billing adapter can be added without changing PFSS account identity.

### Tradeoffs

- App Store commission is higher than many direct payment processors.
- Product configuration and the Paid Applications Agreement are operational
  dependencies.
- PFSS must process signed server events, retries, refunds, billing failures,
  upgrades, downgrades, and reconciliation.

## Required Controls

- Verify JWS signatures and bundle, product, environment, and transaction data.
- Make notification handling idempotent and retain safe event identifiers.
- Reconcile subscription status through Apple's server API after missed events.
- Never log signed payloads or credentials unnecessarily.
- Apply for the App Store Small Business Program when eligible.

## Related Documents

- `../Architecture/ProductionAccountPlatform.md`
- `../Phase Development/Phase_17_Project_Workbook.md`
- `../Product/Roadmap.md`
