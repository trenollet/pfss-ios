# Synchronization Focused Conflict Review

## Purpose

Phase 20 Step 6 limits Manager and Owner review to consequential changes that
PFSS cannot merge deterministically. Routine independent edits, append-only
facts, derived values, and stale-device convergence remain automatic.

## Review Contract

- The Worker derives conflicting fields from the mutation's common-base,
  intended-device, and current-cloud records. Client-supplied field labels are
  fallback evidence for legacy envelopes only.
- The inbox shows the common-base, employee-device, and PFSS Cloud values for
  each unresolved field, plus a plain-language operational impact.
- A resolution reason of at least ten characters is required.
- Every decision records the policy version, resolver identity and role,
  affected fields, reason, original and final revisions, and timestamps.
- Managers and Owners may resolve conflicts. Members cannot list or resolve the
  tenant conflict inbox.

## Atomic Resolution

Migration `0024_phase20_focused_conflict_resolution.sql` adds the durable
conflict policy version. A resolution uses one D1 batch transaction to:

1. compare-and-set the unresolved conflict against the reviewed cloud revision;
2. update the canonical record when the authorized decision keeps the device
   version;
3. preserve the employee search index when an employee record changes;
4. create exactly one idempotent synchronization receipt;
5. append exactly one tenant change-feed entry; and
6. write the immutable access audit event.

If the cloud record changes after the reviewer opens the decision, PFSS rejects
the stale decision and refreshes the stored cloud comparison. A repeated
request for an already completed decision returns the existing result without
creating a second mutation or feed event.

## Device Convergence

The existing source-device resolution receipt and normal tenant change feed
remain the propagation paths. The originating queued conflict is resolved or
removed when its receipt is applied, while every other device receives the
accepted canonical representation through its durable cursor.

## Verification

- Worker regression includes focused same-field detection, independent-field
  exclusion, required reasons, Manager/Owner authorization, stale-review
  rejection, policy-version audit evidence, idempotent retry, and exactly-once
  change-feed propagation.
- iOS coverage verifies common-base/device/cloud comparison and hides an
  independent cloud-only edit from human review.
- The complete iOS unit-test target passed 265 tests on the iPhone 17e
  simulator. Signed builds and installation passed on an iPhone17e and iPad Pro
  mini.
- Migration `0024` and Worker version
  `8a61706f-a560-49af-a8cd-901d25daa2d9` are deployed to PFSS staging.
- Signed iPhone/iPad acceptance passed on 2026-08-22. A non-manager iPad
  originated a same-field customer conflict; a Manager/Owner iPhone reviewed
  and resolved it; both devices converged and the originating conflict cleared.
