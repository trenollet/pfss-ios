# PFSS Phase 17 Project Workbook

## Production Account Platform

**Status:** Completed

**Started:** 2026-07-31

**Completed:** 2026-08-06

## Phase Objective

Replace beta-only Owner enrollment with a durable production account system so
a new business Owner can create a PFSS company, verify their identity, select a
plan, activate the first trusted device, synchronize the initial workspace, and
recover access without depending on an existing device.

Employee invitation-code activation remains supported. Phase 17 adds Owner
registration and durable sign-in beside it; it does not weaken the tenant,
membership, device, or synchronization boundaries completed in Phase 16.

## Non-Negotiable Security Invariants

- The client never chooses or supplies a tenant identifier.
- A human account and a device session are separate identities.
- Device credentials remain independently revocable and stay in Keychain.
- Registration creates the authentication subject, tenant, first Owner,
  subscription allocation, first device, and audit record atomically.
- Failed registration leaves no ownerless tenant, orphaned subscription,
  usable credential, or partially provisioned company.
- Passwords, verification secrets, recovery codes, access tokens, and payment
  credentials never enter application logs or PFSS business archives.
- Subscription limits and role authority are enforced by the server, not only
  hidden in the iOS interface.
- Recovery proves control of a verified recovery method and never relies on an
  employee invitation code as a permanent Owner credential.
- Production, staging, beta, and local development data and credentials remain
  isolated.
- Every security-sensitive transition creates a tenant-scoped audit event.

## Phase 17 Delivery Order

1. Provider-neutral identity, registration, subscription, and consent
   contracts.
2. Authentication, email delivery, MFA/passkey, billing, and production-hosting
   provider decisions recorded through ADRs.
3. Versioned production-account database schema and migration tests.
4. Atomic Owner and company registration service.
5. First-run iOS choice between `Activate Employee Device` and
   `Create New Company`.
6. Verified Owner sign-in, device-session issuance, and initial cloud hydration.
7. Account recovery, replacement-device enrollment, lost-device revocation,
   recovery codes, and multiple-Owner safeguards.
8. Plan entitlements, employee/device limits, and safe account-state behavior.
9. Beta-to-staging migration rehearsal, security regression, failure injection,
   and live iPhone/iPad acceptance testing.

## Step 1 — Provider-Neutral Account Contract

### Goal

Define the durable PFSS-owned account and registration language before choosing
an external authentication or billing implementation. Providers perform
authentication, delivery, or payment services; they do not own PFSS tenant,
membership, device, entitlement, or audit semantics.

### Required Domain Records

- Authentication subject: durable human identity and provider linkage.
- Verified address: normalized email or phone state and verification history.
- Recovery method: protected recovery capability without storing clear-text
  recovery secrets.
- Registration attempt: short-lived, resumable workflow with explicit expiry
  and terminal status.
- Legal consent: accepted document version, timestamp, region, and subject.
- Subscription account: provider-neutral customer and lifecycle state.
- Plan allocation: server-approved plan, entitlements, limits, and effective
  dates.
- Device session: independently revocable device access bound to one member.
- Account audit event: authenticated actor, action, target, outcome, and safe
  metadata.

### Registration State Model

`started` → `identityVerified` → `profileComplete` → `planAuthorized` →
`provisioning` → `active`

Terminal outcomes are `expired`, `cancelled`, and `failedRolledBack`.

No intermediate state grants tenant data access. The first device session is
returned only after the complete transaction reaches `active`.

### Step 1 Acceptance Criteria

- [x] Provider-neutral Swift and Worker types use the same canonical states.
- [x] Registration input cannot contain a tenant ID, Owner role override, plan
  entitlement, price, or infrastructure address.
- [x] Public responses never expose password hashes, provider secrets, tenant
  storage paths, or clear-text recovery material after its one allowed display.
- [x] Registration validation is deterministic and independently testable.
- [x] Duplicate identity and duplicate company requests have explicit safe
  outcomes.
- [x] Cancellation, expiry, and retry behavior are documented.
- [x] The contract supports password, passkey, and federated identity without
  requiring all methods in the first production release.
- [x] The contract supports a billing provider without embedding that
  provider's object model in the iOS application.
- [x] Paid, invited-beta, internal-testing, internal-business, and promotional
  access use explicit server-owned allocation sources in one application.

## Provider Decisions Required Before External Integration

- [x] Authentication and identity provider: WorkOS AuthKit per ADR-004.
- [x] Initial sign-in methods: email Magic Auth and verification first; Sign in
  with Apple after staging validation; passkeys after permanent auth domain.
- [x] Authentication email verification provider: WorkOS AuthKit. General PFSS
  transactional-email delivery remains a later separate decision.
- [x] MFA methods and policy: WorkOS-managed Owner MFA for recovery and
  company-security operations, with passkeys eligible as a verified factor
  after permanent-domain deployment.
- [x] Subscription and payment provider: Apple StoreKit 2, App Store Server API,
  and App Store Server Notifications V2 per ADR-003.
- [x] Initial Beta, Trial, Base, Pro, Expert, and Enterprise/Custom plan names,
  combined-user/device limits, record limits, and trial durations approved.
- [x] Production domain selection, commercial cancellation policy, launch legal
  documents, supported regions, and final App Store metadata transferred to
  the public-release phase, now Phase 25, as release prerequisites.

## First-Run Experience Contract

The unauthenticated entry screen must present two working choices:

1. `Activate Employee Device` — existing invitation-code enrollment.
2. `Create New Company` — verified first-Owner registration.

A later `Sign In to Existing Company` path supports an Owner's new or
replacement device. No dead placeholder or simulated registration success may
ship to users.

## Explicitly Outside the Core Phase 17 Scope

- Job-scoped technician location sharing.
- Final cross-device bottom navigation redesign.
- Field-level synchronization merge controls and deletion tombstones.
- Broad visual redesign unrelated to registration, sign-in, or recovery.

These remain required or planned pre-launch work in the product roadmap but do
not expand the production account implementation boundary.

## Step 8 — Plan Entitlements and Operations Readiness

### Step 8a — Account-State Enforcement and Billing Authority Foundation

- [x] Enforce server-owned plan allocations, account lifecycle state, combined
  user/device limits, and lead/customer/job creation limits.
- [x] Preserve access to existing records after downgrade while blocking new
  records beyond the effective plan limit.
- [x] Add verified StoreKit transaction evidence, App Store Server API and
  Notifications V2 adapters, and Owner-facing plan and usage receipts.
- [x] Approve the 90-day invited Beta duration and 14-day Trial duration.
- [x] Transfer billing-retry grace duration, cancellation effective date, and
  final post-cancellation retention policy to Phase 25 for approval alongside
  the live App Store subscription configuration.

### Step 8b — Private PFSS Operations Control Plane

The product owner explicitly moved the private developer support and account
operations application into active Phase 17 pre-launch work.

- [x] Define a separate administrator identity and authorization boundary.
- [x] Add revocable Operations sessions and immutable control-plane audit data.
- [x] Add platform account lifecycle controls without weakening tenant access.
- [x] Add read-only platform summary, account search/filter, and account detail APIs.
- [x] Create a separate private iPhone/iPad SwiftUI application project.
- [x] Compile the Operations application for iOS Simulator.
- [x] Pass Worker type checking and all 54 local migration/isolation tests.
- [x] Create the dedicated WorkOS Operations staging application.
- [x] Apply migration `0013` and deploy the updated staging Worker.
- [x] Invite and activate the first platform Owner administrator.
- [x] Complete live acceptance on signed iPhone and iPad builds.
- [x] Add audited entitlement overrides, holds, recovery, and protected removal.
- [x] Add account archive and protected deletion scheduling safeguards.
- [x] Add provider/account monitoring, threshold alerts, and summary error logs.
- [x] Connect read-only Cloudflare analytics telemetry for Worker requests and
  D1 rows read/written using a Worker-secret Account Analytics token.
- [x] Keep the Overview scalable with compact provider gauges and dedicated,
  searchable Accounts and Error Logs pages with date ordering.
- [x] Complete the signed iPhone/iPad Step 8b acceptance pass.

### Step 8b Closeout Record — 2026-08-04

- Cloudflare telemetry was verified live for Worker requests and D1 rows read
  and written using a least-privilege Account Analytics token stored only in
  the Worker secret store.
- The Worker passed TypeScript validation and all 54 migration, isolation,
  registration, recovery, entitlement, hold, and Operations authorization
  tests under the supported Node 22 runtime.
- PFSS Operations compiled successfully for iOS and its latest signed build was
  installed and launched on iPhone17e and iPad Pro mini.
- Migration filenames were normalized to unique sequential identifiers: the
  Operations control plane ends at `0017`, followed by App Store entitlement
  migrations `0018` through `0020`.

### Phase 17 Field Stabilization Record — 2026-08-06

- Reconciled legacy assignment technician identifiers with the authenticated
  Owner/employee identity so pre-authentication assignments appear correctly in
  My Day.
- Hardened conflict resolution to propagate the accepted server revision,
  rebase dependent offline operations, and prevent resolved catalog and
  assignment conflicts from immediately recurring.
- Removed catalog usage counters and last-used timestamps from human conflict
  review because they are operational metadata that PFSS can merge safely.
- Restored replacement-device invitation creation for active employees and
  added per-user arrival-to-setup and setup-to-work reminder preferences with
  local notifications.
- Added direct schedule editing from Operations Timeline assignment management,
  including return-to-timeline refresh after saving.
- Expanded Lead entry with Location, Notes, an organized Sales Info section,
  Door Knock as the default source, and multiple quoted-price/frequency options
  that remain editable on existing records.
- Improved invoice payment entry with select-all behavior, exposed the effective
  account plan in App Information, and advanced the application build to 4.
- The Cloudflare Worker passed TypeScript validation and all 55 tests. The iOS
  application passed all 185 unit tests on an iPhone 17 simulator with zero
  failures or skips.
- The signed build was compiled and installed on the paired field-test iPhone
  and iPad devices. Native standalone Mac support remains deferred as the
  post-v1.0 Mac Catalyst parking-lot enhancement.

### App Store Deployment Transfer

The former Step 8c is no longer part of Phase 17. Public product identity,
App Store Connect, TestFlight, subscription activation, production launch
configuration, and release acceptance are now owned by the Phase 25 workbook.
The provider-neutral entitlement engine, StoreKit evidence types, server
adapters, and Operations overrides completed here remain the foundation for
that work.

## Phase 17 Completion Gate

- [x] A new Owner creates a company from an unactivated iPhone or iPad.
- [x] Verified registration creates exactly one tenant and active Owner.
- [x] The first trusted device synchronizes the initial company snapshot.
- [x] An Owner signs in on a replacement device without an employee invitation.
- [x] Recovery succeeds without access to an existing trusted device.
- [x] Multiple Owners prevent a single lost account from locking the company.
- [x] Employee invitation activation continues to work unchanged.
- [x] Server-side entitlements enforce the approved plan and limits.
- [x] Failed registration and provisioning roll back completely.
- [x] Authentication, recovery, device, subscription, and consent actions are
  auditable without storing secrets.
- [x] Automated isolation, authorization, recovery, rollback, and failure tests
  pass.
- [x] Live iPhone and iPad registration, sign-in, recovery, and replacement
  device tests are accepted.

## Step 4 — Atomic Owner and Company Registration Service

- [x] Registration completion requires the registration token and a verified
  WorkOS-backed authentication subject.
- [x] One transactional batch creates the tenant, first active Owner,
  subscription shell, server-owned staging plan allocation, first device,
  consent linkage, and immutable audit event.
- [x] The first device credential is returned only after the attempt reaches
  `active` and is stored only as a digest.
- [x] Repeated completion creates no duplicate tenant and reissues no device
  credential.
- [x] Injected device-provisioning failure rolls back every company resource
  and leaves the attempt safely retryable.
- [x] Production refuses complimentary staging allocation and requires the
  future verified App Store plan-authorization boundary.

## Step 5 — First-Run iOS Company Registration

- [x] The unauthenticated screen retains employee activation and exposes
  `Create New Company` only in development builds.
- [x] Owner verification opens WorkOS through an Apple authentication session
  with PKCE and an exact associated HTTPS callback.
- [x] The form collects only verified Owner identity, company name, current
  time zone, device name, and versioned legal consent.
- [x] The client completes atomic registration, stores the issued device
  credential in this-device-only Keychain storage, and verifies the Owner
  session.
- [x] The staging callback domain and signed app publish matching Apple
  associated-domain metadata.
- [x] Replace the in-process local data store after activation and hydrate the
  initial synchronized workspace without requiring an app restart.
- [x] Complete live signed iPhone and iPad registration acceptance.

## Step 6 — Verified Owner Sign-In and Session Restoration

- [x] An existing Owner can authenticate through WorkOS without an employee
  invitation code.
- [x] Successful authentication issues an independently revocable device
  session and restores the synchronized company workspace.
- [x] Logout clears company data and secure access from the device without
  deleting the company account.
- [x] Logout returns immediately to Get Started, and a successful sign-in
  refreshes the app without requiring it to be closed, reopened, or rebooted.
- [x] Settings displays the authenticated Owner's server-backed name and
  verified email address above the logout action.
- [x] Complete signed replacement-device acceptance on both iPhone and iPad.

## Step 7 — Owner Recovery and Replacement-Device Security

- [x] Existing Owners can add a replacement device through verified WorkOS
  sign-in without an employee invitation or an existing trusted device.
- [x] An authenticated Owner can create a new set of eight high-entropy,
  one-time recovery codes; replacing the set revokes every prior unused code.
- [x] A saved recovery code can restore one replacement device from Get Started
  and is atomically consumed so replay cannot issue another credential.
- [x] Owners can review Owner devices and revoke a lost device while the current
  device remains protected from accidental self-revocation.
- [x] Recovery-code replacement, successful recovery, and device revocation are
  recorded in tenant-scoped audit history without storing clear-text codes.
- [x] Live-device acceptance confirms code creation and export, logout,
  recovery without an existing session, automatic workspace restoration,
  single-use replay rejection, remaining-code tracking, and lost-device
  controls function as intended.
- [x] Add a verified second-Owner invitation and identity-linking workflow.
- [x] Prevent suspension, revocation, or removal of the final active Owner.
- [x] Complete live recovery-code, lost-device, and replacement-device tests on
  signed iPhone and iPad builds.

## Phase 17 Closeout Record — 2026-08-06

- Owner registration, existing-Owner sign-in, logout, automatic session
  restoration, replacement-device access, recovery codes, multiple Owners,
  employee activation, account lifecycle enforcement, and tenant-isolated sync
  were accepted on signed iPhone and iPad builds.
- The private PFSS Operations application was accepted on iPhone and iPad with
  audited plan overrides, holds, recovery assistance, account/user/device
  controls, protected deletion, provider monitoring, account search, and error
  review.
- Server-owned Beta, Trial, Base, Pro, Expert, and Enterprise/Custom entitlement
  structures were established without making the client the billing authority.
- Final regression passed all 185 iOS unit tests and all 55 Worker tests with
  strict TypeScript validation.
- App Store deployment was intentionally transferred intact and is now assigned
  to Phase 25. Phase
  17 therefore closes as the completed production-account and Operations
  foundation, not as a public App Store release.

## Phase Start Record

- 2026-07-31: Implemented the first provider-neutral account foundation. Swift
  now defines canonical registration, authentication-method, subscription,
  consent, company, Owner, device, and validation types without client-authored
  tenant, role, price, entitlement, or infrastructure fields. The Worker adds a
  public validation-only boundary that normalizes safe fields, rejects
  privileged fields recursively, and never echoes the identity assertion.
- 2026-07-31: Added migration `0009_production_account_foundation.sql` with
  authentication subjects and identities, verified contacts, protected recovery
  methods, registration attempts, legal consent, provider-neutral subscription
  accounts, plan allocations, and the authentication-subject membership link.
  The migration is validated locally but has not yet been applied to the
  deployed beta database.
- 2026-07-31: Strict TypeScript validation passed, the Worker regression suite
  passed 34 of 34 tests across all nine local migrations, and focused iOS
  `PFSSProductionAccountModelsTests` passed 8 of 8 with a successful simulator
  build.
- 2026-07-31: Added the provider-neutral registration-attempt coordinator.
  Start and retry are idempotent, stale attempts expire, status and cancellation
  require a one-time-issued registration token, and only token and identity
  digests are stored. Duplicate verified identities and active company requests
  share one non-enumerating sign-in-required response. Starting an attempt does
  not create a tenant, member, device, or subscription account. Migration 0009
  and this Worker remain local and undeployed.
- 2026-07-31: Selected Apple auto-renewable subscriptions as the planned initial
  payment path while preserving a provider-neutral entitlement engine. Added
  server-owned allocation sources for App Store subscriptions, expiring invited
  beta access, internal testing, the PFSS operator's tenant-scoped internal
  business access, and future promotions. Complimentary access requires an
  authenticated issuer and reason and cannot be requested by the client.
  Business-specific behavior will use tenant-scoped modules and feature flags
  rather than a divergent application fork where practical.
- 2026-07-31: Accepted ADR-003 for Apple subscription authority with StoreKit 2,
  server-side verification, Notifications V2, and strict sandbox/production
  isolation. Added proposed ADR-004 recommending WorkOS AuthKit for PKCE-based
  Owner identity, email-code verification, MFA, safe identity linking, and
  future passkeys and SSO. WorkOS was subsequently approved; no provider
  credential has been added.
- 2026-07-31: ADR-004 accepted with WorkOS AuthKit as the managed Owner identity
  and authentication-verification provider. Added provider adapter contracts
  and staging/production configuration guards without adding credentials or
  making live provider calls.
- 2026-07-31: Added the iOS Owner-authentication coordinator with secure random
  PKCE state, verifier and S256 challenge generation; this-device-only Keychain
  persistence; exact callback validation; expiry; single-use callback
  consumption; and a deterministic local adapter. The unactivated first-run
  screen now separates `Activate Employee Device` from a development-only
  `Create New Company` path. Release builds exclude the unfinished Owner route
  until WorkOS staging is configured. Focused tests passed 8 of 8 and both Debug
  test and unsigned Release simulator builds succeeded.
- 2026-07-31: Added the WorkOS HTTP adapter for hosted AuthKit authorization and
  PKCE code exchange. It returns only verified normalized identity data and
  discards provider access and refresh tokens at the adapter boundary. Added
  strict environment-binding loading and a staging setup guide. The product
  authentication domain remains intentionally undecided; no live WorkOS values,
  DNS changes, credentials, or provider calls have been made. Worker tests pass
  34 of 34.
- 2026-07-31: Phase 16 was merged into `main` through PR #5. The Phase 17
  `feature/phase17-production-account-platform` branch was aligned to the Phase
  16 merge commit before new work began.
- 2026-07-31: Phase 17 activated with the provider-neutral account contract as
  the first delivery step. No external identity or billing provider has been
  selected yet.
- 2026-07-31: Applied production-account migrations 0009 and 0010 to staging,
  configured WorkOS AuthKit, and verified the live PKCE Owner signup and
  callback exchange. PFSS persisted one verified WorkOS identity, issued its
  internal one-time identity assertion, and rejected callback replay.
- 2026-07-31: Added the atomic staging registration-completion service. It
  creates the company, active Owner, subscription shell, 90-day server-owned
  beta allocation, first revocable device, consent linkage, and audit event in
  one D1 transaction. Completion is idempotent, device credentials are issued
  once, forced mid-transaction failure rolls back fully, and production cannot
  use the staging grant path. Strict TypeScript validation and all 39 Worker
  tests pass.
- 2026-07-31: Replaced the local Owner-registration placeholder with the live
  staging iOS flow. The app launches WorkOS in an Apple HTTPS authentication
  session, exchanges the PKCE callback through the Worker, presents the minimum
  company and consent form, completes atomic provisioning, stores the first
  device credential in Keychain, and verifies the Owner session. Employee-code
  activation remains unchanged and the Owner route remains development-only.
  The callback site and app publish matching associated-domain metadata. The
  unsigned simulator build succeeded and all 8 focused Phase 17 iOS tests
  passed. In-process data-store replacement and live-device acceptance remain.
- 2026-08-01: Live-device Owner session acceptance passed. The tested device
  launched successfully, displayed the correct authenticated Owner name and
  verified email, logged out directly to Get Started, signed back in without an
  app restart or device reboot, and restored company data plus the Owner's
  operational roles. This accepts the automatic application-session rebuild
  and synchronized workspace restoration; the separate iPhone/iPad matrix and
  replacement-device recovery tests remain open.
- 2026-08-01: Added migration 0011 and deployed the first Owner recovery
  security increment to staging. Owners can replace and securely export eight
  one-time recovery codes, inspect remaining-code status, recover an
  unactivated device from Get Started, review Owner devices, and revoke a lost
  Owner device. Recovery material is stored only as a digest, code replay is
  rejected, and security actions are audited. Worker tests pass 44 of 44,
  strict TypeScript validation passes, and the unsigned iOS simulator build
  succeeds. Multiple-Owner enrollment and final-Owner protection remain next.
- 2026-08-01: Live-device Owner recovery acceptance passed without exceptions.
  The Owner created and saved recovery codes, restored access from Get Started
  without an existing session, received an automatic synchronized workspace,
  confirmed the consumed code could not be replayed, verified the remaining
  count, and exercised the Owner-device security controls. The separate signed
  iPhone/iPad matrix remains part of the Phase 17 completion gate.
- 2026-08-01: Added migration 0012 and deployed verified multiple-Owner
  security to staging. An active Owner can create a seven-day, one-time Owner
  invitation for an exact email address. The invitee must verify that email
  through WorkOS before PFSS links a separate authentication subject, activates
  an independent Owner membership, and issues a revocable device credential.
  Invitation creation, acceptance, cancellation, and Owner revocation are
  audited; active Owner revocation also secures that Owner's devices, while the
  current and final active Owner remain protected. Strict TypeScript validation,
  all 46 Worker tests, and a direct full-app Swift type-check pass. Live signed
  iPhone/iPad multiple-Owner acceptance remains open.
