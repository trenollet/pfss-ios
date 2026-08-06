# PFSS Phase 19 Project Workbook

## App Store Deployment and Production Release

**Status:** Planned

**Created:** 2026-08-06

## Phase Objective

Finalize PFSS product identity, production policy and infrastructure, App Store
Connect configuration, subscription products, TestFlight distribution, store
review materials, and production-release acceptance. Phase 19 consumes the
provider-neutral account and entitlement foundations completed in Phase 17 and
the expanded application produced by Phase 18.

## Transferred from Phase 17

- [ ] Finalize the public app name, icon, category, description, privacy links,
  screenshots, review notes, and subscription disclosures.
- [ ] Create or align the App Store Connect app record using the retained bundle
  identifier and approved public product identity.
- [ ] Create Base, Pro, and Expert products in one subscription group with the
  approved identifiers, prices, limits, and metadata.
- [ ] Configure TestFlight and expiring server-owned Beta access without adding
  a production payment-bypass key.
- [ ] Register App Store Server Notifications V2 and verify purchase, restore,
  upgrade, downgrade, billing retry, cancellation, expiration, refund, and
  revocation end to end on signed iPhone and iPad builds.
- [ ] Preserve a known-good internal field build and verify production upgrades
  retain the authenticated workspace and synchronized company data.

## Commercial and Production Decisions

- [ ] Approve billing-retry grace duration, cancellation effective date, and
  final post-cancellation data-retention policy.
- [ ] Approve legal terms, privacy-policy versions, subscription terms, minimum
  company profile, age rating, and supported launch regions.
- [ ] Select and configure the permanent PFSS production domain.
- [ ] Provision isolated production Worker, D1, R2, secrets, monitoring,
  recovery, rate limits, and cost controls without promoting staging in place.
- [ ] Define Beta/customer migration, production support, rollback, and incident
  response procedures.

## Phase 19 Completion Gate

- [ ] App Store metadata and subscription products are approved and internally
  verified.
- [ ] Sandbox subscription lifecycle tests pass on signed iPhone and iPad
  builds.
- [ ] TestFlight Beta and invited-Beta entitlement paths are accepted.
- [ ] Production identity, billing, synchronization, recovery, monitoring, and
  Operations boundaries pass security and tenant-isolation regression.
- [ ] A production release candidate passes the full feature regression matrix.
- [ ] App Review submission is approved for release by the product owner.
