# PFSS Cloudflare Beta Worker

This Worker is the Phase 16 tenant-isolated beta boundary. D1 stores tenants,
one-time enrollment codes, device credentials, and idempotent offline-operation
receipts. R2 stores complete provider-neutral PFSS archives.

## Isolation invariant

The client never supplies a tenant ID for an authenticated request. The Worker
hashes the bearer device token, resolves its tenant in D1, and derives every
database predicate and R2 key prefix from that server-side identity.

## Provisioning

1. Install dependencies with `npm install`.
2. Authenticate Wrangler with `npx wrangler login`.
3. Create D1 database `pfss-beta` and replace the placeholder database ID in
   `wrangler.jsonc`.
4. Create R2 bucket `pfss-beta-archives`.
5. Apply migrations with
   `npx wrangler d1 migrations apply pfss-beta --remote`.
6. Deploy with `npm run deploy`.

Never commit enrollment codes, device tokens, `.dev.vars`, or `.env` files.

## Creating a beta tenant and one-time enrollment code

Run `pnpm tenant:create -- "Business Name"`. The utility creates a random
tenant identity and seven-day, single-use enrollment code. Only the code's
SHA-256 digest is sent to D1. The clear-text code is printed once for entry on
the owner's Data Management screen and is never stored by Cloudflare.
