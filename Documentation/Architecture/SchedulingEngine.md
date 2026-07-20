# PFSS Scheduling Engine Architecture

- Status: Proposed for Brick 11
- Owner: PFSS Project
- Applies To: v0.9.8+
- Last Updated: 2026-07-18

## Responsibility

The Scheduling Engine evaluates time, availability, assignments, and capacity. It does not own SwiftUI presentation, persistence, route optimization, or automatic dispatch.

## Architectural Boundary

```text
SwiftUI Scheduling Screens
          ↓ input / intent
Scheduling Engine
          ↓ deterministic results
Jobs + Employees + Availability
```

Views provide inputs and display results. The engine returns values and explanations without mutating application state.

## Proposed Types

### SchedulingInterval

Represents a half-open interval `[start, end)`. Two intervals that touch at a boundary do not overlap.

### SchedulingAssignment

A normalized engine input containing job ID, technician IDs, start, end, status, and any blocking classification required by the engine.

### TechnicianAvailability

Represents working intervals and explicit unavailability for one technician on one date.

### SchedulingConflict

A structured result with a stable conflict type, affected job or technician identifiers, and a user-presentable explanation.

### SchedulingEvaluation

Contains validity, normalized interval, conflicts, warnings, and calculated capacity effects.

### SchedulingCandidate

Represents a non-mutating suggested opening with start, end, technician IDs, and any explanatory score or reason.

## Initial Engine API Direction

The exact Swift signatures may evolve during implementation, but responsibilities should remain equivalent:

```swift
protocol SchedulingEvaluating {
    func evaluate(
        request: SchedulingRequest,
        assignments: [SchedulingAssignment],
        availability: [TechnicianAvailability]
    ) -> SchedulingEvaluation

    func capacity(
        for technicianID: UUID,
        on date: Date,
        assignments: [SchedulingAssignment],
        availability: TechnicianAvailability
    ) -> DailyCapacity

    func candidates(
        for request: SchedulingCandidateRequest,
        assignments: [SchedulingAssignment],
        availability: [TechnicianAvailability]
    ) -> [SchedulingCandidate]
}
```

## Rules

- Use half-open intervals to avoid false conflicts between adjacent jobs.
- Normalize all scheduling calculations through `Calendar` and the selected time zone.
- Require positive estimated duration.
- Require every assigned technician to be available for the full interval.
- Return all relevant conflicts rather than stopping at the first one.
- Do not read global application state directly.
- Do not mutate jobs or employees.
- Keep status-to-blocking behavior centralized and testable.

## Persistence Boundary

Jobs and employee schedules remain durable application data. Engine-specific request and result types may be value types created from those models. The engine should not require persistence protocols in its first implementation.

## Testing Strategy

Unit tests should cover:

- Exact overlap
- Partial overlap
- Containment
- Adjacent intervals
- Workday start and end boundaries
- Jobs extending beyond availability
- Multiple technicians with mixed availability
- Archived or inactive employees
- Capacity with no jobs, one job, and multiple jobs
- Candidate generation across occupied intervals
- Daylight-saving and calendar-boundary behavior where applicable

## Future Extensions

- Recurring schedule templates and generated occurrences
- Travel-time buffers
- Route-aware candidate scoring
- Technician skill and equipment constraints
- Weather and bulk rescheduling
- Dispatch optimization
- Multi-user synchronization conflict handling

## Related Documents

- `../Features/Scheduling.md`
- `../Decisions/ADR-002-Scheduling-Source-of-Truth.md`
- `../Standards/ProjectConstitution.md`
- `AppArchitecture.md`
