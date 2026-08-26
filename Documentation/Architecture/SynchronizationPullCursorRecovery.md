# Synchronization Pull Cursor and Stale-Device Recovery

## Purpose

Phase 20 Step 4 changes device recovery from upload-first synchronization to a
server-authoritative pull, reconcile, then upload sequence. A device returning
after an extended offline period must learn what the company accepted while it
was away before PFSS releases locally queued work.

## Server Change Sequence

- Every accepted tenant mutation receives a monotonically increasing
  `tenant_sequence` in `synchronization_change_log`.
- The sequence is scoped to one tenant. Activity in another company cannot
  create gaps or alter a device's cursor meaning.
- Existing accepted operations are backfilled in acceptance order by migration
  `0023_phase20_tenant_sync_cursors.sql`.
- `GET /v1/sync/changes?after=<cursor>` returns ordered changes, the last
  delivered cursor, the current server cursor, and whether another page exists.
- `POST /v1/sync/cursor` durably records the highest cursor acknowledged by the
  authenticated device. Cursor acknowledgements can only advance.
- A fresh bootstrap includes the archive's change cursor in the
  `x-pfss-change-cursor` response header so the installed snapshot and cursor
  represent the same server state.

## Device Recovery Order

1. Confirm current company and device access.
2. Download every authoritative change after the durable local cursor.
3. Reconcile queued local operations for the same record before applying the
   cloud mutation.
4. Apply the cloud mutation locally and advance the cursor only after the page
   succeeds.
5. Upload queue operations whose dependencies are now ready.
6. Pull once more to receive the server's accepted representation and any
   concurrent company activity.

A pull failure stops that synchronization attempt before upload. Local work
remains queued and is not silently discarded.

## Reconciliation Triggers

PFSS keeps one periodic reconciliation loop per active company-data session.
That loop starts with an immediate reconciliation at launch and continues on a
five-second interval while iOS permits the app to run.

Whenever the app becomes active, it sends a synchronization wake signal to the
same loop. The loop cancels its current wait, coalesces repeated wake signals,
and immediately performs the normal bootstrap or pull-before-upload sequence.
It does not create an upload-only foreground path.

Silent push notifications use this same wake signal. A push is only notice that
authoritative changes may exist; it contains no company record data and cannot
advance the local cursor itself. Its payload carries the expected server cursor
and a random delivery correlation ID. The server retains Apple request/response
identifiers, while the authenticated receiving device reports received,
sync-started, sync-completed, or sync-failed timestamps and its final cursor.
These receipts are tenant/device scoped and make Apple deferral distinguishable
from an app or synchronization failure without collecting business records.

APNs background delivery is best-effort. Apple may store or defer a valid signal
for device power considerations even when Background App Refresh is enabled and
Low Power Mode is off. Therefore launch, foreground, and periodic reconciliation
remain correctness mechanisms; push only reduces normal propagation latency.

## Initial Rebase Classifications

Step 4 establishes these deterministic record-mutation outcomes:

- **Already reflected:** queued and authoritative record data are identical;
  the local operation is completed without replay.
- **Superseded by cloud:** the queued record replacement is more than eight
  hours older than the accepted cloud change; PFSS preserves its audit record,
  completes it as superseded, and applies the authoritative version.
- **Queued for normal policy:** a recent divergent change remains queued for
  the Phase 20 policy/conflict path.
- **Quarantined:** malformed or permanently rejected work continues through
  the dependency-aware quarantine path introduced in Step 3.

Later Phase 20 steps expand this into three-way field merging and domain-command
replay. Device wall-clock time remains evidence, not authority.

## User Experience

Sync Status presents one **Latest Device Recovery** summary containing counts
for downloaded cloud changes, replayed, merged, already reflected, superseded,
quarantined, and review-required operations. It avoids presenting routine
stale-device convergence as dozens of individual conflicts.

## Operational Requirements

- Apply migration `0023_phase20_tenant_sync_cursors.sql` before deploying the
  Worker that reads the new change log.
- Deploy the updated Worker and iOS client as one controlled staging rollout.
- Confirm two devices in one tenant converge after one remains offline beyond
  eight hours.
- Confirm a second tenant cannot read or acknowledge another tenant's cursor.
- Monitor stale-device superseded counts and review-required counts during the
  rollout; unexpected growth is a policy signal, not a reason to bypass audit.
