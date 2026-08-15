# PFSS Phase 19 Project Workbook

## Field Intelligence, Workforce Response, and Financial Integrity

**Status:** Completed — 2026-08-14

**Created:** 2026-08-08

## Phase Objective

Build on Phase 18's field-productivity foundation with automatic mileage
capture, operational exception handling, job-lifecycle clarity, and durable
financial engines. Phase 20 is reserved for the multi-device synchronization
redesign, while App Store deployment and production release remain assigned to
Phase 25 so Phase 19 can stay focused on daily field value.

## Phase Theme

**Field Intelligence, Workforce Response, and Financial Integrity**

Phase 19 should capture useful field activity without burdensome manual entry,
make workforce exceptions visible and actionable, and preserve the exact
business facts used for estimates, invoices, payments, and receipts.

## Planning Rules

- Operational value in daily field use remains the primary priority.
- Business decisions belong in reusable engines or server services; SwiftUI
  views present and edit results.
- Sensitive location collection must be opt-in, visible, battery-aware,
  purpose-limited, and protected by role and privacy boundaries.
- Shared alerts and collaborative decisions must be server-backed,
  tenant-scoped, authorized, audited, and synchronized to affected devices.
- Financial records must use decimal money, durable snapshots, deterministic
  calculations, and explicit correction history.
- Every step must define offline behavior, migration compatibility, role
  authority, iPhone/iPad acceptance, and automated regression coverage.
- Phase 19 must close with full regression, documentation, and GitHub alignment.

## Proposed Delivery Order

1. Roadmap, architecture, privacy, and acceptance-plan alignment.
2. Automatic Mileage Tracking and Trip Review.
3. Technician Job Decline and Manager/Owner Review.
4. Job lifecycle and time-detail clarity.
5. Catalog tax classification.
6. Tax Engine.
7. Invoice Engine.
8. Receipt Engine.
9. Regression testing, documentation, and closeout.

The product owner approved the complete Phase 19 delivery order. All nine steps
are implemented and accepted; Phase 20 now owns the synchronization redesign.

## Step 1 — Roadmap and Architecture Alignment

### Goal

Convert the approved Phase 19 scope into durable feature, privacy, data,
permission, synchronization, and test contracts before implementation begins.

### Requirements

- Reconcile the roadmap, parking lot, architecture, feature specifications, and
  UI standards with the completed Phase 18 system.
- Define record ownership, permissions, synchronization, offline behavior,
  audit history, migration, and rollback for every approved capability.
- Define a transparent location-consent and retention policy before collecting
  trip data.
- Preserve `SchedulingEngine` as the scheduling authority and establish
  dedicated engines for mileage, tax, invoices, and receipts.
- Create the automated and signed-device regression matrices before coding.

### Step 1 Progress — 2026-08-09

- [x] Added the mileage subsystem architecture and feature contract.
- [x] Kept foreground address/location services separate from background mileage.
- [x] Defined durable trip, point, accuracy, classification, source, context, and
  versioned detection-configuration models.
- [x] Added the pure Idle → Arming → Tracking → Stopping detection engine.
- [x] Added initial sustained-start, walking, GPS-spike, stop-dwell, brief-stop,
  and poor-accuracy tests.
- [x] Confirmed the complete application target builds for the iOS Simulator
  with the Phase 19 Step 1 foundation included.
- [x] Passed all six mileage-engine tests, including sustained start, walking,
  GPS-spike rejection, poor accuracy, three-minute stop, and brief-stop resume.
- [x] Approved personal-trip visibility and retention boundaries.
- [x] Completed the persistence, synchronization, and signed-device acceptance
  matrices before enabling background collection.

## Step 2 — Automatic Mileage Tracking and Trip Review

### Goal

Automatically detect and measure likely vehicle trips, then let the user
classify each trip as Business or Personal with minimal effort.

### 2.1 Permission, Consent, and Visibility

- Explain why PFSS needs location access before the system permission request.
- Request foreground location first, then request **Always** location only when
  the user enables Automatic Mileage Tracking.
- Enable the iOS Location Updates background mode only for this feature.
- Request notification permission separately for trip-start and trip-end
  notices.
- Provide a Settings control to enable or disable automatic tracking and show
  the current permission and tracking state.
- Always show a visible in-app state for **Monitoring**, **Tracking**,
  **Paused**, **Location Unavailable**, and **Permission Required**.
- Explain that force-quitting PFSS or disabling Location Services can prevent
  automatic detection until the app is reopened.

### 2.2 Battery-Aware Trip Detection

- Do not run continuous high-accuracy GPS while idle.
- Use a low-power combination of Core Location monitoring and motion/activity
  evidence to detect a probable vehicle trip.
- Establish a stable location anchor while idle.
- Arm a trip after displacement exceeds 100 feet (30.48 meters).
- Start a trip only after valid speed reaches at least 10 mph (4.47 m/s) for
  multiple reliable samples; reject stale, inaccurate, invalid, or implausible
  GPS samples.
- On confirmation, switch to route-quality location updates, timestamp the
  start, preserve the start coordinate, and issue a local notification that
  mileage tracking began.
- Make thresholds engine configuration values so field testing can tune them
  without rewriting the UI.

### 2.3 Trip Completion

- Enter a stopping-candidate state when valid speed falls below the driving
  threshold and meaningful displacement ceases.
- End the trip after three continuous minutes without meaningful movement.
- Cancel the stopping candidate if driving resumes during that window.
- Timestamp the finish using the last reliable movement and preserve the final
  coordinate and route.
- Trim the completed route back to the last confirmed driving-speed point so
  walking during the three-minute stop-confirmation window does not inflate
  mileage or extend the displayed route.
- Calculate actual driven distance from accepted route segments rather than
  straight-line distance.
- Reject GPS jumps and avoid adding poor-accuracy segments to mileage.
- Issue a local notification that the trip is ready to classify.

### 2.4 Durable Trip Model

Each trip must preserve:

- stable trip ID, account ID, user ID, and originating device ID;
- automatic or manual origin;
- started and ended timestamps with time-zone context;
- start and end coordinates and resolved display addresses when available;
- accepted route points or an equivalently durable encoded route;
- calculated distance and unit;
- classification: **Unclassified**, **Business**, or **Personal**;
- optional business purpose and user note;
- created, classified, edited, and exported timestamps;
- detection version, threshold version, and accuracy summary.

Incomplete active trips must survive app suspension, device restart, temporary
loss of service, and offline operation without creating duplicate trips.

### 2.5 Trip Review Queue

- Add a Mileage destination appropriate to the user's role and device.
- Default to an **Unclassified Trips** queue sorted newest first.
- Each row shows date, start time, end time, distance, start/end summary, and
  one-tap circular **P** and **B** controls.
- Selecting **P** classifies the trip Personal; selecting **B** classifies it
  Business; either action removes it from the unclassified queue.
- Selecting the trip opens a map with the driven route, full trip facts,
  classification controls, business purpose, note, and edit actions.
- Classification must be reversible from trip history with correction history.
- Provide an undo opportunity after one-tap classification to prevent accidental
  removal from the queue.

### 2.6 Mileage Workspace Navigation

A persistent mileage navigation control provides:

- **To Review** — unclassified trips;
- **Trip History** — classified trips with search, date, and classification
  filters;
- **Add Trip** — manual entry for start/end date and time, distance, category,
  purpose, and note; and
- **Reports** — date-range export.

Manual entries must be visibly identified and must not invent a GPS route.

### 2.7 Reporting and Export

- Provide inclusive start/end date selectors.
- Allow **Business**, **Personal**, or **All** classifications; default reports
  to Business.
- Generate a standards-compliant CSV locally and present the system share sheet
  for save, email, AirDrop, or another authorized destination.
- Include trip date, start/end times, start/end locations, classification,
  business purpose, distance, entry source, and notes.
- Include report totals by classification and the selected distance unit.
- Personal route details remain visible only to the user by default; company
  administrators must not gain silent access to personal movement history.

### 2.8 Accuracy, Privacy, and Failure Acceptance

- No trip starts from one isolated GPS spike.
- Walking around a property does not create a vehicle trip.
- Brief traffic stops do not split one drive into multiple trips.
- A trip ending normally appears once in the review queue.
- Tracking works offline and synchronizes safely after reconnecting.
- Denied, reduced-accuracy, disabled, or revoked location permission produces a
  clear non-destructive state.
- Battery use is measured during realistic idle and driving tests.
- Users can inspect, correct, export, and delete their mileage records under the
  approved retention policy.
- iPhone testing covers foreground, background, locked-screen, intermittent
  service, restart recovery, permission changes, and multi-device sync.

### Step 2 Progress — 2026-08-09

- [x] Added explicit opt-in, staged foreground/Always location permission, and
  separate trip notification permission.
- [x] Added visible Permission Required, Monitoring, Tracking, Paused, and
  Location Unavailable states in Settings.
- [x] Added battery-aware significant-location and automotive-motion monitoring
  that upgrades to route-quality location collection only for a probable trip.
- [x] Connected the pure detection engine to live Core Location samples and
  local trip-start/trip-finished notifications.
- [x] Added account/user-scoped, offline-first persistence for completed trips
  and active-trip checkpoints so collection can recover after interruption.
- [x] Added the Mileage workspace with newest-first review, one-tap Personal and
  Business controls, undo, trip history, route map, notes, correction history,
  and deletion.
- [x] Moved trip review and manual entry to a dedicated Dashboard tile while
  retaining only automatic tracking and monitoring status in Settings.
- [x] Added manual trip entry with start/end time, distance, classification,
  locations, business purpose, and notes.
- [x] Trimmed automatically detected trips to the last confirmed driving point
  so walking after parking is excluded from the saved route and mileage.
- [x] Added persistence/reload, active-checkpoint, and reversible-classification
  regression coverage alongside the seven detection-engine tests.
- [x] Completed signed-device permission, background, locked-screen, driving,
  notification, completion, route, and classification acceptance testing on
  iPhone17e.
- [x] Added map-assisted start and end selection to manual mileage entry and
  automatic Apple Maps driving-distance calculation.
- [x] Simplified manual entries to one trip start date and time; no end date or
  time is required from the user.
- [x] Added a durable Round Trip option that doubles the calculated one-way
  mileage and retains the reason for the doubled total in trip details and
  future reporting.
- [x] Positioned Round Trip directly below the calculated driving distance and
  added in-place editing for saved manual trips, including map locations,
  recalculated mileage, date/time, classification, purpose, and notes.
- [x] Updated the Dashboard Mileage tile to show rounded-up month-to-date
  mileage as its primary value and the actual unclassified-trip count in its
  “Trips to Review” footer.
- [x] Added Trip History search, Business/Personal filtering, inclusive date
  filtering, and newest/oldest sorting.
- [x] Added date-range and classification mileage summaries with deterministic,
  standards-compliant CSV generation and native iOS sharing.
- [x] Added tenant- and member-scoped mileage backup with same-user
  multi-device restoration, cursor-based incremental changes, durable offline
  retry, update deduplication, and deletion tombstones.
- [x] Enforced the approved privacy boundary: another member in the same
  company cannot read Personal or Business trip routes; Manager/Owner business
  summaries omit route geometry and Personal trips entirely.
- [x] Added Worker regression coverage for same-user restoration, cross-user
  isolation, and restricted business summaries.
- [x] Updated the application build identifier to **19.2.8**.
- [x] Applied migration 0021 and deployed the updated beta Worker
  (version `6ebda625-1263-4b97-b1b4-77150597e23e`).
- [x] Completed signed two-device restoration/deletion acceptance.

Approved privacy default: complete trips and routes synchronize only between
devices enrolled to the same signed-in tenant member. Managers and other Owners
receive no Personal-trip visibility. Authorized Manager/Owner business reports
may contain trip ID, employee member ID, date, mileage, and business purpose,
but never route geometry or Personal-trip facts.

### Product Decisions Required Before Step 2 Implementation

- Decide whether Personal trips remain device-private or synchronize as
  user-private encrypted records. Recommended: synchronize for backup but make
  them inaccessible to company Managers and other Owners.
- Approve trip-route retention and deletion periods.
- Approve whether Managers may see Business-trip route details or only mileage
  totals and business purpose.
- Decide whether automatic tracking is available to every role or is enabled by
  company policy per user.
- Approve distance display (miles initially, with kilometers retained as a
  future localization option).
- Decide whether an IRS reimbursement rate belongs in Phase 19 reporting or a
  later payroll/reimbursement feature.

## Step 3 — Technician Job Decline and Manager/Owner Review

### Goal

Let a Technician decline assigned work without granting reassignment authority,
while ensuring Managers and Owners receive and resolve the exception promptly.

### Requirements

- Technicians cannot assign or reassign Jobs.
- A Technician may decline only their assigned Job and must enter a reason.
- Store the request as a tenant-scoped, server-authoritative, immutable-audited
  review item linked to the Job, Assignment, employee, and originating device.
- Show a prominent **Job Review Required** alert on every active Manager and
  Owner device; selecting it opens the affected Job and reason.
- Authorized reviewers can reassign, reschedule, return, or cancel the work.
- Resolution clears the shared alert everywhere and remains visible in Job
  history. Repeated submissions and resolutions must be idempotent.
- Define offline submission, revoked-device, concurrent-review, and stale-record
  behavior explicitly.

### Implementation Status — Build 19.3.1

- [x] Added migration 0022 with tenant-scoped decline reviews and immutable
  submitted/resolved event history.
- [x] Added authenticated submit, list, and atomic idempotent resolution
  endpoints with server-side assignment ownership and role validation.
- [x] Prevented ordinary employee sync operations from changing Job or
  Assignment technician ownership.
- [x] Added a durable offline decline queue that retries with one stable
  idempotency key after connectivity returns.
- [x] Added the Technician **Decline Assigned Job** action with a required
  reason and a visible **Manager Review Requested** state.
- [x] Added a shared Manager/Owner **Job Review Required** Dashboard alert,
  review inbox, affected Job access, existing assignment-management controls,
  and audited resolution actions.
- [x] Worker regression suite passes 60 tests; generic signed-independent iOS
  compilation passes.
- [x] Applied migration 0022 to staging and deployed beta Worker version
  `6d4382ac-7d89-4bd1-9d89-c56102c433fa`.
- [x] Installed Build 19.3.1 and completed the two-device Technician/Manager
  live acceptance sequence on iPhone17e and Tim's iPad.

## Step 4 — Job Lifecycle and Time-Detail Clarity

### Goal

Make the operational and financial state of a Job immediately understandable
from lists and detail screens.

### Requirements

- Add a derived **Closed** presentation for Jobs that reach the approved final
  invoiced workflow state without rewriting historical status facts.
- Display Setup Started, Work Started, Completed, and Time on Job using
  dedicated persisted timestamps; use timeline lookup only for legacy records.
- Keep Job list, Job detail, My Day, calendar, invoice, payment, and history
  presentation consistent through one shared workflow-state projection.
- Preserve correction history and authorization for any time adjustment.

### Implementation Status — Build 19.4.3

- [x] Added one shared workflow projection for open and Closed Job presentation.
- [x] Kept historical Job and invoice facts intact while deriving Closed from
  completed work and finalized invoice states.
- [x] Added a dedicated persisted Work Started timestamp with safe decoding for
  existing records.
- [x] Added canonical Setup Started, Work Started, Completed, and Time on Job
  details, with timeline fallback only for legacy records.
- [x] Aligned Job hub counts, Job lists, Job detail, My Day, role-aware calendar,
  employee daily Jobs, and Job History with the shared projection.
- [x] Preserved the existing authorized timeline-correction and audit workflow.
- [x] Added focused regression coverage for dedicated timestamps, legacy
  fallback, stale workflow recovery, and Closed presentation.
- [x] Corrected every derived Closed workflow card to display 100% completion.
- [x] Added an invoice link directly to Job detail when an invoice exists.
- [x] Exposed authorized time correction beside Setup Started, Work Started,
  and Completed using the authenticated Manager/Owner identity.
- [x] Corrected Owner authorization for operational Owner profiles whose work
  roles are Sales or Technician, and added a visible **Correct** timeline action.
- [x] Installed Build 19.4.3 and completed signed acceptance on the selected test
  devices.

### Signed Acceptance Checklist

- [x] Completed a Job through invoice sent and confirmed every Job-facing surface
  presents **Closed**, while invoice/payment screens retain their financial
  status.
- [x] Confirmed Setup Started, Work Started, Completed, and Time on Job agree on
  Job detail and Job History after relaunch and synchronization.
- [x] Confirmed an older completed Job without dedicated timestamps still displays
  correct time details from its timeline.
- [x] Corrected an authorized timeline timestamp and confirmed the audit trail and
  displayed duration update without changing unrelated history.

## Step 5 — Catalog Tax Classification

### Goal

Prepare services and materials for correct tax calculation without embedding
tax logic in catalog views.

### Requirements

- Add clear item-type and tax-treatment controls to new, existing, and archived
  catalog items.
- Define safe defaults and migration behavior for existing records.
- Synchronize classifications tenant-wide and include them in immutable
  estimate, invoice, and receipt snapshots.
- Restrict configuration to authorized roles and retain audit history.

### Implementation Status — Build 19.5.2

- [x] Added explicit Service, Material, and Fee item types with Non-Taxable,
  Taxable, Tax Included, and Exempt tax treatments.
- [x] Applied safe legacy defaults to catalog records while preserving the
  absence of classification snapshots on historical transaction lines.
- [x] Restricted catalog creation, editing, archive, and restore controls to
  authorized company management roles.
- [x] Added immutable catalog name, item-type, and tax-treatment snapshots to
  estimate, Job, invoice, and receipt-source line items.
- [x] Preserved existing transaction snapshots when catalog classifications
  change later, with invoice creation filling only missing legacy snapshots.
- [x] Included classification data in the existing tenant-scoped record sync
  payloads and conflict comparison path without requiring a database schema
  migration.
- [x] Added focused legacy-decoding, round-trip, and immutability regression
  coverage.
- [x] Added visible invoice-line classification evidence and a tax summary that
  clearly distinguishes Step 5 classification from Step 6 tax calculation.
- [x] Installed Build 19.5.2 and completed signed iPhone/iPad acceptance.

### Signed Acceptance Checklist

- [x] Created Service, Material, and Fee catalog items using each applicable tax
  treatment and confirm they synchronize to a second device.
- [x] Edited and archived catalog classifications as an Owner or Manager, and
  confirm an unauthorized employee cannot configure the catalog.
- [x] Added classified catalog items to an estimate and Job, created an invoice,
  and confirm the stored transaction classification remains unchanged after the
  catalog item is edited.
- [x] Opened existing legacy catalog and transaction records and confirmed they
  remain readable without silently changing historical financial meaning.

## Step 6 — Tax Engine

### Goal

Calculate tax deterministically from the job-site jurisdiction and durable
transaction facts.

### Requirements

- Implement a UI-independent decimal `TaxEngine` with provider abstraction.
- Support taxable and non-taxable lines, exemptions, included tax, manual
  authorized overrides, rounding, and jurisdiction evidence.
- Store rate source, effective date, taxable subtotal, applied rate, rounding,
  exemption, and override evidence with the transaction snapshot.
- Define offline fallback and prohibit silent recalculation of finalized records.

### Implementation Status — Build 19.6.1

- [x] Added a UI-independent Decimal-based `TaxEngine` with a replaceable
  `TaxRateProviding` abstraction.
- [x] Added deterministic handling for taxable, non-taxable, tax-included, and
  exempt lines, proportional discounts, banker rounding, and invoice totals.
- [x] Added immutable invoice evidence for jurisdiction, source, effective date,
  taxable subtotal, included tax, added tax, rounding, exemption, calculation
  time, and authorized manual override.
- [x] Failed closed when classifications or verified jurisdiction rates are
  unavailable; PFSS never guesses a tax rate from an address.
- [x] Added Manager/Owner tax calculation and correction controls with a
  required reason and reviewer identity.
- [x] Added tax to invoice detail, PDF invoices, and thermal receipt output.
- [x] Added focused calculation, discount, exemption, override, and legacy-line
  tests.
- [x] Build 19.6.2 adds an Owner/Manager-controlled company standard tax rate,
  jurisdiction label, effective date, verification evidence, and optional
  source notes through Business Profile.
- [x] Invoice tax calculation defaults to the verified company rate while
  preserving reason-based authorized manual overrides.
- [x] Editing a verified company rate invalidates its verification until an
  authorized reviewer confirms it again; existing invoice snapshots remain
  unchanged.
- [x] Build 19.6.3 synchronizes the authorized company profile to enrolled
  devices and automatically snapshots the verified standard rate when a draft
  invoice is created. Existing uncalculated draft invoices are repaired when
  the verified profile first arrives, while finalized invoice evidence remains
  immutable.
- [x] Installed the Phase 19 tax builds and completed signed iPhone/iPad acceptance.

### Signed Acceptance Checklist

- [x] Calculated mixed taxable and non-taxable invoices and verified the displayed evidence and total.
  and exempt lines and verify the displayed evidence and total.
- [x] Applied discounts and verified the taxable subtotal is reduced
  proportionally before tax.
- [x] Applied exemptions and confirmed no added tax is charged while the reason is
  retained.
- [x] Confirmed Sales and Technician devices cannot apply or correct invoice tax.
- [x] Confirmed a missing rate or legacy unclassified line fails safely without
  changing the invoice total.
- [x] Saved, synchronized, relaunched, and confirmed the same tax snapshot appears on
  a second device.
- [x] Changed catalog classifications and rates later and confirmed saved
  invoice does not silently recalculate.
- [x] Verified invoice PDF and thermal receipt output match the saved invoice tax
  and total.

## Step 7 — Invoice Engine

### Goal

Create consistent invoices from approved estimates and completed Jobs while
preserving the exact commercial record.

### Requirements

- Implement a reusable decimal `InvoiceEngine` independent of SwiftUI.
- Preserve customer, site, services, materials, quantities, prices, discounts,
  tax classifications, totals, source records, and creation history.
- Make repeated creation and synchronization idempotent.
- Define draft, sent, partially paid, paid, voided, and corrected behavior with
  role authorization and audit history.
- Existing invoices remain readable and migrate without silent total changes.

### Stabilization Status — Build 19.7.1

- [x] Catalog and transaction line-item labor estimates support fractional
  minutes, including values such as `1.5` minutes per unit.
- [x] Existing whole-minute catalog and line-item records remain decodable and
  retain their original values.
- [x] Scheduling continues to consume a whole-minute duration only after the
  fractional per-unit value is multiplied by quantity.
- [x] Completed signed-device entry, synchronization, and scheduling acceptance.

### Invoice Engine Status — Build 19.7.4

- [x] Added a reusable, SwiftUI-independent `InvoiceEngine` for draft creation,
  decimal-backed totals, tax snapshot application, payment normalization, and
  job-source idempotency.
- [x] Routed completed-Job invoice creation, invoice editing, tax correction,
  and persistence payment normalization through the shared engine.
- [x] Preserved historical invoice totals during status/payment-only updates so
  legacy invoices are not silently repriced.
- [x] Added focused regression for discounted taxable drafts, partial/full
  payments, void balances, legacy-total preservation, and duplicate Job-source
  lookup.
- [x] Completed signed-device invoice lifecycle and cross-device synchronization
  acceptance before Step 7 is closed.

## Step 8 — Receipt Engine

### Goal

Produce durable receipts that exactly match accepted payments and work with the
existing thermal and PDF output paths.

### Requirements

- Implement a reusable `ReceiptEngine` from persisted invoice and payment facts.
- Snapshot pricing, tax, payment method, amount, balance, customer, site,
  company identity, timestamps, and source identifiers.
- Prevent duplicate receipts for the same idempotent payment event while
  preserving authorized void/correction history.
- Verify thermal printing, PDF presentation, sharing, offline creation, and
  cross-device synchronization.

### Implementation Status — Build 19.9.1

- [x] Added a reusable, SwiftUI-independent `ReceiptEngine` driven by persisted
  invoice and payment facts.
- [x] Added immutable receipt snapshots containing customer, site, Job, line,
  pricing, tax, payment, balance, timestamp, and source identifiers.
- [x] Added stable payment-event idempotency so retrying one payment cannot
  create a duplicate receipt.
- [x] Preserved legacy invoices that predate durable receipt snapshots.
- [x] Routed thermal receipt output through the latest durable snapshot with a
  safe fallback for historical invoices.
- [x] Added focused payment-delta, duplicate-event, and Codable persistence
  regression coverage.
- [x] Verified the existing PDF and thermal presentation paths on signed test
  devices during Phase 19 financial acceptance.

## Step 9 — Regression Testing, Documentation, and Closeout

### Required Regression

- Mileage permission, idle detection, trip start/stop, route accuracy,
  classification, correction, manual entry, reporting, privacy, offline use,
  restart recovery, battery impact, and multi-device synchronization.
- Owner, Manager, Sales, and Technician permissions.
- Job-decline submission, shared alerts, concurrent review, resolution, history,
  offline retry, suspension, and revocation.
- Job status and time projection across every operational surface.
- Catalog classification, tax boundaries, rounding, exemptions, and overrides.
- Estimate/Job to invoice, partial/full payment, receipt, PDF, and thermal print.
- Fresh-device bootstrap, conflicts, account lifecycle, and existing-company
  migration.
- Signed iPhone and iPad acceptance for every applicable workflow.

## Phase 19 Completion Gate

- [x] Product owner approved the final Phase 19 scope and order.
- [x] Diagnosed and resolved the live-production synchronization problems on the
  iPhone17pro Max account/device, then verify its queued changes, server data,
  and second-device state converge without manual backup or restore.
- [x] Mileage tracking meets the privacy, accuracy, battery, offline, and
  reporting acceptance criteria.
- [x] Every other approved capability meets its acceptance criteria.
- [x] Server-backed shared workflows pass tenant-isolation and authorization
  regression.
- [x] Financial engines pass deterministic decimal and snapshot regression.
- [x] Existing company data migrates without loss or silent financial changes.
- [x] Full automated suites pass with zero unexplained failures or skips: 246
  iOS unit tests and 64 Worker tests passed on 2026-08-14.
- [x] Signed iPhone and iPad acceptance passed for applicable roles and workflows.
- [x] Roadmap, parking lot, architecture, feature documents, release records,
  and GitHub agree.
- [x] Product owner accepted Phase 19 for closeout before the Phase 20
  synchronization redesign begins.
