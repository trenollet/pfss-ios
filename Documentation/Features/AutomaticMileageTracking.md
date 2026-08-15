# PFSS Automatic Mileage Tracking

- Status: In Progress — Phase 19
- Owner: PFSS Project
- Last Updated: 2026-08-09

## User Goal

PFSS detects a likely drive without manual timer entry, records the route and
distance, and places the completed trip in a simple queue for Personal or
Business classification.

## Primary Workflow

1. The user opts in and grants foreground, Always Location, and notification
   permissions through an explained sequence.
2. PFSS monitors at low power while idle.
3. Sustained movement beyond 100 feet at 10 mph or faster starts a trip.
4. PFSS notifies the user and records reliable route points.
5. Three minutes without meaningful movement ends the trip unless driving
   resumes.
6. PFSS notifies the user and adds one unclassified trip to **To Review**.
7. The user selects **P**, **B**, or opens the route for detailed review.
8. Classified trips move to history and become available for CSV reporting.

## Required Surfaces

- Mileage status and permission controls in Settings.
- Persistent mileage workspace navigation for To Review, Trip History, Add Trip,
  and Reports.
- Newest-first unclassified queue with one-tap P/B classification and undo.
- Route map and trip-detail editor.
- Manual entry with explicit manual labeling.
- Date-range CSV report with Business, Personal, and All filters.

## Safety and Failure Behavior

- GPS spikes, poor accuracy, walking, and stale points do not create trips.
- Traffic stops do not split a drive.
- Offline drives persist and synchronize later.
- Permission loss and force-quit limitations receive clear status messaging.
- Personal-route access remains private to the user under the approved policy.
- Complete routes restore only to another device enrolled to the same user.
- Manager/Owner business summaries contain only trip ID, member ID, date,
  distance, and business purpose—never Personal trips or route geometry.

## Acceptance

The feature is not complete until signed-device driving tests verify start,
stop, route, mileage, battery use, notifications, locked/background behavior,
offline recovery, restart recovery, classification, privacy, and export.
