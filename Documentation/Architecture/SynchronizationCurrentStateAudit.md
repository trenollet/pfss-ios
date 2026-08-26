# PFSS Synchronization Current-State Audit

**Phase:** 20 — Multi-Device Synchronization Architecture  
**Audit date:** 2026-08-15  
**Status:** Step 1 baseline

## Purpose

This document records the synchronization behavior that exists before the
Phase 20 protocol is introduced. It is the migration baseline: Phase 20 must
improve these boundaries without silently discarding queued work created by a
supported older build.

## Existing Client Envelope

`PendingOfflineOperation` currently persists:

- stable operation and idempotency identifiers;
- one global queue sequence number;
- operation and entity type;
- optional record identifier;
- action name and actor employee identifier;
- a schema-labelled binary payload;
- status, creation, attempt, retry, and completion timestamps;
- complete retry history and durable failure details;
- optional base revision and conflict envelope; and
- free-form string metadata.

The record mutation payload contains an entity type, entity identifier, a
complete encoded record, and the device modification timestamp. The server
stores an opaque accepted operation and a generated record revision.

## Existing Processing Behavior

The client processes every non-terminal operation in global sequence order.
Processing stops when it encounters:

- a conflict awaiting review;
- a permanent failure;
- an operation whose retry time has not arrived;
- loss of connectivity; or
- any attempted operation that fails or conflicts.

Later operations for unrelated records therefore remain blocked. Ordering is
currently broader than the true business dependency graph.

Multiple queued whole-record saves for the same record are chained to the
latest synchronized predecessor revision. The client performs a generic JSON
three-way merge after a revision conflict, but it has no entity/field policy
registry. The server has targeted exceptions for stale records and selected
authorization rules, but mutations remain primarily whole-record replacement.

## Existing Server Authority

The Cloudflare Worker already provides foundations Phase 20 will preserve:

- tenant and device authentication;
- role-based mutation authorization;
- stable idempotency-key receipts;
- per-record opaque revisions;
- tenant-scoped canonical record storage;
- centralized conflict records and atomic Manager/Owner resolution;
- conflict-resolution propagation through normal synchronization receipts;
- selected stale-device automatic retention of the cloud version; and
- plan-limit and account-access enforcement.

Gaps are the absence of a public mutation schema version, changed-field intent,
common-base snapshots, server change sequence/cursor, tombstones, explicit
domain commands, and dependency-aware dead-letter processing.

## Synchronized Entity Inventory

| Entity | Current mutation form | Important relationships | Primary risk |
| --- | --- | --- | --- |
| Job | Whole record plus workflow actions | Customer, site, estimate, employees, assignment, recurring template | Lifecycle, schedule, recurrence, and derived financial fields collide |
| Assignment | Whole record | Job, customer, site, crew employees | Crew, route order, schedule, and status require authorization |
| Invoice | Whole record plus payment handoff | Job, customer, site, receipt events | Payment and tax snapshots must never be recomputed inconsistently |
| Payment | Action/event intent | Invoice and receipt | Duplicate financial side effects |
| Route | Ordered route intent | Technician, assignments, jobs | Concurrent dispatcher route edits |
| Customer | Whole record | Sites, jobs, invoices, leads | Stale devices can overwrite newer contact data |
| Site | Whole record | Customer, jobs, assignments | Relationship and address changes affect routing |
| Lead | Whole record | Sales employee, converted customer | Conversion must be idempotent and preserve identity |
| Estimate | Whole record | Lead, customer, site, line items | Status and conversion are semantic commands |
| Employee | Whole record | Membership, devices, jobs, assignments | Security and lifecycle fields must be server-authoritative |
| Catalog | Whole record | Job/estimate/invoice line-item snapshots | Usage counters conflict with business edits |
| Recurring work | Whole template | Prototype job, generated jobs, exceptions | Regeneration must preserve completed/in-progress work |
| Custom | Whole opaque record | Varies | No field-aware policy is currently possible |

## Mutation and Dependency Inventory

Current intent-labelled operations include workflow actions, technician notes,
job timestamps, invoice handoff, payment recording, route changes, and record
mutations. Most app saves also enqueue a whole-record mutation.

Required dependency keys for the Phase 20 queue are:

1. tenant;
2. entity type and record identifier;
3. explicit prerequisite operation identifiers;
4. referenced parent records for creation only; and
5. domain aggregate where a command must serialize related records.

Unrelated records must not inherit a dependency merely because they were
created earlier on the same device.

## Authorization Boundary Inventory

| Boundary | Required server authority |
| --- | --- |
| Tenant/account access | Account active state, holds, subscription entitlement |
| Employee/device access | Membership lifecycle, device enrollment/revocation |
| Role changes | Owner/Manager authorization and final-owner protection |
| Assignment and schedule override | Manager/Owner policy; technician cannot reassign |
| Job decline | Technician append request; Manager/Owner resolution |
| Archive/delete | Authorized domain command plus tombstone |
| Recurring series rebuild/hold/stop | Authorized atomic domain command |
| Invoice/payment/tax | Immutable payment facts and accepted tax snapshot |
| Conflict override | Manager/Owner only, with reason and audit evidence |

## Baseline Metrics Registry

Phase 20 will capture the following measurements before changing queue
semantics. A metric marked **available** can be derived from current persisted
records. A metric marked **new** needs protocol or telemetry support.

| Metric | Baseline source | Availability |
| --- | --- | --- |
| Queue depth by status/entity | Durable client queue | Available |
| Oldest pending operation age | Durable client queue | Available |
| Retry count and last failure category | Retry histories | Available |
| Permanent failures and schema decode errors | Durable failures | Available |
| Conflicts by entity and changed path | Client/server conflict records | Available, paths incomplete |
| Manual resolution count and age | Server conflict audit | Available |
| Head-of-line blocked operation count | Global queue ordering | New derived metric |
| Dead-letter/quarantine count | No quarantine state exists | New |
| Stale-device recovery duration/outcome | No durable recovery session exists | New |
| Server cursor lag | No server sequence/cursor exists | New |
| Automatic merge policy and result | Metadata only | New structured metric |
| Duplicate delivery acceptance | Idempotency receipts | Available server-side |

## Migration Constraints

- Schema-version 1 payloads and whole-record mutations remain readable.
- Existing idempotency keys remain stable.
- Existing record revisions remain valid bases until migrated or rebased.
- Existing unresolved conflicts remain reviewable.
- No current queue snapshot is deleted during envelope migration.
- New server fields must be additive until the supported-build window closes.

## Step 1 Exit Evidence

Step 1 is complete when this audit and the companion policy registry are
reviewed, the baseline metric snapshot is produced by tests or diagnostics,
and every synchronized entity has an explicit default merge/conflict policy.
