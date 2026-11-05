# PFSS Phase 21 Project Workbook

## Modern, Efficient User Interface

**Status:** In Progress — Home redesign awaiting product-owner acceptance

**Started:** 2026-08-26

## Phase Objective

Reduce the time and attention required for daily PFSS work while establishing
a consistent, modern visual system across iPhone and iPad. Common actions
should require fewer taps, use plain language, and remain easy to recognize in
fast-moving field conditions.

## Design Principles

- Prioritize the most frequent daily actions.
- Remove explanation that repeats an action's clear title.
- Keep navigation targets direct and predictable.
- Build reusable components rather than isolated screen-specific styling.
- Preserve user customization where it already provides operational value.
- Validate layouts and workflows on both iPhone and iPad.

## Step 1 — Home Screen Simplification

- [x] Rename Dashboard to Home in the title and primary navigation.
- [x] Retain the existing My Day and Mileage information tiles.
- [x] Remove the Sales, Service, Operations, and Settings Home tiles.
- [x] Add compact icon shortcuts for New Lead, Customers, Invoices, and
  Jobs.
- [x] Route each shortcut directly to its requested destination.
- [x] Preserve long-press and Arrange-mode tile reordering and blank spaces.
- [x] Start the Phase 21 build line at 21.0.1.
- [x] Complete simulator compilation and diff validation.
- [ ] Complete signed iPhone and iPad visual/product-owner acceptance.

Implementation evidence:

- `DashboardView` owns the simplified six-tile Home configuration and the
  reusable compact square shortcut presentation.
- `CustomizableTileGrid` continues to own persistent user ordering, drag/drop,
  blank positions, and reset-to-default behavior. Its reusable column-count
  option allows the two information cards to remain a two-column row while the
  four daily shortcuts occupy one compact four-column row.
- `AppSection.dashboard` remains the stable internal navigation identity while
  its user-facing title and symbol are now Home and a filled house.

## Field workflow follow-up — 2026-09-17, build 21.1.50

Arrival and setup are now one technician action. `markArrived` ends active
travel and enters `settingUp`, records `setupStartDate` at arrival, and appends
arrival/setup timeline evidence at the same time in one job update. The next
action is Start Job (`startWork`). Assignment arrival remains On Site. The
phone and paired-watch bridge use the same coordinator/engine. Old Arrived
records can start work directly; the legacy setup action remains supported for
older queued clients without appearing as the next step in the refreshed UI.

Arrival now schedules the setup-to-work reminder rather than an arrival-to-setup
reminder. Settings show one reminder timing for arrival/setup and retain the
legacy preference field for wire compatibility.

Validation: 37 field engine/offline integration tests passed, including shared
My Day/job detail behavior, single action queue ordering, travel duration,
full assignment/invoice lifecycle, and legacy Arrived continuation. Signed iOS
build and signature verification passed. Build 21.1.50 installed and launched
on Tim-iPhone17pro and iPhone17e. Physical workflow, watch and cross-device
acceptance remain pending; no live job was advanced by implementation tests.
No Worker/schema changes or Git commit/main integration were performed.

This append records the follow-up only; the earlier workbook does not yet
inventory the entire Phase 21 working set and still needs closeout reconciliation.

## Revenue forecasts — 2026-09-19, build 21.1.51

The Home Revenue shortcut is unchanged. Revenue now has a green Forecasts
button leading to four drill-down totals: current Sunday–Saturday week,
calendar month, fixed calendar quarter (Q1 Jan–Mar, Q2 Apr–Jun, Q3 Jul–Sep,
Q4 Oct–Dec), and calendar year. Unlike the existing period-to-date Scheduled
figure, forecasts include remaining scheduled dates from today through each
period's end. They sum each active scheduled/assigned, not-yet-started job's
current total once. Unscheduled, overdue, canceled, completed, archived, and
already-started jobs are excluded. Cards show job counts and open the matching
job list. Forecasts are projected job value, not recognized or collected cash.

Quarter-boundary and inclusion/exclusion regression tests were added. Physical
device visual and data acceptance remain pending; no live job was changed for
implementation testing. Six targeted Revenue tests passed, and the signed
generic iOS build passed signature verification. Build 21.1.51 installed and
launched on Tim-iPhone17pro. It installed on iPhone17e, but launch was denied
because that phone was locked. The iPad Pro M1 install was denied because it
had not been unlocked recently. No Worker/schema changes or Git commit/main
integration were performed. The earlier workbook remains incomplete pending
Phase 21 closeout reconciliation.

## Forecast horizon follow-up — build 21.1.52

The four main forecast cards are titled Weekly, Monthly, Quarterly, and
Annually, and continue to show only the current period's projected value.
Selecting a card now opens a dedicated totals screen rather than the job list:
Weekly shows this week plus four following weeks (five rows); Monthly shows
this month plus two following months (three rows); Quarterly shows the current
quarter plus the next three (four rows); Annually shows the current year plus
two following years (three rows). Each row displays its calendar dates, total,
and included job count. The first row omits overdue work; future rows use full
calendar periods. Calendar arithmetic crosses year boundaries without merging
or overlapping periods. The Home shortcut remains unchanged. Regression tests
cover counts, month/week/quarter/year rollover, future totals, and quarter
labels. Device/data acceptance remains pending.
Validation completed: eight targeted Revenue tests passed, the signed generic
iOS build compiled and passed signature verification, and build 21.1.52
installed and launched on Tim-iPhone17pro and iPhone17e. The iPad Pro M1
remained locked and refused installation. Forecast values on real company jobs
still need product-owner review. No Worker/schema change or Git commit/main
integration was performed.

## Multi-day job scheduling — 2026-11-05, build 21.1.53

One nonrecurring Job can now carry a primary scheduled workday plus additional
scheduled workdays without duplicating the customer, scope, pricing, invoice,
or Job identity. New Job and Job Detail scheduling include a Multiple Day Work
control with date/time entry, removal, validation against duplicate days, and
sorted display. Recurring jobs remain separate from this feature so recurrence
rules and explicitly scheduled multi-day work cannot silently multiply one
another.

My Day and the Jobs calendar project the same Job onto each scheduled workday.
Moving an additional workday changes that occurrence rather than overwriting
the primary date. Forecast value continues to count the Job once instead of
counting its full price once per workday.

The three static My Day actions Decline, Move, and Skip are consolidated into
one Modify action list. It also offers Add Another Workday. Selecting Pause
Work now asks whether to pause only or pause and schedule continued work; the
latter records the pause first and then opens continuation date/time entry.
This retains one Job and its existing workflow history.

Validation: 40 focused field-engine and offline-workflow tests passed with no
failures, including legacy Job decoding, multi-day My Day projection, stable
Job identity, continuation persistence, duplicate-day rejection, and pause
workflow behavior. The signed generic iOS build compiled and passed strict
signature verification. Build 21.1.53 installed and launched on
Tim-iPhone17pro. iPhone17e and all available iPads were unavailable during this
run. Physical multi-day creation, pause/continue, cross-device synchronization,
calendar movement, and role acceptance remain pending; no live Job was changed
by the automated tests. No Worker/schema change or Git commit/main integration
was performed.

### Added-workday move correction — build 21.1.54

An additional workday remains movable from Modify even after its parent Job has
started or is paused. Move Scheduled Day targets the selected added occurrence,
preserves the primary Job date, other workdays, status, and workflow state, and
rejects a destination day already used by the same Job. The existing pre-start
restrictions remain in place for moving the primary Job date. Two regression
tests cover correction of a paused Job's added workday and duplicate-day
rejection. The focused field/offline suite passed 42 tests with no failures.
The signed build passed strict signature verification and build 21.1.54 was
installed and launched on Tim-iPhone17pro. Physical acceptance remains pending.

### Per-workday time options — build 21.1.55

Every added or continuation workday now stores its own scheduling option:
Fixed Time, Arrival Window, Flexible Day, or Deadline. The Add Workday flow,
planned multi-day Job editor, and existing Job editor expose the appropriate
date/time controls for the selected option. My Day and calendar projections use
that occurrence's scheduling details, and moving an added workday preserves and
allows editing its option without changing the primary Job schedule. Legacy
multi-day records are upgraded from their saved dates using the Job's prior
scheduling mode, while the compatibility date list remains synchronized for
older clients.

Validation: the signed generic iOS build compiled and passed strict signature
verification. The 43-test field/offline suite passed before the final
serialization case was added, and the final 28-test field suite passed with no
failures, including all four time options through JSON synchronization,
arrival-window My Day projection, legacy decoding, continuation, movement, and
duplicate-day rejection. Build 21.1.55 installed and launched on
Tim-iPhone17pro. Cross-device and physical UI acceptance remain pending.

### Rapid-save synchronization hardening — build 21.1.56

Consecutive unattempted saves for the same record now coalesce into the newest
complete snapshot before upload, retaining the earliest verified base record
and revision. Compaction is permitted only while the record mutation remains
untouched and within the same server policy command. Workflow actions,
payments, intervening record intents, retries, and uploads that have already
started remain individually ordered and auditable.

The synchronization processor now observes newly queued work during an active
upload and immediately schedules the next ordered drain. A valid edit arriving
after the current processing snapshot is treated as pending work rather than a
false failed state. True retry delays, validation failures, and record
conflicts retain their existing blocking and review behavior.

Validation: 53 focused mutation-envelope, ordered synchronization, offline
workflow, and recovery tests passed with no failures. Coverage includes rapid
snapshot compaction, workflow barriers, causal revision rebasing, restart
recovery, unrelated-record progress, and a save arriving during an active
upload. The signed generic iOS build compiled and passed strict signature
verification. Build 21.1.56 installed and launched on Tim-iPhone17pro. Live
network timing and cross-device acceptance remain pending because the other
test devices were unavailable. No Worker/schema change or Git integration was
performed.

### My Day active-work ordering — build 21.1.57

My Day now groups the current day's work by operational priority. A Job that
has entered an in-progress workflow moves to the top even when it was
originally scheduled after another Job. Remaining untouched Jobs retain their
existing planned order. Technician-complete, completed, and cancelled Jobs
remain at the bottom, with the most recently completed work first within that
finished group. The list observes workflow and status changes so the movement
happens immediately after an action rather than requiring the screen to be
reopened.

Validation: two focused ordering regression tests passed on Tim-iPhone17pro,
covering both promotion of an active Job and demotion of a completed Job. The
full signed app compiled as part of the physical-device test run and passed
strict signature verification. Build 21.1.57 installed and launched on
Tim-iPhone17pro. Physical interaction acceptance and synchronization behavior
across another device remain pending. No Worker/schema change or Git
integration was performed.

### Paid invoice amount autofill — build 21.1.58

Selecting Paid in the invoice status picker now immediately fills Amount Paid
with the invoice total and shows a zero balance. The paid selection is honored
after any pending line-item or tax recalculation, so the saved payment matches
the final invoice total. Amount Paid is editable only while Partially Paid is
selected. Existing payment evidence remains protected: merely repricing an
already-paid invoice does not invent another collection or silently increase
the amount received.

Validation: all 11 InvoiceEngine tests passed on Tim-iPhone17pro, including
explicit full-payment selection, partial payment, zero-dollar closeout,
historical payment preservation, and corrected invoice totals. The signed app
passed strict signature verification. Build 21.1.58 installed and launched on
Tim-iPhone17pro. Physical UI acceptance and cross-device synchronization remain
pending. No Worker/schema change or Git integration was performed.

### My Day direct invoice printing — build 21.1.59

After Create Invoice succeeds, the My Day Job card now shows equal-width View
Invoice and Print buttons together. Print opens the existing Bluetooth receipt
printer selection directly, avoiding a trip through Invoice Detail. Before a
payment is recorded it prints the invoice; after payment creates a receipt it
prints the latest immutable receipt, matching the established Invoice Detail
behavior. The buttons remain available through payment and Job completion.

Validation: all five ReceiptEngine tests passed on Tim-iPhone17pro, including
the new invoice-before-payment and receipt-after-payment print selection case.
The full signed app compiled, passed strict signature verification, and build
21.1.59 installed and launched on Tim-iPhone17pro. Physical printer and card
layout acceptance remain pending. No Worker/schema change or Git integration
was performed.

### My Day invoice action sizing — build 21.1.60

The My Day invoice actions now use matching View Invoice and Print Invoice
labels. Both buttons share the same smaller 13-point semibold, single-line text,
minimum scaling behavior, equal width, and 34-point minimum height so the pair
renders consistently without one action appearing oversized.

Validation: the full signed app compiled and passed strict signature
verification. Build 21.1.60 installed and launched on Tim-iPhone17pro. Physical
card layout acceptance remains pending. No Worker/schema change or Git
integration was performed.

### Thermal receipt payment-method cleanup — build 21.1.61

Job-generated thermal receipts no longer print the redundant Method payment
row. The invoice payment workflow does not collect a payment method, so this
removes the misleading default Not Specified value while retaining Payment and
Balance information. The separate one-off Print workflow in Settings remains
unchanged.

Validation: all five ReceiptEngine tests passed on Tim-iPhone17pro, including a
new assertion that generated payment receipts contain neither Method nor Not
Specified. The full signed app compiled, passed strict signature verification,
and build 21.1.61 installed and launched on Tim-iPhone17pro. Physical printer
output acceptance remains pending. No Worker/schema change or Git integration
was performed.

### Long-form scrolling and synchronization performance — build 21.1.62

Long editable screens no longer compete with repeated full-database persistence
during synchronization. An incoming synchronization page now applies all of its
records first and performs one atomic local save, instead of rewriting and
re-encoding the complete workspace once for every downloaded record. Repeated
five-second account checks also stop publishing unchanged role, employee, and
access state. Invoice editing additionally uses interactive keyboard dismissal
so an active field does not impede a vertical scroll gesture.

Validation: two focused synchronization regressions passed on
Tim-iPhone17pro, proving that a multi-record remote page completes as one batch
without generating local mutations and that unchanged synchronization identity
updates produce no view publication. A production-optimized signed build
compiled and passed strict signature verification. Build 21.1.62 installed and
launched on Tim-iPhone17pro for representative scrolling acceptance. Physical
scrolling acceptance remains pending. No Worker/schema change or Git
integration was performed.

### Cross-screen scrolling redraw isolation — build 21.1.63

The scrolling investigation expanded beyond Invoice Detail after field testing
confirmed the same stutter on Job Detail and My Day with several jobs. The
shared synchronization queue no longer republishes every progress transition
as a change to the entire AppDataStore. Queue changes now refresh only the
Home, Operations, and Settings surfaces that display queue-derived status;
Invoice Detail, Job Detail, My Day job cards, and other unrelated screens are
not invalidated by background retry and synchronization bookkeeping.

My Day also caches its calculated daily start-time plan when the selected date
or agenda actually changes. Sorting, summary values, and job cards reuse that
plan instead of rebuilding the full daily schedule repeatedly during a single
SwiftUI render and scroll gesture.

Validation: three focused synchronization and redraw regressions passed on
Tim-iPhone17pro, proving queue progress remains observable without republishing
the whole AppDataStore, incoming remote records persist once per completed
page, and unchanged identity checks remain silent. The production-optimized
signed app compiled and passed strict signature verification. Build 21.1.63
installed and launched on Tim-iPhone17pro. Physical scrolling acceptance on
Invoice Detail, Job Detail, and a multi-job My Day remains pending. No
Worker/schema change or Git integration was performed.

### Active-screen rendering isolation — build 21.1.64

Frame-by-frame review of a physical-device screen recording confirmed that
Invoice Detail, Job Detail, and My Day shared the same stop-and-jump scrolling
pattern after the synchronization-specific redraw fixes. The common app shell
was retaining all five primary sections in one ZStack and hiding four with
opacity. Those invisible Home, Sales, My Day, Service, and Settings trees still
participated in SwiftUI layout and observation while the user scrolled the
visible screen.

The primary section host now mounts only the selected section. Inactive sections
no longer lay out or react to synchronization and status publications behind an
unrelated form or agenda. Existing access restrictions, notification routing,
custom navigation, and tap-again-to-reset behavior remain in place.

Validation: the production-optimized app and embedded Watch app compiled
successfully. The signed application passed strict signature verification, and
its packaged build number was confirmed as 21.1.64. Build 21.1.64 installed and
launched on Tim-iPhone17pro. Physical scrolling acceptance on Invoice Detail,
Job Detail, and a multi-job My Day remains pending. No Worker/schema change or
Git integration was performed.

### Long record editor rendering — build 21.1.65

A second physical-device recording showed that active-screen isolation improved
My Day, but Job, Invoice, and other long record editors still advanced in short
bursts separated by visible pauses. The long Job editor was rebuilding the
complete workflow context repeatedly during one SwiftUI render, including the
timeline and lifecycle calculations. It now creates one workflow snapshot and
reuses it across the timeline, time details, correction controls, and workflow
card.

Invoice rendering no longer JSON-encodes both complete invoice records merely
to determine whether the Save toolbar button should be disabled. Save remains
available, while the unsaved-change comparison runs only when dismissal or a
payment-correction action actually requires it. Job, Invoice, and Estimate
editors now use the lighter lazy inset-grouped list container while retaining
their grouped form appearance and existing controls.

Validation: the production-optimized app and embedded Watch app compiled
successfully. The signed application passed strict signature verification, and
its packaged build number was confirmed as 21.1.65. Build 21.1.65 installed and
launched on Tim-iPhone17pro. Physical long-form scrolling acceptance remains
pending. No Worker/schema change or Git integration was performed.

### Field-build coverage instrumentation removal — build 21.1.66

Frame-by-frame review of a third physical-device recording, together with the
reported two downward and three upward continuous swipes, confirmed that the
remaining pauses were true animation hitches rather than separate short scroll
gestures. The resolved Release build settings showed that normal field builds
were still compiling the complete app with test code-coverage instrumentation.
That instrumentation inserts counters throughout the application and is not
appropriate for the production-optimized app used for physical acceptance.

Code coverage is now explicitly disabled for the Release app and embedded Watch
targets. Automated test runs can continue to request coverage independently,
while installed field builds retain whole-module optimization without the
per-function coverage counters or mapping data.

Validation: a fresh DerivedData compile confirmed that the Release Swift
compiler command contains optimization but no profile-generation or
coverage-mapping flags. The resulting application binary contains no LLVM
coverage sections. The app and embedded Watch app compiled successfully, the
signed application passed strict signature verification, and its packaged build
number was confirmed as 21.1.66. Build 21.1.66 installed and launched on
Tim-iPhone17pro. Physical scrolling acceptance remains pending. No
Worker/schema change or Git integration was performed.

### Physical-device hitch isolation — build 21.1.67

An Animation Hitches recording on Tim-iPhone17pro identified two periodic UI
stalls that visual recording alone could not distinguish. A 15-second decline
review poll was publishing progress through an object observed by My Day,
causing the complete daily agenda and scheduling-conflict calculation to run
again. Synchronization receipt handling also repeatedly scanned the durable
operation queue on the main actor.

My Day now observes only the inputs that can change its displayed agenda,
calculates that agenda once per relevant change, and does not redraw for
background decline-review polling. Conflict and quarantine receipt processing
now builds queue indexes once per response and avoids unnecessary revision
writes and retry synchronization requests.

Validation: the production-optimized signed app and embedded Watch app compiled
successfully, passed strict signature verification, and build 21.1.67 installed
and launched on Tim-iPhone17pro. A focused follow-up trace confirmed the costly
daily-agenda recalculation no longer dominated the periodic stall. The trace
also exposed a separate mileage persistence pause, addressed in build 21.1.68.
No Worker/schema change or Git integration was performed.

### Mileage persistence scrolling isolation — build 21.1.68

The build 21.1.67 focused trace measured two remaining main-thread microhangs of
348.13 ms and 318.54 ms, approximately one mileage polling interval apart. Both
were caused by MileageTripRepository encoding the complete stored trip and GPS
point history on the UI actor during an otherwise routine cloud poll.

Mileage polling now skips persistence when a response changes no durable state.
When a synchronization response does require persistence, the immutable mileage
snapshot is JSON-encoded and atomically written on a utility task rather than
the main actor. Foreground save and reload semantics remain unchanged.

Validation: the production-optimized app and embedded Watch app compiled
successfully, the signed application passed strict signature verification, and
its packaged build number was confirmed as 21.1.68. Build 21.1.68 installed and
launched on Tim-iPhone17pro. A 25-second focused Animation Hitches trace crossing
the mileage polling boundary reported zero microhangs, zero main-thread mileage
persistence samples, and a longest potential interaction delay of 54.34 ms.
The preceding trace contained two microhangs and repeated mileage persistence
samples. All four MileageTripRepository regression cases passed in the iPhone
17 Pro simulator (persistence reload, active-trip checkpoint recovery,
classification reversal, and month-to-date mileage). Hands-on scrolling
acceptance was confirmed on Tim-iPhone17pro on November 5, 2026. No
Worker/schema change was required for this performance correction.

### Phase 21 branch preservation validation — November 5, 2026

Before preserving the accumulated Phase 21 working set in Git, the complete
iOS unit-test target ran against the iPhone 17 Pro simulator. All 398 test cases
passed. The Cloudflare Worker and tenant-isolation suite passed all 103 cases,
and the migration-safety suite passed its validation case. The final signed
Release app and embedded Watch app compiled successfully, passed strict
signature verification, and build 21.1.68 remained installed on
Tim-iPhone17pro.

The repository audit classified the Phase 21 iOS, Watch, Worker, migrations,
tests, architecture documentation, and this workbook as project work. Local
diagnostics, build products, rendering output, artwork packages, artwork helper
scripts, and Wrangler cache data were preserved in the working directory but
excluded from the Phase 21 commit. Main-branch integration remains a separate
explicitly authorized step.
