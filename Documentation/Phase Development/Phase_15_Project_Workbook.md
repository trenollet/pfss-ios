# Phase_15_Project_Workbook

# PFSS Project Workbook
## Phase 15 – Field Operations Engine and Workflow Consolidation

## Phase Goal
Make PFSS feel like one operational system instead of several overlapping screens by consolidating field workflows into a single operational engine.

## Strategic Objectives

- Create one shared workflow engine for all field operations.
- Establish a single source of truth for job state, technician actions, and audit history.
- Eliminate duplicate workflow logic across My Day, Dispatch, Timeline, and Assignment Detail.
- Improve offline reliability and synchronization.
- Simplify the technician and dispatcher experience.

---

# Step 1 – Field Operations Engine Foundation

## Objective
Build the shared engine that coordinates technician actions across the application.

### Expected Outcomes
- One place for operational commands.
- Shared state model for travel, arrival, work start, completion, notes, and invoice handoff.
- No screen-specific workflow logic.

### Completion Criteria
- Operational engine created.
- State model documented.
- Shared services integrated.
- Unit tests passing.

---

# Step 2 – Consolidate My Day, Job Detail, and Dispatch

## Objective
Align all operational views to read and write the same workflow state.

### Expected Outcomes
- My Day, Assignment Detail, and Dispatch Board reflect identical workflow state.
- No duplicate action rules.
- Consistent state transitions.

### Completion Criteria
- Views validated against shared engine.
- Duplicate logic removed.
- State consistency verified.

---

# Step 3 – Unify Lifecycle Actions

## Status
Complete and field-validated.

### Commit
`b28d1d8` — Complete Phase 15 Step 3 lifecycle actions

## Objective
Standardize every technician lifecycle action.

### Expected Outcomes
- Travel, arrival, work, pause/resume, completion, and invoice-ready follow one workflow.
- Consistent audit history.
- Reduced edge-case defects.

### Completion Criteria
- [x] Lifecycle actions implemented.
- [x] Audit trail coverage added.
- [x] Xcode build and field workflow validation completed.

### Implementation Record
- Added pause and resume as first-class workflow states and actions.
- Standardized travel, arrival, setup, work, pause/resume, pack-up,
  completion, invoice handoff, payment, and closeout through
  `FieldOperationsEngine`.
- Added a shared validation result with ready, warning, and invalid outcomes.
- Added shared available-action reporting so operational screens use the same
  lifecycle rules.
- Routed legacy job workflow helpers and the workflow coordinator through the
  consolidated engine.
- Added employee, timestamp, action, resulting-state, and optional-note audit
  coverage for lifecycle transitions.
- Added regression tests for the full lifecycle, pause/resume, invalid
  transitions, validation warnings, action availability, and blank notes.

### Files Modified
- `PPS Receipt Printer/Models.swift`
- `PPS Receipt Printer/FieldOperationsEngine.swift`
- `PPS Receipt Printer/FieldOperationsWorkflowCoordinator.swift`
- `PPS Receipt Printer/AppDataStore.swift`
- `PPS Receipt Printer/JobWorkflowComponents.swift`
- `PPS Receipt Printer/JobDetailView.swift`
- `PPS Receipt Printer/TechnicianDailyAgendaView.swift`
- `PPS Receipt Printer/OperationsView.swift`
- `PPS Receipt PrinterTests/FieldOperationsEngineTests.swift`

### Resume Point
Begin Step 4 – Route and Timeline Synchronization. Persist reviewed My Day
route order through the existing audited Assignment/Dispatch boundary, then
merge Job lifecycle events into the shared Operations Timeline without
duplicating Assignment milestones.

---

# Step 4 – Route and Timeline Synchronization

## Status
Complete and field-validated.

### Completion Date
July 25, 2026

### Commit
`Complete Phase 15 Step 4 route and timeline synchronization`

## Objective
Synchronize routing, scheduling, and real-world progress.

### Expected Outcomes
- Timeline reflects actual work.
- Route updates recorded once and reused.
- Dispatch has accurate visibility.

### Completion Criteria
- [x] Timeline lifecycle synchronization implemented.
- [x] Route persistence synchronization implemented.
- [x] Xcode build and regression validation completed.
- [x] Dispatcher, Timeline, Live Map, and My Day validation passed.

### Implementation Record
- My Day route optimization now persists the technician-approved order through
  the audited `DispatchEngine.reorderRoute` boundary.
- Saved `Assignment.routeSequence` values now drive subsequent My Day ordering,
  allowing Dispatch, route previews, maps, and technician agendas to reuse one
  reviewed route order.
- Operations Timeline snapshots now consume active Jobs as well as Assignments.
- Detailed Job lifecycle events—including setup, work start, pause/resume,
  pack-up, payment, and closeout—are merged into assignment timeline entries.
- Job events take precedence over equivalent Assignment timestamps so the
  shared timeline does not display duplicate travel, arrival, completion,
  invoice, closeout, or cancellation milestones.
- Added regression coverage for detailed lifecycle milestones and duplicate
  suppression.
- Timeline scheduling conflicts are deduplicated across Daily Planner and
  Dispatch Board sources using their operational identity rather than their
  source-specific IDs.
- My Day now displays Daily Planner service starts for Flexible Day work, so
  optimized route order produces sequential, duration-aware times instead of
  repeating the Job record's placeholder time.
- Job Details now preserves and edits the same Scheduling Mode, constraint
  fields, and priority used by New Job instead of collapsing every Job into a
  generic scheduled date/time.
- Flexible Day service dates are normalized to calendar days before Assignment
  synchronization, preventing the Job creation time from being interpreted as
  an appointment time.
- Job/Assignment mirroring now persists scheduling mode, arrival-window,
  deadline, and priority changes in addition to technician and lifecycle data.
- My Day offers a one-day overtime availability override when assigned work
  falls on a technician's normal day off. The saved workforce exception uses
  normal start/end hours without changing the employee's weekly schedule, and
  Daily Planner then assigns valid sequential times instead of midnight.
- Saving a linked invoice as Sent, Partially Paid, Paid, or Overdue now closes
  the technician workflow and operational Assignment automatically. My Day
  distinguishes Invoice Sent from Payment Received, displays a bold Job
  Complete confirmation, replaces Close Job with a non-interactive COMPLETE
  indicator, and disables navigation for completed work.
- My Day now treats planned start time as authoritative for all remaining work
  after route optimization. Finished and cancelled Jobs are excluded from
  optimization and stop numbering, automatically grouped at the bottom, and
  can no longer interrupt the technician's chronological list with midnight
  fallback times.
- Route optimization now uses the shared Route Engine with Apple Maps road
  estimates (and the configured straight-line fallback) rather than the older
  distance-only My Day optimizer. The reviewed route sequence remains the
  source reused by My Day, Dispatch, and Live Map.
- Fixed Time and Arrival Window assignments remain hard route anchors.
  Deadline assignments now participate in geographic optimization with
  Flexible Day work and are promoted only when taking another stop first would
  make the deadline infeasible.
- Daily Planner honors a reviewed route sequence across Flexible Day and
  Deadline work, while continuing to report any deadline violation caused by a
  manual override.
- The former three-minute **Travel / Transition** Timeline block was identified
  as the configurable per-stop business buffer, not travel. It is now labeled
  **Stop Buffer** so it cannot be mistaken for a road travel estimate.

### Known Presentation Note
- The optimized route order persists after leaving My Day, but the route
  summary card is view-session state and disappears when the screen is
  recreated. Re-optimizing restores the summary. This is acceptable for the
  current release and is recorded for a future persisted-summary enhancement.

### Route-Timeline Integration
- Operations Timeline now refreshes road travel from the shared Route Engine
  and displays each mapped leg as a dedicated **Travel** interval with Apple
  Maps distance. When no live starting coordinate is available, the first
  scheduled stop is used as the origin so between-job travel remains accurate.
- **Stop Buffer** remains a separate business-overhead interval. **Open
  Capacity** is calculated only from time left after scheduled work, stop
  buffers, and mapped travel, so travel can no longer appear to be available
  for another job.
- Accepted My Day and Route Preview plans are retained for the current app
  session, allowing Timeline to reuse their exact road estimates and order.

### Files Modified
- `PPS Receipt Printer/AppDataStore+DispatchBoardActions.swift`
- `PPS Receipt Printer/AppDataStore+Timeline.swift`
- `PPS Receipt Printer/AppDataStore.swift`
- `PPS Receipt Printer/JobDetailView.swift`
- `PPS Receipt Printer/JobNewView.swift`
- `PPS Receipt Printer/Models.swift`
- `PPS Receipt Printer/Components:ActionTile.swift`
- `PPS Receipt Printer/Components:ActionTileRow.swift`
- `PPS Receipt Printer/SchedulingCalculator.swift`
- `PPS Receipt Printer/TechnicianDailyAgendaView.swift`
- `PPS Receipt Printer/TimelineEngine.swift`
- `PPS Receipt Printer/TimelineModels.swift`
- `PPS Receipt Printer/OperationsTimelineView.swift`
- `PPS Receipt Printer/DailyPlannerEngine.swift`
- `PPS Receipt Printer/DailyPlannerModels.swift`
- `PPS Receipt Printer/RouteEngine.swift`
- `PPS Receipt Printer/AppDataStore+RouteEngine.swift`
- `PPS Receipt Printer/RouteEngineTests.swift`
- `PPS Receipt PrinterTests/OperationsTimelineEngineTests.swift`
- `PPS Receipt PrinterTests/DailyPlannerEngineTests.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Test Checklist
- Optimize a route in My Day, leave the screen, and confirm the saved order is
  restored when My Day is reopened.
- Confirm the Dispatch Board and map show the same stop order.
- Run a job through travel, arrival, setup, work, pause/resume, pack-up,
  completion, invoice, payment, and closeout.
- Confirm Operations Timeline shows each lifecycle milestone once and in
  chronological order.
- Confirm Operations Timeline displays a mapped Travel block between routed
  jobs, keeps Stop Buffer separate, and does not count the travel interval as
  Open Capacity.
- Confirm a manual Dispatch Board reorder appears in My Day.
- Open an existing Flexible Day Job and confirm Job Details displays Flexible
  Day rather than a generic scheduled time.
- Optimize two or more Flexible Day Jobs and confirm My Day assigns sequential
  starts from the technician's configured workday in optimized route order.
- On a normal day off with assigned work, tap **Work This Day (Overtime)** and
  confirm the warning clears and planning begins at the technician's normal
  start time without changing the recurring weekly work schedule.
- Mark one linked invoice Sent and another Paid. Confirm My Day shows Invoice
  Sent or Payment Received followed by Job Complete, presents COMPLETE as a
  status indicator, and disables Navigate on both cards.
- Optimize a mixed day containing Fixed Time, Flexible Day, and completed Jobs.
  Confirm remaining work is ordered by planned start and every completed Job is
  grouped below all remaining stops without a route number.

### Resume Point
Begin Step 4.6 – Dashboard UI and Workflow Optimization using the accepted
Operations tile hub as the visual and navigation reference.

---

# Step 4.5 – Operations UI Cleanup

## Status
Complete and field-validated.

### Completion Date
July 25, 2026

### Commit
`Complete Phase 15 Step 4.5 Operations UI cleanup`

## Objective
Convert Operations from a long mixed dashboard into a compact operational
navigation hub that makes dispatch work and testing faster.

### Expected Outcomes
- Every summary tile is a clear, tappable entry point.
- Active Assignments, Technicians, and Dispatch Queue move to dedicated pages.
- The three extracted pages support search comparable to Customers, Jobs, and
  Estimates.
- Dispatch Board, Daily Planner, and Workforce Intelligence use the same tile
  presentation and continue opening their existing screens.
- Capacity remains an actionable tile linked to the existing capacity dashboard.
- Revenue and Recommendations move to dedicated destinations so Operations
  contains navigation choices rather than embedded reports or record lists.
- Capacity Forecast becomes the first section of Capacity Dashboard.
- The resulting tile language becomes the reference design for Step 4.6.

### Implementation Record
- Replaced the noninteractive Operations summary cards with nine linked tiles:
  Today's Jobs, Technicians, Dispatch Queue, Dispatch Board, Daily Planner,
  Workforce Intelligence, Capacity, Revenue, and Recommendations.
- Added a searchable Active Assignments page. Searches cover assignment and Job
  numbers, customer and site information, technician names, and lifecycle state.
- Added a searchable Operations Technicians page linked to existing Employee
  Detail records and backed by current-day workload summaries.
- Added a searchable Dispatch Queue page while preserving recommendation,
  technician selection, human override, assignment, and detail actions.
- Removed full Active Assignment, Technician Status, Dispatch Queue, Dispatch
  Board, Daily Planner, and Workforce Intelligence sections from the main
  Operations scroll.
- Added dedicated Revenue and Recommendations pages and removed both embedded
  sections from Operations.
- Moved Capacity Forecast to the top of Capacity Dashboard and based the forecast
  on the dashboard's selected date.
- Standardized Capacity Dashboard and Workforce Intelligence on the compact
  inline navigation-title style used by the other Operations destinations.

### Files Added
- `PPS Receipt Printer/OperationsHubDestinationViews.swift`

### Files Modified
- `PPS Receipt Printer/DashboardStatCard.swift`
- `PPS Receipt Printer/OperationsView.swift`
- `PPS Receipt Printer/WorkforceCapacityDashboardView.swift`
- `PPS Receipt Printer/WorkforceIntelligenceDashboardView.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Test Checklist
- Confirm Operations opens as a compact tile hub without the former long Active
  Assignments, Technician Status, or Dispatch Queue lists.
- Tap Today's Jobs and confirm Active Assignments opens; search by customer,
  site/address, Job number, Assignment number, technician, and status.
- Open an Assignment from search results and confirm Assignment Detail works.
- Tap Technicians, search by name/email/phone, and open Employee Detail.
- Tap Dispatch Queue, search its records, view details, assign the recommended
  technician, and exercise a human override when appropriate.
- Confirm Dispatch Board, Daily Planner, Workforce Intelligence, and Capacity
  tiles open their existing destinations.
- Confirm Revenue and Recommendations open dedicated pages and no longer render
  full sections beneath the Operations tiles.
- Confirm Capacity Forecast is the first Capacity Dashboard section and changes
  with the dashboard date.
- Confirm Capacity Dashboard and Workforce Intelligence titles use the same
  compact centered style as the other Operations destinations without truncation.
- Confirm all tile counts, capacity, credential-alert text, revenue, and
  recommendations update from live AppDataStore state.
- Confirm light/dark mode, large text, Back navigation, and pull-to-refresh do
  not introduce clipping or duplicate navigation controls.

### Completion Criteria
- [x] Tile-based Operations hub implemented.
- [x] Dedicated searchable destination pages implemented.
- [x] Existing operational action boundaries preserved.
- [x] Xcode build completed by product owner.
- [x] Navigation and search field validation accepted.

### Acceptance Result
Product-owner testing confirmed that all nine Operations tiles open their
intended destinations, extracted lists remain searchable and actionable,
Capacity Forecast is correctly embedded in Capacity Dashboard, and the compact
navigation titles render consistently without truncation.

### Resume Point
Begin Step 4.6 – Dashboard UI and Workflow Optimization. Review the existing
Dashboard information hierarchy and convert it to the accepted tile-based hub
without removing high-value business summaries.

---

# Step 4.6 – Dashboard UI and Workflow Optimization

## Status
Complete and accepted.

## Objective
Redesign the main Dashboard using the validated Operations tile language so the
application's primary entry screen has clearer information hierarchy, faster
workflow access, and consistent navigation.

### Accepted Information Architecture
- The Dashboard is the primary application hub and uses the reusable Operations
  tile language.
- The first row contains Sales and Service.
- My Day is centered in the second row.
- Operations and Admin occupy the final row.
- The top-level tab order is Dashboard, Sales, My Day, Service, Operations,
  Admin.
- Leads and Estimates live under the Sales hub.
- Jobs, Invoices, and Customers live under the Service hub.
- Catalog Items and Print live under Admin.

### Implementation Record
- Replaced the former record-heavy Dashboard with five focused navigation tiles.
- Added a Sales hub containing Leads and Estimates tiles.
- Added a Service hub containing Jobs, Invoices, and Customers tiles.
- Reduced the top-level application navigation to the six accepted business
  areas in the approved order.
- Dashboard tiles switch directly to their matching top-level tab, avoiding
  nested navigation stacks and duplicate Back buttons.
- Added an Admin navigation stack and moved Catalog Items and Print into a
  dedicated Catalog & Printing section.
- Removed the redundant inner navigation stack from Leads so it behaves like the
  other hub destinations.
- Extended the tile-based navigation pattern to Invoices, Jobs, Customers,
  Leads, and Estimates.
- Added filtered record destinations for invoice status, job status, customer
  sales status, lead follow-up status, and estimate workflow status.
- Preserved pull-down search on every record hub; a live Search Results tile
  opens the complete matching record list.
- Preserved each existing All-record list, archive toggle, record detail flow,
  and create-record workflow.

### Files Created
- `PPS Receipt Printer/BusinessHubViews.swift`
- `PPS Receipt Printer/RecordHubViews.swift`

### Files Modified
- `PPS Receipt Printer/ContentView.swift`
- `PPS Receipt Printer/DashboardView.swift`
- `PPS Receipt Printer/AdminView.swift`
- `PPS Receipt Printer/LeadsView.swift`
- `PPS Receipt Printer/InvoicesView.swift`
- `PPS Receipt Printer/JobsView.swift`
- `PPS Receipt Printer/CustomersView.swift`
- `PPS Receipt Printer/EstimatesView.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Validation Checklist
- [x] Project builds cleanly in Xcode.
- [x] Top-level tabs appear in the accepted order.
- [x] Dashboard tiles open Sales, Service, My Day, Operations, and Admin.
- [x] Sales tiles open Leads and Estimates with one Back button.
- [x] Service tiles open Jobs, Invoices, and Customers with one Back button.
- [x] Admin opens Catalog Items and Print successfully.
- [x] Existing add, search, edit, archive, and detail actions remain available.
- [x] Invoice Sent, Paid, Past Due, Draft, and All filters return correct records.
- [x] Job Active, Completed, and All filters return correct records.
- [x] Customer New Lead and Follow Up filters return correct records.
- [x] Lead and Estimate Follow Up filters use their accepted combined statuses.
- [x] Dashboard and hub tiles render correctly in light and dark mode.

### Completion Criteria
- [x] Dashboard tile hierarchy implemented.
- [x] Sales and Service hubs implemented.
- [x] Top-level navigation simplified and reordered.
- [x] Catalog and printing navigation moved under Admin.
- [x] Xcode build completed by product owner.
- [x] Navigation and workflow validation accepted.

### Acceptance Result
Product-owner testing confirmed that the redesigned Dashboard, Sales, Service,
My Day, Operations, and Admin navigation works successfully. The Invoice, Job,
Customer, Lead, and Estimate hubs present the accepted status tiles, retain
pull-down search, and preserve the existing create, detail, archive, and All
record workflows. Step 4.6 is accepted as the application-wide UI pattern for
future workflow pages.

### Resume Point
Begin Step 5 – Offline-Safe Workflow Handling by auditing the existing local
persistence, mutation, and synchronization paths before designing the offline
action queue.

---

# Step 5 – Offline-Safe Workflow Handling

## Status
Complete and validated. All seven implementation parts, the clean Xcode build,
and the complete regression and recovery test suite are accepted.

## Objective
Ensure reliable operation with poor or no connectivity.

### Architectural Boundary
PFSS remains a local-first application in this step. The offline queue and
synchronization contracts must not assume that CloudKit or another remote
backend already exists. Future adapters will consume the shared operation
envelope without changing technician-facing workflow code.

### Implementation Order
1. Offline operation models.
2. Persistent operation queue.
3. Workflow integration.
4. Connectivity monitor.
5. Synchronization processor.
6. Conflict handling.
7. Connection and synchronization status UI.
8. Regression and field testing.

## Part 1 – Offline Operation Model

### Status
Complete and validated.

### Implementation Record
- Added a standard `PendingOfflineOperation` envelope for any action awaiting
  synchronization.
- Added stable operation IDs and idempotency keys that remain unchanged across
  retries.
- Added typed operation and entity categories without coupling the model to a
  specific remote service.
- Added versioned, type-labelled Codable payload storage.
- Added pending, synchronizing, retry, failure, conflict, synchronized, and
  cancelled operation states.
- Added complete retry-attempt history, controlled retry timestamps, and
  durable failure diagnostics.
- Added local, remote, and merged record snapshots so conflicts never require
  discarding technician data.
- Added creation, update, attempt, retry, and synchronization timestamps.
- Added optimistic base-revision storage for future remote conflict detection.
- Added regression tests for persistence round trips, idempotency, retry timing,
  terminal-state protection, and preservation of conflicting versions.

### Files Created
- `PPS Receipt Printer/OfflineOperationModels.swift`
- `PPS Receipt PrinterTests/OfflineOperationModelsTests.swift`

### Part 1 Validation
- [x] Project builds cleanly in Xcode.
- [x] Offline operation model tests pass.
- [x] Payload encode/decode round trip is preserved.
- [x] Idempotency identity remains stable after persistence.
- [x] Retry readiness respects scheduled delays and terminal states.
- [x] Conflict models preserve both local and remote versions.

### Part 1 Acceptance Result
Product-owner validation confirmed a clean Xcode build with no errors. The
shared offline operation contract is accepted as the foundation for Step 5.

## Part 2 – Persistent Operation Queue

### Status
Complete and validated.

### Implementation Record
- Added an observable `OfflineOperationQueue` as the single source of truth for
  pending synchronization work.
- Added a separate versioned queue snapshot rather than expanding the primary
  `AppDataStore` snapshot.
- Added atomic disk writes so a crash cannot leave a partially written queue.
- Added automatic queue restoration during initialization for app and device
  restart recovery.
- Added monotonic sequence numbers that preserve original action order even
  when creation timestamps are identical.
- Added duplicate prevention using durable idempotency keys and operation IDs.
- Added guarded updates that prevent operation identity and queue position from
  changing during retries.
- Added mutation, lookup, removal, terminal-history cleanup, reload, pending
  counts, and persistence-error reporting.
- Ensured an unsuccessful disk write never publishes the unpersisted mutation
  to observers.
- Added regression tests for restart restoration, order preservation, duplicate
  prevention, failed-write safety, identity protection, and cleanup behavior.

### Files Created
- `PPS Receipt Printer/OfflineOperationQueue.swift`
- `PPS Receipt PrinterTests/OfflineOperationQueueTests.swift`

### File Modified
- `PPS Receipt Printer/OfflineOperationModels.swift`

### Part 2 Validation
- [x] Project builds cleanly in Xcode.
- [x] Persistent queue tests pass.
- [x] Queued operations survive constructing a new queue instance.
- [x] Original queue order survives persistence and reload.
- [x] Duplicate idempotency keys do not create duplicate actions.
- [x] Failed persistence leaves the last durable in-memory state unchanged.
- [x] Terminal cleanup never removes pending, failed, or conflicted work.

### Part 2 Acceptance Result
Product-owner validation confirmed a clean Xcode build and successful model and
persistent-queue test runs. Queue restoration, ordering, duplicate prevention,
failed-write protection, and terminal cleanup are accepted.

## Part 3 – Route Workflow Actions Through the Queue

### Status
Complete and validated.

### Implementation Record
- Added an explicit synchronization mode. PFSS remains `localOnly` until a
  remote adapter exists, preventing the app from presenting a false permanent
  backlog while retaining the full queue integration boundary.
- Injected the persistent operation queue into `AppDataStore` so future sync
  services and SwiftUI status views observe the same queue instance.
- Routed every successful Field Operations lifecycle action through one
  local-first boundary after the local Job and Assignment changes succeed.
- Added typed durable payloads for workflow actions, technician notes, invoice
  status/payment handoffs, and technician route-order changes.
- Technician notes retain the exact timeline event ID, author, text, and
  timestamp used by the local audit trail.
- Sent/overdue invoice handoffs and partial/full payment changes are queued as
  distinct operation types while preserving the linked Job number.
- My Day accepted routes and Dispatch Board manual route changes enqueue the
  exact ordered Job and Assignment identifiers plus the human-readable reason.
- Invalid lifecycle transitions do not mutate local state and do not enter the
  synchronization queue.
- Queue encoding or persistence failure never rolls back technician work that
  is already safe in the primary local store; the error is retained for the
  reusable sync-status UI planned in Part 6.
- Added integration tests for immediate local updates, durable workflow intent,
  invalid-transition protection, note identity, payment handoff, automatic Job
  completion, and local-only operation.

### Files Created
- `PPS Receipt Printer/AppDataStore+OfflineOperations.swift`
- `PPS Receipt PrinterTests/OfflineWorkflowIntegrationTests.swift`

### Files Modified
- `PPS Receipt Printer/AppDataStore.swift`
- `PPS Receipt Printer/AppDataStore+DispatchBoardActions.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 3 Validation
- [x] Project builds cleanly in Xcode.
- [x] All existing regression tests pass.
- [x] Successful lifecycle actions update the UI/local model immediately.
- [x] Successful lifecycle actions create one durable synchronization intent.
- [x] Invalid lifecycle actions create no queue entry.
- [x] Technician notes preserve their local timeline identity in the queue.
- [x] Invoice and payment transitions create correctly typed queue operations.
- [x] Accepted and manually changed route order is captured for synchronization.
- [x] Local-only mode does not create a false remote backlog.

### Part 3 Acceptance Result
Product-owner testing confirmed a clean build and successful complete test run.
The local-first workflow boundary, queue payloads, invalid-transition protection,
and repeat-run test isolation are accepted.

## Part 4 – Connectivity and Synchronization Service

### Status
Complete and validated.

### Implementation Record
- Added an `NWPathMonitor`-backed connectivity service with explicit Unknown,
  Offline, and Online states.
- Added a remote synchronization adapter protocol so CloudKit or a future PFSS
  server can plug in without changing the queue or technician workflow.
- Added a single ordered processor that submits operations by their durable
  sequence number and never processes later work after an earlier failure.
- Added automatic processing when connectivity returns and a manual Sync Now
  entry point that can intentionally bypass a scheduled retry delay.
- Added controlled retry backoff, a maximum-attempt limit, and durable attempt
  history including timestamps, outcomes, failures, and scheduled delays.
- Added startup recovery for operations interrupted while Synchronizing. Their
  original identity and order are preserved, the interrupted attempt is marked
  Deferred, and the operation safely returns to Waiting for Retry.
- Retryable failures become Waiting for Retry; permanent or exhausted failures
  remain visible and stop automatic processing safely.
- Successful operations retain their remote revision and are never resubmitted,
  including after repeated manual synchronization requests.
- Added an initial conflict result boundary. Part 5 will implement merge and
  human-review resolution policies while preserving both versions.
- Added processor tests for ordered delivery, offline safety, retry recovery,
  permanent-failure ordering, and duplicate-submission prevention.

### Files Created
- `PPS Receipt Printer/OfflineConnectivityMonitor.swift`
- `PPS Receipt Printer/OfflineSynchronizationService.swift`
- `PPS Receipt PrinterTests/OfflineSynchronizationServiceTests.swift`

### Files Modified
- `PPS Receipt Printer/OfflineOperationQueue.swift`
- `PPS Receipt PrinterTests/OfflineOperationQueueTests.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 4 Validation
- [x] Project builds cleanly in Xcode.
- [x] All existing regression tests pass.
- [x] Offline state leaves queued operations untouched.
- [x] Returning online begins processing in original queue order.
- [x] Retry delays and attempt history persist correctly.
- [x] Manual Sync Now safely retries eligible failed work.
- [x] Permanent failures stop later causally dependent operations.
- [x] Successful operations are never submitted twice.

### Part 4 Acceptance Result
Product-owner testing confirmed a clean build and successful synchronization
test run. Connectivity recovery, ordered delivery, retry behavior, and duplicate
submission protection are accepted.

## Part 5 – Conflict Handling

### Status
Complete and validated.

### Implementation Record
- Added conservative three-way JSON merging using the last common base, local
  technician version, and remote version.
- Independent changes to different fields merge automatically; competing edits
  to the same field never overwrite either version silently.
- Added backward-compatible optional base-version decoding. Older conflicts
  without a common ancestor remain safe and require human review.
- Automatically merged operations retain their identity and queue position,
  update their base revision, and are resubmitted exactly once.
- Repeated conflicts after an automatic merge stop for review instead of
  entering an unbounded retry loop.
- Human resolutions support Keep Local, Keep Remote, and Preserve Both.
- Every human decision records the employee, timestamp, resolution, note, and
  retained conflict snapshots in the durable operation envelope.
- Keep Local returns the same operation to the queue against the latest remote
  revision. Keep Remote completes it locally, while Preserve Both closes the
  synchronization intent without deleting either captured version.
- Added focused tests for safe automatic merges, competing-field detection,
  audited Keep Local resolution, and automatic merged-operation resubmission.

### Files Created
- `PPS Receipt Printer/OfflineConflictResolver.swift`
- `PPS Receipt PrinterTests/OfflineConflictResolverTests.swift`

### Files Modified
- `PPS Receipt Printer/OfflineOperationModels.swift`
- `PPS Receipt Printer/OfflineSynchronizationService.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 5 Validation
- [x] Project builds cleanly in Xcode.
- [x] All existing regression tests pass.
- [x] Independent local and remote edits merge automatically.
- [x] Competing edits preserve both versions and require review.
- [x] Automatically merged operations resubmit once without changing identity.
- [x] Human conflict resolutions retain actor, timestamp, note, and snapshots.
- [x] Keep Local, Keep Remote, and Preserve Both leave durable safe states.

### Part 5 Acceptance Result
Product-owner testing confirmed a clean build and successful complete test run.
Automatic merging, preservation of unsafe versions, audited human resolution,
and safe merged-operation resubmission are accepted.

## Part 6 – Connection and Synchronization Status UI

### Status
Complete and validated.

### Implementation Record
- Added one reusable presentation resolver for local-only, checking, online,
  offline-safe, synchronizing, pending, failed, conflict, and fully synchronized
  states.
- Added a compact, accessible status badge to My Day. Selecting it opens the
  detailed synchronization screen without disrupting the technician workflow.
- Added a Sync Status tile to Operations using the established Operations hub
  visual and navigation pattern.
- Added a detailed queue screen with connection state, pending, synchronizing,
  failed, and conflict counts plus recent synchronization activity.
- Failure messages and unresolved conflict preservation are visible without
  exposing raw payload contents or silently discarding local work.
- Added a shared connectivity monitor and optional synchronization service to
  `AppDataStore`, ensuring My Day and Operations observe the same live state.
- Added a manual Sync Now control. It activates automatically when remote mode,
  an adapter, and connectivity are available; it remains honestly disabled in
  the current local-only application configuration.
- Added a specific Saved on Device state so PFSS never claims cloud
  synchronization before a CloudKit or server adapter exists.
- Limited detailed synchronized history to the latest 50 operations while all
  durable queue history remains available to the persistence layer.
- Added resolver tests for local-only truthfulness, offline pending work,
  conflict priority, and fully synchronized remote state.

### Files Created
- `PPS Receipt Printer/OfflineSyncStatusView.swift`
- `PPS Receipt PrinterTests/OfflineSyncStatusResolverTests.swift`

### Files Modified
- `PPS Receipt Printer/AppDataStore.swift`
- `PPS Receipt Printer/TechnicianDailyAgendaView.swift`
- `PPS Receipt Printer/OperationsView.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 6 Validation
- [x] Project builds cleanly in Xcode.
- [x] All existing regression tests pass.
- [x] My Day shows a compact status without obstructing the schedule.
- [x] Operations provides detailed queue and connection information.
- [x] Local-only mode says Saved on Device rather than Fully Synchronized.
- [x] Offline pending work clearly states that changes are saved locally.
- [x] Failures and conflicts take priority over lower-severity states.
- [x] Sync Now enables only when a real remote synchronization path is ready.

### Part 6 Acceptance Result
Product-owner testing confirmed a clean build, successful complete test run,
accurate local-only and connection messaging, and working detailed status
navigation. Duplicate navigation containers in the Operations and Admin hubs
were removed so every subpage presents exactly one system back button.

## Part 7 – Recovery and Testing

### Status
Complete and validated.

### Implementation Record
- Added an end-to-end offline field workflow covering travel, arrival, setup,
  work, pause/resume, pack-up, completion, invoice, payment, and job closure.
- Verified the complete workflow survives queue reconstruction and later
  synchronizes in its original causal order.
- Added a connection-loss scenario that interrupts processing between actions,
  leaves remaining work pending, and resumes without resubmitting completed
  operations.
- Added simulated app-termination recovery for an operation left in the
  Synchronizing state, preserving its identifier, idempotency key, queue
  position, attempt history, and retry eligibility.
- Added retry-after-restart coverage proving the same durable idempotency key is
  reused and no duplicate queue entry is created.
- Added conflict restart coverage proving both technician and remote versions
  remain intact and visible for human review.
- Added repeated queue-reconstruction coverage to prove stable ordering and
  unique identities across multiple simulated launches.

### File Created
- `PPS Receipt PrinterTests/OfflineRecoveryTests.swift`

### Files Modified
- `PPS Receipt Printer/OperationsView.swift`
- `PPS Receipt Printer/AdminView.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 7 Validation
- [x] Project builds cleanly in Xcode.
- [x] All existing regression tests pass.
- [x] Complete offline lifecycle survives restart and synchronizes in order.
- [x] Connection loss during processing does not lose or duplicate work.
- [x] Interrupted synchronization recovers to a durable retryable state.
- [x] Retry after restart preserves operation identity and idempotency.
- [x] Conflicts preserve both versions after queue restoration.
- [x] Repeated app-style queue restoration preserves order and uniqueness.

### Part 7 Acceptance Result
Product-owner testing confirmed a clean Xcode build and a successful complete
test run, including every `OfflineRecoveryTests` scenario. Offline lifecycle
ordering, restart recovery, intermittent connectivity handling, retry identity,
duplicate prevention, and conflict preservation are accepted.

### Expected Outcomes
- Actions continue offline.
- Queued synchronization.
- Reduced conflict risk.
- No technician data loss.

### Completion Criteria
- [x] Offline testing completed.
- [x] Queue recovery validated.
- [x] Conflict handling verified.

### Step 5 Acceptance Result
Phase 15 Step 5 is complete. PFSS now has a durable local-first synchronization
boundary that preserves technician actions through lost connectivity, app or
device restarts, retryable failures, and conflicting remote edits. The current
application remains honest about its local-only configuration while exposing a
ready integration point for a future CloudKit or server adapter. The complete
implementation builds cleanly and all regression and recovery tests pass.

### Resume Point
Commit the completed Step 5 offline-safe workflow infrastructure, then begin
Step 6 by auditing the current workflow surfaces for redundant navigation,
duplicate actions, inconsistent terminology, and unnecessary technician taps.

---

# Step 6 – Workflow Cleanup and UI Simplification

## Status
Complete and validated.

## Objective
Remove redundant workflows and simplify navigation.

## Part 1 – Workflow Surface Audit

### Status
Complete.

### Objective
Inventory every operational surface before changing behavior, identify where
the same action or state is presented more than once, and establish the single
ownership boundary for the remaining Step 6 cleanup.

### Surfaces Reviewed

| Surface | Current workflow source | Actions or controls exposed | Audit result |
| --- | --- | --- | --- |
| Technician My Day | `FieldOperationsEngine` through `AppDataStore` and `FieldOperationsWorkflowCoordinator` | Navigate, Call, the next field action, pause/resume when available, invoice handoff, and a noninteractive Complete state | This is the accepted technician execution surface and should remain the primary field workflow. |
| Job Detail | Shared workflow context plus older Job-status branching | Shared Field Workflow card, technician notes, Job Log, Job Timeline, and a second Next Step button | Contains duplicate action presentation and duplicate timeline presentation. The older status-based Next Step path can disagree with the shared engine. |
| Assignment Detail | `AssignmentEngine` and `DispatchEngine` | Dispatch, Start Travel, Mark Arrived, Complete Work, Mark Invoice Ready, Close Assignment, scheduling, crew, cancel, and unassign | Dispatch, scheduling, crew, cancel, and unassign belong here. Travel-through-close duplicates the technician lifecycle and creates a second operational authority. |
| Dispatch Board queues | Dispatch Board snapshot and Assignment Detail/Manage destinations | Details and Manage | The queues do not mutate field state directly, but Details currently opens the parallel Assignment lifecycle while Manage exposes the correct dispatcher tools. |
| Operations Timeline | Timeline snapshot with Assignment Detail/Manage destinations | Details, Manage, alert review, and accepted plan visibility | The timeline is an operational review surface. It should not become another field-action owner. Details and Manage need clearly separated responsibilities. |
| Daily Planner | Daily Planner, Route, and Assignment planning services | Generate/refresh proposal, inspect capacity/conflicts, review and apply route | Correctly behaves as a preview-and-commit planning surface and does not directly execute technician lifecycle actions. |
| Live Map | Live Map snapshot with Assignment Detail or Employee Detail destinations | View assignment or technician details | Correctly acts as a situational-awareness surface, but Assignment Detail currently exposes the duplicated lifecycle after navigation. |
| Invoice Detail | Invoice record workflow through `AppDataStore` | Change invoice status, record payment information, share, print, archive, and restore | Invoice-domain actions belong here. Invoice Sent/Paid technician completion must be represented consistently by the shared field-workflow context. |

### Current Workflow Ownership

The intended operational path already exists:

```text
SwiftUI Surface
      ↓
FieldOperationsWorkflowCoordinator
      ↓
AppDataStore.performWorkflowAction
      ↓
FieldOperationsEngine
      ↓
Job + Assignment synchronization + offline queue
```

The audit found a competing path in `AssignmentDetailView`:

```text
Assignment Detail
      ↓
AssignmentEngine / DispatchEngine
      ↓
Assignment lifecycle only
```

`AppDataStore.performWorkflowAction` already synchronizes accepted Job workflow
milestones into the related Assignment and writes the offline operation intent.
Therefore, field actions must enter through the first path. Direct Assignment
field actions can bypass Job workflow state, technician timeline behavior, and
the Step 5 offline synchronization boundary.

### Duplicate and Inconsistent Behavior Found

1. **Parallel lifecycle controls** – Assignment Detail independently offers
   Start Travel, Mark Arrived, Complete Work, Mark Invoice Ready, and Close
   Assignment even though those milestones are already owned by the shared Job
   workflow.
2. **Two Job Detail action systems** – Job Detail renders the shared Field
   Workflow card and also renders a legacy `Next Step` button calculated from
   `JobStatus`. The two systems use different rules and labels.
3. **Duplicate history presentation** – Job Detail displays the same technician
   events in both Job Log and Job Timeline. The note composer is valuable, but
   the event list only needs one presentation.
4. **Vocabulary drift** – Equivalent actions currently appear as Arrived versus
   Mark Arrived, Start Job versus Start Work, Complete Job versus Complete Work,
   and Close Job/Close Assignment versus the accepted technician status
   Complete.
5. **Repeated presentation mappings** – My Day and `JobWorkflowComponents`
   separately map workflow actions and states to colors and icons. These can
   drift even when both screens consume the same engine context.
6. **Coordinator recreation** – My Day and Job Detail create a new workflow
   coordinator for individual reads and actions. This preserves the mutation
   result but discards observable coordinator outcome/error state between calls.
7. **Invoice completion mismatch** – My Day correctly treats Invoice Sent and
   Payment Received as technician-complete, while the core workflow still
   presents Invoice Created/Record Payment until payment is received. This
   accepted business rule needs one reusable presentation decision.
8. **Details/Manage overlap** – Dispatch Board and Timeline correctly provide
   Details and Manage destinations, but Assignment Detail duplicates several
   Manage responsibilities and also exposes technician actions. The destination
   contracts need to be made explicit.

### Action Ownership Decisions

#### Shared Field Workflow — one source of truth
- Start Travel
- Arrived
- Start Setup
- Start Work
- Pause Work
- Resume Work
- Start Pack-up
- Complete Work
- Create Invoice
- Record Payment or open the corresponding invoice
- Complete technician status

These actions must be validated and executed by the shared Field Operations
path so Job state, Assignment state, history, UI, and the offline queue remain
synchronized.

#### Dispatch and Assignment Management — remains separate
- Create and dispatch an Assignment.
- Assign, reassign, add, or remove crew.
- Schedule, reschedule, and apply planning constraints.
- Insert emergency work and apply route overrides.
- Cancel or unassign work with an audited reason.

These are office/dispatcher controls and remain owned by the Assignment and
Dispatch engines.

#### Record and Utility Actions — remain in their domains
- Invoice status, payment details, sharing, printing, archive, and restore remain
  in Invoice Detail.
- Technician notes use the shared Job timeline/audit path.
- Navigate, Call, Details, search, and filtering remain utility controls and do
  not change lifecycle state.

### Canonical Vocabulary Proposed for Part 2

| Milestone | Canonical technician label |
| --- | --- |
| Travel begins | Start Travel |
| Technician reaches site | Arrived |
| Setup begins | Start Setup |
| Productive work begins | Start Work |
| Work temporarily stops | Pause Work |
| Paused work continues | Resume Work |
| Pack-up begins | Start Pack-up |
| Field work ends | Complete Work |
| Invoice is created | Create Invoice |
| Payment workflow opens | Record Payment |
| Invoice sent or payment received | Complete |

`Complete Work` is an action. `Complete` is the final technician-facing status
after the invoice has been sent or payment has been received. The two must not
be used interchangeably.

### Prioritized Cleanup Backlog

1. Lock the vocabulary and move titles, icons, colors, and completion
   presentation into shared workflow presentation metadata.
2. Remove the legacy Job Detail Next Step action path and retain one shared
   Field Workflow control.
3. Consolidate Job Log and Job Timeline while preserving the note composer.
4. Remove technician lifecycle mutations from Assignment Detail; retain only
   dispatch, scheduling, crew, cancel, unassign, and record-detail functions.
5. Make Dispatch Board, Timeline, and Live Map detail destinations read from the
   shared operational state and route mutations to the correct owner.
6. Reuse one observable coordinator per workflow surface and surface failed
   action feedback consistently.
7. Add regression tests proving every entry surface produces the same action,
   state, history, Assignment synchronization, and offline operation intent.

### Files Reviewed
- `PPS Receipt Printer/FieldOperationsEngine.swift`
- `PPS Receipt Printer/FieldOperationsWorkflowCoordinator.swift`
- `PPS Receipt Printer/AppDataStore.swift`
- `PPS Receipt Printer/JobWorkflowComponents.swift`
- `PPS Receipt Printer/TechnicianDailyAgendaView.swift`
- `PPS Receipt Printer/JobDetailView.swift`
- `PPS Receipt Printer/AssignmentDetailView.swift`
- `PPS Receipt Printer/DispatchBoardView.swift`
- `PPS Receipt Printer/DispatchBoardDestinationViews.swift`
- `PPS Receipt Printer/OperationsTimelineView.swift`
- `PPS Receipt Printer/DailyPlanPreviewView.swift`
- `PPS Receipt Printer/OperationsLiveMapView.swift`
- `PPS Receipt Printer/InvoiceDetailView.swift`

### Part 1 Validation
- [x] Technician workflow surfaces inventoried.
- [x] Dispatcher and office workflow surfaces inventoried.
- [x] Planning, timeline, map, and invoice handoff surfaces inventoried.
- [x] Duplicate action owners identified.
- [x] Inconsistent labels and completion semantics identified.
- [x] Field, dispatch, record, and utility action boundaries documented.
- [x] Cleanup order documented without changing production behavior.

### Part 1 Acceptance Result
The audit confirms that the Step 5 offline-safe mutation boundary is the correct
foundation for Step 6. My Day and the shared Job workflow should remain the
technician execution authority. Assignment Detail should retain assignment and
dispatcher management but must no longer act as a parallel field workflow.
Planning, Timeline, and Live Map remain review and navigation surfaces.

### Files Modified
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Resume Point
Begin Step 6 Part 2 – Action Vocabulary and Shared Presentation Metadata. Adopt
the canonical labels above, centralize action/state titles, icons, colors, and
technician-complete presentation, then add tests before removing redundant
controls in Part 3.

## Part 2 – Action Vocabulary and Shared Presentation Metadata

### Status
Complete and validated.

### Objective
Give every technician workflow surface one reusable source for action labels,
symbols, colors, state labels, and technician-complete presentation without
changing lifecycle rules or removing controls yet.

### Implementation Record
- Added `JobWorkflowActionPresentation` as the canonical action-presentation
  record.
- Added `JobWorkflowAccent` so presentation intent is testable without coupling
  the field engine to SwiftUI.
- Added `JobWorkflowPresentation` to every `JobWorkflowContext`.
- Adopted the accepted canonical action vocabulary: Start Travel, Arrived,
  Start Setup, Start Work, Pause Work, Resume Work, Start Pack-up, Complete
  Work, Create Invoice, Record Payment, Complete, and Details.
- Distinguished the `Complete Work` lifecycle action from the final
  technician-facing `Complete` status.
- Centralized state labels, symbols, and semantic accents for Not Started,
  Traveling, Arrived, Setting Up, Working, Paused, Packing Up, Work Complete,
  Invoice Created, Payment Received, Complete, and Cancelled.
- Centralized the accepted invoice handoff rule: Sent or Overdue displays
  Invoice Sent and Job Complete; Partially Paid or Paid displays Payment
  Received and Job Complete.
- Preserved invoice financial state independently from technician completion,
  allowing a technician to finish the workday while an invoice remains unpaid.
- Updated the reusable Job workflow card to consume shared presentation
  metadata instead of maintaining its own icon, color, and action-tint switches.
- Updated My Day to consume the same presentation metadata and removed its
  duplicate invoice-state and workflow-color mappings.
- Updated Job Detail status and its legacy action label/icon to read from the
  shared context. The redundant legacy control remains scheduled for removal in
  Part 3.

### Files Modified
- `PPS Receipt Printer/FieldOperationsEngine.swift`
- `PPS Receipt Printer/JobWorkflowComponents.swift`
- `PPS Receipt Printer/TechnicianDailyAgendaView.swift`
- `PPS Receipt Printer/JobDetailView.swift`
- `PPS Receipt PrinterTests/FieldOperationsEngineTests.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Regression Coverage Added
- Canonical title and accent coverage for every `JobWorkflowAction`.
- Nonempty shared symbol coverage for every action.
- Invoice Sent presentation coverage without changing the underlying unpaid
  financial state.
- Paid invoice coverage for Payment Received and Job Complete presentation.

### Part 2 Validation
- [x] A single canonical action vocabulary is defined.
- [x] Action labels, symbols, and accents share one source.
- [x] State labels, symbols, and accents share one source.
- [x] My Day consumes shared presentation metadata.
- [x] Job Detail and the reusable workflow card consume shared metadata.
- [x] Invoice Sent and Payment Received completion semantics are centralized.
- [x] Modified Swift files pass syntax parsing.
- [x] No Swift compiler error was reported during the command-line source build.
- [x] Project builds cleanly in the product owner's Xcode environment.
- [x] Complete regression suite passes.
- [x] Product owner accepts the visible vocabulary and status presentation.

### Validation Note
The command-line build reached Swift compilation without reporting a source
error. It could not complete asset-catalog processing because CoreSimulator
runtimes were unavailable to the Codex process. Final Xcode build and test
validation remains with the product owner.

### Part 2 Acceptance Result
Product-owner validation confirmed a clean Xcode build and accepted the shared
workflow vocabulary and presentation. The final missing explicit SwiftUI return
in My Day was corrected and the affected source passed parsing and diff checks.

## Part 3 – Remove the Redundant Job Detail Action Path

### Status
Complete and validated.

### Objective
Make the shared Field Workflow card the only Job Detail lifecycle control and
remove the older status-based Next Step path that could disagree with the Field
Operations engine.

### Implementation Record
- Made the shared Field Workflow card visible as the single lifecycle control
  on Job Detail.
- Removed the separate Next Step section and its duplicate title, icon,
  disabled-state, and guided-action calculations.
- Removed the older `performGuidedPrimaryAction` entry point from Job Detail.
- Preserved local Job edits before a workflow transition is submitted.
- Kept every lifecycle mutation routed through
  `FieldOperationsWorkflowCoordinator` and the Step 5 offline-safe store
  boundary.
- Preserved invoice handoff: Create Invoice opens the newly linked Invoice
  Detail after the shared action succeeds, while Record Payment opens the
  existing invoice so payment is recorded in its proper domain.
- Kept dispatcher, scheduling, pricing, technician, archive, and work-order
  editing behavior unchanged.
- Corrected a test-isolation defect discovered during Part 3 validation. The
  offline workflow tests now disable primary AppDataStore disk persistence
  instead of writing fixtures into the hosted app's production JSON store.
- Added a narrowly targeted startup cleanup for legacy fixtures whose exact
  customer marker is `PPS-OFFLINE-TEST` and whose Job number begins with
  `JOB-OFFLINE-` or equals `JOB-LOCAL-ONLY`. Related test invoices and
  assignments are removed without touching business records.
- Added editable Amount Paid entry to Invoice Detail so partial payments can be
  recorded in the field and the remaining balance updates immediately.
- Centralized invoice payment normalization in `AppDataStore`: partial amounts
  become Partially Paid, full amounts become Paid, overpayments are clamped to
  the invoice total, Balance Due is recalculated, and Paid Date is retained only
  for fully paid invoices.

### Files Modified
- `PPS Receipt Printer/JobDetailView.swift`
- `PPS Receipt Printer/AppDataStore.swift`
- `PPS Receipt Printer/InvoiceDetailView.swift`
- `PPS Receipt PrinterTests/OfflineWorkflowIntegrationTests.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 3 Validation
- [x] Job Detail exposes only one lifecycle control in source.
- [x] The remaining control consumes the shared `JobWorkflowContext`.
- [x] Workflow mutations continue through the shared coordinator.
- [x] Invoice creation and payment handoff remain connected to Invoice Detail.
- [x] Offline workflow tests cannot load or save the production app snapshot.
- [x] Previously leaked offline-test fixtures have a marker-specific cleanup.
- [x] Partial payment amount, remaining balance, status, and queue intent have
  focused regression coverage.
- [x] Project builds cleanly in the product owner's Xcode environment.
- [x] Start Travel through Complete remains functional from Job Detail.
- [x] Create Invoice and Record Payment open the corresponding invoice.
- [x] Complete regression suite passes.

### Part 3 Acceptance Result
Product-owner testing confirmed that the single Job Detail workflow control,
invoice handoff, partial-payment entry, remaining-balance calculation, and
invoice bucket behavior all work correctly. Partially paid invoices remain in
Sent until an unpaid balance passes its due date, when they appear in Past Due.

## Part 4 – Consolidate Job Activity History

### Status
Complete and validated.

### Objective
Replace the duplicate Job Log and Job Timeline presentations with one
chronological Job Timeline while retaining technician note entry and author
attribution.

### Implementation Record
- Replaced the separate Job Log event renderer with the reusable
  `JobTimelineView` driven by the shared `JobWorkflowContext`.
- Kept the technician note composer and Add Note action in the same Job
  Timeline section.
- Preserved chronological workflow events, timestamps, technician attribution,
  and note text.
- Removed the second hidden Job Timeline section.
- Removed the duplicate Job Detail event-row and event-icon mappings.
- Kept Field Workflow, technician assignment, scheduling, pricing, work-order,
  and invoice behavior unchanged.

### Files Modified
- `PPS Receipt Printer/JobDetailView.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 4 Validation
- [x] Job Detail contains one Job Timeline section in source.
- [x] The timeline consumes the shared workflow context.
- [x] Technician note entry remains available.
- [x] Duplicate Job Log rendering and icon mappings are removed.
- [x] Modified Swift sources pass syntax parsing.
- [x] Repository diff passes whitespace validation.
- [x] Project builds cleanly in the product owner's Xcode environment.
- [x] Existing and newly added notes appear once in chronological order.
- [x] Complete regression suite passes.

### Part 4 Acceptance Result
Product-owner testing confirmed a clean build and clean regression suite. Job
Detail now presents one chronological activity history, and technician notes
remain available without duplicating timeline events.

## Part 5 – Separate Assignment Management from Field Execution

### Status
Complete and validated.

### Objective
Keep Assignment Detail focused on dispatcher and assignment-management work and
remove its parallel technician lifecycle path.

### Implementation Record
- Retained Dispatch Assignment as the sole primary transition on Assignment
  Detail because dispatch remains an office/dispatcher responsibility.
- Removed Start Travel, Mark Arrived, Complete Work, Mark Invoice Ready, and
  Close Assignment controls from Assignment Detail.
- Removed the private action enum and direct Assignment-engine calls that
  powered those duplicate technician transitions.
- Preserved schedule editing, priority, crew management, unassignment,
  cancellation, notes, history, and Assignment record details.
- Preserved both `DispatchEngine` dispatch and the existing Assignment-engine
  fallback for contexts where a Dispatch engine is not supplied.
- Left technician lifecycle execution owned by My Day and the shared Job Field
  Workflow path, which also preserves Job state, audit history, Assignment
  synchronization, and offline operation intent.

### Files Modified
- `PPS Receipt Printer/AssignmentDetailView.swift`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 5 Validation
- [x] Assignment Detail exposes Dispatch Assignment only for scheduled work.
- [x] Technician travel-through-completion controls are absent from Assignment
  Detail source.
- [x] Scheduling, priority, crew, unassign, cancel, notes, and history remain.
- [x] Modified Swift source passes syntax parsing.
- [x] Repository diff passes whitespace validation.
- [x] Project builds cleanly in the product owner's Xcode environment.
- [x] Dispatch Assignment remains functional.
- [x] Assignment management controls remain functional for their valid states.
- [x] Complete regression suite passes.

### Part 5 Acceptance Result
Product-owner testing confirmed a clean build and working Assignment behavior.
Technician lifecycle execution remains owned by My Day and Job Detail, while
dispatcher assignment responsibilities remain available through the Operations
management flow.

## Part 6 – Align Operational Destinations

### Status
Complete and validated.

### Objective
Make Dispatch Board, Operations Timeline, Live Map, and Operations hub links
consume the same Assignment state while giving Details and Manage distinct,
predictable responsibilities.

### Implementation Record
- Audited Assignment destinations across Dispatch Board, Operations Timeline,
  Live Map, Active Assignments, Dispatch Queue, and Operations hub surfaces.
- Confirmed these destinations resolve current Assignment records through the
  shared `AppDataStore` Assignment engine rather than maintaining independent
  copies of operational state.
- Kept Details routed to `AssignmentDetailView` and dispatcher actions routed
  to `DispatchBoardAssignmentActionsView` where a Manage action is presented.
- Made Assignment Detail read-only by default: priority, scheduling, crew,
  status, notes, and history remain visible without exposing mutation controls.
- Retained an explicit `allowsManagement` entry point for contexts that
  intentionally need an editable Assignment detail in the future.
- Preserved scheduling, ownership, route insertion, crew, reassignment, and
  dispatch controls in the dedicated Manage Assignment surface.
- Added installed-app Version and Build values to Admin for physical-device
  build verification.
- Incremented the application build from 1 to 2; this build displays as
  Version 1.0, Build 2.

### Files Modified
- `PPS Receipt Printer/AssignmentDetailView.swift`
- `PPS Receipt Printer/AdminView.swift`
- `PPS Receipt Printer.xcodeproj/project.pbxproj`
- `Documentation/Phase Development/Phase_15_Project_Workbook.md`

### Part 6 Validation
- [x] Operations destinations resolve current Assignment data from the shared
  store and engine.
- [x] Details destinations are read-only by default.
- [x] Manage destinations retain dispatcher-owned actions.
- [x] Assignment Detail contains no technician lifecycle controls.
- [x] Admin displays the installed Version and Build identifiers.
- [x] Modified Swift sources pass syntax parsing.
- [x] Project file passes property-list validation.
- [x] Repository diff passes whitespace validation.
- [x] Project builds cleanly in the product owner's Xcode environment.
- [x] Dispatch Board, Timeline, and Live Map reflect the same status.
- [x] Details and Manage routes behave correctly on a physical device.
- [x] Complete regression suite passes.

### Part 6 Acceptance Result
Product-owner testing confirmed a clean build and complete regression suite.
Operations destinations reflect shared Assignment state, Details remains
read-only, Manage retains dispatcher-owned actions, and Admin correctly shows
Version 1.0, Build 2 for device verification.

### Resume Point
Step 6 is complete. Proceed to Step 7 acceptance testing and polish using
Version 1.0, Build 2 as the verified test baseline.

### Expected Outcomes
- Cleaner navigation.
- Fewer taps.
- Consistent controls and terminology.
- Reduced confusion.

### Completion Criteria
- Redundant UI removed.
- UX review approved.
- Documentation updated.

---

# Step 7 – Acceptance Testing and Polish

## Objective
Validate the consolidated workflow in real-world scenarios.

### Expected Outcomes
- Dispatcher-managed, technician-managed, and hybrid workflows validated.
- Known issues resolved.
- Ready for workbook closeout and Git tagging.

### Completion Criteria
- Acceptance testing signed off.
- Critical defects resolved.
- Workbook completed.
- Release tagged.

---

# Phase Success Criteria

- One workflow engine drives all operational screens.
- Actions behave identically from every entry point.
- Timeline, Route, Dispatch, and My Day remain synchronized.
- Offline handling is reliable and recoverable.
- The UI is simpler and more intuitive.
- The workbook provides a complete implementation record ready for Git tagging.
