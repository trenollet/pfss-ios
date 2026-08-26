# Synchronization Migration Safety

Phase 20 has two independent preservation boundaries: the server's D1 schema
and each device's durable offline-operation queue. Both must pass before a
migration can be considered safe.

## Server upgrade simulation

`test/migration-safety.migration.ts` runs in a fresh isolated D1 database. It
applies the real migrations only through 0022, seeds representative legacy
state for two tenants, snapshots that state, and then applies the actual Phase
20 migrations 0023 through 0030.

The fixture includes accepted upserts and deletions inserted out of timestamp
order, canonical live and tombstone records, an unresolved conflict with both
versions and affected-field evidence, a deleted mileage trip, and a pending job
decline review. The assertions prove:

- every legacy operation, payload, revision, record, tombstone, conflict, and
  pending review remains byte-for-byte equivalent in its stored fields;
- migration 0023 creates an independent, gap-free, chronological change feed
  for each tenant without duplicates or cross-tenant ordering;
- all Phase 20 synchronization tables are present; and
- `PRAGMA foreign_key_check` reports no integrity violations.

Run the dedicated simulation with:

```sh
npm run test:migrations
```

Run normal Worker regressions and the migration simulation together with:

```sh
npm run test:all
```

## Device queue preservation

`OfflineSynchronizationServiceTests.
testPhase20QueueSurvivesReloadWithoutLosingSynchronizationEvidence` uses an
isolated persistence store and recreates the queue as an app restart would. It
proves that pending, retrying, and conflicted operations retain their durable
IDs, idempotency keys, sequence, payloads, base revisions, retry and failure
evidence, dependency metadata, and local/remote conflict versions. It also
proves that the next operation continues at the next sequence without replacing
or duplicating prior work.

This suite does not replace a pre-deployment backup, migration listing review,
or signed fresh-device acceptance. Those remain separate release gates.
