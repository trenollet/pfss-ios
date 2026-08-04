# PFSS WorkOS Staging Setup

- Status: Required before live Phase 17 identity testing
- Owner: PFSS Project
- Last Updated: 2026-07-31

## Purpose

Connect PFSS to WorkOS AuthKit staging without allowing staging identities,
callbacks, credentials, or sessions to enter production.

## Permanent Domain Decision

PFSS needs a product-owned domain before hosted authentication or passkeys are
enabled. Do not use a temporary WorkOS domain for passkey enrollment and do not
bind the public product to the Patriot business website.

Recommended names after the PFSS product domain is acquired:

- Production identity host: `auth.<pfss-domain>`
- Temporary staging callback host: `auth-staging.patriot-ok.com`
- Production callback: `https://auth.<pfss-domain>/callback`
- Temporary staging callback:
  `https://auth-staging.patriot-ok.com/callback/`

The iOS app will claim only the exact callback hosts through Associated Domains.
No wildcard callback is permitted.

The temporary callback is hosted by the `pfss-auth-staging` Cloudflare Pages
project at `pfss-auth-staging.pages.dev`. Its trailing slash is required so
Cloudflare Pages does not redirect the OAuth callback and risk dropping the
authorization query parameters.

## WorkOS Environments

Create separate WorkOS staging and production environments. Initially configure
only staging:

1. Create the PFSS iOS public application.
2. Enable AuthKit and email Magic Auth with required email verification.
3. Configure the exact staging callback URL.
4. Keep passkeys disabled until the permanent custom domain is active.
5. Keep Sign in with Apple disabled until its callback and identity-linking
   acceptance tests are ready.
6. Enable the agreed Owner MFA policy for staging tests.

## Worker Configuration Contract

The following non-secret values are required in the staging Worker environment:

- `PFSS_ENVIRONMENT=staging`
- `WORKOS_ENVIRONMENT=staging`
- `WORKOS_API_BASE_URL=https://api.workos.com`
- `WORKOS_ISSUER=https://api.workos.com/`
- `WORKOS_REDIRECT_URIS=["https://auth-staging.patriot-ok.com/callback/"]`

The following values are required as encrypted Worker secrets:

- `WORKOS_CLIENT_ID=<staging application client ID>`
- `WORKOS_API_KEY=<dedicated staging Worker API key>`

PFSS refuses to start the managed adapter when environment names differ, URLs
are not HTTPS, callback entries are duplicated, or configuration is malformed.

Do not commit WorkOS API keys, webhook signing secrets, session tokens, refresh
tokens, or verification codes. The authorization-code exchange sends the API
key only as WorkOS's `client_secret` parameter while retaining PKCE verification;
neither credential nor returned session tokens may enter PFSS logs or responses.

## Staging Acceptance Gate

- Hosted AuthKit opens from an unactivated iPhone and iPad.
- Callback returns through the exact PFSS universal link.
- PKCE state mismatch, expired state, replay, and wrong callback are rejected.
- Verified email is required; access and refresh tokens are not exposed to the
  registration response or logs.
- Staging identity cannot create or enter a production tenant.
- MFA, cancellation, retry, identity linking, deletion, and provider outage are
  exercised before enabling production configuration.

## Related Documents

- `ProductionAccountPlatform.md`
- `../Decisions/ADR-004-Managed-Owner-Identity.md`
- `../Phase Development/Phase_17_Project_Workbook.md`
