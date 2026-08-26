# PFSS Synchronization Policy Registry

**Phase:** 20 — Multi-Device Synchronization Architecture  
**Policy version:** 1  
**Status:** Initial registry for versioned mutation design

## Field Classes

| Class | Authority and merge rule |
| --- | --- |
| Server-owned | Client values are ignored or rejected; server value wins |
| Client-editable | Three-way merge; independent paths merge automatically |
| Derived | Never accepted as conflict authority; recompute from canonical inputs |
| Commutative | Apply idempotent set/counter semantics rather than replacement |
| Append-only | Add immutable event with stable ID; duplicate delivery is a no-op |
| Relationship | Validate target tenant, lifecycle, and authorization before acceptance |
| Lifecycle | Apply an authorized domain command and create a tombstone when removed |
| Security-sensitive | Server command only, fail closed, immutable audit required |

## Global Rules

The server owns accepted revision, accepted timestamp, tenant, actor identity,
device identity, authorization result, change sequence, and tombstone state for
every entity. Device timestamps are audit evidence only.

Record identifiers are client-proposed UUIDs for offline creation and become
immutable after first acceptance. Human-readable business numbers are assigned
or reserved by the server and are never collision authority.

Unknown fields from a supported newer schema are preserved by the transport.
An older client may change known paths without deleting unknown paths.

## Entity Policies

### Job

| Field group | Class | Policy |
| --- | --- | --- |
| `id`, accepted revision, job number | Server-owned | Immutable after acceptance; offline UUID is retained |
| Customer/site/estimate references | Relationship | Validate same tenant and active parent; change through job edit command |
| Service type, other service, work notes | Client-editable | Three-way path merge |
| Line items and discount | Client-editable aggregate | Replace by stable line-item ID; recompute totals |
| Subtotal and total | Derived | Recompute from accepted line items, discount, and tax policy |
| Technician IDs, schedule, priority | Relationship/domain command | Manager/Owner policy; authorized technician self-actions do not reassign |
| Workflow state and status | Lifecycle/domain command | Validate state transition and role; append timeline event atomically |
| Workflow timestamps | Append-only/derived | Timeline event is authoritative; projections are recomputed |
| Timeline events | Append-only | Stable event ID; correction creates audited correction event |
| Recurrence fields | Derived/domain command | Recurring template is source of truth; series edit atomically rebuilds future work |
| Lifecycle status | Lifecycle | Archive/restore command; tombstone prevents stale resurrection |
| Created/modified device dates | Server-owned audit | Preserve as evidence, not merge authority |

### Assignment

| Field group | Class | Policy |
| --- | --- | --- |
| IDs, numbers, job/customer/site references | Server-owned/relationship | Immutable linkage after creation except authorized repair |
| Scheduling, crew, priority, route sequence | Domain command | Validate role, capacity, and referenced employees; serialize by assignment aggregate |
| Dispatch/field notes | Append-only preferred | New note event; legacy text uses three-way merge during migration |
| Status and lifecycle dates | Lifecycle/domain command | Validated transition with atomic history event |
| History | Append-only | Stable event ID, duplicate-safe |
| Derived technician/status views | Derived | Recompute from crew and history |

### Invoice, Payment, and Receipt

| Field group | Class | Policy |
| --- | --- | --- |
| Invoice identity and relationships | Server-owned/relationship | Immutable after acceptance |
| Line items and discount | Client-editable aggregate | Stable line IDs; totals recomputed |
| Tax snapshot | Server-accepted snapshot | Created once from canonical settings/lines; later correction is audited |
| Subtotal, total, balance | Derived | Recompute from accepted facts |
| Payment | Append-only financial event | Stable payment event ID; never whole-record increment |
| Amount paid, paid date, status | Derived/lifecycle | Project from payment events and authorized status commands |
| Receipt snapshot | Append-only immutable | Generated once per accepted payment event |
| Notes/due date | Client-editable | Three-way merge; same-field contradiction requires review |
| Archive/delete | Lifecycle | Restricted command; financial retention policy applies |

### Customer and Site

| Field group | Class | Policy |
| --- | --- | --- |
| IDs/customer number/tenant | Server-owned | Immutable after acceptance |
| Contact, business, address, access/work notes | Client-editable | Independent path merge; same-field contradiction review only when both changed |
| Customer-site link | Relationship | Same-tenant active customer required |
| Lead source/status/follow-up/assignee | Client-editable/relationship | Employee target validated; status change may be a command |
| Lifecycle | Lifecycle | Archive/restore/delete command plus tombstone |

### Lead and Estimate

| Field group | Class | Policy |
| --- | --- | --- |
| Identity/business number | Server-owned | Offline UUID retained; server number reserved |
| Contact, location, notes, requested service, quotes | Client-editable | Path or stable child-ID merge |
| Salesperson | Relationship | Same-tenant active eligible employee required |
| Status/follow-up | Lifecycle/client-editable | Valid transition; independent date edit merges |
| Lead conversion | Domain command | Idempotently create/link exactly one customer; never overwrite by list position |
| Estimate conversion/approval | Domain command | Idempotent semantic transition |
| Financial totals | Derived | Recompute from accepted line items |
| Lifecycle | Lifecycle | Tombstone-backed archive/delete |

### Employee, Membership, and Device

| Field group | Class | Policy |
| --- | --- | --- |
| Tenant membership, access role, status | Security-sensitive | Server command only; Owner protections and audit required |
| Device enrollment/revocation | Security-sensitive | Server command only; credential rotation/removal enforced |
| Name/contact/base address | Client-editable with role policy | Self-edit or Manager/Owner edit as authorized |
| Operational roles and capacity | Relationship/domain command | Authorized update; preserve access role separation |
| Working schedule/preferences | Client-editable | Set semantics for working days; independent preference fields merge |
| Active/lifecycle flags | Lifecycle/security-sensitive | Server is canonical; stale client cannot reactivate |

### Catalog

| Field group | Class | Policy |
| --- | --- | --- |
| Name, description, defaults, estimated minutes, type, tax treatment | Client-editable | Three-way path merge with Manager/Owner policy where configured |
| Usage count | Commutative/derived | Increment by stable usage event; never replace absolute count |
| Last-used date | Derived | Maximum accepted usage-event timestamp |
| Lifecycle | Lifecycle | Tombstone-backed archive/delete |

### Recurring Work

| Field group | Class | Policy |
| --- | --- | --- |
| Rule, anchor, end condition, prototype, horizon | Domain command | Versioned template edit atomically supersedes future unstarted occurrences |
| Revision and timestamps | Server-owned | Increment/accept on server |
| Exceptions | Append-only | Stable exception ID and occurrence key |
| Hold/pause/stop | Lifecycle/domain command | Atomic transition; preserve completed and in-progress jobs |
| Generated jobs | Derived | Deterministic occurrence key; duplicate generation is a no-op |

### Route

| Field group | Class | Policy |
| --- | --- | --- |
| Ordered assignment/job IDs | Domain command | Replace route order for technician/day against explicit base revision |
| Travel estimates and arrival projections | Derived | Recompute; never conflict-review calculated values |
| Manual override reason | Append-only audit | Required for constrained override |

### Custom/Unknown

Custom records remain whole-record and conservative during migration. They use
base revision matching and Manager/Owner review for concurrent modification.
No custom record may bypass tenant, authorization, schema, or tombstone rules.

## Conflict Threshold

Create a human review item only when all are true:

1. the device and server changed the same protected field or issued
   incompatible domain commands from a common base;
2. neither intent is already reflected or safely superseded;
3. an entity policy cannot deterministically merge them; and
4. the result changes a consequential business, financial, lifecycle,
   scheduling, relationship, or security decision.

Derived fields, server-owned fields, usage counters, append-only events, stale
device defaults, and independent path edits do not create human conflicts.

## Policy Evolution

Every accepted mutation records the policy version used. Policy changes are
additive and testable. Reprocessing an accepted idempotency key never applies a
new policy or produces a second side effect.

## Executable Client/Server Contract

`PPS Receipt Printer/SynchronizationPolicyContract.json` is the shared,
version-controlled list of fields allowed for each entity and domain command.
The Cloudflare Worker imports this manifest directly when validating mutation
envelopes; it does not maintain a separate handwritten field list.

`SynchronizationMutationEnvelopeTests.testRecurringWorkClientSchemaMatchesSharedWorkerPolicyContract`
encodes a fully populated `RecurringWorkTemplate`, derives every mutable client
field, and requires exact equality with the Worker's `recurringWork.update`
contract. The test also verifies that every field is classified as that domain
command. Adding, removing, or renaming a mutable recurring-work field on only
one side therefore fails the iOS test before deployment.

The contract is intentionally entity-specific. Commands with the same name do
not inherit fields from unrelated entities, and wildcard policy applies only
where the manifest explicitly declares it.
