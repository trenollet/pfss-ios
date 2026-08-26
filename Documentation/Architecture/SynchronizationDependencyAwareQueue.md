# Synchronization Dependency-Aware Queue

## Purpose

Phase 20 Step 3 removes global head-of-line blocking from the device queue. A
failure now blocks only operations that depend on the same record or explicitly
name the failed operation as a prerequisite. Independent company work continues
to synchronize in sequence.

## Dependency Identity

Each queued operation exposes one or more dependency keys:

- a record key derived from entity type and record identifier;
- optional domain keys in `dependencyKey`, `dependencyKeys`, or
  `aggregateDependencyKey` metadata;
- explicit prerequisite operation identifiers in
  `prerequisiteOperationIDs` metadata.

Operations without a record identifier receive an operation-scoped fallback
key. They do not become a tenant-wide barrier merely because their record is
unknown.

## Processing Rules

The processor scans the ordered queue once per pass:

1. A successful operation completes normally and does not block later work.
2. A retry delay blocks only the affected dependency keys during that pass.
3. A permanent failure or human-review conflict quarantines that dependency
   chain while unrelated records continue.
4. A later operation is skipped only when it shares a blocked key or names a
   blocked prerequisite operation.
5. The earliest retry time is scheduled after the complete scan.

This preserves record-local ordering without allowing one malformed record to
stall unrelated jobs, assignments, customers, catalog items, or other work.

## Quarantine and Recovery

Terminal failures and human-review conflicts carry durable quarantine evidence:

- `quarantinedAt`;
- `quarantineReason`;
- `quarantineActions`.

The queue supports explicit outcomes:

- **Repair and retry** keeps the original operation identity and audit history,
  then begins a new bounded retry cycle.
- **Supersede** cancels the quarantined operation and records the replacement
  operation identifier.
- **Discard** cancels the operation with an operator-provided reason.

The Sync Status screen keeps quarantined work in its compact Action Required
section and names the available recovery paths. Successful operations remain
idempotent and are never replayed by a manual sync.

## Compatibility Boundary

Step 3 changes device queue scheduling only. It does not weaken server
authorization, revision comparison, conflict policy, or mutation-envelope
validation. Pull cursors and stale-device rebasing remain Step 4 scope.

