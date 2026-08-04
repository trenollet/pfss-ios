# ADR-004: Managed Owner Identity and Verification

- Status: Accepted
- Date: 2026-07-31
- Last Reviewed: 2026-07-31

## Context

Production Owners need verified registration, durable sign-in, recovery,
multiple authentication methods, MFA, safe identity linking, and future
enterprise SSO. PFSS should not store passwords or build its own authentication
and email-verification service. The provider must support a native public client
without embedding a client secret and must keep staging separate from
production.

## Decision

Use WorkOS AuthKit as the initial managed identity and authentication provider.

- Use OAuth Authorization Code with PKCE for the iOS public client.
- Begin with email Magic Auth codes and required email verification.
- Require Owner MFA using supported AuthKit policy before sensitive recovery or
  company-security operations.
- Add Sign in with Apple after its callback and identity-linking paths pass
  staging tests.
- Defer passkey enrollment until PFSS owns and configures the permanent
  authentication domain; passkeys must not be issued against a temporary
  provider domain.
- Let WorkOS send authentication verification messages initially. Select a
  separate transactional-email provider only for PFSS business messages that
  fall outside authentication.
- Treat WorkOS user and organization identifiers as provider references. PFSS
  remains authoritative for tenant, membership, role, employee, device,
  subscription, entitlement, and audit records.

## Why WorkOS Is Recommended

- Managed email verification, identity linking, bot protection, passwordless
  codes, MFA, passkeys, social identity, and future SSO share one identity
  boundary.
- Staging and production environments are explicitly separate.
- Public-client PKCE is supported without storing a secret in the app.
- Current AuthKit pricing provides substantial room for PFSS's expected launch
  scale, while optional enterprise connections and custom domains remain
  separately priced.
- Using the provider's verification delivery avoids a second vendor during the
  first implementation.

## Rejected Initial Alternatives

- Self-hosted passwords and verification: excessive security and recovery risk.
- Email magic links: automated mail scanners can consume links before the user;
  numeric one-time codes are more reliable.
- Passkey-only launch: creates recovery and permanent-domain dependencies before
  the Owner account flow is proven.
- A separate identity organization as the PFSS tenant source of truth: would
  transfer business authority out of PFSS and duplicate Phase 16 access rules.

## Implementation Gate

Before changing this ADR to Accepted or binding production code:

1. Create isolated WorkOS staging and production environments.
2. Confirm the permanent PFSS authentication domain strategy.
3. Record key ownership, rotation, webhook signing, export, outage, and provider
   exit procedures.
4. Verify hosted mobile login, universal-link return, PKCE, email delivery, MFA,
   identity linking, and deletion in staging.

## Related Documents

- `../Architecture/ProductionAccountPlatform.md`
- `../Phase Development/Phase_17_Project_Workbook.md`
- `ADR-003-App-Store-Subscription-Authority.md`
