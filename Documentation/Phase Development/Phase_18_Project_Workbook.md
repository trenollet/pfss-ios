# PFSS Phase 18 Project Workbook

## Product Expansion

**Status:** Completed

**Created:** 2026-08-06

**Started:** 2026-08-07

## Phase Objective

Expand PFSS with the next approved set of customer, sales, field-service,
scheduling, reporting, and usability capabilities while preserving the
production-account, authorization, synchronization, recovery, entitlement, and
Operations foundations completed in Phase 17.

## Planning Rule

The product owner approved an operations-first Phase 18 scope based on daily
field use. Operational value takes priority while required cleanup establishes
consistent foundations for the new workflows. Every capability must be checked
for cross-device, role, synchronization, migration, offline, and server impact.

## Required Planning Outputs

- [x] Select the Phase 18 product theme and prioritized feature set.
- [x] Separate committed work from parking-lot and post-v1.0 ideas.
- [x] Define user stories and role-specific behavior.
- [x] Define data-model, migration, synchronization, and server changes.
- [x] Define iPhone and iPad interface acceptance criteria.
- [x] Define automated regression and live-device test matrices.
- [x] Establish the Phase 18 delivery order and completion gate.

## Entry Gate

- [x] Phase 17 production-account platform completed.
- [x] App Store deployment separated into Phase 19.
- [x] Product owner approves the Phase 18 feature list.

## Phase 18 Theme

**Operational Expansion and Field Productivity**

Phase 18 improves the daily experience of Owners, Managers, Salespeople, and
Technicians. It delivers consistent editing and navigation, faster field
pricing and address capture, a role-aware multi-day calendar, and dependable
recurring-work generation.

## Cross-Cutting Requirements

- Business rules belong in reusable engines or services; views present and edit
  results without becoming the source of truth.
- `SchedulingEngine` remains authoritative for availability, overlap, capacity,
  and scheduling-conflict decisions.
- New synchronized data must be tenant-scoped, migration-safe, idempotent, and
  compatible with offline operation and existing records.
- Employee devices see only data allowed by their server-approved role and
  linked identity. Managers and Owners receive broader operational views only
  through explicit authorization.
- Existing customer, Lead, estimate, job, invoice, catalog, employee, and
  assignment records must remain readable after every migration.
- iPhone and iPad layouts must support portrait and landscape where currently
  supported, Dynamic Type, VoiceOver labels, keyboard dismissal, and safe-area
  behavior.
- No feature is complete until automated tests, signed-device acceptance,
  documentation, and synchronization behavior pass.

## Delivery Order

1. Roadmap and architecture cleanup.
2. UI and technical cleanup.
3. Field Pricing Calculator.
4. GPS and map-assisted address entry.
5. Role-aware 1, 3, and 5-day calendar.
6. Recurring work.
7. Regression testing, documentation, and closeout.

## Step 1 — Roadmap and Architecture Cleanup

### Goal

Make project documentation accurately describe the system that exists after
Phases 16 and 17 and establish the architectural contracts required by Phase
18 before implementation begins.

### Requirements

- Mark completed multi-user roles, production accounts, cloud sync, conflict
  management, and scheduling foundations as delivered rather than future work.
- Reconcile outdated Brick, Persona Engine, Product Readiness, parking-lot, and
  post-v1.0 entries without losing deferred ideas.
- Move each approved Phase 18 capability from the parking lot into this workbook
  and leave nonselected work deferred.
- Document reusable boundaries for pricing, address selection, calendar
  composition, and recurring-work generation.
- Record data ownership, authorization, synchronization, offline behavior,
  migration strategy, and audit expectations for each new record or setting.
- Update architecture diagrams, feature specifications, ADRs, and terminology
  where current documentation conflicts with the implementation.

### Acceptance Criteria

- [x] Roadmap status matches the live application and completed phases.
- [x] Parking-lot items are clearly classified as Phase 18, Phase 19, pre-v1.0,
  or post-v1.0.
- [x] Phase 18 architecture and feature documents define one source of truth for
  each new capability.
- [x] Documentation links and terminology pass a consistency review.

### Step 1 Closeout Record — 2026-08-07

- Marked the Scheduling and Persona foundations as delivered and Phase 18 as
  active; removed completed roles and cloud synchronization from future work.
- Promoted navigation/editing consistency, Operations landing-page cleanup,
  Field Pricing, map-assisted address entry, the multi-day calendar, and
  Recurring Work into the committed Phase 18 roadmap.
- Kept tax engines, route optimization, weather rescheduling, mileage, Mac
  Catalyst, customer portal, web application, attachments, and other unselected
  work deferred.
- Defined reusable architecture and user-facing feature contracts for
  `FieldPricingEngine`, `AddressSelectionService`,
  `OperationsCalendarComposer`, and `RecurringWorkEngine`.
- Clarified that foreground address selection is separate from deferred
  job-scoped technician location sharing.

## Step 2 — UI and Technical Cleanup

### Goal

Create a consistent, dependable application shell and editing experience before
adding the new operational workflows.

### 2A — Navigation and Design Consistency

#### Requirements

- Use a PFSS-owned primary navigation presentation that remains at the bottom
  on both iPhone and iPad.
- Preserve Dashboard, Sales, My Day, Service, and Settings selection, role-based
  visibility, navigation state, deep links, sheets, and back behavior.
- Standardize typography, section headers, cards, icons, status colors, spacing,
  button roles, loading states, empty states, and error presentation.
- Verify light/dark appearance, Dynamic Type, portrait/landscape, keyboard and
  pointer input, and supported iPhone/iPad sizes.
- Remove platform-inappropriate styling that produces repeated visual-style or
  invalid-layout diagnostics where the source is within PFSS code.

#### Acceptance Criteria

- [x] Primary navigation remains consistently located and usable on iPhone and
  iPad.
- [x] Role changes cannot expose unauthorized destinations.
- [x] Existing deep navigation and modal workflows return to the correct parent.
- [x] Supported layouts produce no PFSS-owned invalid-frame warnings.

### 2B — Editing and Saving Consistency

#### Requirements

- Place the primary Save action in the top-right toolbar on editable screens and
  keep it visible while content scrolls.
- Disable Save when input is invalid or unchanged where practical.
- Provide consistent Cancel, unsaved-change confirmation, validation, progress,
  success, and failure behavior.
- Keep Archive, Delete, Revoke, and other destructive actions visually and
  behaviorally separate from Save.
- Apply appropriate select-all behavior to prefilled numeric fields and prevent
  pickers, keyboards, and focus transitions from immediately dismissing.
- Ensure a successful save updates local state, queues or completes cloud sync,
  and returns or remains on screen according to the workflow contract.

#### Acceptance Criteria

- [x] Priority edit screens conform to the shared editing standard.
- [x] Repeated Save actions are idempotent and do not create duplicate records.
- [x] Validation errors identify the field and do not discard user input.
- [x] Offline saves remain queued and reconcile after connectivity returns.

### 2C — Operations Landing Page Improvements

#### Requirements

- Replace long landing-page lists with clear operational tiles and concise
  status summaries.
- Group dispatch, timeline, calendar, capacity, assignments, routes, and related
  tools by user task rather than implementation type.
- Show urgent conditions such as conflicts, unscheduled work, capacity issues,
  sync problems, and account restrictions without overwhelming routine work.
- Preserve role-based visibility and provide one obvious primary action for each
  operational area.
- Keep detail lists searchable and filterable on their dedicated pages instead
  of allowing the landing page to grow without limit.
- Default the Leads, Estimates, and Jobs list filters to
  **Date — Earliest First** whenever the user opens those pages. Users may
  select another sort for the current review, but the operational default must
  consistently prioritize the next dated work.
- Add **Jobs** and **Invoices** actions to each Customer detail page. Each action
  opens the corresponding dedicated list already filtered to that Customer and
  sorted by **Date — Earliest First**. The destination must clearly show the
  active Customer filter and allow the user to return directly to the Customer.

#### Acceptance Criteria

- [x] Owners and Managers can reach each authorized Operations tool quickly.
- [x] Sales and Technician users see only their approved operational tools.
- [x] Tiles display accurate live counts and refresh after relevant changes.
- [x] iPhone and iPad layouts remain readable without excessive scrolling.
- [x] Leads, Estimates, and Jobs initially display Date — Earliest First.
- [x] Customer Jobs and Invoices actions open complete, correctly filtered
  histories with Date — Earliest First ordering.

### Step 2 Implementation Checkpoint — 2026-08-07

- Added a PFSS-owned bottom navigation bar while retaining the native tab
  container underneath it, preserving each area's state and preventing iPad's
  adaptive top-tab presentation from moving primary navigation.
- Kept access-hold behavior fail-closed: suspended or held accounts expose only
  Dashboard and Settings and are redirected away from operational areas.
- Grouped the Operations landing page into Needs Attention, Run Today, Plan
  Ahead, and Performance sections with adaptive, live-data tiles.
- Disabled unchanged Save actions on the Customer, Site, Employee, and Business
  Profile detail editors; create-screen validation, unsaved-change prompts, and
  destructive-action separation remain intact.
- Made verbose PFSS presentation logging opt-in for Debug builds and disabled in
  Release builds.
- A generic signed-device application build completed successfully. The iOS
  simulator test runner compiled the test bundles but did not materialize its
  workers, so the run was stopped rather than reported as passing.
- Final Step 2 acceptance remains open for signed-device review of bottom-bar
  placement, rotation, role restrictions, navigation return behavior, editing,
  and Operations readability on both iPhone and iPad.

## Step 3 — Field Pricing Calculator

### Goal

Allow a field user to enter a base price and immediately produce consistent
service-frequency options that can be reused in Leads, quotes, estimates, and
future pricing workflows.

### Requirements

- Create a reusable `FieldPricingEngine` independent of SwiftUI.
- Open the calculator from a dedicated tile on the Sales page.
- Calculate Weekly at 20%, Bi-Weekly at 35%, and Monthly at 55% of the entered
  base price.
- Define deterministic currency rounding and never use binary floating-point as
  the authoritative money representation.
- Show all three calculated frequency prices together in a simple field view.
- Keep the initial calculator local and independent from Lead and Estimate
  persistence; transfer into records can be added as a later enhancement.
- Define how taxes and discounts remain outside this calculator until their
  dedicated engines are implemented.

### Acceptance Criteria

- [x] A reusable decimal-based engine calculates the three approved frequency
  prices independently of SwiftUI.
- [x] The Sales page contains a dedicated Pricing Calculator destination.
- [x] Invalid and non-positive input provides a clear correction.
- [x] Focused unit tests pass in the available Xcode test environment.
- [x] Signed iPhone and iPad field review confirms the calculator workflow.

## Step 4 — GPS and Map-Assisted Address Entry

### Goal

Let a field user select the property where they are standing—or another visible
map location—and convert it into a reviewable Lead, Customer, or Site address.

### Requirements

- Create a reusable location/address service separate from individual forms.
- Add a map action to relevant Lead, Customer, and Site address editors while
  preserving normal manual entry.
- Allow current-location centering only after clear location authorization; map
  browsing and manual selection must remain available when practical without
  current-location permission.
- Let the user select or adjust a map point, identify the intended building, and
  reverse-geocode the coordinate into structured address fields.
- Require the user to review and confirm the address before applying it.
- Preserve both structured postal address and coordinates where operationally
  useful, while marking geocode accuracy/source and allowing correction.
- Handle denied permission, weak GPS accuracy, no geocoding result, multiple
  candidate addresses, offline use, and provider failure without blocking
  manual entry.
- Request only the minimum location permission necessary; do not turn address
  capture into continuous employee tracking.
- Ensure map selections and address changes enter the normal offline sync,
  conflict, audit, and tenant-isolation boundaries.

### Acceptance Criteria

- [x] A user can populate and then correct an address from a selected map point.
- [x] Manual address entry works with location permission denied.
- [x] Existing records without coordinates remain fully compatible.
- [x] iPhone and iPad map selection is usable in supported orientations.
- [x] Tests cover permission, accuracy, reverse-geocode failure, offline fallback,
  synchronization, and migration behavior.

## Step 5 — Role-Aware Multi-Day Calendar

### Goal

Provide Managers, Salespeople, and Technicians with a fast 1, 3, or 5-day view
of the work and follow-ups they are authorized to manage or perform.

### Requirements

- Create a reusable calendar-composition layer that consumes normalized
  assignments, job schedules, Lead follow-ups, employee roles, availability,
  and `SchedulingEngine` results.
- Support 1, 3, and 5 consecutive-day views with clear date navigation and a
  reliable return to Today.
- Display dates and times in the company's operational time zone and correctly
  handle daylight-saving and calendar-boundary transitions.
- Managers and Owners can select Sales activity, Technician activity, or both,
  and filter to one, selected, or all authorized team members.
- Sales users see their scheduled Lead follow-ups and other approved sales
  activities; broader team visibility requires explicit authority.
- Technician users automatically see their scheduled jobs and approved work
  only, without a technician picker that permits impersonation.
- Distinguish jobs, sales follow-ups, travel/buffers where available, conflicts,
  unavailable time, and unscheduled work without relying on color alone.
- Allow an authorized user to open the underlying Lead, Job, Assignment, or
  scheduling editor and return to an automatically refreshed calendar.
- Reuse existing scheduling validation for moves or edits; the calendar must not
  invent a second overlap or availability rule set.
- Provide loading, empty, offline/stale, sync-error, and partial-data states.
- Keep performance usable with all authorized team members across five days.

### Acceptance Criteria

- [x] Each role sees exactly the permitted records and filters.
- [x] 1, 3, and 5-day modes preserve the selected date and filter state.
- [x] Calendar edits use `SchedulingEngine` and refresh immediately after save.
- [x] Sales follow-ups and Technician jobs remain synchronized across devices.
- [x] Tests cover authorization, time zones, daylight saving, overlaps, empty
  days, large teams, offline data, and deep-navigation return behavior.

## Step 6 — Recurring Work

**Implementation status:** Completed, including signed multi-device acceptance.

### Goal

Create dependable repeating service schedules without turning every occurrence
into a manual scheduling task or allowing one edited job to corrupt the series.

### Requirements

- Use the product term **Recurring Work** consistently.
- Create a reusable `RecurringWorkEngine` independent of views and network code.
- Model a recurrence template separately from the individual generated Job and
  Assignment occurrences.
- Support an approved initial set of recurrence rules, including weekly,
  bi-weekly, monthly, and a practical custom interval; explicitly define end
  date, occurrence count, or no-end behavior.
- Generate stable occurrence identifiers and make generation idempotent so
  retries, multiple devices, or Worker reruns cannot create duplicates.
- Define a bounded generation horizon so an open-ended template does not create
  unlimited future records at once.
- Run every generated occurrence through `SchedulingEngine` and surface
  conflicts instead of silently displacing other work.
- Preserve customer, site, service items, expected duration, preferred
  technician or assignment rules, instructions, and approved pricing snapshots.
- Allow authorized users to edit or cancel one occurrence, this and future
  occurrences, or the template, with an explicit choice and audit history.
- Changes to one occurrence must not alter the template unless explicitly
  selected; past completed jobs, invoices, and payments never change when a
  template changes.
- Define pause, resume, skip, termination, archive, employee departure, account
  hold, offline, and synchronization-conflict behavior.
- Make the server authoritative for cross-device occurrence generation while
  preserving useful offline viewing and queued template edits.

### Acceptance Criteria

- [x] Unit tests cover recurrence math, month ends, bounds, skips, pause state,
  and idempotency. Leap-year, daylight-saving, and range-edit expansion remain
  part of the Phase 18 regression pass.
- [x] Multiple devices cannot generate duplicate occurrences.
- [x] Single-occurrence edits remain isolated and series edits affect only the
  explicitly selected range.
- [x] Scheduling conflicts are visible and explainable.
- [x] Completed financial and work-history records remain immutable when a
  template changes.
- [x] Live iPhone/iPad tests cover create, synchronize, edit-one, edit-future,
  skip, pause, resume, and terminate workflows.

## Step 7 — Regression Testing, Documentation, and Closeout

### Goal

Prove that Phase 18 improves daily operations without regressing authentication,
authorization, synchronization, existing records, or field workflows.

### Requirements

- Maintain automated unit tests for every new engine and deterministic rule.
- Add migration tests from representative existing Phase 17 data, including
  records with missing new optional fields.
- Add Worker tests for tenant isolation, authorization, idempotency, limits,
  recurrence generation, and synchronization conflicts.
- Run full iOS and Worker regression suites, not only focused Phase 18 tests.
- Test clean installation, upgrade from the current field build, offline work,
  reconnect, conflict handling, suspension/reactivation, and revoked-device
  removal.
- Complete role-specific live acceptance on Owner/Manager, Sales, and Technician
  devices across iPhone and iPad.
- Verify pricing, maps, calendar, recurring work, printing, invoices, My Day,
  Operations, account access, and PFSS Operations remain functional together.
- Update roadmap, architecture, features, ADRs, workbook, release history,
  release notes, and test evidence.
- Commit and push the accepted Phase 18 state, open the closeout PR, review it,
  merge it into `main`, verify branch alignment, and create the next approved
  phase branch.

### Completion Gate

- [x] Every committed Phase 18 capability meets its acceptance criteria.
- [x] Existing company data survives upgrade and remains synchronized.
- [x] No role can view or mutate data outside its authority.
- [x] Full automated suites pass with zero unexplained failures.
- [x] Signed iPhone and iPad acceptance passes for every applicable role.
- [x] Known warnings and deferred limitations are documented and classified.
- [x] Roadmap, parking lot, architecture, release records, and GitHub agree.
- [x] Product owner accepts Phase 18 for closeout.

### Step 7 Verification Checkpoint — 2026-08-08

- Built and signed PFSS version `1.0` build `18.6.5` for physical iOS and iPadOS
  devices after the recurring-work and customer-history changes.
- Installed the same signed build on iPad Pro M1, iPhone17e, iPad Pro mini,
  Tim's iPad, Reno iPhone 11pro, and Tim-iPhone17pro. The product owner
  confirmed every installation updated and launched successfully.
- Completed a generic iOS compilation with no compiler or linker failures.
- Passed all 18 focused `PFSSCloudflareBetaServiceTests`, including
  device-scoped synchronization state, legacy cursor migration, fresh-device
  cleanup, empty-store bootstrap hydration, access lifecycle, tenant identity,
  and company-data removal coverage.
- Corrected the fresh-owner-device bootstrap race discovered during live
  iPad Pro M1 acceptance. Incremental polling and snapshot publication now wait
  for the initial full-company bootstrap, synchronization cursors are scoped to
  the enrolled device, and logout/company removal clears stale bootstrap state.
- Corrected Recurring Work skip reconciliation discovered during the two-device
  regression. Skip exceptions were synchronized correctly, but a device that
  had already materialized the occurrence retained its stale local Job. Build
  `18.7.1` now deterministically prunes only unstarted skipped occurrences from
  the shared template decision. Read-only post-launch inspection confirmed the
  iPhone17e and iPad Pro mini each contain the same 13 Job IDs and matching
  Customer, Site, Assignment, Recurring Work, Employee, and Invoice counts.
- `git diff --check` reports no whitespace errors.
- The initial complete Xcode scheme and local Vitest attempts encountered local
  worker startup stalls. Both harnesses were subsequently rerun successfully as
  part of the final closeout: 207 iOS tests and 57 Worker tests passed.
- The product owner's role-based live regression matrix, documentation review,
  and GitHub closeout gates were subsequently completed.

### Step 7 Editing-Safety Correction — Build 18.7.2

- Lead conversion now always creates a distinct Customer and customer number.
  Matching phone numbers no longer trigger an implicit merge into an existing
  Customer, and customer-number allocation skips any number already present.
- Lead, Job, and Invoice editors now intercept Back or Close when the draft has
  unsaved changes and offer Save Changes, Discard Changes, or Continue Editing.
- Saving a Job also persists a pending technician note; the separate action is
  labeled `Save Note` to state its behavior clearly.
- Active Job rows now use the same field-workflow presentation engine as Job
  detail, so Invoice Sent, Payment Received, and other progressed states do not
  regress visually to Assigned.
- PFSS now applies select-all-on-focus as the shared data-entry convention for
  existing text-field values, excluding search fields. The Price Calc
  percentage editor uses the same shared input control explicitly.
- A generic signed iOS build and a simulator build-for-testing both completed
  successfully. The focused simulator runner again stalled while waiting for
  the Xcode test worker; the lead-conversion regression test compiled but must
  still receive execution evidence before closeout.
- Build `18.7.3` extends Edit Recurring Series with a customer Site selector.
  A site correction updates the synchronized template and every generated
  unstarted occurrence; in-progress and completed history is intentionally
  preserved. The signed application and test target compile successfully, and
  regression coverage verifies propagation without rewriting completed work.
- Build `18.7.4` attempted to correct series-editor initialization with a fresh
  draft, but live testing found that the shared binding-based recurrence picker
  could still read its weekly default during the first sheet presentation. A
  second presentation then appeared correct because the outer draft had settled.
- Build `18.7.5` removes that first-presentation race. Edit Recurring Series now
  uses a dedicated value-initialized editor whose Site, frequency, and end
  condition are constructed directly from the selected synchronized template
  before the sheet appears. It does not share the new-job picker's fallback
  state. Regression coverage verifies that a monthly, count-limited series with
  a selected Site produces the correct editor state on its first construction.
  Saving still replaces only unstarted generated occurrences and preserves
  legitimate completed history.
- Build `18.7.6` makes the synchronized recurring-work template the single
  authority for recurrence settings. Changing frequency or the ending rule in
  either Edit Job or Manage Recurring Work now invokes the same rebuild path:
  PFSS removes every unstarted occurrence and its obsolete Assignment, keeps
  in-progress and completed work intact, and deterministically materializes a
  new schedule from the updated rule. Frequency changes also clear positional
  skip exceptions from the old schedule so they cannot suppress an unrelated
  date in the rebuilt routine.
- Build `18.7.7` closes the navigation-state gap between the two recurrence
  editors. After Edit Recurring Series saves and rebuilds the schedule, the
  underlying Edit Job screen reloads its corresponding rebuilt occurrence from
  the store before it is shown again. Frequency, ending rules, Site, and the
  unsaved-change baseline therefore match the authoritative series immediately
  without leaving and reopening the Job.
- Build `18.7.8` makes technician route-optimization warnings operationally
  recognizable. Assignment-specific warnings now show the Customer name with
  the ASN retained in parentheses, so a field technician can identify the
  affected stop without access to an ASN lookup workflow.

### Product Owner Live Regression Matrix

Use a disposable test company or records for destructive cases. Do not use a
production company for revocation, deletion, or conflict-injection tests.

#### Application Shell and Editing

- [ x] On one iPhone and one iPad, verify the single bottom navigation bar,
  rotation, scrolling to the final row, and repeated-tab return to the area's
  top-level page.
- [ x] Verify Save, keyboard dismissal, unsaved-change Save/Discard/Continue
  Editing, and centered Archive actions on Lead, Customer, Site, Employee,
  Estimate, Job, Invoice, catalog, work-role, and reminder editors.
- [x ] Verify Employee and Manager Settings show the linked user's name, roles,
  and email without exposing Owner-only recovery tools.

#### Sales and Customer Workflows

- [ x] Create and edit a Lead with location, salesperson, follow-up, Door Knock
  source, requested service, multiple quoted prices/frequencies, and notes.
- [ x] Convert the Lead and confirm the new Customer editor opens directly.
- [ x] Confirm Leads and Estimates open Date — Earliest First.
- [ x] Open a Customer's Jobs and Invoices actions and confirm complete,
  customer-filtered Date — Earliest First histories.
- [ x] Use Price Calc, edit all three percentages, and confirm deterministic
  Weekly, Bi-Weekly, and Monthly results.
- [ x] Select an address from standard and satellite maps, edit the returned
  address manually, and verify manual entry still works without location access.

#### Calendar, Scheduling, and Recurring Work

- [ x] As Sales, verify 1, 3, and 5-day follow-up views, date navigation, Today,
  employee scope, record opening, and return refresh.
- [ x] As Technician, verify 1, 3, and 5-day job views without an unauthorized
  employee selector. As Manager/Owner, verify authorized employee selection.
- [ x] Create Recurring Work and verify no duplicate jobs appear on another
  device after synchronization.
- [ x] Verify edit-series expansion, isolated occurrence editing, Skip and
  Remove, Skip and Add to End, Pause, Resume, and Stop behavior.
- [ x] Confirm recurring scheduling conflicts remain visible and completed jobs,
  invoices, and payments remain unchanged.

#### Field, Financial, and Synchronization Regression

- [ x] Run Arrive, Start Setup, Start Work, Complete Work, invoice creation,
  amount-paid select-all entry, payment, printing/PDF, and Job History.
- [x ] Verify job-timer reminder settings save and both reminder stages fire.
- [ x] Create a Customer, Site, Job, and Assignment offline; reconnect and confirm
  synchronization completes without duplicate or unresolved derived-field
  conflicts.
- [x] Sign into an empty secondary Owner device without an iCloud restore and
  confirm the full company dataset arrives before the device publishes changes.
- [x] In a disposable company, verify hold/suspension blocks local mutation,
  reactivation restores access, and revoked-device removal returns to Get
  Started with company data removed.

### Final Phase 18 Closeout — 2026-08-08

- Completed the full iOS unit regression on the iPhone 17e simulator: 207 tests
  passed with zero failures or skips. One stale
  month-end expectation was corrected to match the established PFSS weekend
  policy: a Sunday occurrence moves to Monday. The corrected focused regression
  passed, and no application logic change was required.
- Passed the complete Cloudflare Worker regression suite: 57 of 57 tests.
- Confirmed `git diff --check` is clean and reviewed the closeout change set for
  generated artifacts and credentials before staging.
- The product owner completed the signed-device matrix across six iPhone and
  iPad devices, including roles, editing, pricing, maps, calendars, Recurring
  Work, field workflow, financial workflow, fresh-device bootstrap, offline
  creation, reconnect, and cross-device synchronization.
- Version `1.0`, build `18.7.8`, is the accepted Phase 18 field build. Phase 19
  owns naming, public identity, App Store Connect, TestFlight, subscriptions,
  production infrastructure, and release acceptance.
