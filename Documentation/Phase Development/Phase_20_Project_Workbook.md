# PFSS Phase 20 Project Workbook

## Multi-Device Synchronization Architecture

**Status:** Planned — begins after Phase 19 closeout

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

- [ ] Inventory every synchronized entity, mutation, queue dependency, server-
  owned field, derived field, append-only event, and authorization boundary.
- [ ] Classify each field as server-owned, client-editable, derived,
  commutative, append-only, relationship, lifecycle, or security-sensitive.
- [ ] Define explicit merge and conflict policies for each entity and field.
- [ ] Capture baseline metrics for queue age, failures, conflicts, stale-device
  recovery, schema decode errors, and manual resolutions.

## Step 2 — Versioned Mutation Envelope

- [ ] Introduce a backward-compatible, schema-versioned mutation envelope with
  operation ID, tenant, device, record ID, entity, base revision, changed
  fields or command, and audit timestamps.
- [ ] Preserve unknown fields and migrate queued payloads created by supported
  older application builds.
- [ ] Make server-controlled revisions and acceptance sequences immutable to
  clients.
- [ ] Keep existing whole-record mutations readable during the transition.

## Step 3 — Resilient Dependency-Aware Queue

- [ ] Process independent records without global head-of-line blocking.
- [ ] Preserve ordering only where records or commands have real dependencies.
- [ ] Quarantine malformed or permanently rejected operations with an exact
  repair, retry, supersede, or discard path.
- [ ] Add bounded retries, exponential backoff, idempotency enforcement, and
  compact Action Required presentation.
- [ ] Verify a poison operation cannot stall unrelated company work.

## Step 4 — Pull, Cursor, and Stale-Device Recovery

- [ ] Add a tenant-scoped server change sequence and per-device durable cursor.
- [ ] Pull and apply authoritative deltas before upload after extended offline
  periods, application/schema upgrades, or cursor uncertainty.
- [ ] Rebase queued intent against current server revisions.
- [ ] Classify stale changes as replayed, merged, already reflected,
  superseded, quarantined, or requiring review.
- [ ] Present one understandable recovery summary instead of dozens of routine
  conflicts.

## Step 5 — Three-Way Merge and Domain Commands

- [ ] Compare base, current server, and intended device changes.
- [ ] Automatically merge independent field edits.
- [ ] Convert notes, timeline actions, payments, mileage events, and similar
  facts to immutable append operations with stable IDs.
- [ ] Route assignment, scheduling, lifecycle, recurring-work, billing,
  permission, archive, and revocation changes through authorized domain
  commands and explicit policies.
- [ ] Recompute derived values instead of treating them as user conflicts.

## Step 6 — Focused Conflict Review and Propagation

- [ ] Create review items only for unresolved same-field or semantic business
  contradictions.
- [ ] Show actual device, cloud, and common-base values plus operational impact.
- [ ] Resolve atomically on the server with authorization, reason, policy
  version, audit evidence, and normal change-feed propagation.
- [ ] Clear or supersede the originating device operation automatically after
  resolution.

## Step 7 — Push Hints, Reconciliation, and Observability

- [ ] Use push notifications only as a signal that authoritative changes are
  available; fetch changes through the server cursor.
- [ ] Retain periodic reconciliation and launch/foreground recovery.
- [ ] Add Operations monitoring for queue age, dead letters, conflict rates by
  entity and field, auto-resolution policy, stale recovery, and schema errors.
- [ ] Alert on tenant divergence, stuck dependencies, excessive retries, and
  unresolved high-impact conflicts.

## Step 8 — Migration, Regression, and Closeout

- [ ] Migrate existing tenants, queued changes, revisions, tombstones, and
  conflict records without silent data loss.
- [ ] Test concurrent online edits, extended offline use, old application
  builds, schema evolution, duplicate delivery, out-of-order delivery, partial
  failure, suspension, revocation, and fresh-device bootstrap.
- [ ] Complete signed multi-device iPhone/iPad acceptance for Owner, Manager,
  Sales, and Technician roles.
- [ ] Update architecture, operations, recovery, support, and release documents.
- [ ] Align the Phase 20 branch, pull request, main branch, and next-phase branch.

## Phase 20 Completion Gate

- [ ] No single malformed operation can block unrelated synchronization.
- [ ] Routine system-field and independent-field changes resolve without human
  review.
- [ ] Legitimate offline field actions survive rebasing and synchronize once.
- [ ] Stale devices converge through pull/rebase without overwriting newer
  production data.
- [ ] Archive, deletion, security, billing, and role boundaries remain
  server-authoritative and tenant-isolated.
- [ ] Manager/Owner conflicts are rare, consequential, understandable, audited,
  and resolved across every affected device.
- [ ] Full automated and signed-device regression passes with documented
  failure-injection evidence.
- [ ] Product owner accepts Phase 20 before broader expansion continues.
