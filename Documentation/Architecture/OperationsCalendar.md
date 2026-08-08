# PFSS Operations Calendar Architecture

- Status: Approved for Phase 18
- Owner: PFSS Project
- Applies To: Phase 18+
- Last Updated: 2026-08-07

## Responsibility

The Operations Calendar composes authorized Lead follow-ups, Job assignments,
availability, conflicts, and operational context into 1, 3, or 5-day views. It
does not own scheduling rules or grant role authority.

## Boundary

```text
Calendar SwiftUI Views
          ↓ display request
OperationsCalendarComposer
          ↓ role-filtered sections
Durable Records + Server Authority + SchedulingEngine
```

## Core Concepts

- `CalendarRange`: selected start date plus a 1, 3, or 5-day span.
- `CalendarAudience`: authenticated role, linked employee, and authorized team
  scope.
- `CalendarActivity`: normalized Lead follow-up, Job assignment, buffer,
  availability, or conflict presentation value.
- `CalendarFilter`: Sales, Technician, or combined discipline plus authorized
  team-member selection.
- `CalendarSnapshot`: ordered day and person sections with freshness state.

## Authorization Rules

- Owners and Managers may request authorized team scopes and discipline filters.
- Sales users see their approved sales activity unless broader authority is
  explicitly granted by the server.
- Technician users are locked to the employee linked to their device and see
  only approved assigned work.
- Display-name matching never grants access or establishes identity.

## Scheduling Rules

The composer maps records into `SchedulingEngine` inputs and displays its
conflicts, capacity, and availability results. Calendar views and drag/edit
workflows may not calculate overlap independently. All time operations use the
company operational time zone and Calendar APIs.

## State and Synchronization

Selected range and filters are presentation preferences. Business activities
remain in their owning Lead, Job, Assignment, and availability records. Opening
and saving an underlying record returns to a refreshed snapshot. Offline
snapshots must disclose stale or partial state rather than presenting it as
current cloud truth.

## Testing

Cover role isolation, employee linking, 1/3/5-day boundaries, time zones,
daylight saving, filters, empty days, large teams, conflicts, offline data,
freshness, record navigation, and refresh after save.

## Related Documents

- `SchedulingEngine.md`
- `../Features/OperationsCalendar.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
