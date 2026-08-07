# PFSS Production Account Platform Architecture

- Status: Proposed for Phase 17
- Owner: PFSS Project
- Applies To: Phase 17 and production account services
- Last Updated: 2026-07-31

## Purpose

Define the stable PFSS boundary between human authentication, company tenancy,
subscription authority, and revocable device sessions.

## Identity Layers

PFSS treats these as separate durable concepts:

1. **Authentication subject** — the verified human account.
2. **Tenant membership** — the person's role and lifecycle inside one company.
3. **Device session** — one revocable credential for one installation.
4. **Employee record** — the operational workforce profile used by PFSS.

An authentication subject may hold memberships in more than one tenant. A
membership may link to an employee record, but neither record replaces the
other. A device receives company access only through an active membership.

## Registration Boundary

The registration coordinator accepts verified identity evidence, minimum
company profile, versioned legal consent, requested published plan, and device
attestation metadata. It never accepts a tenant ID, Owner role, raw price,
entitlement set, database name, bucket name, or storage path from the client.

After validation, one server-controlled transaction or compensating workflow
creates:

- authentication subject;
- subscription customer and approved allocation;
- tenant;
- first active Owner membership;
- first device session;
- initial recoverable synchronization snapshot; and
- immutable registration audit event.

The device credential is released only after all required resources are active.
Any failure revokes provisional credentials and removes or quarantines every
partial resource.

The staging coordinator completes a verified registration through
`POST /v1/account-registration/attempts/{id}/complete`. The registration token
authenticates that operation. One D1 batch claims the attempt, creates the
tenant, active Owner membership, subscription shell, server-issued beta plan
allocation, first revocable device credential, consent linkage, and audit
event, then marks the attempt active. The clear device credential is returned
only on the successful first completion. Repeated completion is idempotent and
does not reissue that credential. Production refuses this staging grant path
until an App Store authorization has been verified by the billing adapter.

## Service Boundaries

- Identity adapter proves the human identity and authentication method.
- Verification adapter delivers and validates short-lived challenges.
- Billing adapter authorizes the published plan and reports lifecycle changes.
- Registration coordinator owns the PFSS transaction and rollback policy.
- Entitlement engine converts the approved plan into server-enforced limits.
- Device-session service issues, rotates, and revokes installation credentials.
- Audit service records safe, immutable security and subscription events.

External providers remain replaceable adapters. PFSS owns tenant creation,
membership authority, device access, plan semantics, and audit history.

## Access Allocation Sources

PFSS uses one application and one entitlement engine. A tenant's effective plan
is backed by exactly one server-approved allocation source:

- `appStoreSubscription` — a transaction verified through Apple's server APIs;
- `betaGrant` — time-limited complimentary access for an invited beta company;
- `internalTesting` — isolated development or automated-test access;
- `internalBusinessGrant` — auditable, revocable access restricted to the PFSS
  operator's own company; or
- `promotionalGrant` — a future time-limited customer promotion.

The client cannot request or modify an allocation source. Complimentary grants
require an authenticated server-side issuer and a recorded reason. They may be
expired or revoked independently. The internal-business source is tenant-scoped
and cannot be inferred from an email address, device, build, or locally stored
flag.

Development-signed and TestFlight builds use Apple's sandbox for subscription
testing and never treat a simulated transaction as production access. Private
business-specific behavior should use tenant-scoped modules and feature flags
so it continues receiving changes from the shared PFSS codebase.

## Application Boundary

The iOS application presents registration and sign-in, stores only revocable
device credentials in Keychain, and consumes server-resolved session and
entitlement results. It does not calculate its own authority, approve its own
plan, or infer successful registration from partial responses.

The existing employee invitation-code flow remains a separate entry path. Both
Owner sign-in and employee activation converge only after the server has issued
a valid device session.

## Failure and Recovery Rules

- Registration requests use idempotency keys.
- A registration attempt expires after 30 minutes unless it has reached a
  later server-controlled provisioning state.
- The server stores digests of identity assertions and registration tokens,
  never their clear-text values. The registration token is returned only when
  the attempt is first created.
- The same idempotency key and normalized request returns the existing attempt;
  reuse with different input returns a stable conflict and creates nothing.
- Existing verified identities and active requests for the same identity or
  normalized company name return the same generic sign-in-required outcome so
  callers cannot discover which account or company already exists.
- Status and cancellation require the registration token. Cancellation is
  idempotent, while provisioning or active registrations cannot be cancelled
  through the pre-provisioning endpoint.
- Verification challenges expire and have attempt limits.
- Repeated completion requests return the same safe result or a stable terminal
  error; they never create a second tenant.
- Provider timeouts leave an explicit resumable or rollback state.
- Recovery invalidates used challenges and optionally rotates existing device
  sessions according to risk policy.
- Billing failure changes entitlements through a controlled lifecycle; it never
  silently deletes company data.
- Audit metadata excludes credentials, challenge values, and payment details.

## Required Architectural Decisions

Provider selection, authentication methods, MFA policy, billing integration,
plan definitions, production environment topology, and legal-consent ownership
must each be recorded before the corresponding external integration is built.

Current decision records:

- `../Decisions/ADR-003-App-Store-Subscription-Authority.md` — accepted Apple subscription
  boundary.
- `../Decisions/ADR-004-Managed-Owner-Identity.md` — accepted WorkOS AuthKit
  identity and verification boundary; staging setup remains required.
