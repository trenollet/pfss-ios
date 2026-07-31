# PFSS Phase 16 Project Workbook

## Data Management, Sync, Backup, and Restore

**Status:** Completed and accepted on 2026-07-31

Unchecked items explicitly labelled as deferred below are production-readiness
follow-ons. They remain visible for accountability but are not part of the
accepted Phase 16 delivery boundary.

### Phase Objective

Create a safe, provider-neutral data foundation that can support local backup,
iCloud synchronization, Google Drive backup and restore, and a future
multi-tenant Cloudflare service without allowing one customer's records to mix
with another customer's data.

### Planned Delivery Order

1. Portable archive format and versioned data contract.
2. Local backup, inspection, and guarded restore.
3. iCloud synchronization and recovery.
4. Google Drive backup and restore.
5. Cloudflare development and beta adapter.
6. Multi-user and tenant isolation boundary.
7. Recovery, migration, device, and regression testing.

---

# Step 1 — Portable Data Archive Foundation

## Goal

Define one PFSS-owned archive format before connecting any cloud provider. A
provider transports the archive or synchronized records; it does not own the
PFSS data schema.

## Implemented Data Contract

- [x] Added the `.pfssarchive` file type and PFSS media type.
- [x] Added independent archive-format and data-schema version numbers.
- [x] Added a manifest with archive identity, creation time, app version/build,
  business name, protection state, payload size, checksum, and record counts.
- [x] Included all primary local records and the durable offline-operation queue.
- [x] Added deterministic JSON encoding for stable, testable archives.
- [x] Added SHA-256 payload integrity validation.
- [x] Added strict validation before archive contents are returned for restore.
- [x] Added an explicit migration protocol and sequential migration boundary.
- [x] Reject archives created by a newer unsupported data schema.
- [x] Keep the existing on-device persistence format readable while sharing its
  snapshot model with the portable archive.

## Safety Rules

- Never mutate live application data while merely inspecting or validating an
  archive.
- Never silently accept damaged, incomplete, unsupported, or newer archives.
- Validate the media type, archive format, payload size, SHA-256 checksum,
  schema version, decodability, and record-count manifest before restore.
- Preserve pending offline actions so an exported device state does not lose
  field work awaiting synchronization.
- Treat integrity validation and encryption as separate responsibilities.
  Step 1 validates integrity; protected cloud export will add encryption before
  an archive leaves the device.

## Architecture Boundary

`AppDataStore` creates a `PFSSDataSnapshot`, which is wrapped with pending
offline operations in a `PFSSArchivePayload`. `PFSSArchiveService` creates and
validates the provider-neutral archive. Future iCloud, Google Drive, and
Cloudflare adapters will receive validated archive data through this boundary
rather than reading application collections independently.

## Automated Coverage

- [x] Archive round-trip preserves manifest metadata and primary records.
- [x] Multiple employee roles survive the portable archive round-trip.
- [x] Changed payload bytes fail integrity validation.
- [x] Unreadable files are rejected without attempting a restore.
- [x] Archives from a newer unsupported schema are rejected safely.

## Validation

- [x] Swift syntax validation passed for the archive service, store integration,
  and focused tests.
- [x] Repository whitespace and patch-integrity checks passed.
- [x] Focused `PFSSArchiveFormatTests` run in Xcode.
- [x] Full application build and regression suite run in Xcode.

### Environment Note

The command-line build environment did not have an available iOS simulator
runtime for the asset catalog compiler. No Swift diagnostic was emitted before
that environment-level failure. Final build and test confirmation remains an
Xcode validation action on the configured development machine.

## Step 1 Completion Criteria

- [x] PFSS has a portable, versioned archive contract.
- [x] The archive can be created from the current local store.
- [x] Archive contents are integrity checked before decoding.
- [x] Future schema migrations have an explicit extension point.
- [x] Cloud providers remain replaceable transport adapters.
- [x] Xcode build and focused tests confirmed by the product owner.

---

# Step 2 — Local Backup, Inspection, and Guarded Restore

## Goal

Give an owner a clear, provider-independent way to create, export, inspect,
and restore a complete PFSS backup without risking an accidental overwrite.

## Implemented Backup and Restore Workflow

- [x] Added a native `.pfssarchive` document type for Files export/import.
- [x] Added local Application Support backup storage with atomic writes.
- [x] Added unique, timestamped manual and pre-restore backup filenames.
- [x] Added newest-first local backup discovery and file metadata.
- [x] Added archive inspection without changing live application data.
- [x] Added an archive summary with business, version, creation, size, and
  per-record counts before restore.
- [x] Added a destructive confirmation step after inspection and before restore.
- [x] Added an automatic pre-restore safety backup of the complete current state.
- [x] Added replacement of primary records, assignments, and pending offline
  operations from the validated archive.
- [x] Added rollback to the original in-memory state if applying a restore fails.
- [x] Added a Settings → Data Management screen for backup and restore actions.
- [x] Added access to both manually created backups and automatic safety backups.
- [x] Added an Owner-labelled Danger Zone action to clear the complete local
  operational database.
- [x] Added two separate destructive confirmations before clearing any data.
- [x] Preserved local archive files and cloud backup history when the live local
  database is cleared.
- [x] Reset customers, sites, leads, estimates, jobs, invoices, business profile,
  catalog data, recommendations, employees, assignments, numbering state,
  route-session state, and pending offline operations.

## Restore Safety Rules

1. Selecting a file only reads and validates it; selection never restores data.
2. Damaged, incomplete, incompatible, or newer archives are rejected before any
   safety backup or live-data mutation occurs.
3. A validated summary is shown before the owner can confirm replacement.
4. Immediately before replacement, PFSS saves the current complete state as a
   separate pre-restore safety backup.
5. The restore includes queued offline work so pending field actions are not
   silently lost.
6. If applying the replacement fails, PFSS attempts to return every collection,
   assignment, and queued operation to its original state.

## Automated Coverage

- [x] A manual backup is written, listed, and read without changing its bytes.
- [x] A validated restore replaces the target business data.
- [x] Pending offline operations survive a backup and restore.
- [x] The automatic safety backup contains the target's pre-restore state.
- [x] A damaged archive is rejected before mutation.
- [x] A rejected archive does not create a misleading safety backup.
- [x] Clearing local data resets the store and durable offline queue.
- [x] Clearing local data does not delete an existing portable backup file.

## Validation

- [x] Swift syntax validation passed for the Step 2 services, store integration,
  user interface, and focused tests.
- [x] Repository whitespace and patch-integrity checks passed.
- [x] Focused `PFSSLocalBackupRestoreTests` run in Xcode.
- [x] Full application build and regression suite run in Xcode.

## Step 2 Completion Criteria

- [x] The owner can create a complete local backup and export it through Files.
- [x] The owner can inspect a local or imported archive before restoring it.
- [x] Restore requires explicit confirmation of a validated archive summary.
- [x] Current data is automatically backed up immediately before replacement.
- [x] Restored data includes the durable offline-operation queue.
- [x] A failed restore has an automatic rollback path.
- [x] Clearing the local database requires two explicit confirmations.
- [x] Backup files remain available after clearing the local database.
- [x] Xcode build and focused tests confirmed by the product owner.

### Owner Authorization Note

The action is intentionally placed and labelled as an Owner action. Phase 17
will enforce that policy against the authenticated user's role; Phase 16 does
not yet have a signed-in user identity to authorize against.

## Next Step

Step 3 will connect the provider-neutral foundation to iCloud. It will define
the iCloud container boundary, availability and account-state handling,
automatic synchronization behavior, recovery behavior, and conflict-safe
rules without changing the portable PFSS schema.

---

# Step 3 — iCloud Backup Synchronization and Recovery

## Goal

Synchronize validated PFSS archives through the signed-in Apple account so an
owner can recover business data on another Apple device without coupling the
PFSS schema to iCloud or weakening the guarded restore workflow.

## Implemented iCloud Boundary

- [x] Added the PFSS iCloud Drive and ubiquity-container entitlement definition.
- [x] Activated the entitlement for Debug and Release after enrollment under
  the paid Apple Developer team.
- [x] Registered and associated the dedicated
  `iCloud.com.patriot.PPS-Receipt-Printer` container.
- [x] Added explicit signed-out, unavailable, available, checking, and failure
  presentation states.
- [x] Added an iCloud Drive transport dedicated to complete `.pfssarchive` files.
- [x] Kept archive creation, validation, schema migration, and restore owned by
  PFSS rather than the cloud provider.
- [x] Added timestamped, collision-safe cloud archive names.
- [x] Added newest-first cloud backup discovery.
- [x] Retained the ten newest iCloud backups and removed older cloud history.
- [x] Added download support for iCloud items not yet present on the device.
- [x] Added Data Management controls to refresh status, back up immediately,
  and inspect the latest iCloud backup.
- [x] Routed iCloud recovery through the existing validation, preview,
  confirmation, pre-restore safety backup, and rollback workflow.

## Product Boundary

iCloud Drive synchronizes backups for the Apple account signed in on the
device. It is appropriate for an owner moving between their own Apple devices
and for disaster recovery. It is not the shared live database for a company of
multiple employees. Shared-company synchronization will use the tenant-isolated
server boundary in a later Phase 16 step so one company's records can never be
exposed through another company's account.

## Automated Coverage

- [x] An available iCloud transport uploads, lists, and reads archives.
- [x] The newest cloud archive is selected deterministically.
- [x] Cloud retention removes the oldest archive after the configured limit.
- [x] A signed-out device cannot read or write the iCloud container.
- [x] Downloaded iCloud data remains a valid provider-neutral PFSS archive.

## Validation

- [x] Swift syntax validation passed for the iCloud transport, UI integration,
  and focused tests.
- [x] Entitlement plist validation passed.
- [x] Repository whitespace and patch-integrity checks passed.
- [x] Paid Apple Developer team selected, entitlement attached, and iCloud
  Documents container registered for the app identifier.
- [x] Focused `PFSSICloudArchiveServiceTests` run in Xcode.
- [x] Full application build and regression suite run in Xcode.
- [x] On-device iCloud upload and second-device visibility confirmed.

## Step 3 Completion Criteria

- [x] PFSS reports whether iCloud backup is usable on the current device.
- [x] The owner can create a complete iCloud backup on demand.
- [x] The owner can inspect the latest iCloud backup before recovery.
- [x] iCloud recovery cannot bypass the Step 2 restore protections.
- [x] The iCloud implementation remains replaceable and provider-neutral.
- [x] Xcode build and focused tests confirmed by the product owner.
- [x] Real iCloud container behavior confirmed on signed-in Apple devices.

## Next Step

Step 4 will add Google Drive authorization, backup upload, history discovery,
download, and guarded recovery through the same archive boundary.

---

# Step 4 — Google Drive Backup and Recovery

## Goal

Allow an owner to connect a Google account, store complete PFSS archives in
Google Drive, inspect the latest cloud backup, and recover it through the same
guarded restore workflow used for local and iCloud backups.

## Implemented Google Drive Boundary

- [x] Configured the production iOS OAuth client identifier supplied by the
  product owner.
- [x] Added a native callback URL scheme for the Google authorization response.
- [x] Added OAuth authorization-code flow with PKCE and state validation.
- [x] Kept client secrets out of the application.
- [x] Requested only Google's narrow `drive.file` scope.
- [x] Stored the long-lived refresh token in the iOS Keychain using
  device-only protection.
- [x] Added automatic access-token refresh without repeated sign-in prompts.
- [x] Added multipart upload of provider-neutral `.pfssarchive` files.
- [x] Tagged PFSS-created Drive files with private app properties so discovery
  does not scan or request access to unrelated Drive content.
- [x] Added newest-first Drive backup history discovery.
- [x] Added download and inspection of the latest Google Drive archive.
- [x] Routed Google Drive recovery through validation, preview, confirmation,
  pre-restore safety backup, and rollback.
- [x] Added connect, refresh, backup, inspect, and disconnect controls to Data
  Management.

## Privacy and Tenant Rules

- PFSS can see only Drive files it creates or files the user explicitly shares
  with the app under the `drive.file` scope.
- The OAuth client ID and callback scheme are public app configuration. No
  Google client secret is stored in the app.
- Refresh credentials are stored in Keychain and removed when the owner
  disconnects Google Drive.
- Google Drive remains an owner-controlled backup/recovery destination. It is
  not the future shared multi-user tenant database.

## Automated Coverage

- [x] The configured client ID produces the expected native callback scheme.
- [x] The redirect URI is derived consistently from the native client.
- [x] PFSS requests the narrow per-file Drive permission.
- [x] The manager initializes in a stable, non-working state.

## Validation

- [x] Swift syntax validation passed for the Google Drive service, UI, and
  focused tests.
- [x] Callback Info.plist validation passed.
- [x] Repository whitespace and patch-integrity checks passed.
- [x] Confirm the Google Drive API is enabled for the OAuth project.
- [x] Confirm the OAuth consent screen permits the testing Google account.
- [x] Focused `PFSSGoogleDriveServiceTests` run in Xcode.
- [x] Full application build and regression suite run in Xcode.
- [x] On-device Google connection, upload, discovery, and guarded recovery
  confirmed.

## Step 4 Completion Criteria

- [x] The owner can authorize and disconnect a Google account.
- [x] PFSS can create and discover its own Google Drive backups.
- [x] The latest Drive archive can be inspected before restore.
- [x] Drive recovery cannot bypass PFSS restore protections.
- [x] Google Drive cannot inspect unrelated account files through PFSS.
- [x] Xcode build and focused tests confirmed by the product owner.
- [x] Real Google Drive behavior confirmed with the configured OAuth project.

## Next Step

Step 5 will add the Cloudflare development and beta adapter using explicit
tenant identifiers, server-authorized storage paths, and the existing durable
offline operation queue.

---

# Step 5 — Cloudflare Development and Beta Adapter

## Goal

Create a deployable Cloudflare Worker boundary for beta backup and ordered
offline-operation synchronization while making cross-tenant access impossible
through client-supplied identifiers.

## Implemented Server Boundary

- [x] Added a TypeScript Cloudflare Worker project with Wrangler configuration.
- [x] Added D1 schema migrations for tenants, one-time enrollment codes,
  devices, and idempotent synchronized-operation receipts.
- [x] Added an R2 archive binding for complete PFSS portable backups.
- [x] Added one-time enrollment-code exchange for a random device credential.
- [x] Stored only SHA-256 hashes of enrollment codes and device credentials in
  D1.
- [x] Added revocable, tenant-bound device records.
- [x] Added idempotent operation acceptance using a unique tenant/key boundary.
- [x] Added tenant backup upload, history, and latest-backup download endpoints.
- [x] Added explicit archive type and 100 MB beta upload limit enforcement.
- [x] Added deployment and beta-tenant provisioning documentation.
- [x] Added repository exclusions for local Worker dependencies and secrets.

## Tenant Isolation Invariant

The iOS app never supplies a tenant ID on an authenticated data request. The
Worker hashes the bearer device credential, resolves its tenant from D1, and
derives every D1 predicate and R2 key prefix from that server-side identity.
The R2 layout is `tenants/{serverResolvedTenantID}/backups/...`; a client cannot
choose or override that prefix.

## Implemented iOS Beta Client

- [x] Added HTTPS-only Worker endpoint configuration.
- [x] Added one-time device enrollment and Keychain credential storage.
- [x] Added beta backup upload, history refresh, latest archive inspection, and
  device disconnect controls to Data Management.
- [x] Routed beta recovery through the existing validated guarded restore.
- [x] Added an `OfflineSynchronizationAdapter` that sends durable operations
  with their existing idempotency keys and consumes server revisions.
- [x] Kept deployment secrets, Cloudflare API tokens, tenant IDs, D1 IDs, and R2
  credentials out of the iOS application.

## Automated Coverage

- [x] The client rejects non-HTTPS Worker addresses.
- [x] A fresh client has no implicit tenant credential.
- [x] The adapter constructor intentionally has no tenant-ID parameter.
- [x] Worker endpoint tests run against local D1 and R2 bindings.
- [x] Two-tenant negative tests prove credentials cannot list, download, or
  synchronize into another tenant's namespace.

## Validation

- [x] Installed Worker development dependencies and passed strict TypeScript
  validation.
- [x] Created the beta D1 database and Standard-class R2 bucket in the owner's
  Cloudflare account.
- [x] Replaced the Wrangler D1 placeholder with the generated database ID.
- [x] Applied D1 migrations and deployed `pfss-beta-api` with both bindings.
- [x] Created the isolated `PFSS Development` beta tenant and redeemed its
  single-use enrollment code on device.
- [x] Focused `PFSSCloudflareBetaServiceTests` passed as part of the complete
  Xcode test run.
- [x] Full application build and regression suite passed in Xcode.
- [x] On-device enrollment, backup upload, listing, download, archive inspection,
  guarded restore, and pre-restore safety backup confirmed against the live
  Worker.
- [x] Live offline-operation synchronization confirmed.

## Step 5 Completion Criteria

- [x] Tenant identity is resolved only from a server-validated credential.
- [x] Backup object paths cannot be selected by the client.
- [x] Offline operations are idempotent within a tenant.
- [x] Cloudflare account credentials are absent from the app and repository.
- [x] Local Worker tests and two-tenant isolation tests pass.
- [x] Deployed beta Worker passes backup and guarded-recovery device integration
  testing.

## Next Step

Step 6 will formalize multi-user tenant membership, roles, invitations, device
revocation, and the transition boundary into Phase 17 authentication and plan
limits.

---

# Step 6 — Multi-User Tenant Authority

## Goal

Place an active human membership between every device credential and tenant so
future Phase 17 authentication can attach verified users without changing the
tenant-isolation or offline-data contracts.

## Implemented Server Authority

- [x] Added a versioned D1 migration for tenant memberships.
- [x] Added Owner, Manager, and Member roles with active, invited, suspended,
  and revoked membership states.
- [x] Bound every enrolled device to one member inside one tenant.
- [x] Backfilled the existing beta tenant and device to an active Owner
  membership without changing its protected device credential.
- [x] Added a server-resolved session endpoint that returns display metadata
  without exposing a client-selectable tenant identifier.
- [x] Added tenant-scoped member and device inventories for authorized roles.
- [x] Added seven-day, single-use invitations whose clear-text code is returned
  once and whose digest alone is stored in D1.
- [x] Restricted Manager invitations and device administration to Member-level
  targets; Owner authority is required for elevated accounts.
- [x] Added immediate device revocation enforced during every authenticated
  request.
- [x] Updated first-tenant provisioning to create the Owner membership before
  issuing its enrollment code.

## Implemented iOS Boundary

- [x] Added typed tenant-session, member-role, and device metadata.
- [x] Refreshes server-resolved membership status with Cloudflare backup status.
- [x] Shows Company, Signed In As, Access Role, and This Device in Data
  Management after enrollment.
- [x] Selects the Cloudflare synchronization adapter at app startup whenever a
  valid endpoint and protected device credential are present; otherwise keeps
  the existing local-only mode.
- [x] Keeps tenant IDs absent from all iOS session and adapter constructors.
- [x] Prevents a transient post-enrollment refresh error from misreporting a
  successfully consumed one-time code as a failed enrollment.

## Owner Registration Contract — Required Phase 17 Entry Point

Owner registration is distinct from inviting a user into an existing company.
The production registration service must accept verified owner identity,
business profile, authentication method, recovery contacts, terms acceptance,
time zone, and initial plan selection. It must then create the following as one
atomic server operation:

1. Authentication subject and verified recovery methods.
2. Subscription customer and selected plan allocation.
3. New tenant with a globally unique server-generated identifier.
4. First active tenant membership with the Owner role.
5. First trusted device session attached to that Owner membership.
6. Immutable audit event recording tenant and ownership creation.

Registration must roll back completely if any component fails. PFSS must never
leave an ownerless tenant, a credential without a membership, or a membership
attached to a client-selected tenant. Email/phone verification, password and
federated sign-in, account recovery, duplicate-account handling, subscription
limits, and legal-consent versioning belong to Phase 17 authentication. The
Step 6 schema and role authority are intentionally ready for that subject to
replace beta enrollment without changing tenant-scoped data paths.

## Owner/Manager Administration Interface

- [x] Added role-aware Company Access navigation from Data Management.
- [x] Added company member names, roles, and lifecycle status.
- [x] Added enrolled-device inventory with owner, role, and last-seen status.
- [x] Added Owner invitations for Managers or Members.
- [x] Restricted Manager invitations to Members.
- [x] Displays a newly generated single-use code once with copy support and
  expiration guidance.
- [x] Added explicit revocation confirmation and explains that remote
  revocation does not erase data already stored on the physical device.
- [x] Prevents the current session from revoking itself in both the UI and
  Worker, avoiding accidental company lockout.
- [x] Hides administration navigation from Members and duplicates the same
  authorization rules on the Worker.

## Automated Isolation Coverage

- [x] Local tests use Cloudflare's Workers Vitest runtime with real D1 and R2
  bindings and all repository migrations.
- [x] Tenant A cannot list or download Tenant B's backup.
- [x] Identical idempotency keys remain independently valid in two tenants.
- [x] An Owner cannot revoke a device belonging to another tenant.
- [x] A Member cannot list members or create invitations.
- [x] A revoked device is rejected on its next authenticated request.
- [x] Strict TypeScript, Swift syntax, and repository whitespace validation pass.

## Deployment Validation

- [x] Applied `0002_tenant_membership.sql` to the remote beta D1 database.
- [x] Deployed Worker version `e9c81795-26d9-4e66-9518-7b6a856ff9d4`
  with the production D1 and R2 bindings attached.
- [x] Confirmed the existing enrolled device resolves to the backfilled Owner
  without re-enrollment or a client-supplied tenant identifier.
- [x] Focused Cloudflare client tests passed in Xcode.
- [x] Complete Xcode regression suite passed.
- [x] Confirmed a live technician-note operation automatically moved from the
  durable local queue to the tenant-isolated Worker without requiring manual
  Sync Now intervention.
- [x] Deployed current-session revocation protection to the beta Worker.
- [x] Full Xcode regression suite passed with the Owner/Manager administration
  client and UI.
- [x] Live Owner view shows the expected membership, role, and active device.
- [x] Current device cannot revoke itself.
- [x] Live invitation creation displays the expected role choices, single-use
  code, and expiration.
- [x] Redeemed an invitation on a second installation and confirmed the resulting
  membership and device appear only in the same tenant.
- [x] Revoked the second device and confirmed its next request is rejected while
  the Owner device remains connected.

## Next Step

Step 7 hardens recovery, access lifecycle, retention, device loss, interrupted
synchronization, and migration behavior before Phase 16 closes.

---

# Step 7 — Recovery and Lifecycle Hardening

## Access Lifecycle Foundation

- [x] Added `0003_access_lifecycle.sql` for invitation cancellation,
  credential-purge timestamps, and tenant-scoped access audit events.
- [x] Added pending-invitation cancellation; the code becomes unusable
  immediately and only its audit outcome remains.
- [x] Added Member suspension, reactivation, and permanent revocation.
- [x] Revoking a Member immediately revokes every device attached to that
  membership.
- [x] Managers may administer Members only; Owners may administer Managers and
  Members; Owner memberships remain protected.
- [x] The current membership and current device cannot disable themselves.
- [x] Added immutable access audit events for enrollment, invitation creation
  and cancellation, device revocation, member lifecycle changes, and cleanup.

## Retention and Cleanup

- [x] Added a daily Worker cleanup schedule.
- [x] Expired pending invitations close automatically.
- [x] Redeemed, cancelled, or expired invitation secrets are deleted after 30
  days.
- [x] Revoked device token hashes are irreversibly scrubbed after 90 days while
  non-secret audit metadata remains.
- [x] Owners can run the same safe cleanup manually and see exact purge counts.
- [x] Active views hide revoked/inactive entries by default with an explicit
  Show Inactive and Revoked option.

## Owner/Manager Lifecycle Interface

- [x] Added Cancel Pending Invitation with confirmation.
- [x] Added Suspend, Reactivate, and Revoke controls according to server role
  authority.
- [x] Added clear consequences for temporary suspension versus permanent
  revocation.
- [x] Added safe access-history cleanup guidance and result reporting.
- [x] Preserves business/audit history instead of hard-deleting referenced
  members or devices.

## Automated Coverage

- [x] Eight Workers-runtime D1/R2 tests pass.
- [x] Cancelled invitation codes cannot enroll a device.
- [x] Suspended members are denied and regain access after reactivation.
- [x] Revoked members remain denied while the Owner remains connected.
- [x] Owner memberships reject lifecycle mutation.
- [x] Retention cleanup deletes aged invitation secrets and scrubs aged revoked
  credentials without deleting device history.
- [x] Swift syntax, strict TypeScript, and repository whitespace checks pass.

## Deployment Validation

- [x] Applied `0003_access_lifecycle.sql` to remote D1.
- [x] Deployed lifecycle Worker version
  `85e1f65d-2173-4ead-9d6e-a32f06d87c27` with D1, R2, and daily
  `17 3 * * *` cleanup trigger attached.
- [x] Run focused access-management tests and the complete Xcode suite.
- [x] Live-test invitation cancellation.
- [x] Live-test Member suspension and reactivation.
- [x] Live-test permanent Member revocation and inactive-history filtering.
- [x] Confirm manual cleanup reports zero for newly created access records.

## Phase 16 Closeout — Data Management UI Refinement

Phase 16 remains open until the Data Management experience is simplified and
the resulting interface passes final regression and product-owner review.

### Required UI Cleanup

- [x] Reorganize backup providers, tenant access, local recovery, and destructive
  actions into a clearer information hierarchy.
- [x] Reduce the initial page density so routine backup actions remain easy to
  find without exposing every secondary control at once.
- [x] Keep provider status, latest-backup information, and primary actions
  immediately understandable.
- [x] Move advanced administration and recovery details into focused destination
  screens or disclosure areas where appropriate.
- [x] Preserve the two-stage local-database deletion confirmation and all archive
  inspection and restore safeguards.
- [x] Confirm the reorganized layout works cleanly on both iPhone and iPad.
- [x] Run the focused tests and complete Xcode suite after the UI refactor.
- [x] Complete product-owner acceptance of the final Data Management page.

### PFSS Cloud Product Alignment

The beta client now ships with the fixed
`https://pfss-beta-api.timrenollet.workers.dev` service address. Normal users
cannot view or replace the infrastructure endpoint. The production roadmap
requires a separate production Worker, data stores, credentials, and PFSS-owned
domain before live-customer release.

- [x] Treat the Cloudflare-backed PFSS Cloud service as required application
  infrastructure rather than an optional backup provider.
- [ ] **Deferred — Production Account Platform:** Enable tenant-isolated synchronization automatically after Owner account
  registration or invited-user sign-in, with no Worker address or provider
  configuration exposed to normal users.
- [ ] **Deferred — Production Account Platform:** When the production account platform is implemented, expand the current
  unauthenticated Device Activation screen with a functional `Create New
  Company` path for first-Owner registration. Keep invitation-code activation
  as the parallel path for employees and replacement devices; do not add a
  dead signup placeholder before the workflow exists.
- [x] Present the service only as PFSS Cloud in customer-facing language; keep
  the underlying infrastructure provider as an implementation detail.
- [x] Keep synchronization connectivity-aware and queue-driven so "always on"
  means automatic and resilient rather than continuous network polling.
- [x] Retain iCloud, Google Drive, and portable files as optional independent
  recovery copies, not primary synchronization paths.
- [x] Remove manual PFSS Cloud backup controls from routine user workflows once
  automatic synchronization and server recovery coverage are complete.

### Employee-Linked Membership and Device Administration

Employee archival now cancels a pending invitation or suspends an active linked
membership before changing the local employee lifecycle. The archive fails
closed if PFSS cannot confirm the security action, the employee-list swipe
bypass has been removed, and restoring the business record does not silently
reactivate authentication access.

Revoked memberships remain immutable audit records, but an authorized Owner or
Manager can invite the employee back through a new membership and fresh device
credential. Migration `0005_reinvite_revoked_employee.sql` permits one current
non-revoked membership per employee while retaining any number of revoked
historical memberships. The Worker regression suite covers invite, enrollment,
revocation, re-invitation, and replacement-device enrollment.

Live replacement-device testing exposed a partial enrollment failure in which a
previously registered device identifier collided after the invitation code had
already been marked redeemed. The client now generates a fresh identifier for
every credential-less enrollment, and Worker enrollment guards device creation
and code redemption in one database batch. Identifier conflicts return an
explicit HTTP 409 without consuming the invitation. Regression coverage proves
the same code succeeds on a subsequent valid device enrollment.

Live Member enrollment also exposed a role-ordering defect in the shared refresh
routine: it attempted to list Owner-only recovery archives before applying the
session role, causing a correctly enrolled Member to display a misleading
`forbidden` refresh failure. Refresh is now role-aware: Owners refresh recovery
archives, Managers refresh authorized team administration, and Members refresh
only their session state while normal queued synchronization remains available.

### Initial Device Synchronization Bootstrap

The original remote operation adapter accepted selected queued actions but did
not contain enough complete record data to hydrate a newly enrolled device.
Phase 16 now adds a separate internal synchronization snapshot boundary:

- Owner devices automatically publish a debounced, integrity-checked current
  company snapshot to a tenant-isolated R2 key.
- Any active tenant member may fetch only that tenant's current synchronization
  snapshot for in-app hydration; Members still cannot list, inspect, export, or
  restore recovery archives.
- Bootstrap applies only when the installation has no existing company data,
  validates the portable archive before mutation, and never copies the source
  device's pending operation queue.
- An Owner installation that is already empty attempts bootstrap before it can
  publish, preventing an empty replacement device from overwriting the current
  cloud snapshot.
- The Worker suite proves Owner-only publication, Member bootstrap access,
  cross-tenant isolation, no-cache delivery, and continued denial of Member
  recovery administration.

This closes initial hydration for beta testing. Complete record-level
bidirectional merging and conflict resolution remains a separate synchronization
layer; the existing queue continues to carry supported incremental field
operations without being represented as full-dataset replication.

### Incremental Record Synchronization

- [x] Convert changes to customers, sites, leads, estimates, jobs, assignments,
  invoices, employees, and catalog items into durable full-record mutations.
- [x] Add a paginated, tenant-isolated PFSS Cloud change feed with a durable
  per-installation cursor.
- [x] Push pending local operations before each pull and apply accepted remote
  records without creating synchronization loops.
- [x] Poll automatically while the app is active so normal use requires no
  visible Cloudflare controls.
- [x] Prevent Members from changing protected catalog data or another
  employee's identity record at the server boundary.
- [x] Add canonical tenant-scoped per-record revisions and reject stale writes
  without replacing the newer cloud value.
- [x] Persist each device's observed record revisions and translate a server
  revision conflict into the existing durable local/remote conflict envelope.
- [x] Add a human conflict-review UI with explicit Keep Cloud Version and Keep
  This Device's Version decisions, immediate local application of the selected
  cloud record, reviewed local resubmission, and durable resolution metadata.
- [x] Add a centralized Manager and Owner conflict inbox with unresolved counts,
  oldest-first triage, record-aware labels, conflicting-field summaries, and
  one authoritative review path outside the general synchronization activity.
- [x] Persist rejected multi-device changes as tenant-scoped PFSS Cloud conflict
  cases, synchronize them to Manager and Owner inboxes, deny Member inbox access,
  and apply authorized resolutions through the server before clearing review.
- [ ] **Deferred — Production Sync Hardening:** Add record-aware field comparison and field-level merge controls before
  declaring multi-writer synchronization production-ready.
- [x] Present record-aware device-versus-cloud field values together in the
  Manager and Owner conflict inbox before either whole-record decision.
- [ ] **Deferred — Production Sync Hardening:** Make conflict resolution authority-aware. A Keep This Device decision
  must never grant a user more mutation authority than their normal role and
  record permissions.
- [ ] **Deferred — Production Sync Hardening:** Allow Members to resolve only conflicts within their approved operational
  scope, such as their own notes or permitted field updates; route sensitive
  customer identity, pricing, invoice, employee, access, and administrative
  conflicts to a Manager or Owner.
- [x] Apply the conservative interim boundary: Members may accept the current
  cloud version but cannot submit a reviewed Keep This Device override. The app
  hides that choice and the Worker independently rejects it; Managers and
  Owners retain both whole-record choices until field-level policy is complete.
- [x] Record the authenticated resolver, role, affected fields, reason, original
  versions, and final accepted revision in the tenant audit trail. Do not treat
  device possession or last-write timing as decision authority.
- [ ] **Deferred — Production Sync Hardening:** Add tombstones for true record deletion; current archive/lifecycle edits
  synchronize as ordinary record updates.

- [x] Associate each tenant membership with the corresponding PFSS employee
  record while preserving distinct employee and authentication identities.
- [x] Move invitation creation, role/license management, enrolled-device
  visibility, and device revocation into the applicable employee detail page.
- [x] Make invitation roles and server authorization consistent with the
  employee's approved application role.
- [x] Add a concise Data Management summary of active licenses, pending
  invitations, and enrolled devices with guidance that access is managed under
  Employees.
- [x] Preserve an Owner-level cross-company access overview for auditing and
  exceptional device-loss response without making it the primary editing UI.
- [x] Cover employee archival, member suspension/revocation, invitation expiry,
  and device reassignment with explicit lifecycle rules and regression tests.

### Authenticated Employee Navigation and Identity

- [x] Add a `User Info` section to the Settings page for authenticated Sales,
  Technician, and Manager users. Show the linked employee's full name and
  readable PFSS application roles, for example `Geoff Nordmeyer` and
  `Sales, Technician`. Do not show this redundant section for the Owner.
- [x] Make the authenticated device membership and linked employee record the
  single source of truth for the employee identity shown in `User Info`; never
  infer identity from a manually selected employee or locally cached name.
- [x] Remove the Technician picker from `My Day` on employee devices. Selecting
  `My Day` must automatically use the employee linked to the authenticated
  device and navigate directly to that technician's greeting and schedule.
- [x] Prevent an employee device from switching `My Day` to another employee,
  including through stale navigation state, reload, or a previously saved
  technician selection. Define an appropriate non-technician experience for a
  Sales-only or Manager-only employee who opens `My Day`.
- [x] Remove the Dashboard `Settings` tile from Member employee devices. Keep the
  tab-bar destination available when an employee legitimately needs its
  permitted settings or account information.
- [x] Add an employee-facing `Sync Status` indicator to the Settings page's App
  Information section. Derive suspension and reactivation from the recurring
  authenticated PFSS Cloud check rather than only from pending local changes,
  and link the indicator to the existing synchronization activity details.
- [x] Rename the tab-bar and page title from `Admin`
  to `Settings`, then apply the approved name consistently to navigation,
  accessibility labels, help text, and documentation.
- [x] Add regression coverage for linked-employee identity display, Owner
  exclusion, automatic `My Day` routing, cross-employee schedule denial, and
  role-aware Dashboard tile visibility.

### Revoked-Device Company Data Removal

- [x] When a revoked device next contacts PFSS Cloud, return an authenticated,
  explicit company-data removal directive instead of only rejecting access.
- [x] Execute the directive before the app displays or processes any tenant data
  and prevent synchronization from rehydrating the revoked tenant.
- [x] Remove the tenant's local business records, assignments, pending offline
  operations, downloaded archives, cached documents, and tenant-scoped
  credentials from the revoked device.
- [ ] **Deferred — Production Removal Hardening:** Preserve only non-company application settings that are safe and necessary
  to return the app to its sign-in or enrollment state.
- [x] Make the removal operation atomic, idempotent, and recoverable after an
  interruption so a partially cleared tenant can never reopen.
- [x] Record the server-side directive issuance and device acknowledgement in
  the access audit trail without retaining the revoked device credential.
- [x] Ensure a revoked device that never reconnects remains cryptographically
  denied; document that network-triggered local removal cannot occur until the
  device contacts the service again.
- [ ] **Deferred — Production Removal Hardening:** Add regression coverage for revoked-device startup, foreground refresh,
  background synchronization, offline relaunch, interrupted removal, and
  attempted reuse of old credentials.

### Owner-Only Data Portability and Recovery

- [x] Restrict iCloud backup, Google Drive connection/backup, portable archive
  export, archive import, restore, and destructive local-data administration to
  the authenticated tenant Owner.
- [x] Hide restricted controls from Managers and Members and replace the Data
  Management content with a concise explanation that company recovery is
  Owner-managed.
- [x] Enforce the same policy in the application service layer and PFSS Cloud
  authorization boundary; UI visibility alone is not a security control.
- [x] Allow automatic internal safety snapshots needed for reliable recovery,
  but do not permit non-Owners to export, share, inspect, or restore them.
- [x] Remove stored Google Drive credentials and any tenant-scoped export state
  when a device enrolls as a non-Owner, changes from Owner to another role, or
  receives a company-data removal directive.
- [x] Prevent non-Owner devices from creating new company archives through
  background actions, deep links, stale screens, or previously granted cloud
  provider sessions.
- [x] Audit Owner archive creation, external-provider backup, import, restore,
  and local-database clearing without storing cloud-provider credentials.
- [x] Add regression coverage proving Managers, Members, suspended users, and
  revoked devices cannot extract or restore company data through any supported
  backup path.

## Final UI Debug Session

Complete one focused UI-debugging session before the final Phase 16 regression
run. This is a diagnostic and correction pass, not a feature-expansion pass.

- [x] Exercise every primary tab and Phase 16 destination on Owner, Manager,
  and Member devices while monitoring the Xcode console and Issue navigator.
- [x] Reproduce and trace any app-owned invalid-frame, negative-dimension,
  navigation, sheet, alert, keyboard, or constraint warnings. Use symbolic
  breakpoints where needed and distinguish PFSS layout defects from known
  simulator or system-framework noise.
- [x] Verify representative iPhone and iPad layouts used during Phase 16. The
  exhaustive portrait/landscape, light/dark, larger Dynamic Type, and unified
  bottom-navigation matrix is assigned to the required final pre-launch UI
  consistency pass in the product roadmap.
- [x] Verify long employee names, multiple-role labels, synchronization status
  text, empty states, confirmation messages, and activation guidance wrap or
  truncate intentionally without overlapping adjacent controls.
- [x] Verify tab, Dashboard tile, deep-navigation, dismissal, and relaunch state
  transitions for Settings, My Day, conflict review, access lifecycle, recovery,
  and Device Activation.
- [x] Correct every reproducible PFSS-owned UI defect, record any confirmed
  operating-system-only warning separately, and rerun the affected focused
  tests before starting the complete Xcode regression suite.

## Phase 16 Completion Gate

- [x] Complete all remaining live access-lifecycle checks.
- [x] Complete and approve the authenticated employee identity, `My Day`, and
  role-aware Dashboard navigation changes.
- [x] Complete and approve the Data Management UI refinement.
- [x] Complete the final UI debug session and resolve all reproducible PFSS-owned
  presentation defects.
- [x] Confirm local file, iCloud, Google Drive, and Cloudflare backup and restore
  entry points remain functional.
- [x] Record final build and regression results.
- [x] Phase 16 is complete. Production-only hardening and the final pre-launch
  UI consistency pass remain tracked separately and are not Phase 16 blockers.

### Latest Regression Record

- 2026-07-31: Phase 16 final Xcode closeout compiled the application and test
  targets and passed all 175 application unit and integration tests on the
  iPhone 17e simulator. The generated UI launch test timed out while Xcode was
  requesting simulator launch progress; the saved result contains no PFSS unit
  or integration failure. Real-device Owner, Manager, and Member UI walkthroughs
  completed the presentation verification, and the simulator-only launch-harness
  timeout is recorded separately rather than treated as an application defect.
- 2026-07-31: Product owner completed the Manager-role Data Management access
  check on iPad. The authenticated user was identified as a Manager and could
  manage employee and device access, while all Owner-only recovery, archive,
  import, restore, and database-clearing tools remained hidden. Creating and
  sharing a new Manager invitation also completed successfully. The accompanying
  visual-style, LaunchServices, usermanagerd, and hosted-scene messages were
  classified as operating-system share-controller diagnostics; no PFSS failure
  or incorrect role exposure was observed.
- 2026-07-31: Product owner confirmed the corrected sample invoice now opens in
  the dedicated in-app PDF viewer and provides the intended preview experience.
- 2026-07-31: Began the final live UI-debug pass on the Owner device. Network
  framework, QUIC, MapKit/VectorKit rendering and cleanup, performance telemetry,
  and SwiftUI visual-style console messages were classified as operating-system
  diagnostics because the corresponding PFSS screens displayed and navigated
  correctly. The pass identified one PFSS-owned semantic defect: `Preview Sample
  PDF Invoice` opened a system share controller, producing temporary-file and
  LaunchServices diagnostics instead of presenting the document. It now opens
  a dedicated in-app PDFKit viewer with normal dismissal. The conflict-inbox UI
  tests pass 3 of 3 without the prior Swift actor warnings, and the iOS simulator
  build succeeds after the PDF preview correction.
- 2026-07-31: Product owner completed the final Data Management interface
  review on iPhone and iPad and confirmed the reorganized page, collapsed and
  expanded recovery tools, provider actions, destructive safeguards, and
  responsive layouts all look and function as intended. The Data Management UI
  refinement and product-owner acceptance gates are complete.
- 2026-07-31: Product owner ran the authenticated Owner safe-cleanup action
  after live suspension, reactivation, and revocation testing. The server
  reported 0 expired invitation secrets removed and 0 revoked device
  credentials scrubbed, confirming the newly created records remain inside
  their retention windows. All remaining live access-lifecycle checks are now
  complete.
- 2026-07-31: Product owner completed live permanent-revocation verification.
  The employee device completed company-data removal, reopened at the protected
  Device Activation gate with normal PFSS tabs unavailable, and could not use
  its old credential. The revoked membership and device were absent from active
  access and visible only after enabling inactive and revoked history.
- 2026-07-31: Product owner completed live suspension and reactivation testing.
  The employee device reported `Access Suspended`, retained its authenticated
  employee name and roles, returned to `Fully Synchronized` after reactivation,
  and regained its linked `My Day` schedule without re-enrollment.
- 2026-07-31: Live employee lifecycle testing confirmed suspension. After the
  Owner suspended the active membership, the employee device's authenticated
  PFSS Cloud check reported `Access Suspended`. Local data remained intact for
  the reversible state, as designed. Reactivation remains to be confirmed on
  the same membership before closing the combined suspension/reactivation item.
- 2026-07-31: Product owner completed and approved live backup and recovery
  testing. Local file, iCloud, Google Drive, and PFSS Cloud backup and restore
  entry points are confirmed functional on the test devices.
- 2026-07-31: Added authenticated employee navigation. The Settings page now shows
  server-linked employee name and application roles for non-Owners. Employee
  devices route `My Day` directly to their own technician agenda, ignore stale
  or alternate technician selections, and show a role-appropriate unavailable
  state when the linked employee is not a Technician. The Dashboard Settings tile
  is Owner-only while tab-bar access remains available. All 13 focused identity
  and service tests pass and the iOS simulator test build succeeds.
- 2026-07-31: Product owner approved renaming the user-facing `Admin`
  destination to `Settings`. The tab label, navigation title, Owner Dashboard
  tile, derived accessibility text, and Phase 16 documentation now use the
  approved name consistently.
- 2026-07-31: Product owner completed live testing and approved the linked
  employee User Info, automatic employee-specific `My Day`, cross-employee
  schedule lock, and role-aware Dashboard navigation behavior.
- 2026-07-31: Added employee Sync Status under Settings → App Information. The
  existing queue status now incorporates the recurring PFSS Cloud authorization
  result, explicitly reports `Access Suspended` even when no edits are pending,
  and returns to normal after successful reactivation. The row opens the full
  synchronization activity view. All 19 focused identity and status tests pass
  and the iOS simulator test build succeeds.
- 2026-07-31: Refined the Settings Sync Status presentation after live device
  review. The oversized capsule-in-navigation layout was replaced by one
  standard compact row with status icon, status text, and disclosure chevron;
  the live authorization state and full activity destination are unchanged.
  The iOS simulator build succeeds.
- 2026-07-31: Live suspension testing exposed that the linked employee identity
  existed only in memory after session refresh, causing User Info to show a
  perpetual syncing state after relaunch while access was suspended. PFSS now
  retains the last server-authenticated role and employee link as device-local
  identity state across launches and reversible suspension, while permanent
  revocation/company-data removal erases it. All 14 focused Cloudflare identity
  and lifecycle tests pass and the iOS simulator test build succeeds.
- 2026-07-31: Live permanent-revocation testing confirmed company data and
  credentials were removed, but exposed that removal completion was handled
  only inside Data Management, leaving the root tab interface visible without
  a path to enter a replacement activation code. The protected app root now
  presents the Company Access Removed message and gates every unenrolled or
  revoked installation into a dedicated Device Activation screen. Unlinked
  identity wording is now `No Linked Employee Profile` in Settings and My Day,
  with administrator guidance on My Day. The iOS simulator build succeeds.
- 2026-07-30: Product owner confirmed the application build and complete Xcode
  test suite passed after the Data Management refinement, fixed PFSS Cloud
  endpoint, employee-linked access UI, revoked-device removal handling, and
  secure employee-archive lifecycle changes.
- Worker isolation suite passes 9 of 9 tests and strict TypeScript validation
  passes locally.
- Applied `0004_employee_security_alignment.sql` to remote beta D1 database
  `1648cb57-4d75-41bb-9268-71caa9569905`; the migration ledger reports no
  pending migrations and the new employee-link and removal-acknowledgement
  columns are readable.
- Deployed beta Worker version `861b0eb3-f410-4f8e-8024-7c261980bc37` with the
  expected D1, R2, and daily cleanup bindings.
- Confirmed the live session and backup endpoints both reject unauthenticated
  requests with HTTP 401 after deployment.
- 2026-07-30: Product owner confirmed the updated application built and the full
  Xcode suite passed on both test devices after the replacement-device
  enrollment correction.
- Applied `0005_reinvite_revoked_employee.sql`; the remote ledger reports no
  pending migrations and the unique employee-membership index now applies only
  to non-revoked memberships.
- Deployed Worker version `df07ef53-4461-42d6-a1f7-618e2a083dfe`, confirmed the
  expected D1/R2/cleanup bindings, and reconfirmed unauthenticated session access
  returns HTTP 401.
- 2026-07-30: Product owner confirmed both test devices built successfully and
  were ready for initial synchronization hydration testing.
- Deployed Worker version `ed7d956e-ced1-4a40-837e-13968621a57b` with the
  tenant synchronization snapshot publish/bootstrap boundary. No migrations
  were pending, expected D1/R2/cleanup bindings remained attached, and both
  synchronization endpoints rejected unauthenticated access with HTTP 401.
- 2026-07-30: Added the first complete incremental record push/pull path across
  enrolled devices. Worker isolation and authorization coverage passes 14 of
  14 tests, strict TypeScript validation passes, and the iOS simulator build
  completes successfully.
- Deployed Worker version `633ab65a-c300-4dd4-840f-675ac20a0b2d` with the
  tenant-scoped synchronization change feed; the live unauthenticated feed
  request returns HTTP 401 as expected.
- 2026-07-30: Applied `0006_canonical_record_revisions.sql` and deployed Worker
  version `feef12d8-c345-4272-8080-d7a324951cc7`. The Worker now protects each
  tenant record with an optimistic revision, preserves the current canonical
  operation when a stale device writes, and returns both versions for review.
- Worker isolation, authorization, feed, and stale-write coverage passes 15 of
  15 tests; strict TypeScript validation and the iOS simulator build pass.
- 2026-07-30: Added conflict review to Sync Status. Focused Cloud client and
  conflict resolver tests pass 15 of 15, including preservation, automatic
  merge, reviewed local resubmission, and durable resolution behavior.
- 2026-07-30: Added role-aware conflict authority. Worker authorization tests
  pass 16 of 16, strict TypeScript validation passes, and the iOS simulator
  build succeeds. Deployed Worker version
  `a3a1ec5d-d5a8-4160-b44b-cfea2c1e302e`.
- 2026-07-30: Applied `0007_synchronization_conflict_inbox.sql` to the remote
  beta D1 database and deployed Worker version
  `23c0f5a2-21c8-46bc-8173-31f9040d553e`. The migration ledger reports no
  pending migrations, the tenant conflict table and indexes are readable, and
  unauthenticated session and conflict-inbox requests both return HTTP 401.
- 2026-07-30: Deployed Worker version
  `12847fe0-d948-4f7f-a1cc-b59b0afb39be` with recovery reporting for conflicts
  already durable on a Member device. The client now backfills any unresolved
  local case that lacks a server ID, allowing existing cases to reach the
  Manager and Owner inbox without recreating the conflicting edit.
- 2026-07-30: Live testing showed an older local conflict could lack the remote
  revision needed by the first recovery request. Deployed Worker version
  `c2bec395-eb66-4d9c-9a47-1f9711ce1260`; PFSS Cloud now validates recovery
  reports against its own canonical record and the Member log exposes delivery
  failures instead of silently retrying them.
- 2026-07-30: Deployed Worker version
  `286165c4-cfcb-41f4-9628-c4075b79eb29` with tenant resolution receipts and a
  source-device recovery query. Employee devices now convert their durable
  conflict log entry to synchronized after a Manager or Owner decision,
  including decisions completed before the receipt feed was deployed.
- 2026-07-30: Applied `0008_conflict_resolution_audit.sql` and deployed Worker
  version `d5d956d6-913a-4c6f-9b7e-935fff2083d1`. Conflict decisions now retain
  authenticated resolver identity and role, optional reason, affected fields,
  both original operations, and the final canonical revision. Owner-only audit
  retrieval is covered by the 16-test Worker authorization suite.
- 2026-07-30: Deployed Worker version
  `1b5f4063-5827-40f3-8338-1227172a85e5` with employee-linked invitation-role
  enforcement. The client derives access from approved PFSS employee roles,
  and the Worker independently rejects linked Manager elevation unless the
  canonical employee record authorizes it.
- 2026-07-30: Closed the employee self-promotion path. Management UI now uses
  the authenticated PFSS Cloud membership, employee role editing is unavailable
  to Members, and Worker version `78023d95-7ab4-47ec-acbc-2fce27c72ca8`
  independently rejects changes to a Member's accepted employee roles. The
  Worker suite passes 17 of 17 tests and the iOS simulator build succeeds.
- 2026-07-30: Restored an Owner-only company access overview under Data
  Management for company-wide membership, device, inactive-history, and lost
  device review while employee detail remains the primary access workflow.
- 2026-07-30: Began employee access lifecycle hardening with a centralized iOS
  transition policy and immediate server-side invitation expiry. Expired
  invitations are now closed and audited when access is listed or a replacement
  invitation is requested, so they cannot occupy an employee's current access
  slot until the daily cleanup runs. The Worker suite passes 18 of 18 tests,
  strict TypeScript validation passes, and the iOS simulator build succeeds.
- 2026-07-30: Completed the employee-linked access lifecycle boundary. Employee
  archive now calls one server-authoritative transition that atomically cancels
  pending invitations or suspends active access before the local record is
  archived. Restore leaves authentication unchanged, reactivation remains a
  separate authorized decision, revocation remains permanent, and replacement
  devices receive a new membership and credential. The end-to-end Worker suite
  passes 19 of 19 tests, strict TypeScript validation passes, and the iOS
  simulator build succeeds.
- 2026-07-30: Hardened Owner-only data portability below the interface. Manual,
  iCloud, Google Drive, and PFSS Cloud archive inspection, creation, restore,
  and destructive local clearing now require the authenticated Owner role at
  the application-service boundary, including actions originating from stale
  screens or existing provider sessions. Manager and Member denial regression
  coverage was added, and the iOS simulator build succeeds.
- 2026-07-30: Completed local recovery-credential revocation. Non-Owner
  enrollment, Owner role downgrade, and company-data removal now erase the
  Google Drive refresh credential, cancel active authorization, discard
  in-memory access and archive/export state, and close active import or export
  presentation. Internal synchronization safety snapshots remain available but
  cannot be inspected, exported, or restored by a non-Owner. The focused
  Google Drive and local recovery suites pass 9 of 9 tests, and the iOS
  simulator build succeeds.
- 2026-07-30: Added server-backed Owner recovery auditing for archive creation,
  local export, iCloud, Google Drive, PFSS Cloud backup, archive import,
  restore, and destructive local clearing. The Worker accepts only allowlisted
  event and provider values and stores authenticated tenant, member, and device
  identity without filenames, archive contents, provider accounts, or tokens.
  The Worker suite passes 20 of 20 tests, strict TypeScript validation and the
  iOS simulator build pass, and beta Worker version
  `e3c7c4c3-8797-4f79-920e-0647b671ca77` is deployed. Live unauthenticated
  access to the audit endpoint returns HTTP 401.
- 2026-07-30: Completed the Owner recovery security regression matrix. The iOS
  service boundary proves the Owner can create, inspect, restore, and clear
  while Managers and Members cannot mutate or extract company recovery data.
  Server coverage proves even credentials originally issued to an Owner lose
  backup download, upload, and audit access immediately after suspension or
  revocation; revoked devices receive removal instructions and become HTTP 401
  after acknowledgement. The focused iOS recovery suites pass 25 of 25 tests,
  the Worker isolation suite passes 21 of 21 tests, strict TypeScript
  validation passes, and the iOS simulator test build succeeds.
