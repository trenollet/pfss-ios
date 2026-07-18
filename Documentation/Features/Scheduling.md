# PFSS Scheduling

- Status: Proposed for Brick 11
- Owner: PFSS Project
- Applies To: v0.9.8+
- Last Updated: 2026-07-18

## Purpose

Scheduling turns jobs, employee availability, estimated duration, and operational constraints into a clear, editable field-service plan.

## Brick 11 Goal

Establish a reusable Scheduling Engine and a dependable scheduling workflow without attempting full dispatch automation, recurring-work generation, or route optimization in the first brick.

## Primary Users

- Office staff creating and changing the schedule
- Owners reviewing workload and capacity
- Technicians viewing assigned work

## Core Inputs

- Job identifier and status
- Scheduled date and start time
- Estimated duration
- Primary and secondary technician assignments
- Employee working days and available hours
- Existing assignments
- Job site and customer identity

## Core Outputs

- Valid scheduled time range
- Technician availability result
- Conflict list with explainable reasons
- Daily workload and remaining capacity
- Candidate time slots for a selected job and technician set

## Required Brick 11 Capabilities

### Schedule Validation

The engine must detect:

- Missing or invalid duration
- Start times outside an assigned technician's working schedule
- Overlapping job assignments
- Duplicate technician assignment on the same job
- Assignments to archived or unavailable employees
- Jobs that extend beyond available working time

### Explainable Results

Validation must return structured reasons suitable for both UI messages and diagnostics. The UI must not recreate scheduling rules independently.

### Capacity

The engine calculates scheduled minutes, available minutes, and remaining minutes for each employee and selected day.

### Candidate Openings

Given a job duration, date range, and selected technicians, the engine can produce valid openings that satisfy working hours and existing assignments.

### Manual Control

Users remain in control. Brick 11 may recommend openings but must not silently move, assign, or reschedule jobs.

## Scheduling Rules

- Job duration is required for reliable scheduling.
- All technicians assigned to a job must be available for the entire scheduled interval.
- Existing active assignments block overlapping time.
- Completed, cancelled, or archived jobs should not block future capacity unless their stored state explicitly represents active scheduled work.
- The engine uses durable identifiers rather than employee display names.
- Date calculations must use Calendar APIs and explicit time-zone assumptions rather than fixed-second arithmetic for day boundaries.

## Out of Scope for Brick 11

- Automatic route optimization
- Weather-driven bulk rescheduling
- Recurring schedule templates and occurrence generation
- Travel-time prediction
- Automatic technician selection
- Cloud multi-user conflict resolution
- Payroll and advanced labor-time reporting

## Acceptance Criteria

- Scheduling decisions are performed by a reusable engine outside SwiftUI views.
- Conflicts are deterministic and explainable.
- Existing employee and job data continue to load.
- A job can be evaluated against one or more technicians and an estimated duration.
- Daily capacity can be calculated without UI-specific dependencies.
- Candidate openings can be generated without mutating stored jobs.
- Unit tests cover overlap boundaries, working-hour boundaries, multi-technician availability, and capacity totals.

## Related Documents

- `../Architecture/SchedulingEngine.md`
- `../Decisions/ADR-002-Scheduling-Source-of-Truth.md`
- `../Standards/ProjectConstitution.md`
- `../Product/Roadmap.md`
- `../Product/ParkingLot.md`
