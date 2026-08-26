# Synchronization Local Database Recovery

## Failure found during Phase 20 acceptance

The Owner recovery tool previously emptied the application store without
invalidating the enrolled device's synchronization cursor or completed-baseline
marker. The next launch therefore performed incremental delivery from the old
cursor. Records appeared only when another device changed them, and the first
returned record could make the partial Owner store eligible to replace the
tenant recovery snapshot.

## Recovery invariant

An enrolled device whose local company store was intentionally cleared is not
allowed to upload operations or publish a tenant snapshot until it has rebuilt
and validated a current baseline.

The recovery sequence is:

1. Cancel scheduled snapshot publication.
2. Mark the in-memory publisher unready.
3. remove every persisted cursor and baseline marker.
4. Fetch and validate the tenant recovery archive.
5. Overlay every current record from the tenant-scoped canonical record table.
6. Store the newer authoritative cursor and acknowledge it.
7. Mark the new baseline generation complete.
8. Resume pull-first synchronization and Owner snapshot publication.

The canonical overlay is important because the archive and canonical record
table fail independently. A record accepted after an archive was produced, or
omitted from an accidentally incomplete archive, is restored from its current
server revision before the device becomes publish-eligible.

## Deployment recovery

Baseline generation 5 intentionally invalidates earlier generations for all enrolled
devices. This forces devices that may already have experienced the defective
clear flow through the guarded baseline process after installing the corrected
client. Generation 3 keys are still removed during logout and company-data
removal. Generation 5 was finalized after staging normalized canonical record
timestamps, ensuring the affected acceptance device repeats recovery against
the final endpoint contract.

## Remaining operational validation

After staging deployment, install the signed corrected app on the affected
Owner iPhone and verify company setup, customers, leads, jobs, and other shared
record families before allowing it to publish a new recovery snapshot. Compare
record-family counts with the unaffected device and server inventory. Restore a
known-good Owner backup if data predating canonical record synchronization is
missing from both server baseline sources.
