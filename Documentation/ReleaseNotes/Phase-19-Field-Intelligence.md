# Phase 19 Release Notes

## Field Intelligence, Workforce Response, and Financial Integrity

**Accepted build:** 19.9.1
**Closed:** 2026-08-14

Phase 19 expands PFSS's daily field value while strengthening the exact
operational and financial facts shared across company devices.

### Delivered

- Automatic, opt-in mileage tracking with battery-aware trip detection,
  Personal/Business review, manual trips, correction, history, reporting, CSV
  export, and private same-user device backup.
- Technician Job decline with a server-backed Manager/Owner review inbox,
  shared alerts, audited resolution, tenant isolation, and offline retry.
- Consistent Closed Job and time-detail presentation, authorized timeline
  correction, invoice access, Held Jobs, and recurring-series hold/release.
- Fractional catalog labor time and durable catalog tax classification.
- Verified company tax settings with deterministic decimal Tax and Invoice
  engines and immutable calculation evidence.
- Durable, idempotent receipt snapshots tied to accepted payment events and
  thermal receipt output.

### Validation

- 246 iOS unit tests passed with no failures or skips.
- 64 Cloudflare Worker tests passed with no failures or skips.
- Signed iPhone and iPad field acceptance covered mileage, workforce review,
  Job lifecycle, tax, invoices, receipts, offline recovery, and device sync.

### Next

Phase 20 replaces broad whole-record conflict handling with a server-
authoritative, versioned, field-aware synchronization architecture. App Store
deployment remains scheduled for Phase 25.
