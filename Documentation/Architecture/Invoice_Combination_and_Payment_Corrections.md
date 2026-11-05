# Invoice combination and payment corrections

## Agreed workflow

Select multiple invoices, select the customer to bill, reserve a new invoice
number, and review all source services/materials and job references. On save,
retain the originals as Combined and redirect each job to the new invoice.

A Paid status and an automatically generated receipt are not independent proof
of collection. Require an explicit check of the collected amount for sources
with recorded payments, Paid status, or receipt history. This check is not
owner/manager-only; existing invoice access rules remain applicable. An amount
different from the recorded payment needs an explanation. Never issue another
receipt merely because a previously collected payment moves between invoices.

If a combination is wrong after another payment has been collected, use a
manual correction workspace: pool verified existing and additional collections,
break up/rebuild the affected bills, and explicitly allocate the pool. Display
Still Due for underpaid invoices and Refund Required for unallocated excess.
A refund request is not a completed refund and must not automatically alter
cash history. Collection and refund actions remain manual.

Mistaken collection checks are reversible through append-only adjustments with
an identified user, time, and reason. Earlier confirmations, receipts, and
allocation proposals remain unchanged. A new redistribution references the
previous one. Only the latest committed redistribution owns active allocations;
historical proposals must not be summed as additional payments.

## Implemented foundation (not a released UI)

`InvoicePaymentPoolEngine` validates cent-exact verified collections, unique
receipt and payment-event identities, legacy lump-sum duplication, signed
verification corrections, and conservation of funds during redistribution.
Additional disjoint, verified collections can join the same pool without
rewriting earlier evidence. Funds cannot be allocated twice to an invoice or
above its total; excess remains explicitly available for refund review.

`InvoiceCombinationEngine` creates a proposal retaining source invoices,
original receipt/tax evidence, job numbers, and source-to-new-line identities.
It does not reprice old charges for the newly selected billing customer, and
does not manufacture a common jurisdiction/rate for different job sites.
Paid amounts only contribute after an explicit collection check. Original
line-item discounts and measurement descriptions are preserved by copying.
When receipt history exists, its recorded payment amounts form the collection
review basis, so a legacy cap on cumulative amountPaid does not silently lose
overpayment evidence. Receipt history is still not proof of actual collection.

## Required integration before enabling combined-invoice saves

The proposal is intentionally not directly saved as an ordinary InvoiceRecord.
The current synchronization contract operates on individual records. Saving a
new invoice, marking sources Combined, redirecting jobs, and transferring
payment allocations as independent mutations would permit partial combinations
and double-counting during a conflict or concurrent operation on another device.

Add a tenant-scoped atomic combination/correction command with idempotency,
source revision checks, unique ownership of selected sources/collections, and
server-determined actor attribution. Revalidate customer access and invoice
authorization server-side, not from a supplied display name. Commit the entire
relationship/allocation change or none; source changes during review require a
fresh review. Persist append-only correction history and retain immutable source
tax evidence. Record genuine subsequent payments separately from transfers.

Then connect invoice selection, collection review, bill-to customer selection,
manual split/rebuild/allocation, job navigation, receipt presentation, PDF tax
breakdowns, and revenue summaries to the committed relationships. Exclude
superseded sources from collectible/invoiced totals without deleting their
historical receipts. Correction and refund requirements must remain visible
until explicitly resolved.

Validate legacy decoding, concurrent two-device selection of the same source,
offline queue retries, rejected/partial commands, mixed jurisdiction tax,
manual paid-status mistakes, additional combined-invoice payments, split and
redistribution, and refund/underpayment presentation before field acceptance.

## Foundation validation — September 16, 2026

The current source compiled and all 32 targeted XCTest cases passed on the
iPhone 17e iOS 26.5 simulator: 15 payment-pool cases, 10 combination-proposal
cases, and 7 existing invoice-engine regression cases. Coverage includes
duplicate receipt/event rejection, cent precision, mistaken collection checks,
append-only verification adjustments, later collections, manual allocation,
refund/underpayment calculations, preserved source references, mixed-site tax,
legacy overpayment evidence, and Codable round trips.

This is foundation validation only. No Combine/correction UI or synchronization
command has been released, no phone was updated, and no live financial record
was changed. Device field tests, PDFs, synchronization, and user acceptance are
still unverified. The app's device build remains 21.1.43.

## UI review stage — build 21.1.44

All Invoices now includes a blue Combine button with white text. Entering
selection mode clears status/date/search filters, shows selectable circles,
hides share/edit actions, and disables archiving. The button stays gray until
at least three invoices are selected, then becomes green. Cancel clears the
selection; unavailable/deleted invoices are removed from it. Paid and unpaid
active invoices are eligible; void and archived invoices remain ineligible.

The next sheet supports billing-customer selection, explicit collected-amount
checks without a manager-only gate, discrepancy notes, and a combined-invoice
preview showing source items, quantities/rates, discounts, per-site tax, job
numbers, payment carryover, amount due, and any refund requirement. Source
changes during review require reopening the selection. No invoice number is
consumed and no financial record is mutated. Saving remains disabled and the
screens explicitly state this is an unsaved review.

All 35 targeted simulator tests passed (the prior 32 plus three selection-state
tests). The generic iOS build passed signature verification and build 21.1.44
installed on Tim-iPhone17pro and iPhone17e. Visual field acceptance and actual
combination persistence/synchronization remain unverified.
The app launched successfully on iPhone17e; launch on Tim-iPhone17pro was
denied because the phone was locked. Installation is not launch evidence.

## Selection threshold correction — build 21.1.45

The user corrected the minimum to two invoices, not three. Continue now
activates at two or more selections, remains active when three becomes two,
and disables when selection drops below two. The list instruction and
selection-state regression tests were updated to match. Review-only saving
restrictions are unchanged.
All three selection-state regression tests passed on the iPhone17e simulator.
Build 21.1.45 compiled, passed signature verification, and installed and
launched successfully on both Tim-iPhone17pro and iPhone17e. Visual acceptance
and combination persistence/synchronization remain unverified.

## Initial atomic save implementation — September 16, 2026 (unreleased)

The review screen now prepares one online-only, tenant-scoped save request.
It reuses company invoice numbering with a reserved `-C` suffix. Customer and
source invoices must be synchronized; pending source/customer edits require
synchronization first. No local source or receipt changes occur before the
server commits. A retry within the review uses the same request identity/body.

Migration 0032 adds commit receipts and unique source/payment-event claims.
The new `/v1/invoices/combine` command checks the billing customer, source
revisions and exact snapshots, original charge/line provenance, job references,
explicit collected-amount confirmations, and cent-exact allocation. The D1
batch commits the new bill, original markers, operation history and tenant
change feed together or none. Actor identity is supplied by authentication,
not a client display name. Ordinary members retain existing invoice access.

Original invoices retain all receipts and payment evidence. They use the
legacy-compatible Void raw value plus `combinedIntoInvoiceID`; new UI displays
Combined. This prevents older clients from counting them as collectible
charges. All job invoice lookups resolve the combined invoice. Normal writes
cannot strip provenance, edit source charges, erase later receipt evidence,
reuse carried payment events, reduce combined payments or void the combination.
Charge changes require the future atomic correction command.

The app applies the committed records in one snapshot without enqueuing
individual edits or issuing transfer receipts. Incomplete receipts and local
source edits during the save cannot partially apply. A historical retry receipt
does not overwrite an already synchronized combined invoice's newer payments.
Revenue collection retains the original receipt/paid date for verified
carryover rather than treating combination day as a new collection. For a
disputed partial collection check against multiple receipts, earliest receipts
are attributed first; unknown legacy payment dates are not invented.

PDF output shows all jobs, original invoice/job attribution on each copied
line, original per-source tax jurisdictions/amounts and aggregate tax. Page
space checks prevent the summary/notes overlapping the footer.

Validation: 44 targeted simulator tests passed (15 pool, 10 proposal, 7 invoice
regressions, 6 persistence, 4 revenue and 2 PDF cases). All 94 Worker tests,
including nine atomic-save cases, passed. The migration preservation test and
TypeScript checks passed. The two-page combined PDF fixture was rendered and
visually inspected. These are local tests, not live synchronization acceptance.
The final generic iOS build also passed with signing disabled; this is compile
evidence only, not a signed install or physical-device validation.

Release gate: the reversible manual split/rebuild/payment redistribution UI
and atomic correction command remain unimplemented. Migration 0032 and the
new Worker command have NOT been deployed. No live invoices were combined,
no phones were updated, and their installed build remains 21.1.45. Do not
enable live financial combinations until correction, deployment review and
cross-device acceptance are completed; the next shipped app change needs a
new build number.

## Reversible correction rollout — build 21.1.46

Invoice details now opens Split & Redistribute Payments for the combined bill
or any restored invoice in its payment group. The workspace can split all,
retain two or more original invoices, add an eligible replacement invoice,
and choose the billing customer. It preserves original charges, line-item
measurement descriptions/discounts, site taxes and invoice identities. A
retained combined bill keeps its existing number; no duplicate bill is created
when rebuilding it. Standalone job links return to their original invoices.

Users explicitly verify actual collections, including later receipt events,
correct earlier confirmations through append-only signed adjustments, and
manually allocate the pool to the resulting invoices. There is no owner-only
gate. A final confirmation shows total Still Due and Refund Required; a refund
remains a request for manual action, not evidence of returned cash. Every old
verification and redistribution remains visible through Correction History.
Only the latest redistribution owns the active allocations.

Migration 0033 and `/v1/invoices/correct-payments` provide the tenant-scoped
atomic correction command. It checks all canonical revisions/snapshots and
historical prefixes, cent-exact funds and allocations, unique receipt/event
ownership, original line/tax evidence, and authenticated attribution. Its batch
commits all resulting invoices, correction history and change-feed records or
none. Repeated identical requests return the same receipt; conflicting devices,
changed requests, forged evidence and late SQL claim failures cannot partially
commit. Existing notes, dates, lifecycle and actual receipts are retained.

Invoice source/payment ownership stays with the group after splitting; these
invoices use this workspace for subsequent regrouping, rather than a new
Combine command that could count transfers as new cash. Additional actual
payments still use the normal invoice payment entry and create receipts only
for the new money. Future corrections verify these disjoint receipt events.
Separately verified later receipt collections may follow a legacy lump sum,
but another unreferenced legacy lump sum is rejected. Independent edits cannot
erase group evidence, change historical charges or reduce paid money outside
the correction workspace.

Revenue summarizes each group's actual verified collection once, on original
collection dates, regardless of which current invoices receive allocations.
Archived invoices remain available as historical payment evidence, but their
charges/balances do not enter active invoiced/outstanding totals. A fully split
root is labelled Split and retained for audit; it cannot generate a bill PDF.
Restored/current bills print their corrected balance and normal original tax.
The restored PDF fixture was rendered and inspected with no footer overlap.

Validation: all 54 targeted simulator tests passed (the prior 44 plus ten
correction cases), all 102 Worker tests passed, the migration preservation test
passed, and TypeScript checks passed. The signed generic iOS build passed
signature verification. These do not constitute live synchronization acceptance.

Rollout: a restricted-permission database export was saved before changing the
staging schema. Remote migrations 0032 and 0033 applied successfully. Worker
version `28c259b2-440c-4c7e-9207-76996270c45f` deployed and `/health` returned
OK. Installed build 21.1.46 on Tim-iPhone17pro and iPhone17e. No live financial
record was combined, split or paid by these implementation tests. Cross-device
field acceptance remains pending. No Git commit/main integration was performed.
The app launched successfully on iPhone17e. Launch on Tim-iPhone17pro was
denied because it was locked; installation is not launch or sync evidence.
Read-only staging checks confirmed zero combination/correction commits after
rollout, so no live financial group was created by deployment validation.

## Numbering follow-up — build 21.1.47

The existing monthly/device numbering engine is still authoritative. The
combined namespace additionally skips any `-C` number already synchronized
from another device. Server-side uniqueness remains the final concurrent-save
guard. All seven persistence cases passed, including the new synchronized-number
collision regression. The signed build passed signature verification. This
client-only follow-up requires no further schema or Worker deployment.
Build 21.1.47 installed on both phones and launched on iPhone17e. Launch on
Tim-iPhone17pro remained blocked by its lock screen. Field synchronization and
user acceptance remain pending; no live invoice was changed for testing.

## Legacy item compatibility — build 21.1.48

Following a field-reported combination rejection, read-only staging inspection
confirmed older invoice items omit the later discount fields. Swift's item
decoder materializes `Dollar Amount`, zero discount input and zero estimated
minutes when these fields are missing. Strict server snapshot equality treated
that round trip as a changed invoice. A regression reproduced the rejection.
Financial comparisons now recognize only these documented item defaults,
including items nested in receipts/history. Original stored evidence is not
rewritten. Exact revision checks, transactional CAS, payment ownership and
byte-semantic request hashes remain unchanged; changed prices and discounts
remain rejected. This applies to combination, correction and read-only guards.

Server snapshot mismatches now have distinct error codes. Client messages no
longer blame another device for every rejection: missing customer, number
collision, record changes and mismatched details have separate explanations.
The screenshot alone did not expose the original request's specific code.

All nine targeted simulator persistence tests passed, including the Swift
legacy-item round-trip and distinct save-message regressions. All 103 Worker
tests, TypeScript checks and migration preservation passed.
The signed build passed signature verification. Worker version
`1666dc7e-3b60-43b1-a860-e3fdef0f7d29` deployed successfully and health returned
OK; no schema change was needed. Build 21.1.48 installed and launched on both
Tim-iPhone17pro and iPhone17e. Actual combination save/reopen/cross-device
acceptance is pending the user's retry. No live financial record was modified
by implementation validation, and no Git commit/main integration was made.

## Zero-dollar closeout — build 21.1.49

An explicit Paid selection on a zero-dollar invoice now survives editor
recalculation. It records zero paid, zero balance and a closeout date without
creating a payment receipt. New zero-dollar drafts remain open until explicitly
closed; Void bills remain Void. Existing positive-dollar payment/repricing
rules and immutable evidence are unchanged. This is a client-only engine fix;
no Worker/schema deployment or live financial record mutation is required.

Validation: all 28 targeted simulator tests passed (invoice engine, combination
persistence and payment corrections), including two zero-dollar regressions.
The signed build and signature verification passed, and build 21.1.49 installed
on both phones. Both phones launched successfully (Tim-iPhone17pro after a
transient tunnel failure and retry). User closeout/synchronization
acceptance remains pending; no live invoice was changed for implementation tests.
