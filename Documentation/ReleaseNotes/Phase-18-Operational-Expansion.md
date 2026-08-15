# Phase 18 — Operational Expansion and Field Productivity

- Status: Completed
- Accepted build: 18.7.8
- Completed: 2026-08-08

## What Changed

- Standardized navigation, editing, keyboard dismissal, save protection,
  destructive actions, and operational list sorting across iPhone and iPad.
- Added a field pricing calculator with adjustable Weekly, Bi-Weekly, and
  Monthly percentages.
- Added GPS and map-assisted address entry with standard and satellite maps.
- Added role-aware 1, 3, and 5-day calendars for Sales follow-ups and
  Technician jobs.
- Added recurring-work creation and management, including series edits,
  skip-and-remove, skip-and-add, pause, resume, and stop behavior.
- Added customer-filtered Jobs and Invoices histories.
- Hardened fresh-device bootstrap, manual synchronization retry, and
  collision-safe offline record numbering.

## Field Acceptance

The accepted signed build was installed and exercised on the active iPhone and
iPad test fleet. Final field regression covered connected and disconnected
record creation, reconnection, fresh-device synchronization, recurring work,
calendar views, customer conversion, and core Sales and Service workflows.

## Automated Verification

- iOS application unit regression: 207 passed, 0 failed, 0 skipped.
- Cloudflare Worker regression: 57 passed, 0 failed.
- Repository whitespace and staged-content checks: passed.

## Notes

App Store naming, subscription-product activation, TestFlight, public listing,
and production launch remain assigned to Phase 25.
