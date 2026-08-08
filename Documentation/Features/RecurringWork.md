# PFSS Recurring Work

- Status: Implemented; live multi-device acceptance pending
- Owner: PFSS Project
- Last Updated: 2026-08-07

## User Goal

An authorized user defines repeating service once and PFSS produces dependable,
individually manageable Job occurrences without duplicates or silent schedule
changes.

## Template Workflow

1. Select customer, site, service details, pricing snapshot, duration, and
   assignment preferences.
2. Choose weekly, bi-weekly, monthly, or an approved custom interval.
3. Choose start plus end date, occurrence count, or no end.
4. Review projected occurrences and scheduling conflicts.
5. Save the template and allow the server to publish the bounded horizon.

## Occurrence Workflow

- Open an occurrence as a normal Job.
- When editing, explicitly choose only this occurrence or this and future.
- Skip or cancel an occurrence without deleting the template.
- Pause, resume, archive, or terminate future generation with clear effect dates.

## Safety Rules

- Repeated generation and multiple devices cannot create duplicates.
- Conflicts are shown rather than silently rescheduled.
- Editing one occurrence does not alter the template.
- Series changes do not rewrite past completed Jobs, Invoices, Payments, or
  work history.
- Employee departure, account hold, offline edits, and sync conflict behavior
  are explicit and recoverable.

## Completion Criteria

- Recurrence math, idempotency, concurrency, range-editing, conflict, and
  migration tests pass.
- Server generation and device synchronization pass tenant-isolation tests.
- Signed iPhone/iPad create, edit-one, edit-future, skip, pause, resume, and
  terminate tests pass.

## Phase 18 Implementation

- `RecurringWorkEngine` performs calendar-aware bounded planning and derives a
  stable occurrence key and deterministic Job identifier from the template and
  occurrence position.
- Existing recurring Jobs migrate in place to `RecurringWorkTemplate` records;
  prior Job identifiers and completed history remain unchanged.
- Job creation and editing support frequency plus no-end, final-date, or total-
  job end conditions.
- Authorized users can pause, resume, stop, and skip one unstarted occurrence
  from the Job's Recurring Work management page.
- The intended Skip path is: open a saved occurrence in the recurring series,
  select **Manage Recurring Work**, then select **Skip** beside the applicable
  entry under **Upcoming Jobs**. **Skip and Remove** permanently reduces the
  delivered occurrence count by one. **Skip and Add to End** preserves the
  promised visit count by extending a bounded series and materializing a
  replacement at its end. A newly created or unsaved Job cannot expose this
  control because its recurring template and generated occurrences do not
  exist yet.
- **Edit Recurring Series** changes the template's frequency or ending rule,
  removes only unstarted generated occurrences, and immediately regenerates the
  eligible 120-day planning window. Completed or in-progress work is preserved.
- Templates synchronize as the protected `recurringWork` entity. The Worker
  permits Manager/Owner changes and rejects employee template mutations.
- Future Job numbers, identifiers, and creation timestamps are deterministic so
  separate devices submit equivalent occurrences rather than conflicting ones.

## Related Documents

- `../Architecture/RecurringWorkEngine.md`
- `../Architecture/SchedulingEngine.md`
- `Scheduling.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
