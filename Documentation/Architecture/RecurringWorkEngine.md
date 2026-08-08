# PFSS Recurring Work Engine Architecture

- Status: Implemented for Phase 18; live multi-device acceptance pending
- Owner: PFSS Project
- Applies To: Phase 18+
- Last Updated: 2026-08-07

## Responsibility

The Recurring Work Engine evaluates a recurrence template and produces a
deterministic occurrence plan. It does not silently mutate Jobs, schedule around
conflicts, invoice work, or independently publish duplicate occurrences.

## Boundary

```text
Recurring Work UI / Worker Coordinator
                  ↓ template and horizon
          RecurringWorkEngine
                  ↓ occurrence plan
SchedulingEngine + Server Idempotent Persistence
```

## Core Concepts

- `RecurringWorkTemplate`: tenant-owned service intent, recurrence rule,
  effective range, source customer/site, service snapshot, scheduling defaults,
  status, and revision.
- `RecurrenceRule`: weekly, bi-weekly, monthly, or approved custom interval.
- `OccurrenceKey`: stable identity derived from the template and recurrence
  position, not from the generating device.
- `PlannedOccurrence`: proposed date and copied business snapshot before
  persistence.
- `OccurrenceException`: skip, single-occurrence edit, cancellation, or detached
  occurrence state.

## Rules

- Use Calendar APIs and the company time zone; never use fixed seconds for
  month, year, or daylight-saving recurrence math.
- Generation is bounded by a configured horizon.
- The same template, rule revision, and occurrence position always produce the
  same occurrence key.
- Server persistence enforces tenant-scoped uniqueness and idempotency.
- Every proposed occurrence is evaluated by `SchedulingEngine`; conflicts are
  visible and are not silently moved.
- Editing one occurrence does not modify the template.
- Editing this-and-future creates an explicit template revision boundary.
- Completed Jobs, Invoices, Payments, and historical work evidence are immutable
  when a template changes.

## Authority and Synchronization

Authorized users may create and edit templates. The server coordinates
cross-device occurrence publication and auditing. Devices may view cached
templates and queue edits offline, but they do not independently create
authoritative duplicate Job occurrences while disconnected.

The synchronization coordinator persists templates through the tenant-scoped
`synchronized_records` authority as entity type `recurringWork`. Only Manager
and Owner identities may mutate that entity. Each device may materialize its
bounded cached view, while deterministic Job IDs and occurrence keys make
retries converge on the same server records.

## Testing

Cover weekly, bi-weekly, monthly, custom intervals, month ends, leap years,
daylight saving, bounds, stable keys, retries, concurrent devices, skips,
single/future edits, pause/resume, termination, conflicts, and immutable
financial history.

## Related Documents

- `SchedulingEngine.md`
- `../Features/RecurringWork.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
