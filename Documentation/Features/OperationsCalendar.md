# PFSS Operations Calendar

- Status: Approved for Phase 18
- Owner: PFSS Project
- Last Updated: 2026-08-07

## User Goal

Managers, Salespeople, and Technicians see the next one, three, or five days of
authorized work in a schedule that matches their responsibilities.

## Role Experience

### Owner and Manager

- Select Sales activity, Technician activity, or both.
- Select one, multiple, or all authorized team members.
- See follow-ups, assignments, conflicts, and operational availability.
- Open underlying records and reschedule through approved workflows.

### Sales

- See scheduled Lead follow-ups and approved sales activity.
- Open the underlying Lead and return to the refreshed calendar.
- See team activity only when broader authority is explicitly granted.

### Technician

- Automatically see Jobs assigned to the device-linked employee.
- Do not receive an employee picker that permits another identity.
- Open the Job or approved assignment workflow and return to the calendar.

## Shared Behavior

- Switch between 1, 3, and 5 consecutive days.
- Navigate dates and reliably return to Today.
- Distinguish activity types and conflicts without color alone.
- Use the company operational time zone.
- Show accurate loading, empty, stale/offline, partial, and sync-error states.
- Refresh after edits without requiring the app to restart.

## Completion Criteria

- Role, time-zone, range, filter, performance, navigation, and sync tests pass.
- Every schedule mutation uses `SchedulingEngine` validation.
- Signed iPhone and iPad acceptance passes for Manager, Sales, and Technician
  identities.

## Related Documents

- `../Architecture/OperationsCalendar.md`
- `../Architecture/SchedulingEngine.md`
- `Scheduling.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
