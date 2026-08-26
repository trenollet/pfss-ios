# Centralized Quarantine Review

Phase 20 stores synchronization quarantines as tenant-scoped server review
items. A quarantine is an operation that the source device could not safely
submit or automatically repair; it is not an accepted cloud record change.

## Delivery

The source device reports the preserved operation, failure reason, employee and
device identity, detection time, and mutation evidence. The Worker captures the
current canonical record and revision when available. Manager and Owner devices
receive only unresolved items for their authenticated tenant.

## Review

The Quarantine Inbox shows the record family, originating device, failure,
affected fields, operational impact, and common-base/device-intended/current-
cloud values when the mutation envelope supports a focused comparison.

Initial authorized actions are:

- **Discard Device Change** cancels the unaccepted source operation and leaves
  the canonical cloud record unchanged.
- **Retry Device Change** returns the preserved operation to the source queue.
  Normal validation, authorization, conflict, and synchronization policy still
  applies; review does not bypass those controls.

Both actions require a reason of at least ten characters. Resolution is atomic,
tenant-scoped, idempotent, and audited with reviewer identity, role, policy
version, operation identity, action, and time. A durable source-device receipt
applies the decision exactly once and triggers synchronization after retry.

## Reversal boundary

An already accepted change is not a quarantine. Reversal must be represented as
a new authorized compensating mutation against the current cloud revision; PFSS
does not perform blind historical rollback from this inbox.
