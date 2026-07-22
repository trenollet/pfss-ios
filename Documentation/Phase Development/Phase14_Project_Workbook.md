# PFSS Phase 14 Project Workbook

**Phase:** 14 – Dispatch and Field Intelligence  
**Branch:** `feature/phase14-dispatch-field-intelligence`  
**Status:** Step 3 complete and accepted; Step 4 ready to begin
**Current Step:** Step 4 – Route Engine Integration
**Document Type:** Living engineering workbook  

---

## 1. Purpose

This workbook is the authoritative implementation, architecture, and progress record for Phase 14 of PFSS. It exists so development can pause and resume at any point without repeating the planning process.

The workbook serves four purposes:

1. **Architecture reference** – records what was decided and why.
2. **Implementation roadmap** – defines the build sequence and expected outcome of every step.
3. **Engineering logbook** – records files, classes, tests, commits, decisions, and lessons as work is completed.
4. **Resume point** – identifies exactly where development stopped and what must happen next.

This file must be updated at the end of every implementation step and before moving to the next step.

---

## 2. Phase Vision

Phase 14 transforms PFSS from a business-record system into an operational field-service platform.

The system should not merely ask:

> How do we schedule this job?

It should help answer:

> How do we run today's field operation as efficiently as possible?

The phase introduces a formal operational layer between a Job and field execution. The central operational object is the **Assignment**.

```text
Lead
  ↓
Estimate
  ↓
Approved
  ↓
Job
  ↓
Ready for Scheduling
  ↓
Assignment
  ↓
Daily Planning
  ↓
Route Optimization
  ↓
Dispatch
  ↓
Field Operations
  ↓
Invoice
  ↓
Payment
```

Everything above Assignment is primarily business management. Everything at and below Assignment is field operations.

---

## 3. Design Philosophy

Phase 14 is governed by the following principles:

### 3.1 PFSS recommends; humans decide

Scheduling, routing, technician selection, and emergency insertion should be supported by intelligent recommendations. The dispatcher or technician retains final authority.

### 3.2 Trust field professionals

Technicians may adjust their route and sequence when real-world conditions require it. The system should record changes for analysis, not unnecessarily prevent them.

### 3.3 Assignment is the operational object

A Job is the business record. An Assignment is the operational record used to schedule, dispatch, route, execute, and track the work.

### 3.4 Technician-centric operations

The primary Dispatch Board should be organized around technicians because dispatchers typically think in terms of who is doing what next.

### 3.5 Small-business flexibility

PFSS must support dispatcher-managed, technician self-managed, and hybrid operations. Permissions and responsibilities should not be hard-coded to a single company structure.

### 3.6 Intelligence augments experience

The software should improve decisions by considering route, workload, availability, skills, equipment, urgency, and history. It should not replace human judgment.

---

## 4. Core Architectural Decisions

### Decision 1 – Assignment, not Job, is the operational object

A Job remains the commercial/business record. Assignment owns the operational concerns associated with field execution.

Assignment will own or reference:

- Primary technician
- Supporting technicians
- Scheduling mode and constraints
- Assignment lifecycle status
- Planned and actual timestamps
- ETA and travel information
- Route position
- Field notes
- Dispatch history
- Status history
- Labor participation
- Location-related operational data

### Decision 2 – V1 Job-to-Assignment relationship

For Version 1:

```text
One Job
  ↓
One Assignment
  ↓
One or More Employees
```

Multiple technicians are supported from the beginning. Multiple Assignments per Job are deferred to a later phase.

### Decision 3 – Assignment lifecycle

The lifecycle begins when the work is scheduled.

```text
Scheduled
  ↓
Dispatched
  ↓
En Route
  ↓
On Site
  ↓
Work Complete
  ↓
Invoice Ready
  ↓
Closed
```

These are workflow states, not decorative labels. State transitions must be validated and recorded.

### Decision 4 – Hybrid lifecycle ownership

Dispatcher responsibilities:

- Create and schedule assignments
- Assign and reassign technicians
- Monitor progress
- Override when needed
- Insert emergency work

Technician responsibilities:

- Progress the assignment in the field
- Manage operational execution
- Adjust route order when necessary
- Record completion and field information

Dispatch authority is permission-based rather than tied to a rigid employee type.

### Decision 5 – Technician route autonomy

The Route Engine provides an intelligent recommended route. The technician may reorder assignments in the field.

```text
Route Engine → recommendation
Technician   → authority
```

Route changes should be recorded silently for future analytics and optimization.

### Decision 6 – Emergency work insertion

When emergency work is introduced, PFSS should analyze:

- Technician GPS/location
- Current route
- Estimated travel time
- Technician skills
- Certifications
- Equipment and vehicle availability
- Existing crew
- Current schedule
- Assignment priority
- Remaining daily capacity

PFSS recommends the best technician and insertion point. The dispatcher or technician accepts or modifies the recommendation.

### Decision 7 – Assignment ownership

Each Assignment has:

- One **Primary Technician**
- Zero or more **Supporting Technicians**

The Primary Technician owns completion, communication, and primary status authority. Supporting technicians assist and have their labor participation tracked individually.

### Decision 8 – Job readiness controls Assignment creation

An approved Job does not automatically become an Assignment if the work is not ready.

A Job may remain in the queue while waiting for:

- Materials
- Permits
- HOA approval
- Deposit
- Customer scheduling
- Insurance authorization
- Other operational prerequisites

Only work marked ready for scheduling moves into the Assignment workflow.

### Decision 9 – Every Assignment has a Scheduling Mode

Assignments are not defined by whether they have an appointment. They are defined by scheduling constraints.

V1 Scheduling Modes:

| Mode | Meaning |
|---|---|
| Fixed Time | Must begin at a specific time. |
| Arrival Window | Must begin within a defined time range. |
| Flexible Day | Must be completed on a specific day but has no fixed start time. |
| Deadline | Must be completed before a specified date/time. |

Assignments should exist independently of calendar appointments. Appointment-like data is represented as scheduling constraints on the Assignment.

### Decision 10 – Primary Dispatch Board is technician-centric

The primary operational view is organized by technician.

```text
Mike
  8:00  Roof Inspection
  10:30 Gutter Cleaning
  1:00  Window Cleaning

Sarah
  8:00  Estimate
  11:00 Mailbox Repair
  2:00  Deck Repair
```

The technician view, timeline view, and map view are synchronized lenses over the same operational state.

### Decision 11 – Recommendations never remove technician choice

The Dispatch Queue highlights PFSS's recommended technician but also presents every eligible technician in a picker. A dispatcher or self-managing technician may override the recommendation. Conflict and capacity warnings remain visible so the decision is informed rather than blocked.

### Decision 12 – Recurring Jobs materialize one future occurrence

Recurring Jobs support Weekly, Bi-Weekly, Monthly, Quarterly, Bi-Annual, and Annual schedules.

- PFSS creates exactly one upcoming occurrence at a time.
- The future occurrence is unassigned and enters dispatch planning naturally.
- Completing an occurrence creates the next occurrence.
- Series and sequence identifiers prevent duplicates across saves and app launches.
- Disabling recurrence removes only unstarted future occurrences.
- Existing saved Jobs remain backward compatible.

---

## 5. Engine Architecture

### 5.1 Assignment Engine

**Question answered:** What is the operational work object and how does it progress?

Responsibilities:

- Assignment creation and validation
- Job-to-Assignment relationship
- Lifecycle and state transitions
- Primary and supporting technicians
- Scheduling constraints
- Planned and actual timestamps
- Assignment history
- Crew participation and labor attribution

### 5.2 Scheduling Engine

**Question answered:** When may this work occur?

Responsibilities:

- Scheduling mode interpretation
- Customer availability
- Technician availability
- Business hours
- Earliest/latest start constraints
- Duration requirements
- Deadlines
- Hard and soft scheduling restrictions

### 5.3 Daily Planner Engine

**Question answered:** What is the best practical workday?

The Daily Planner sits between scheduling and routing.

Responsibilities:

- Place fixed-time assignments
- Respect arrival windows
- Identify open time between commitments
- Insert Flexible Day assignments into available capacity
- Account for estimated duration
- Reserve travel buffers
- Consider lunch and breaks
- Identify unused capacity
- Identify overload and overtime risk
- Produce an ordered proposed daily plan

Example:

```text
8:00–10:00   Fixed assignment
10:00–2:00   Available planning window
2:00–4:00    Fixed assignment

Flexible work:
- 45-minute mailbox repair
- 90-minute gutter cleaning

Planner result:
8:00–10:00   Fixed assignment
10:15–11:00  Mailbox repair
11:15–12:45  Gutter cleaning
2:00–4:00    Fixed assignment
```

### 5.4 Route Optimization Engine

**Question answered:** What is the most efficient travel order?

Responsibilities:

- Optimize geographic sequence
- Estimate travel time
- Respect fixed starts and arrival windows
- Preserve Daily Planner constraints
- Recalculate after route changes or emergency insertion
- Return recommendations without removing human authority

### 5.5 Dispatch Engine

**Question answered:** Who is doing the work, and what is happening now?

Responsibilities:

- Dispatch assignments
- Assign and reassign technicians
- Support dispatcher-managed and self-managed workflows
- Insert emergency assignments
- Track current technician and assignment status
- Coordinate crew changes
- Apply dispatcher overrides
- Feed synchronized UI views

### 5.6 Workforce Intelligence

**Question answered:** What operational capabilities does each employee bring?

Employee profiles should evolve beyond basic HR records to include:

- Skills
- Certifications
- Equipment access
- Vehicle access
- Availability
- Current assignment
- Workload
- Hours worked
- Work history
- Performance metrics
- Preferred service types
- Training records
- Future crew compatibility data

### 5.7 Recommendation Engine

**Question answered:** What action does PFSS recommend?

Responsibilities:

- Best technician recommendation
- Emergency insertion recommendation
- Workload balancing recommendation
- Skill and equipment matching
- Route-aware assignment selection
- Capacity and overtime warnings

Recommendations are advisory and must include enough context for a human to evaluate them.

---

## 6. Shared Operational State and Views

The Dispatch Board, Timeline View, and Live Map should read and mutate the same underlying Assignment/Dispatch state.

```text
                    Assignment + Dispatch State
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
     Technician View     Timeline View     Live Map View
```

A change made in one view must appear immediately in the others.

### Technician View

Primary workspace for assignment ownership, route order, crew, workload, and current status.

### Timeline View

Time-based visualization of fixed assignments, windows, flexible work, gaps, conflicts, and capacity.

### Live Map View

Geographic visualization of technicians, assignments, route sequence, travel progress, and emergency opportunities.

---

## 7. Development Discipline

Every implementation step follows the same sequence:

1. Review this workbook and the current step requirements.
2. Confirm the architecture and dependencies.
3. Design or update models.
4. Implement engines/services.
5. Implement supporting UI.
6. Add and run tests.
7. Perform a focused stability check.
8. Commit the completed step to Git.
9. Update this workbook with files, classes, tests, decisions, commit hash, completion date, and known improvements.
10. Begin the next step only after completion criteria are met.

### Definition of Done for Every Step

A step is complete only when:

- Required code is implemented.
- Existing behavior remains stable.
- New behavior is tested.
- Error and empty states are handled where applicable.
- The project builds successfully.
- No known blocking defect remains.
- Code is committed to the Phase 14 branch.
- This workbook is updated.

---

## 8. Phase 14 Implementation Checklist

- [x] Step 1 – Assignment Engine *(completed and accepted 2026-07-22)*
- [x] Step 2 – Dispatch Engine *(completed and accepted 2026-07-22)*
- [x] Step 3 – Daily Planner Engine *(completed and accepted 2026-07-22)*
- [ ] Step 4 – Route Engine Integration
- [ ] Step 5 – Workforce Intelligence
- [ ] Step 6 – Recommendation Engine
- [ ] Step 7 – Dispatch Board UI
- [ ] Step 8 – Timeline View
- [ ] Step 9 – Live Map View
- [ ] Step 10 – Field Operations
- [ ] Step 11 – Operational Analytics
- [ ] Step 12 – Stabilization and Phase Completion

---

## 9. Detailed Implementation Roadmap

## Step 1 – Assignment Engine

### Objective

Create the foundation for all operational work in Phase 14.

### Requirements

- Define the Assignment model.
- Preserve the V1 one-Job-to-one-Assignment relationship.
- Support one Primary Technician and multiple Supporting Technicians.
- Define Scheduling Mode and all required constraint fields.
- Define and validate the Assignment lifecycle.
- Record lifecycle transitions and operational history.
- Store planned and actual timestamps.
- Support estimated duration.
- Track crew participation and technician labor attribution.
- Keep the model extensible for multiple Assignments per Job later.

### Expected Components

Names may be adjusted to match existing project conventions.

- `Assignment`
- `AssignmentStatus`
- `AssignmentSchedulingMode`
- `AssignmentScheduleConstraint`
- `AssignmentCrewMember`
- `AssignmentHistoryEntry`
- `AssignmentStore`
- `AssignmentEngine`
- Assignment validation/state-transition tests

### Outcome

PFSS has a complete operational work object that all scheduling, routing, dispatch, field, and analytics components can depend on.

### Completion Criteria

- Assignment persists correctly.
- Valid lifecycle transitions succeed.
- Invalid transitions are rejected safely.
- Primary and supporting technicians are represented correctly.
- All four Scheduling Modes can be represented.
- Assignment history records meaningful changes.
- Tests pass and project builds.

### Engineering Record

- **Status:** Complete — implementation, integration, stabilization, and product-owner acceptance testing passed
- **Start date:** 2026-07-21
- **Completion date:** 2026-07-22
- **Implementation commit:** `8ca08f8`
- **Published integration checkpoint:** `942c7b5` / `v0.9.9-phase14.1`
- **Final closeout checkpoint:** This workbook's containing commit, tagged `v0.9.10-phase14.1-complete`
- **Files added:** `Assignment.swift`, `AssignmentEnums.swift`, `AssignmentHistory.swift`, `AssignmentCrew.swift`, `AssignmentScheduling.swift`, `AssignmentStore.swift`, `AssignmentEngine.swift`, `AssignmentCard.swift`, `AssignmentStatusBadge.swift`, `AssignmentDetailView.swift`, `CrewEditor.swift`
- **Files modified:** `AppDataStore.swift`, `Models.swift`, Operations and supporting record views
- **Tests completed:** Product-owner end-to-end acceptance testing; lifecycle and scheduling-mode validation; Primary/Supporting Technician rules; Operations dispatch override; persistence and legacy Job migration; recurring-job generation; Assignment Detail and Active Assignment UI; customer/site creation workflow; navigation regression checks; clean-build validation; full Swift-module type-check validation
- **Automated coverage note:** Dedicated Assignment-domain unit-test expansion remains desirable and is tracked for the stabilization/test-hardening workstream; it is not a blocker to Step 2 after successful acceptance and integration testing
- **Decisions made during implementation:** AssignmentEngine is the public Operations API; store lookup methods use explicit names; recommendations remain overridable; recurrence generates one future occurrence
- **Known improvements:** Expand automated Assignment-domain regression coverage during test hardening
- **Acceptance result:** All corrective retests passed; no known blocking Step 1 defect remains

---

## Step 2 – Dispatch Engine

### Objective

Implement the operational movement and ownership of Assignments.

### Requirements

- Dispatch a scheduled Assignment.
- Assign and reassign a Primary Technician.
- Add and remove Supporting Technicians.
- Support dispatcher-managed, technician self-managed, and hybrid permissions.
- Support emergency work insertion.
- Preserve and record dispatch/reassignment history.
- Expose current technician and Assignment state for all synchronized views.
- Allow dispatcher override without corrupting lifecycle history.

### Expected Components

- `DispatchEngine`
- `DispatchStore` or dispatch state extension
- `DispatchAction`
- `DispatchEvent`
- `DispatchPermission`
- Emergency insertion request/result models
- Dispatch and reassignment tests

### Outcome

PFSS can assign, dispatch, reassign, and monitor operational work while maintaining a trustworthy history.

### Completion Criteria

- Assignment dispatch works for valid states.
- Reassignment preserves audit history.
- Crew changes are reflected consistently.
- Permission rules support all three operating styles.
- Emergency insertion requests can be represented and processed.
- Tests pass and project builds.

### Engineering Record

- **Status:** Complete — implementation, integration, corrective stabilization, and product-owner acceptance testing passed
- **Start date:** 2026-07-22
- **Completion date:** 2026-07-22
- **Closeout checkpoint:** This workbook's containing commit, tagged `v0.9.11-phase14.2-complete`
- **Files added:** `DispatchModels.swift`, `DispatchEngine.swift`, `DispatchEngineTests.swift`
- **Files modified:** `AppDataStore.swift`, `AssignmentCard.swift`, `AssignmentDetailView.swift`, `AssignmentEngine.swift`, `AssignmentEnums.swift`, `AssignmentScheduling.swift`, `AssignmentStore.swift`, `CrewEditor.swift`, `OperationsView.swift`, `TechnicianDailyAgendaView.swift`
- **Tests added/completed:** Automated coverage includes hybrid technician self-assignment, dispatcher-managed restrictions, durable dispatch history, Primary Technician reassignment with Supporting Technician preservation, Supporting Technician replacement with audit history, authorized office status override, technician-owned route reordering, emergency insertion planning/application, weekend recurring-work adjustment, time preservation, and recurrence-anchor preservation. Product-owner acceptance testing passed for dispatch, reassignment, crew editing, schedule visibility, My Day synchronization, calendar navigation, and recurring-work weekend behavior.
- **Decisions made during implementation:** `DispatchDecisionEngine` remains the advisory technician-ranking component; `DispatchEngine` is the execution boundary for human-approved dispatch decisions; `AssignmentEngine` remains the only Assignment mutation API and its history remains the durable audit trail; the default operating policy is Hybrid; no duplicate `DispatchStore` was introduced because `AssignmentStore` remains the single source of operational truth; emergency insertion returns ranked options but allows an authorized human override.
- **Known improvements:** Persist configurable Dispatch operating mode when the Business Operations UI is added; connect authenticated employee identity when application authentication is introduced; add the dedicated emergency-insertion UI during the Dispatch Board workstream; expand full-device automated execution during stabilization.

---

## Step 3 – Daily Planner Engine

### Objective

Automatically build a practical daily schedule from Assignment constraints and available technician capacity.

### Requirements

- Accept fixed-time, arrival-window, flexible-day, and deadline assignments.
- Respect technician availability and business hours.
- Respect estimated duration.
- Place hard commitments first.
- Detect open windows between hard commitments.
- Insert flexible assignments into valid open time.
- Include configurable travel and transition buffers.
- Account for breaks/lunch where represented by existing scheduling models.
- Detect insufficient capacity, overlap, and overtime risk.
- Return a proposed plan with reasons or warnings.
- Avoid silently changing committed customer constraints.

### Expected Components

- `DailyPlannerEngine`
- `DailyPlan`
- `DailyPlanItem`
- `PlanningWindow`
- `PlanningConflict`
- `PlanningRecommendation`
- Daily planner unit tests with representative mixed-mode days

### Outcome

PFSS can convert a collection of constrained and flexible Assignments into a coherent proposed technician workday.

### Completion Criteria

- Mixed fixed and flexible schedules are planned correctly.
- Arrival windows are honored.
- Flexible work fills valid gaps.
- Over-capacity days produce warnings instead of invalid plans.
- Output is deterministic for the same inputs unless an intentional heuristic changes.
- Tests pass and project builds.

### Engineering Record

- **Status:** Complete — implementation, automated tests, visual acceptance, and corrective retesting passed
- **Start date:** 2026-07-22
- **Completion date:** 2026-07-22
- **Closeout checkpoint:** This workbook's containing commit, tagged `v0.9.12-phase14.3-complete`
- **Files added:** `DailyPlannerModels.swift`, `DailyPlannerEngine.swift`, `AppDataStore+DailyPlanner.swift`, `DailyPlannerEngineTests.swift`, `DailyPlanPreviewView.swift`
- **Files modified:** `OperationsView.swift`
- **Tests added/completed:** The automated Daily Planner suite passed in Xcode and covers preservation of fixed commitments, flexible work filling the first valid gap, arrival-window placement, deadline completion, over-capacity work remaining unplaced, lunch movement around fixed work, configured transition buffers, and deterministic output. Product-owner visual acceptance passed through Operations → Daily Planner for plan generation, timeline presentation, open capacity, conflicts, planner decisions, non-mutating behavior, and use of the Job's manual scheduled-duration override.
- **Decisions made during implementation:** The Daily Planner returns immutable proposals and never silently changes committed Assignments or Jobs; fixed commitments are placed first, lunch is fitted around fixed work, constrained work is placed before flexible work, and unplaceable work is surfaced rather than overlapped; Assignment remains the owner of scheduling mode, constraints, buffers, crew, priority, and history; the related Job's effective duration is resolved through `SchedulingEngine.scheduledMinutes(for:)` so manual duration overrides and calculated labor remain consistent with My Day; geographic ordering, mileage, road travel time, and constraint-preserving route recalculation remain intentionally deferred to Step 4.
- **Known improvements:** Add road-network travel and ETA calculations during Step 4; add an explicit human-reviewed apply/commit workflow when planned proposals become operational schedules; expand regression coverage for inactive technicians, non-working days, Supporting Technician shared plans, daily reserve isolation, and proof that generating a proposal leaves persisted Assignment state unchanged.

---

## Step 4 – Route Engine Integration

### Objective

Connect the Daily Planner to the existing route optimization capabilities.

### Requirements

- Feed planned Assignment sequences into the existing Route Engine.
- Optimize travel without violating fixed starts, arrival windows, deadlines, or required duration.
- Recalculate estimated arrival and completion times.
- Preserve human route overrides.
- Recalculate after emergency insertion, reassignment, cancellation, or significant delay.
- Record planned route versus technician-adjusted route for later analytics.

### Outcome

PFSS produces efficient routes that remain operationally and contractually valid.

### Completion Criteria

- Route optimization accepts Daily Planner output.
- Schedule constraints remain valid after optimization.
- ETA values update correctly.
- Technician overrides remain possible.
- Replanning works after major operational changes.
- Integration tests pass and project builds.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 5 – Workforce Intelligence

### Objective

Expand employee records into operational profiles used by planning and dispatch.

### Requirements

- Represent skills and proficiency.
- Represent certifications and expiration where relevant.
- Represent equipment and vehicle access.
- Represent availability and current workload.
- Expose work history and operational metrics.
- Preserve compatibility with existing employee data.
- Avoid coupling employee profiles directly to one engine.

### Outcome

Scheduling and dispatch engines can evaluate whether a technician is capable, available, and appropriately equipped for an Assignment.

### Completion Criteria

- Operational profile data can be stored and retrieved.
- Existing employee workflows remain intact.
- Engines can query capability and availability cleanly.
- Missing optional intelligence data degrades gracefully.
- Tests pass and project builds.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 6 – Recommendation Engine

### Objective

Provide explainable operational recommendations while preserving human control.

### Requirements

- Recommend the best technician for an Assignment.
- Recommend emergency insertion technician and position.
- Consider skills, certifications, equipment, location, travel, workload, availability, crew, priority, and schedule.
- Surface warnings and tradeoffs.
- Return ranked options when appropriate.
- Never make irreversible operational changes without human acceptance.

### Outcome

PFSS provides useful, understandable decision support for dispatchers and technicians.

### Completion Criteria

- Recommendations are reproducible and explainable.
- Unqualified technicians are excluded or clearly warned.
- Ranked options include rationale.
- Acceptance or modification can be captured.
- Tests cover common and edge cases.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 7 – Dispatch Board UI

### Objective

Create the primary technician-centric operational workspace.

### Requirements

- Group Assignments by technician.
- Show route order and current Assignment.
- Show status, ETA, duration, workload, and relevant warnings.
- Support assignment and reassignment actions.
- Support crew management.
- Support route reordering where authorized.
- Support emergency insertion workflow.
- Provide access to technician detail, route, and Assignment detail.
- Keep UI synchronized with Timeline and Map views.

### Outcome

A dispatcher or authorized technician can manage the current field operation from one primary screen.

### Completion Criteria

- Technician columns/cards render correctly.
- Operational actions update shared state.
- Empty, loading, conflict, and error states are handled.
- Changes appear consistently in all synchronized views.
- UI tests/manual acceptance checks pass.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 8 – Timeline View

### Objective

Provide a time-based operational view of the day.

### Requirements

- Display technician schedules over time.
- Distinguish fixed time, arrival window, flexible day, and deadline work.
- Show travel, gaps, conflicts, and unused capacity.
- Support authorized schedule changes.
- Remain synchronized with Assignment and Dispatch state.

### Outcome

Users can understand the operational day chronologically and identify conflicts or opportunities quickly.

### Completion Criteria

- Timeline accurately represents planned and actual state.
- Constraint types are visually understandable.
- Edits respect permissions and scheduling rules.
- Updates synchronize across views.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 9 – Live Map View

### Objective

Provide geographic operational awareness.

### Requirements

- Show technician locations when permission and data are available.
- Show Assignment locations.
- Show route sequence and current destination.
- Show relevant status and ETA information.
- Support selection/navigation to technician and Assignment details.
- Handle stale, unavailable, or denied location data safely.
- Remain synchronized with Dispatch Board and Timeline.

### Outcome

Users can see where technicians and work are located and make better real-time dispatch decisions.

### Completion Criteria

- Map state matches shared operational state.
- Location permission and unavailable-data states are handled.
- Technician and Assignment selection works.
- Route and ETA data render correctly.
- Performance remains acceptable with realistic data volumes.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 10 – Field Operations

### Objective

Complete the technician-facing Assignment execution workflow.

### Requirements

- Receive and review assigned work.
- View schedule, route, customer, service, notes, and crew.
- Progress lifecycle states.
- Reorder route where authorized.
- Record arrival, work start, completion, and relevant notes.
- Support supporting-technician participation.
- Record labor per technician.
- Handle offline/intermittent connectivity according to existing app architecture.
- Hand completed work into Invoice Ready state.

### Outcome

Technicians can execute the full operational workflow from dispatch through completion.

### Completion Criteria

- End-to-end lifecycle works from Scheduled through Invoice Ready.
- Primary and Supporting Technician behavior is correct.
- Labor and timestamps are recorded.
- Route adjustments remain available.
- Error/offline recovery is safe.
- End-to-end tests and field acceptance checks pass.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 11 – Operational Analytics

### Objective

Capture the data required for future operational intelligence and reporting.

### Requirements

- Record planned versus actual start and completion.
- Record planned versus actual route order.
- Record route changes.
- Record assignment/reassignment history.
- Record technician labor and participation.
- Capture utilization, travel, delay, and productivity inputs.
- Preserve privacy and permission boundaries.
- Define stable metrics without tightly coupling analytics to UI.

### Outcome

PFSS gains a trustworthy operational dataset for future reporting, forecasting, and recommendation improvements.

### Completion Criteria

- Required events and metrics are captured consistently.
- Analytics collection does not block field workflows.
- Data definitions are documented.
- Privacy-sensitive data is handled deliberately.
- Tests confirm important events are recorded.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## Step 12 – Stabilization and Phase Completion

### Objective

Make Phase 14 stable, documented, maintainable, and ready to merge.

### Requirements

- Run full build and test suite.
- Test representative dispatcher-managed, self-managed, and hybrid workflows.
- Test all Scheduling Modes.
- Test mixed fixed and flexible daily planning.
- Test emergency insertion.
- Test reassignment and crew changes.
- Test lifecycle recovery and invalid transitions.
- Review performance of board, timeline, and map.
- Resolve blocking defects.
- Complete code cleanup and documentation.
- Update this workbook with final files, commits, lessons, and deferred work.
- Prepare merge/PR documentation.

### Outcome

Phase 14 is production-ready and can be merged without losing its engineering context.

### Completion Criteria

- All required workflows pass acceptance testing.
- No known blocking defect remains.
- Documentation matches implementation.
- Workbook checklist is complete.
- Final Phase 14 commit/PR is recorded.

### Engineering Record

- **Status:** Not started
- **Start date:**
- **Completion date:**
- **Commit(s):**
- **Files added:**
- **Files modified:**
- **Tests added/completed:**
- **Decisions made during implementation:**
- **Known improvements:**

---

## 10. Testing Strategy

Testing should be added throughout the phase, not deferred to Step 12.

Minimum test categories:

- Assignment model and persistence tests
- Lifecycle transition tests
- Scheduling constraint validation tests
- Daily Planner mixed-mode tests
- Conflict and insufficient-capacity tests
- Route integration tests
- Dispatch/reassignment tests
- Emergency insertion tests
- Permission tests
- Workforce matching tests
- Recommendation ranking tests
- Shared-state synchronization tests
- Field workflow end-to-end tests
- Regression tests for existing scheduling and routing behavior

Representative scenarios must include:

1. A day with one fixed assignment and two Flexible Day assignments.
2. Multiple fixed assignments with insufficient time for all flexible work.
3. An Arrival Window assignment between fixed commitments.
4. An emergency call inserted into an active route.
5. A technician changing the recommended route order.
6. Reassignment from one technician to another.
7. One Primary Technician with multiple Supporting Technicians.
8. Missing location or capability data.
9. A Job that is approved but not ready for scheduling.
10. Completion through Invoice Ready.

---

## 11. Git Workflow

- Development occurs on `feature/phase14-dispatch-field-intelligence`.
- Commit each completed implementation step separately when practical.
- Keep commit messages focused and descriptive.
- Do not mark a workbook step complete until its code is committed.
- Record every relevant commit hash in the corresponding Engineering Record.
- Update this workbook in the same step commit or an immediately following documentation commit.
- Keep the stable branch protected from incomplete Phase 14 work until stabilization is complete.
- Planned annotated checkpoint tag after Step 1 tests: `v0.9.9-phase14.1`.

Recommended commit pattern:

```text
feat(assignments): implement assignment domain and lifecycle
test(assignments): add assignment lifecycle coverage
docs(phase14): complete assignment engine record
```

---

## 12. Current Resume Point

### Current Status

Phase 14 Step 3 is complete and accepted. The deterministic, non-mutating Daily Planner handles fixed, arrival-window, flexible-day, and deadline Assignments; technician availability; lunch; operational buffers; open capacity; conflicts; unplaced work; and Job duration overrides. Automated tests and product-owner visual acceptance passed.

### Current Step

**Step 4 – Route Engine Integration**

### Next Action

Review the Step 4 requirements, the accepted `DailyPlan` proposal model, `DailyRouteOptimizer`, MapKit routing boundaries, Assignment scheduling constraints, and existing route summary behavior. Define the constraint-preserving route-integration contract before implementing mileage, road travel time, ETAs, and replanning.

### Known Branch State

- Stability Pass documentation was previously committed to `main`.
- Phase 14 work belongs on `feature/phase14-dispatch-field-intelligence`.
- Assignment implementation commit: `8ca08f8`.
- Published Phase 14.1 integration checkpoint: `942c7b5` / tag `v0.9.9-phase14.1`.
- Final tested Step 1 closeout will be published with tag `v0.9.10-phase14.1-complete`.
- Final tested Step 2 closeout will be published with tag `v0.9.11-phase14.2-complete`.
- Final tested Step 3 closeout will be published with tag `v0.9.12-phase14.3-complete`.
- The local branch was rebased onto remote documentation commits `8571b87` and `00541ed` before publication.
- This workbook is the source of truth for the remainder of the phase.

## 13. Deferred and Future Enhancements

The following are intentionally outside the initial Phase 14 scope unless implementation reveals they are required:

- Multiple Assignments per Job
- Advanced traffic-aware live routing
- Machine-learned technician matching
- Crew compatibility scoring
- Predictive duration estimates
- Predictive delay and cancellation risk
- Automated dispatch without human acceptance
- Advanced capacity forecasting across multiple days
- Customer live tracking links
- Sophisticated service territory balancing

These should remain visible so the V1 architecture does not block them.

---

## 14. Engineering Log

Add a dated entry whenever an important implementation decision, milestone, or deviation occurs.

### 2026-07-22 – Step 3 Daily Planner Engine implementation and acceptance

- Added immutable Daily Planner configuration, plan-item, planning-window, conflict, recommendation, and plan-result models.
- Added a deterministic `DailyPlannerEngine` that preserves fixed commitments, fits lunch around fixed work, places arrival-window and deadline work before flexible-day work, and returns excess work as unplaced rather than creating overlaps.
- Integrated technician working days, configured start/end times, lunch duration, Assignment pre/post buffers, Business Operations per-stop transition buffers, and daily route reserve.
- Added `AppDataStore` planning entry points for one technician or all active technicians without allowing the planner to mutate the Assignment Store.
- Added automated tests for fixed/flexible placement, arrival windows, deadlines, over-capacity handling, lunch movement, transition buffers, and deterministic output; the suite passed cleanly in Xcode.
- Added Operations → Daily Planner → Build Daily Plan as a visual acceptance surface with technician/date selection, proposal summary, timeline, scheduling-mode indicators, service-versus-occupied duration, buffer windows, open capacity, conflicts, unplaced work, and planner decisions.
- Corrected the Job/Assignment integration boundary so planning duration uses the same `SchedulingEngine.scheduledMinutes(for:)` calculation as My Day. A positive manual scheduled-duration override now takes precedence, while removing it returns planning to calculated labor duration.
- Replaced the initial optional technician `Picker` with a selection `Menu`, eliminating the invalid `nil` picker-selection runtime error when opening Build Daily Plan.
- Kept route geography, road travel time, mileage, live traffic, and ETA recalculation out of Step 3 so they enter through the dedicated Step 4 Route Engine Integration boundary.
- **Acceptance result:** Application build passed, automated tests passed, Daily Plan visual acceptance passed, the manual duration-override correction passed, and the planner remained non-mutating.
- **Status:** Complete and ready for the Phase 14.3 closeout commit and tag.

### 2026-07-22 – Step 2 Dispatch Engine implementation

- Added `DispatchModels.swift` with Dispatch operating modes, permission policy, actor identity, command types, command results, and emergency-insertion request/option/plan models.
- Added `DispatchEngine.swift` as the public execution boundary for assigning and reassigning Primary Technicians, managing Supporting Technicians, dispatching scheduled Assignments, and applying emergency insertion plans.
- Kept `DispatchDecisionEngine` advisory: it ranks technician options while an authorized dispatcher or technician makes the final selection.
- Kept `AssignmentStore` as the single operational source of truth and routed every mutation through `AssignmentEngine` so lifecycle validation and durable Assignment history remain centralized.
- Added Dispatcher Managed, Technician Self-Managed, and Hybrid permission policies; Hybrid remains the default agreed operating mode.
- Added audited dispatcher status override and technician-owned route reordering APIs so human operational decisions remain authoritative without bypassing Assignment history.
- Integrated the shared Dispatch Engine into `AppDataStore`, Operations assignment actions, Assignment Detail, and Crew Editor.
- Corrected Primary Technician reassignment so an existing Supporting Technician is preserved instead of blocking the operation.
- Added automated Dispatch tests covering permissions, ownership, durable history, crew-preserving reassignment, status override, route reordering, and emergency insertion.
- Completed clean Swift type-check validation for the application module and Dispatch test suite.
- Cleared Xcode concurrency warnings in Assignment Detail and Crew Editor by resolving the acting employee outside `Optional.map` before creating the `DispatchActor`; dispatch behavior is unchanged.
- Added scheduled date and time beneath the status on Active Assignment cards and between Status and Priority in Assignment Detail. Presentation is derived from the Assignment's Scheduling Mode, including fixed times, arrival windows, flexible days, and deadlines.
- Added visible Replace and Remove actions for the V1 Supporting Technician slot. Replacement is atomic, permission-checked, and recorded as a durable Assignment history event.
- Added Assignment-to-Job synchronization for Primary Technician, Supporting Technician, scheduled date, lifecycle status, workflow state, and completion date. Synchronization runs after Assignment mutations and at launch so dispatched work appears in the existing Job-backed My Day workflow.
- Made the displayed date beneath the My Day greeting interactive. Tapping it opens a graphical month calendar while retaining the previous/next-day and Return to Today controls.
- Added an automated regression test for Supporting Technician replacement and its audit-history entry.
- Corrected recurring scheduling at the Job-to-Assignment boundary: Saturday occurrences move to the preceding Friday and Sunday occurrences move to the following Monday while preserving the scheduled time.
- Recurrence dates are calculated from the original series anchor so a weekend adjustment does not cause monthly, quarterly, biannual, or annual schedules to drift in later occurrences.
- Existing unstarted recurring Assignments are rescheduled to the corrected business-day date during Job/Assignment synchronization, preventing a persisted weekend Assignment from restoring the obsolete date in Dispatch or My Day.
- Added recurrence regression coverage for Saturday-to-Friday, Sunday-to-Monday, time preservation, and monthly anchor preservation.
- **Acceptance corrections passed:** schedule visibility on cards/details; Supporting Technician replace/remove; dispatched Assignment visibility in My Day; graphical My Day date selection.
- **Acceptance result:** All Step 2 implementation and corrective retests passed, including newly generated and previously persisted recurring occurrences following the Saturday-to-Friday and Sunday-to-Monday business-day rule.
- **Status:** Complete and ready for the Phase 14.2 closeout commit and tag.

### 2026-07-20 – Phase 14 planning completed

- Confirmed Assignment as the operational object.
- Confirmed one Job to one Assignment for V1.
- Confirmed Primary Technician plus Supporting Technicians.
- Confirmed Assignment lifecycle.
- Confirmed hybrid dispatcher/technician authority.
- Confirmed technician route autonomy.
- Confirmed recommendation-based emergency insertion.
- Confirmed readiness gate before Assignment creation.
- Confirmed Scheduling Modes.
- Added Daily Planner as a dedicated engine between Scheduling and Routing.
- Confirmed technician-centric Dispatch Board with synchronized Timeline and Map views.
- Established this workbook as the living Phase 14 engineering record.

### 2026-07-21 – Assignment foundation and UI workflow cycle

- Added the Assignment model family, store, and AssignmentEngine Operations API.
- Added Assignment card, status badge, detail, and crew-editing interfaces.
- Added an overridable technician picker to the Dispatch Queue while preserving recommendation highlighting and conflict warnings.
- Added dedicated New Record screens for Customers, Leads, Sites, Jobs, and Estimates.
- Added upper-right contextual Save actions and removed duplicate nested-navigation back buttons.
- Added search to Customers, Leads, Sites, Jobs, Estimates, and Invoices.
- Changed Job and Estimate cards to lead with the customer name.
- Added Site name/address to Job and Estimate cards, search, and edit screens.
- Limited Job scheduling to quarter-hour increments.
- Added recurring-job frequencies and automatic one-occurrence-ahead dispatch scheduling.
- Confirmed the updated flows manually in Xcode.
- Deferred Step 1 completion and tag creation until automated unit tests pass.

### 2026-07-21 – Step 1 manual test findings and corrections

- **Finding:** Only Fixed Time was exposed through the current scheduling UI.
- **Correction:** Added `AssignmentSchedulingEditorView` with Fixed Time, Arrival Window, Flexible Day, and Deadline modes, mode-specific fields, duration, buffers, confirmation, notes, validation, and Operations API persistence.
- **Retest required:** Create and save each scheduling mode, reopen it, and confirm the selected constraints persist.
- **Finding:** The Assignment domain and Crew Editor allowed multiple Supporting Technicians even though the current V1 product limit is one.
- **Correction:** Added the one-Supporting-Technician rule to model validation, Assignment creation, AssignmentEngine mutations, errors, and Crew Editor availability.
- **Retest required:** Confirm one Supporting Technician succeeds and a second is prevented until the first is removed.
- **Finding:** Opening a technician Job from My Day produced `Invalid frame dimension (negative or non-finite)` during navigation.
- **Likely cause:** `QuarterHourDatePicker` normalized and mutated its bound date during `.onAppear`, while SwiftUI was performing the Job Detail navigation animation.
- **Correction:** Removed navigation-time state mutation. Quarter-hour normalization now occurs during Job creation/save, outside the navigation layout pass.
- **Retest required:** Launch PFSS, open My Day, tap multiple Jobs from Today's Schedule, return, and repeat while monitoring the console.

### 2026-07-21 – Assignment domain connected to live Operations

- **Finding:** Assignment models, store, engine, and UI compiled but were not owned by `AppDataStore`, persisted, migrated from existing Jobs, or reachable through app navigation.
- **Correction:** `AppDataStore` now owns the shared `AssignmentStore` and `AssignmentEngine` used throughout live Operations.
- Added backward-compatible Assignment persistence to the existing application data snapshot.
- Added one-time/idempotent migration that creates one active Assignment for each eligible legacy or newly created Job.
- Changed the Dispatch Queue source from job-only ownership checks to the Assignment store's unassigned operational records.
- Dispatch selection now flows through `AssignmentEngine` before mirroring technician ownership and recommended start time to the related Job.
- Added an Active Assignments section to Operations and wired both its cards and Dispatch Queue Details actions to `AssignmentDetailView`.
- Connected My Day workflow milestones—dispatch/travel, arrival, work completion, invoice readiness, and closure—to the corresponding Assignment lifecycle commands.
- **Retest required:** Verify migration creates no duplicates across relaunches, Assignment edits persist, dispatch remains synchronized with Jobs, and My Day actions advance Assignment history/status.

### 2026-07-21 – Assignment visual identification and priority editing

- Updated Active Assignment cards to lead with the resolved customer name in bold rather than the internal customer number.
- Added the resolved site name directly beneath the customer name.
- Retained Job and Assignment numbers as smaller diagnostic identifiers during Phase 14 testing.
- Added a compact customer/site header to Assignment Detail, including the site address when available, and reduced the initial List content spacing.
- Added an always-visible Priority picker to Assignment Detail for Low, Normal, High, and Emergency.
- Priority changes flow through `AssignmentEngine.updatePriority`, persist through `AssignmentStore`, and create Assignment history events.
- **Retest required:** Confirm customer/site resolution, compact detail layout, priority persistence, and priority history entries.
- **Layout correction:** The reusable capsule badge stretched vertically inside a large-text List row on iOS. Assignment Detail now uses a compact colored icon-and-text status row; capsule badges remain on cards where they render correctly.
- Stacked the Job number and ASN vertically in the customer/site header using matching secondary typography, and removed the duplicate ASN row from Overview.
- Simplified Assignment Detail's Overview section to operational state only: Status and editable Priority. Job, customer number, and route-stop identifiers are no longer repeated there.
- Simplified Operations Active Assignment cards to customer name, site name, status, primary technician, and the supporting-technician count indicator. Removed Job/ASN identifiers, scheduling mode, route stop, and the extra divider from this summary card.

### 2026-07-22 – Customer and site workflow refinement

- Simplified the New Job customer picker to display customer names without internal customer numbers.
- Simplified the New Estimate customer and lead pickers to display names without customer or lead identifiers.
- Moved the standalone Sites directory from the primary More menu into Admin → Reports.
- Added an associated Sites section to Customer Detail with direct site navigation and an inline Add Site action.
- Changed New Customer save behavior to immediately continue into New Site creation with the new customer preselected.
- After the initial site is saved—or the site step is canceled—the workflow now lands on Customer Detail so additional sites can be added without leaving the customer workflow.
- Changed Site Detail and the administrative Sites directory to resolve and display the customer name instead of the internal customer number.
- Replaced free-form property type entry during New Site creation with built-in choices for Retail, Restaurant, Office, Home, Warehouse, and Gas Station.
- Added a New Property Type choice that accepts a custom value; custom values are retained through saved sites and automatically become available in future property-type pickers.
- Replaced Site Detail's context-dependent Job navigation destination with a self-contained Job Detail sheet, eliminating the misplaced `navigationDestination` runtime warning when a site is opened from either Customer Detail or Admin Sites.
- **Retest result:** Customer/site creation, additional-site creation, customer-name resolution, built-in/custom property types, name-only Job/Estimate pickers, and both Site Detail entry paths passed acceptance testing.

### 2026-07-22 – Step 1 accepted and closed

- Completed the full Phase 14 Step 1 acceptance-test cycle.
- Confirmed Assignment creation, persistence, lifecycle status, history, priorities, all four Scheduling Modes, V1 crew limits, dispatch overrides, recurring-work behavior, and live Operations/My Day synchronization.
- Confirmed the corrected Job, Estimate, Customer, and Site workflows operate as designed.
- Confirmed the Site Detail navigation warning is resolved from both Customer Detail and Admin Sites.
- Confirmed no known blocking Step 1 defects remain.
- Marked Step 1 complete and moved the authoritative resume point to Step 2 – Dispatch Engine.
- Selected `v0.9.10-phase14.1-complete` as the immutable final Step 1 checkpoint tag; the earlier `v0.9.9-phase14.1` integration tag remains unchanged.

---

## 15. Lessons Learned

This section is intentionally maintained throughout implementation.

- Planning the operational domain before coding reduces cross-engine coupling.
- Scheduling constraints are more expressive than a simple appointment model.
- Daily planning and route optimization are related but distinct responsibilities.
- Field-service software must support real-world judgment rather than enforce fragile theoretical optimization.

---

## 16. Workbook Maintenance Rules

When updating this document:

- Preserve completed records.
- Do not delete architectural decisions; supersede them with a dated note if they change.
- Record why a decision changed.
- Keep the Current Resume Point accurate.
- Check off a step only when its completion criteria are met.
- Add commit hashes immediately after completing work.
- Record deferred items rather than silently dropping them.
- Keep this workbook useful to a developer who has not read the original planning conversation.
