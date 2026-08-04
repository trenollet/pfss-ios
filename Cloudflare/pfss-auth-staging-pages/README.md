# PFSS Authentication Staging Callback

Upload the contents of the `public` folder to Cloudflare Pages using Direct
Upload. Do not upload this README as part of the public site.

After deployment:

1. Confirm the generated `*.pages.dev` site loads.
2. Add `auth-staging.patriot-ok.com` as the Pages custom domain.
3. Add the Squarespace CNAME only after Cloudflare shows the exact Pages target.
4. Verify `/callback`, `/operations-callback`, and
   `/.well-known/apple-app-site-association` over HTTPS.

This site contains no credentials, application secrets, analytics, forms, or
company data.

The registered staging callback must include its trailing slash:
`https://auth-staging.patriot-ok.com/callback/`. This avoids the Pages directory
redirect and preserves the authorization code and state query parameters.

The separate PFSS Operations application uses:
`https://auth-staging.patriot-ok.com/operations-callback/`.
