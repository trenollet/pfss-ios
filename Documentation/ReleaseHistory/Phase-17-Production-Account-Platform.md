# Phase 17 — Production Account Platform

- Status: Completed
- Started: 2026-07-31
- Completed: 2026-08-06
- Branch: `feature/phase17-production-account-platform`

## Outcome

Phase 17 replaced beta-only Owner enrollment with a durable, server-authorized
account platform. PFSS now supports verified company creation, existing-Owner
sign-in, multiple Owners, independent device sessions, recovery codes,
replacement and lost-device workflows, account entitlements, lifecycle
enforcement, and a private Operations control plane.

## Delivered

- Provider-neutral account, subscription, consent, recovery, device-session,
  and audit models with versioned Cloudflare D1 migrations.
- WorkOS AuthKit Owner registration and sign-in using PKCE and the staging
  callback domain.
- Atomic tenant, first Owner, plan allocation, first device, consent, and audit
  provisioning with rollback and idempotency safeguards.
- Existing-Owner login, immediate logout, automatic workspace restoration, and
  independent replacement-device sessions.
- One-time recovery codes, lost-device revocation, verified second-Owner
  invitations, and final-Owner protection.
- Server-owned Beta, Trial, Base, Pro, Expert, and Enterprise/Custom entitlement
  structures with combined-user, device, lead, customer, and job limits.
- Account hold, suspension, reactivation, archive, protected deletion, and
  fail-closed client behavior.
- Private PFSS Operations iPhone/iPad application with audited entitlement
  overrides, support controls, account/user/device management, provider usage
  monitoring, threshold visibility, account search, and error-log review.
- Field stabilization for synchronization conflict rebasing, catalog telemetry
  merging, replacement employee-device invitations, workflow reminders,
  timeline rescheduling, Lead quote options, invoice payment entry, and account
  plan visibility.

## Acceptance Evidence

- Live Owner registration, login, logout, recovery, replacement-device,
  multiple-Owner, invitation replay, cancellation, revocation, and company-data
  removal checks passed on signed iPhone and iPad builds.
- PFSS Operations acceptance passed on signed iPhone and iPad builds.
- Final iOS regression: 185 tests passed with zero failures or skips.
- Final Worker regression: strict TypeScript validation and all 55 tests passed.

## Deferred by Product Decision

App Store Connect, public naming and metadata, TestFlight, subscription-product
activation, permanent production infrastructure and domain, launch policy, and
App Review were subsequently moved to Phase 25. Phases 18 through 24 provide the
approved product-development runway before the release candidate is frozen.

## References

- `../Phase Development/Phase_17_Project_Workbook.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
- `../Phase Development/Phase_19_Project_Workbook.md`
- `../Phase Development/Phase_20_Project_Workbook.md`
- `../Architecture/ProductionAccountPlatform.md`
- `../Architecture/PFSSOperationsControlPlane.md`
- `../Decisions/ADR-003-App-Store-Subscription-Authority.md`
- `../Decisions/ADR-004-Managed-Owner-Identity.md`
