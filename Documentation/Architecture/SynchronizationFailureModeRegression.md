# Synchronization Failure-Mode Regression

## Purpose

This suite proves that synchronization failures remain contained, recoverable,
and observable without allowing one malformed or delayed change to block
unrelated company work. Automated tests use isolated local databases and do not
modify a live tenant.

## Coverage Matrix

| Failure mode | Automated proof | Signed or live proof | Remaining acceptance |
| --- | --- | --- | --- |
| Concurrent online edits | Independent fields merge; contradictory fields create focused review; same-device causal revisions chain correctly | Earlier Owner/employee two-device change propagation passed | Repeat one independent-field edit and one contradictory-field edit on build 20.7.19 |
| Extended offline use | A 250-operation queue survives persistence reload with stable IDs, idempotency keys, order, and one submission per operation | Focused test passed on iPhone17e | Run a small human-readable offline workflow on the employee iPad |
| Older application payloads | Legacy whole-record compatibility, missing inner record IDs, schema-contract checks, and canonical recovery regressions | Build 20.7.19 recovered the live tenant | No destructive older-build installation is required unless release policy adds a supported-version floor |
| Duplicate delivery | Queue enqueue and server acceptance are idempotent; concurrent processor signals submit once | Focused concurrent-signal test passed on iPhone17e | None |
| Out-of-order delivery | Server orders changes by tenant sequence rather than device timestamp and resumes after an exact cursor | 79-test Worker suite passed | None |
| Partial failure | Rejected input consumes no cursor; permanent local failure blocks only its dependency group; unrelated work continues | Existing quarantine and repair acceptance passed | Exercise one controlled validation failure only if product-owner acceptance requires a visible-device check |
| Suspension | Server immediately denies suspended credentials while preserving tenant data; client presents suspended cloud access | Earlier lifecycle acceptance passed | Optional current-build confirmation using a disposable employee membership |
| Revocation | Revoked credentials are denied; required local removal precedes synchronization; replacement enrollment is isolated | Earlier revoked-device cleanup acceptance passed | Optional current-build confirmation using a disposable employee membership |
| Fresh-device bootstrap | Canonical baseline, cursor-zero pull, and no-republish regressions | Wiped iPhone11 Pro rebuilt the full tenant on build 20.7.19; case `PFSS-PU5H-M6BG` | None |

## New Phase 20 Regression Scenarios

The Worker failure-mode regression submits a valid operation with a newer
device timestamp, rejects malformed input, submits a second valid operation
with an older device timestamp, and replays the first operation. It proves:

- accepted changes remain in server tenant-sequence order;
- rejected input creates no sequence gap;
- duplicate replay creates no second stored operation or feed event; and
- resuming after the first sequence returns exactly the second change.

The client regression triggers synchronization concurrently from two signals
and proves the operation is submitted once. A separate stress case queues 250
offline changes, reconstructs the queue from durable persistence, and proves
stable identity, exact ordering, and one successful attempt per operation.

## Validation Evidence

- Worker regression: 79 tests passed.
- TypeScript validation passed.
- Signed generic iOS test build passed.
- Two focused tests passed on iPhone17e with zero failures.
- No live tenant record was created, edited, rejected, or removed by these
  automated failure-mode tests.

