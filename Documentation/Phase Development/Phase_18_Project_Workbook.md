# PFSS Phase 18 Project Workbook

## Product Expansion

**Status:** Active

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

- [ ] Roadmap status matches the live application and completed phases.
- [ ] Parking-lot items are clearly classified as Phase 18, Phase 19, pre-v1.0,
  or post-v1.0.
- [ ] Phase 18 architecture and feature documents define one source of truth for
  each new capability.
- [ ] Documentation links and terminology pass a consistency review.

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

- [ ] Primary navigation remains consistently located and usable on iPhone and
  iPad.
- [ ] Role changes cannot expose unauthorized destinations.
- [ ] Existing deep navigation and modal workflows return to the correct parent.
- [ ] Supported layouts produce no PFSS-owned invalid-frame warnings.

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

- [ ] Priority edit screens conform to the shared editing standard.
- [ ] Repeated Save actions are idempotent and do not create duplicate records.
- [ ] Validation errors identify the field and do not discard user input.
- [ ] Offline saves remain queued and reconcile after connectivity returns.

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

#### Acceptance Criteria

- [ ] Owners and Managers can reach each authorized Operations tool quickly.
- [ ] Sales and Technician users see only their approved operational tools.
- [ ] Tiles display accurate live counts and refresh after relevant changes.
- [ ] iPhone and iPad layouts remain readable without excessive scrolling.

## Step 3 — Field Pricing Calculator

### Goal

Allow a field user to enter a base price and immediately produce consistent
service-frequency options that can be reused in Leads, quotes, estimates, and
future pricing workflows.

### Requirements

- Create a reusable `FieldPricingEngine` independent of SwiftUI.
- Support at least weekly, bi-weekly, monthly, quarterly, annual, and one-time
  frequencies.
- Store configurable multiplier or adjustment rules in tenant-owned settings;
  provide safe defaults and restrict configuration to authorized roles.
- Define deterministic currency rounding and never use binary floating-point as
  the authoritative money representation.
- Show the base price, frequency, applied rule, and calculated result clearly.
- Allow selected price/frequency options to be copied into a Lead's quote
  options or an Estimate without retyping.
- Preserve the chosen price as a durable snapshot so later multiplier changes
  do not silently rewrite an existing quote, estimate, job, or invoice.
- Support editing, removing, and reordering proposed options before saving.
- Define how taxes and discounts remain outside this calculator until their
  dedicated engines are implemented.

### Acceptance Criteria

- [ ] Unit tests cover every frequency, rounding boundary, zero/invalid input,
  and customized multiplier.
- [ ] Authorized users can configure rules and other users can calculate with
  the approved rules.
- [ ] Calculated options transfer correctly to new and existing Leads and
  Estimates.
- [ ] Existing saved prices remain unchanged after pricing settings change.
- [ ] Pricing settings and saved options synchronize across devices without
  exposing another tenant's configuration.

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

- [ ] A user can populate and then correct an address from a selected map point.
- [ ] Manual address entry works with location permission denied.
- [ ] Existing records without coordinates remain fully compatible.
- [ ] iPhone and iPad map selection is usable in supported orientations.
- [ ] Tests cover permission, accuracy, reverse-geocode failure, offline fallback,
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

- [ ] Each role sees exactly the permitted records and filters.
- [ ] 1, 3, and 5-day modes preserve the selected date and filter state.
- [ ] Calendar edits use `SchedulingEngine` and refresh immediately after save.
- [ ] Sales follow-ups and Technician jobs remain synchronized across devices.
- [ ] Tests cover authorization, time zones, daylight saving, overlaps, empty
  days, large teams, offline data, and deep-navigation return behavior.

## Step 6 — Recurring Work

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

- [ ] Unit tests cover recurrence math, month ends, leap years, daylight saving,
  bounds, edits, skips, termination, and idempotency.
- [ ] Multiple devices cannot generate duplicate occurrences.
- [ ] Single-occurrence edits remain isolated and series edits affect only the
  explicitly selected range.
- [ ] Scheduling conflicts are visible and explainable.
- [ ] Completed financial and work-history records remain immutable when a
  template changes.
- [ ] Live iPhone/iPad tests cover create, synchronize, edit-one, edit-future,
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

- [ ] Every committed Phase 18 capability meets its acceptance criteria.
- [ ] Existing company data survives upgrade and remains synchronized.
- [ ] No role can view or mutate data outside its authority.
- [ ] Full automated suites pass with zero unexplained failures.
- [ ] Signed iPhone and iPad acceptance passes for every applicable role.
- [ ] Known warnings and deferred limitations are documented and classified.
- [ ] Roadmap, parking lot, architecture, release records, and GitHub agree.
- [ ] Product owner accepts Phase 18 for closeout.
