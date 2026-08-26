# Phase 20 Release Notes

## Multi-Device Synchronization Architecture

**Accepted build:** 20.7.29

**Closed:** 2026-08-26

Phase 20 makes the PFSS server authoritative for shared company data while
keeping field work usable through temporary loss of connectivity. Routine
independent changes now merge automatically, consequential same-field changes
reach a focused Manager/Owner review, and one bad operation cannot hold up
unrelated work.

### Delivered

- Versioned synchronization mutations with server revisions, tenant ordering,
  domain commands, and an executable client/server policy contract.
- Dependency-aware upload processing, stale-device pull/rebase, duplicate
  replay protection, and poison-operation quarantine.
- Server-backed Manager/Owner conflict and quarantine review with focused
  comparisons, plain-language explanations, authorization, audit history,
  repair/retry, supersede, and discard.
- Guarded Clear Local Database recovery, fresh-device bootstrap, migration
  safety, and protection against republishing an empty or partial snapshot.
- Signal-only APNs wakeups backed by authoritative cursor pulls and periodic
  launch/foreground reconciliation.
- Consent-based, redacted synchronization diagnostics and tenant-scoped support
  cases without customer or job payloads.
- Owner/Manager synchronization health, durable alerts, automatic recovery
  clearing, and a Dashboard banner linking directly to corrective guidance.
- Field hardening for recurring work, assignment rescheduling, role changes,
  map-assisted addresses, single-occurrence job moves, test-notification
  containment, and safe post-creation invoice correction.

### Financial Correction Safety

Completed invoices can be opened directly from their My Day job card. Service
and labor lines can be added, edited, or removed. Saving recalculates the
invoice while preserving immutable receipt and payment evidence. A higher
corrected total produces a remaining balance instead of inventing a payment;
an overpayment remains visible rather than being silently erased.

### Validation

- 291 iOS unit tests passed with no failures or skips.
- 83 Cloudflare Worker regressions passed.
- The fresh-D1 migration-safety suite passed.
- TypeScript validation and the signed iOS build passed.
- Signed Owner, Manager, Sales, and Technician testing passed across the active
  iPhone and iPad fleet. Salesperson-only acceptance proved role propagation,
  removal of Manager/Admin authority, authenticated Sales Calendar identity,
  and lead-assignment eligibility without sign-out or re-enrollment.

### Deployment

- Signed app build 20.7.29 is installed on Tim-iPhone17pro.
- Staging Worker version `b2c82300-6ebd-4872-aec1-b81c8062511b` is deployed.
- App Store production deployment remains reserved for Phase 25.
