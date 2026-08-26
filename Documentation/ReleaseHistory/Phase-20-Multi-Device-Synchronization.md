# Phase 20 Release History

## Multi-Device Synchronization Architecture

Phase 20 began as a replacement for broad whole-record conflict handling and
became a full live-device synchronization stabilization milestone. The work
moved shared authority to tenant-scoped server revisions and ordered feeds,
then added the client machinery required to survive offline work, stale local
state, malformed operations, duplicate delivery, and security changes without
silently losing accepted business data.

Product-owner testing on active production and test accounts repeatedly drove
the design. Clear Local Database exposed incremental-only recovery; real
assignment conflicts exposed the need for centralized quarantine decisions;
device troubleshooting led to consent-based server diagnostics; and induced
retry, divergence, and revocation conditions led to plain-language health
alerts and guided recovery. Each correction was exercised across signed iPhone
and iPad devices rather than accepted from a client-only mock.

The resulting architecture uses versioned mutation envelopes, a shared policy
contract, dependency-isolated queues, server-backed focused review, guarded
baseline recovery, signal-only push hints, operational health, migration
safety, and durable audit evidence. Late field testing also hardened recurring
work, role propagation, map selection, single-job moves, notification
containment, and invoice correction because those workflows depend directly on
trustworthy multi-device state.

The 20.7.29 closeout candidate passes 291 iOS tests, 83 Worker tests, the
fresh-D1 migration suite, TypeScript validation, and signed Owner, Manager, and
Technician acceptance. Formal closure awaits the final Sales-role device check
and repository integration. App Store deployment remains a Phase 25 activity.
