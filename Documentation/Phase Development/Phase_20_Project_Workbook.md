# PFSS Phase 20 Project Workbook

## Multi-Device Synchronization Architecture

**Status:** Complete — accepted 2026-08-26 on build 20.7.29

**Created:** 2026-08-14

## Phase Objective

Replace broad whole-record conflict handling with a server-authoritative,
versioned, field-aware synchronization architecture that safely supports
multiple online and offline devices. PFSS must automatically reconcile routine
changes, preserve legitimate offline work, isolate malformed operations, and
reserve Manager/Owner review for consequential business conflicts.

## Architecture Principles

- The PFSS server is canonical for record revisions, accepted timestamps,
  authorization, lifecycle state, and synchronization ordering.
- Devices submit versioned intent, field patches, or domain commands instead of
  replacing complete records wherever practical.
- Device timestamps remain audit evidence and never independently determine
  authority.
- Offline business actions use stable operation identifiers and are safe to
  replay without duplication.
- One malformed or rejected operation must not block unrelated queued work.
- Archive and deletion use server tombstones so stale devices cannot resurrect
  removed records.
- Human conflict review is limited to incompatible, consequential decisions.

## Step 1 — Current-State Audit and Policy Registry

- [x] Inventory every synchronized entity, mutation, queue dependency, server-
  owned field, derived field, append-only event, and authorization boundary.
- [x] Classify each field as server-owned, client-editable, derived,
  commutative, append-only, relationship, lifecycle, or security-sensitive.
- [x] Define explicit merge and conflict policies for each entity and field.
- [x] Capture baseline metrics for queue age, failures, conflicts, stale-device
  recovery, schema decode errors, and manual resolutions.

Implementation evidence:

- `Documentation/Architecture/SynchronizationCurrentStateAudit.md`
- `Documentation/Architecture/SynchronizationPolicyRegistry.md`
- `SynchronizationBaselineMetrics` creates a deterministic snapshot of current
  queue age, status/entity/failure counts, retries, conflicts, schema errors,
  and the estimated unrelated work blocked by global queue ordering.
- Stale-device recovery and server-resolution metrics are registered as new
  Phase 20 protocol metrics because the current client has no durable recovery
  session or server change cursor.

Verification note:

- Source and documentation validation passed. Three focused
  `SynchronizationBaselineMetricsTests` pass on the iPhone 17e simulator.
- Untracked duplicate files whose names ended in ` 2.swift` were moved intact
  to a dated quarantine folder outside the Xcode project before verification.

## Step 2 — Versioned Mutation Envelope

- [x] Introduce a backward-compatible, schema-versioned mutation envelope with
  operation ID, tenant, device, record ID, entity, base revision, changed
  fields or command, and audit timestamps.
- [x] Preserve unknown fields and migrate queued payloads created by supported
  older application builds.
- [x] Make server-controlled revisions and acceptance sequences immutable to
  clients.
- [x] Keep existing whole-record mutations readable during the transition.

Implementation evidence:

- `SynchronizationMutationEnvelope` defines schema version 2, stable operation
  and record identity, authenticated-context evidence, base revision, mutation
  kind, changed fields, command identity, audit timestamps, and unknown-field
  preservation.
- `OfflineRecordMutationCodec` writes version 2 while decoding both version 2
  and legacy Phase 15–19 whole-record payloads.
- Record application, conflict comparison, and catalog auto-rebase now use the
  compatibility codec.
- The beta Worker rejects mismatched operation, tenant, device, entity, record,
  and base-revision context before applying a version 2 mutation.
- Six focused Phase 20 client tests pass on the iPhone 17e simulator, including
  legacy decoding and unknown-field round trips.
- `Documentation/Architecture/SynchronizationMutationEnvelope.md`

## Step 3 — Resilient Dependency-Aware Queue

- [x] Process independent records without global head-of-line blocking.
- [x] Preserve ordering only where records or commands have real dependencies.
- [x] Quarantine malformed or permanently rejected operations with an exact
  repair, retry, supersede, or discard path.
- [x] Add bounded retries, exponential backoff, idempotency enforcement, and
  compact Action Required presentation.
- [x] Verify a poison operation cannot stall unrelated company work.

Implementation evidence:

- Queue dependencies are derived from record identity plus optional aggregate
  keys and explicit prerequisite operation identifiers.
- The processor scans beyond delayed, failed, and conflicted operations while
  preserving ordering inside the affected dependency chain.
- Quarantined operations retain durable reason and action metadata and can be
  retried, superseded, or discarded without erasing audit history.
- Existing bounded retry/backoff and idempotency behavior remains active, and
  successful operations are not replayed by manual synchronization.
- Sync Status identifies quarantined work in the compact Action Required
  section without burying the blocking item behind pending queue entries.
- `Documentation/Architecture/SynchronizationDependencyAwareQueue.md`

Verification note:

- Twenty focused queue, synchronization service, and mutation-envelope
  regression tests pass on the iPhone 17e simulator, including poison-operation isolation,
  record-local blocking, retry-delay isolation, explicit discard, durable
  retry recovery, and no duplicate successful delivery.

## Step 4 — Pull, Cursor, and Stale-Device Recovery

- [x] Add a tenant-scoped server change sequence and per-device durable cursor.
- [x] Pull and apply authoritative deltas before upload after extended offline
  periods, application/schema upgrades, or cursor uncertainty.
- [x] Rebase queued intent against current server revisions.
- [x] Classify stale changes as replayed, merged, already reflected,
  superseded, quarantined, or requiring review.
- [x] Present one understandable recovery summary instead of dozens of routine
  conflicts.

Implementation evidence:

- Migration `0023_phase20_tenant_sync_cursors.sql` creates a tenant-scoped
  accepted-change sequence and durable per-device acknowledgement cursor, with
  a deterministic backfill of previously accepted operations.
- The Worker change feed now reads the tenant sequence, reports the current
  server cursor, records monotonic device acknowledgements, and tags bootstrap
  archives with the matching cursor.
- Device synchronization now pulls and applies authoritative company changes
  before uploading queued work, then performs a second pull after upload.
- Same-record queued mutations are classified as already reflected,
  superseded by a cloud change older than the eight-hour stale window, or left
  queued for the normal policy and human-review path.
- Sync Status shows one persisted Latest Device Recovery summary rather than a
  stream of routine stale-device conflicts.
- `Documentation/Architecture/SynchronizationPullCursorRecovery.md`

Verification note:

- The beta Worker passes TypeScript validation.
- Focused iOS recovery-summary, versioned-envelope, and dependency-aware queue
  tests pass on the iPhone 17e simulator.
- Staging migration `0023` was applied on 2026-08-15 and backfilled 2,075
  accepted changes. Worker version
  `bdfd2e4c-9933-4367-9130-2ff090a50bb8` was deployed successfully.
- Signed clients installed on iPhone17e and iPad Pro M1 each pulled their
  authoritative tenant feed and durably acknowledged a device cursor.
- The Worker regression suite now contains 68 passing tests, including the
  versioned mutation envelope and legacy-compatibility paths.

## Step 5 — Three-Way Merge and Domain Commands

- [x] Compare base, current server, and intended device changes.
- [x] Automatically merge independent field edits.
- [x] Convert notes, timeline actions, payments, mileage events, and similar
  facts to immutable append operations with stable IDs.
- [x] Route assignment, scheduling, lifecycle, recurring-work, billing,
  permission, archive, and revocation changes through authorized domain
  commands and explicit policies.
- [x] Recompute or preserve derived values through command policies instead of
  treating unrelated device and cloud values as user conflicts.

Implementation evidence:

- Phase 20 mutation envelopes carry the device's synchronized base snapshot,
  intended record, changed paths, schema version, device identity, and stable
  mutation identity.
- The Worker performs a true base/current/intended three-way merge. Independent
  field edits are accepted together; same-field contradictions remain eligible
  for focused review.
- Job timeline events, assignment history/notes, and invoice receipt/payment
  facts use append semantics with stable identities instead of replacing an
  entire record collection.
- Status, scheduling, assignment, recurring-work, lifecycle/archive, and
  payment changes are classified into explicit domain commands with per-command
  field allowlists.
- Pre-Phase-20 unresolved conflicts are retired only when the authoritative
  record already proves the legacy operation was applied or superseded. Any
  ambiguous historical conflict remains available for human review.

Verification evidence:

- Worker regression: 68 tests passed.
- Worker TypeScript validation: passed with no errors.
- iOS classifier coverage was added for independent patches, append facts,
  payment commands, scheduling, assignments, recurring work, and lifecycle
  commands.
- The signing-free iOS compile reached Swift compilation, but the local Xcode
  CoreSimulator service has no available simulator runtimes and stopped asset
  catalog compilation. This is an environment limitation, not a claimed iOS
  build or simulator-test pass.
- Signed two-device acceptance remains required before Step 5 is considered
  operationally accepted.

## Step 6 — Focused Conflict Review and Propagation

- [x] Create review items only for unresolved same-field or semantic business
  contradictions.
- [x] Show actual device, cloud, and common-base values plus operational impact.
- [x] Resolve atomically on the server with authorization, reason, policy
  version, audit evidence, and normal change-feed propagation.
- [x] Clear or supersede the originating device operation automatically after
  resolution.

Implementation evidence:

- The Worker derives focused review fields from common-base, device-intended,
  and current-cloud records. Legacy conflicts retain a conservative fallback.
- The Manager/Owner inbox displays all three values and explains scheduling,
  assignment, billing, lifecycle, security, or general shared-data impact.
- Resolution requires a reason and records policy version 1, resolver identity
  and role, affected fields, original/final revisions, and audit evidence.
- One conditional D1 batch atomically updates the conflict and canonical record,
  creates the idempotent receipt, appends the tenant change feed, and writes the
  audit event. A cloud revision change rejects and refreshes a stale review.
- Source-device receipts and the normal cursor feed clear or supersede the
  originating queued operation without a second decision.
- `Documentation/Architecture/SynchronizationFocusedConflictReview.md`

Verification evidence:

- Worker regression: 70 tests passed; TypeScript validation passed.
- Focused iOS conflict-inbox and Cloudflare service tests passed on the iPhone
  17e simulator, including common-base display and independent-field exclusion.
- The complete iOS unit-test target passed 265 tests on the iPhone 17e
  simulator. The combined unit/UI run reached the UI runner but Xcode's LLDB
  service did not attach; no UI-test result is claimed from that stalled run.
- Signed Debug builds succeeded for the physical iPhone17e and iPad Pro mini,
  and the updated app was installed on both devices.
- Staging migration `0024_phase20_focused_conflict_resolution.sql` was applied
  after capturing a D1 recovery bookmark. The schema was verified remotely.
- Staging Worker version `8a61706f-a560-49af-a8cd-901d25daa2d9` deployed
  successfully on 2026-08-22.
- Product-owner acceptance passed on 2026-08-22 using a non-manager iPad and a
  Manager/Owner iPhone. A same-field customer conflict reached the centralized
  inbox, displayed the focused review, resolved successfully, converged on both
  devices, and cleared the originating device conflict automatically.

## Recovery Safety Fix — Clear Local Database

- [x] Reproduce and identify incremental-only recovery after an Owner clears
  the local database.
- [x] Invalidate persisted and in-memory cursors and baseline markers as part
  of the Owner clear operation.
- [x] Block queued uploads and Owner snapshot publication until recovery is
  complete.
- [x] Rebuild from the validated tenant archive and overlay every current
  tenant-scoped canonical record before accepting a new cursor.
- [x] Advance the baseline generation so already-affected devices are forced
  through guarded recovery after installing the corrected client.
- [x] Deploy the corrected Worker and install the signed app on the affected
  Owner iPhone.
- [x] Verify the recovered Owner iPhone restores its company data after the
  guarded baseline rebuild.

Implementation evidence:

- `PFSSCloudSnapshotPublisher.beginOwnerLocalRecovery()` cancels publication,
  clears delivery checkpoints, and closes the bootstrap gate immediately after
  the authorized local reset succeeds.
- `/v1/sync/baseline-records` returns only the authenticated tenant's current
  canonical operations and authoritative cursor.
- The client applies the archive and canonical overlay before storing baseline
  generation 5 or resuming synchronization.
- `Documentation/Architecture/SynchronizationLocalDatabaseRecovery.md`

Verification evidence:

- Worker regression: 70 tests passed, including tenant isolation for canonical
  recovery records; TypeScript validation passed.
- Focused iOS regression coverage verifies the Owner clear callback occurs only
  after the local company store is empty.
- The simulator build completed Swift compilation, but the local Xcode UI test
  runner stalled during attachment as previously observed. The interrupted run
  is not claimed as a focused iOS test pass.
- The final signed iOS build succeeded and was installed on the Owner
  iPhone17e. Staging Worker version
  `65e84611-798d-4d04-8fb8-cc3d1cfa6e72` serves the canonical baseline
  endpoint.
- Product-owner acceptance passed on 2026-08-22: after opening the corrected
  app, the previously cleared Owner iPhone17e completed guarded recovery and
  its company data returned without another local-database clear.

## Step 7 — Push Hints, Reconciliation, and Observability

### Centralized Quarantine Management Precursor

- [x] Add tenant-scoped server storage for source-device quarantines.
- [x] Deliver exact mutation comparison, failure, affected fields, and
  operational impact to a Manager/Owner Quarantine Inbox.
- [x] Require an authorized, reasoned, atomic discard or retry decision.
- [x] Return an idempotent receipt that clears or retries the originating
  device operation automatically.
- [x] Preserve audit history and distinguish unaccepted discard from an
  authorized compensating reversal.
- [x] Complete signed two-device acceptance using existing employee-iPad
  quarantines and the Owner iPhone17e.

Verification and deployment evidence:

- Worker regression: 71 tests passed; TypeScript validation passed.
- iOS application and test targets compile successfully. The focused simulator
  runner again stalled during Xcode attachment and was stopped; no executed
  simulator-test pass is claimed.
- D1 recovery bookmark before migration:
  `0000024e-00000000-000050cf-98f38a85039c9986244c479356de90ef`.
- Migration `0025_phase20_centralized_quarantine.sql` applied successfully.
- Staging Worker version `5755de20-5959-45d5-900b-f6ff8d8c1a09` deployed.
- The final signed build succeeded and installed on the employee iPad Pro mini
  and Owner iPhone17e.
- Live acceptance confirmed three iPad quarantines reached the Owner iPhone.
  The Owner discarded one with a required reason; the server stored action
  `discard`, reduced the inbox from three to two, and wrote exactly one audit
  event. The remaining Conflict label was verified as a distinct operation for
  the same assignment record and source device, not a reclassification of the
  discarded quarantine.
- Retry acceptance confirmed an unchanged invalid assignment operation was
  released to the source iPad, failed validation again, and reopened the same
  tenant quarantine review approximately 0.6 seconds later with a separate
  retry audit event. This proves retry does not bypass normal policy.
- Final discard acceptance confirmed the authorized decision removed the
  quarantined operation from the Manager inbox and from Sync Status on both the
  employee iPad and Owner iPhone.
- Retry-cycle hardening deployed as staging Worker version
  `2b8f640c-63c0-44fd-b4d8-30fdffc2cca2`; the matching signed client was
  installed on both acceptance devices.
- `Documentation/Architecture/SynchronizationCentralizedQuarantineReview.md`

### Consent-Based Synchronization Support Diagnostics — Build 20.7.2

- [x] Add **Settings → Send Sync Diagnostics** for every enrolled role.
- [x] Explain exactly what is and is not included and require explicit consent
  before every submission.
- [x] Collect only redacted synchronization identifiers, state, timestamps,
  failure codes, retry results, cursor, app build, and recovery summary.
- [x] Add the trusted tenant/member/device header on the server rather than
  accepting identity from the client.
- [x] Store a tenant-scoped case index in D1 and the redacted package in the
  private R2 archive bucket.
- [x] Return a readable `PFSS-XXXX-XXXX` support case number.
- [x] Enforce a 256 KB limit, five submissions per device per hour, audited
  access/deletion, and automatic 30-day removal.
- [x] Verify a submitted device case can be retrieved without connecting to or
  exporting the device database.

Verification and deployment evidence:

- Worker regression: 73 tests passed; TypeScript validation passed.
- The signed iOS app and test targets compiled successfully on the connected
  physical-device destination. Simulator execution is not claimed because the
  local simulator runtimes remain unavailable.
- D1 recovery bookmark before migration:
  `00000257-00000000-000050cf-24349ab9b06c950cdbdee3024efcb266`.
- Migration `0027_phase20_sync_diagnostics.sql` applied successfully.
- Staging Worker version
  `50e359a9-0fc4-43cc-906e-865c0119d152` deployed.
- Build 20.7.2 installed on Tim-iPhone17pro without clearing local data.
- Live acceptance case `PFSS-C6XB-PN2D` contained the trusted Patriot tenant,
  Owner member, Tim-iPhone17pro device, iOS 26.6, and build 20.7.2 header. The
  10,608-byte redacted package reported cursor 1214 and 13 synchronized
  operation summaries. Inspection found no payload, body, record data, base
  record data, or conflict-version fields. The temporary downloaded copy was
  deleted immediately after verification.
- Build 20.7.3 corrected the diagnostics link placement so employees see it in
  App Information beneath Sync Status without requiring the Owner-only Account
  Security section. Employee acceptance case `PFSS-AMW2-BPA5` correctly
  identified role `member`, the enrolled iPad, iPadOS 26.5, and build 20.7.3.
  Its 23,339-byte package contained cursor 1245 and 33 synchronized operation
  summaries with no payload or record-data fields. The temporary downloaded
  copy was deleted after verification.
- `Documentation/Architecture/SynchronizationSupportDiagnostics.md`

### Executable Client/Server Policy Contract

- [x] Add one shared, version-controlled policy manifest for client mutation
  classification and Worker field validation.
- [x] Replace the Worker's handwritten cross-entity command-field lookup with
  exact entity-and-command rules from the shared manifest.
- [x] Add an iOS contract test that encodes the real recurring-work client
  model and fails if its mutable fields differ from the server policy.
- [x] Verify the focused contract test on a connected physical iPhone and run
  the complete Worker regression suite.

Verification and deployment evidence:

- `SynchronizationMutationEnvelopeTests.testRecurringWorkClientSchemaMatchesSharedWorkerPolicyContract`
  passed on Tim-iPhone17pro: 1 test, 0 failures.
- Worker regression: 73 tests passed; TypeScript validation passed.
- `git diff --check` passed.
- Staging Worker version
  `bbb4d0d3-0bc0-4c03-8301-fc76e0a0189f` deployed.
- App build remains 20.7.3 because this work adds an automated contract guard
  and server validation source, with no user-facing client behavior change.
- `Documentation/Architecture/SynchronizationPolicyRegistry.md`

- [x] Use push notifications only as a signal that authoritative changes are
  available; fetch changes through the server cursor. Build 20.7.7 registers a
  tenant/device-scoped sandbox APNs token and receives a data-free background
  wake containing only the server cursor and a random delivery correlation ID.
  The normal pull-before-upload path remains authoritative. The Worker records
  the APNs request/response identifiers and the client reports received,
  synchronization-started, synchronization-completed, or synchronization-
  failed timestamps without customer or job payloads. A controlled Apple Push
  Notifications Console test proved APNs accepted the iPad signal but deferred
  delivery at the device's request for power considerations, confirming why
  foreground and periodic reconciliation remain required fallbacks. A later
  build 20.7.7 signed two-device acceptance recorded the complete server-side
  lifecycle: APNs accepted cursor 1217 at 21:26:40.531Z, the backgrounded iPad
  reported receipt at 21:26:40.990Z, synchronization start at 21:26:41.469Z,
  and completion at 21:26:42.977Z. Its authenticated reported and acknowledged
  cursors both reached the server cursor 1217 with no push or sync failure.
  Reverse-direction acceptance also passed: an authorized employee-device
  change produced cursor 1218, APNs accepted the signal to Tim-iPhone17pro at
  21:33:16.649Z, the backgrounded Owner iPhone reported receipt at
  21:33:17.026Z, synchronization start at 21:33:17.158Z, and completion at
  21:33:18.747Z. Its reported and acknowledged cursors both reached 1218 with
  no push or synchronization failure. The signal-only path is therefore signed
  off in both Owner-to-employee and employee-to-Owner directions.
- [x] Retain periodic reconciliation and launch/foreground recovery.
  The existing single five-second reconciliation loop still starts immediately
  at launch. Returning to the active foreground now restarts that same loop for
  an immediate bootstrap or authoritative pull-before-upload pass; repeated
  lifecycle signals are coalesced by cancellation. A generic physical-iOS
  build completed successfully after this wiring was added. Future silent push
  handling will invoke this same signal-only wake path. Build 20.7.4 was
  installed in place on the employee iPad Pro mini and Owner iPhone17e. Signed
  two-device acceptance confirmed saved job changes synchronized cleanly after
  reopening the backgrounded peer, with no manual refresh, restart, conflict,
  quarantine, or duplicate activity observed.
- [x] Add Operations monitoring for queue age, dead letters, conflict rates by
  entity and field, auto-resolution policy, stale recovery, and schema errors.
  - [x] Server-side calculation and secured `GET /v1/sync/health` contract.
    Owner/Manager devices receive payload-free Healthy, Delayed, or Action
    Required classifications; employee access is denied. The response covers
    tenant/device cursor divergence, queue counts and oldest age, latest push
    lifecycle, 24-hour delivery totals, and seven-day entity, field, and
    quarantine-reason trends. Tenant isolation and payload redaction are
    enforced by regression tests. TypeScript validation and all 77 Worker
    tests passed; staging Worker version
    `8523b6f4-3835-494f-b035-8923a156dcb6` was deployed.
  - [x] Add the plain-language Synchronization Health screen as the first
    application consumer of this contract. Build 20.7.8 places the screen in
    Settings > App Information for Owner/Manager roles only. It presents the
    company and device states as Healthy, Delayed, or Action Required; explains
    each device condition and recommended response; summarizes held changes,
    background delivery, and recent problem trends; and converts known server
    reasons into business-language descriptions. The employee device receives
    neither the navigation link nor server authorization. Build 20.7.11 fixed
    an initial visibility defect by separating this Owner/Manager feature from
    the unrelated linked-employee-profile condition. Tim-iPhone17pro then
    displayed and successfully loaded the report in signed-device acceptance.
    Owner-role visibility and report loading were then confirmed on iPhone17e
    and iPad Pro M1. Employee-role negative acceptance passed on iPad Pro mini:
    the navigation link was absent, matching the server's independent employee
    denial contract. The health screen is signed off across all four devices.
- [x] Alert on tenant divergence, stuck dependencies, excessive retries, and
  unresolved high-impact conflicts.
  - [x] Build 20.7.12 adds payload-free device health reports, durable
    tenant-scoped alert storage, scheduled and on-demand evaluation, automatic
    resolution, warning/critical thresholds, and a plain-language Alerts
    section in the Owner/Manager Synchronization Health screen. Employee
    devices submit only operational counts and timestamps and remain denied
    access to tenant-wide health. TypeScript validation, all 78 Worker tests,
    and a signed generic physical-iOS build passed. Signed-device acceptance
    on build 20.7.12 then exercised all four conditions using the employee iPad
    Pro mini and Owner iPhone17e. Every alert appeared with its expected
    plain-language explanation and automatically cleared after its condition
    was restored. Final server verification found all four durable alert types
    resolved, zero active alerts, and zero unresolved conflicts.
  - [x] Build 20.7.14 adds an Owner/Manager-only Dashboard banner for active
    alerts. The non-dismissible banner distinguishes warning and critical
    conditions, explains the active issue count in plain language, refreshes
    when the Dashboard opens or the app becomes active, and links directly to
    Synchronization Health. Health-screen refreshes update the Dashboard state
    immediately so a corrected alert disappears on return. Signed acceptance
    on the Owner iPhone17e confirmed warning presentation, correct navigation,
    and immediate disappearance after the health screen reported Healthy.
    Employee-role negative acceptance passed on the iPad Pro mini while a real
    tenant alert was active: its Dashboard remained unchanged. The isolated
    test conflict was removed; final server verification found zero active
    alerts and zero unresolved conflicts.

## Step 8 — Migration, Regression, and Closeout

- [x] Migrate existing tenants, queued changes, revisions, tombstones, and
  conflict records without silent data loss.
  - [x] Add the migration-safety test suite. A separate fresh-D1 runner applies
    the real schema only through migration 0022, seeds two legacy tenants, then
    applies migrations 0023–0030. It proves accepted operations, payloads,
    canonical records, revisions, deletion tombstones, unresolved conflict
    evidence, and pending review work remain unchanged; verifies independent
    gap-free tenant feeds; inventories every Phase 20 synchronization table;
    and passes foreign-key integrity checks. The companion signed iPhone17e
    unit test proves pending, retrying, and conflicted device queue entries
    preserve identity, ordering, payload, revision, retries, dependencies, and
    conflict versions across reload. The dedicated migration test, all 78
    Worker regressions, TypeScript validation, diff validation, and the signed
    device queue test passed.
  - [x] Complete live local-database recovery acceptance without server
    republishing. Build 20.7.19 reconstructs legacy mutations whose inner
    record IDs are missing, installs assignments as one canonical snapshot,
    and isolates duplicate historical assignment numbers so one invalid pair
    cannot empty the assignment store. The focused physical iPhone17e
    regression passed. Pre-clear diagnostics matched between the Owner
    iPhone17e and employee iPad Pro mini at cursor 1259: 16 customers, 15
    sites, 8 leads, 1 estimate, 46 jobs, 11 invoices, 3 employees, 8 catalog
    items, 3 recurring-work templates, 56 compatible assignments, and no
    queued operation summaries. After Clear Local Database on the iPhone17e,
    case `PFSS-D6LR-LRJ2` reproduced those counts exactly. The server remained
    unchanged at cursor 1259, 1,259 change rows, and 263 canonical records, so
    no empty or downloaded snapshot was republished. For true fresh-device
    acceptance, PFSS and all local app data were removed from the employee
    iPhone11 Pro before build 20.7.19 was reinstalled and the device enrolled
    again. Diagnostic case `PFSS-PU5H-M6BG` independently rebuilt the identical
    inventory at cursor 1259 with cloud access available, no persistence error,
    and no queued operation summaries. A final server comparison remained
    unchanged at cursor 1259 and 263 canonical records. The live migration,
    local-clear recovery, and fresh-device acceptance requirements are closed.
- [x] Test concurrent online edits, extended offline use, old application
  builds, schema evolution, duplicate delivery, out-of-order delivery, partial
  failure, suspension, revocation, and fresh-device bootstrap.
  - [x] Add deterministic failure-mode regressions without mutating the live
    tenant. The Worker suite now proves reversed device timestamps remain in
    tenant-sequence order, rejected input consumes no cursor, duplicate replay
    creates no second operation or feed event, and cursor resume returns only
    the remaining change. The client suite proves concurrent launch/foreground
    signals submit one operation once and that a 250-change offline queue
    survives reload with stable identity, exact order, and one successful
    attempt per change. All 79 Worker tests, TypeScript validation, the signed
    iOS test build, and both focused iPhone17e tests passed. Existing regressions
    cover legacy schemas, focused concurrent conflicts, dependency-isolated
    partial failure, suspension, and revocation; true fresh-device bootstrap
    passed on the wiped iPhone11 Pro. Controlled current-build multi-device
    acceptance was completed on the current-build device fleet.
  - [x] Complete the controlled build 20.7.19 device pass: independent and
    contradictory concurrent edits, a short employee offline workflow, and—if
    required—a disposable employee suspension/revocation lifecycle.
    Signed testing exercised independent cross-device updates, an intentional
    same-record conflict, employee offline work and recovery, suspension,
    revocation, retry containment, and fresh-device bootstrap. Owner and
    employee devices returned to Healthy with no unresolved conflict after each
    controlled condition was cleared.
  - See `Documentation/Architecture/SynchronizationFailureModeRegression.md`.
- [x] Complete signed multi-device iPhone/iPad acceptance for Owner, Manager,
  Sales, and Technician roles.
  - [x] Owner acceptance on Tim-iPhone17pro, iPad Pro M1, Tim's iPad mini, and
    iPhone17e.
  - [x] Manager promotion and demotion propagated in both directions on the
    iPhone11 Pro without requiring re-enrollment.
  - [x] Technician authorization, synchronization, quarantine, diagnostics,
    recovery, and role-negative checks passed on iPad Pro mini and iPhone11 Pro.
  - [x] Sales-role acceptance passed on iPhone11 Pro. The Owner iPhone17e
    changed the employee to Salesperson-only; the employee device received the
    change without sign-out or re-enrollment, Manager/Admin access disappeared,
    the Sales Calendar locked to the authenticated salesperson, and the
    employee became available for lead assignment. Normal roles were restored
    after the check.
- [x] Update architecture, operations, recovery, support, and release documents.
  Phase 20 architecture notes cover mutation envelopes, policy, dependency
  isolation, conflict/quarantine review, recovery, diagnostics, health,
  migration safety, and failure modes. Release notes and release history were
  added for the accepted build line.
- [x] Publish the complete Phase 20 branch for repository integration.
  Commit `b496ee0` and this final acceptance update are published on
  `origin/codex/phase20-recovery`. Main-branch integration remains a repository
  administration action, not an implementation or acceptance blocker.

### Late Field Hardening and Closeout Build

- Build 20.7.28 prevents automated test fixtures from scheduling notifications
  on physical devices and removes only known leaked test-job reminders at app
  launch. Legitimate job reminders are not matched by the cleanup filter.
- Build 20.7.29 adds direct **View Invoice** access from completed My Day jobs
  and permits existing invoice service/labor lines to be corrected. Invoice
  totals and retained tax evidence are recalculated while immutable payment
  receipts remain unchanged. The shared client/server policy now recognizes
  `invoice.edit`; staging Worker version
  `b2c82300-6ebd-4872-aec1-b81c8062511b` is deployed, and the signed build is
  installed on Tim-iPhone17pro.
- Final automated closeout on 2026-08-26 passed 291 iOS unit tests, 83 Worker
  regressions, one fresh-D1 migration-safety test, TypeScript validation, and
  `git diff --check`, with zero test failures or skips.

## Phase 20 Completion Gate

- [x] No single malformed operation can block unrelated synchronization.
- [x] Routine system-field and independent-field changes resolve without human
  review.
- [x] Legitimate offline field actions survive rebasing and synchronize once.
- [x] Stale devices converge through pull/rebase without overwriting newer
  production data.
- [x] Archive, deletion, security, billing, and role boundaries remain
  server-authoritative and tenant-isolated.
- [x] Manager/Owner conflicts are rare, consequential, understandable, audited,
  and resolved across every affected device.
- [x] Full automated and signed-device regression passes with documented
  failure-injection evidence.
  Automated validation and the Owner, Manager, Sales, and Technician
  signed-device matrix pass.
- [x] Product owner accepts Phase 20 before broader expansion continues.
  Product-owner acceptance was confirmed on 2026-08-26 after the final signed
  Sales-role check passed.
