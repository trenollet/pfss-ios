# ADR-002: Scheduling Source of Truth

- Status: Accepted
- Date: 2026-07-18
- Last Reviewed: 2026-07-18

## Context

PFSS already stores jobs, employee assignments, employee work schedules, and estimated job duration. Scheduling behavior will grow to include conflict detection, capacity, candidate openings, recurring work, dispatch, route planning, and bulk rescheduling.

Without a clear ownership rule, individual views could calculate availability differently, duplicate overlap logic, or mutate jobs while merely evaluating possible schedules.

## Decision

Durable job and employee records remain the source data. A reusable Scheduling Engine is the single source of scheduling decisions derived from that data.

The engine will:

- Accept normalized job assignments, employee availability, duration, and date constraints.
- Evaluate conflicts and capacity deterministically.
- Return structured, explainable results.
- Generate non-mutating candidate openings.
- Avoid SwiftUI, global stores, and persistence side effects.

Views will:

- Collect scheduling intent.
- Convert durable models into engine inputs.
- Display engine results and explanations.
- Mutate stored jobs only after an explicit user action confirms a schedule.

## Consequences

### Positive

- One consistent definition of overlap and availability.
- Scheduling logic can be unit tested independently of UI.
- Candidate generation cannot silently alter stored work.
- Future dispatch, route, recurring-work, and rescheduling features share the same foundation.
- Conflict explanations can be reused across office and technician experiences.

### Tradeoffs

- Model-to-engine normalization introduces additional value types.
- Views cannot take shortcuts by calculating schedule validity locally.
- Status and availability rules must be deliberately centralized and maintained.

## Interval Rule

Scheduling intervals are half-open: `[start, end)`. A job ending at 10:00 and another beginning at 10:00 are adjacent, not overlapping.

## Related Documents

- `../Features/Scheduling.md`
- `../Architecture/SchedulingEngine.md`
- `../Standards/ProjectConstitution.md`
