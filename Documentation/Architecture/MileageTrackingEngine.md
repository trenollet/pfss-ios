# PFSS Mileage Tracking Architecture

- Status: Approved foundation for Phase 19
- Owner: PFSS Project
- Applies To: Phase 19+
- Last Updated: 2026-08-09

## Responsibility

Mileage tracking is a separate subsystem from foreground address selection and
route planning. It detects likely vehicle trips, validates GPS samples,
calculates actual driven distance, persists recoverable trip facts, and emits
events for notification, review, synchronization, and reporting.

```text
Low-power location + motion evidence
                  ↓
        Mileage Detection Engine
                  ↓
 Idle → Arming → Tracking → Stopping
                  ↓
       Durable unclassified trip
                  ↓
 Review / classify / correct / export
```

## Boundaries

- `TechnicianLocationManager` remains a foreground one-location service.
- `AddressSelectionService` remains a user-initiated map/geocoding service.
- `MileageDetectionEngine` contains deterministic detection and distance rules
  and imports no SwiftUI or Core Location APIs.
- A later `MileageLocationCoordinator` translates authorized Core Location and
  Core Motion events into `MileageTripPoint` values and manages battery modes.
- Persistence and synchronization consume completed engine events; the engine
  never writes directly to `AppDataStore` or the network.

## State Contract

- **Idle:** low-power monitoring and a stable anchor.
- **Arming:** displacement and speed qualify, but sustained evidence is pending.
- **Tracking:** route-quality points are accepted and accumulated.
- **Stopping:** meaningful movement has ceased; tracking completes after the
  approved dwell unless driving resumes.

## Privacy Contract

- Automatic tracking is disabled until the user explicitly opts in.
- Always authorization is requested only after foreground permission and the
  mileage explanation.
- Tracking state is visible and start/end notifications are user-facing.
- Personal trips are user-private. Tenant roles do not imply permission to
  inspect personal routes.
- Complete trip payloads synchronize only between devices enrolled to the same
  authenticated tenant member. The server derives that ownership and never
  trusts account or user identifiers inside a submitted payload.
- Authorized business summaries omit route geometry and Personal-trip facts.
- Collection, synchronization, retention, export, and deletion must remain
  purpose-limited and auditable.

## Durability and Offline Rules

- Active-trip state is checkpointed locally so suspension, restart, and
  connectivity loss do not duplicate or discard a trip.
- Completed trips receive stable UUIDs and enter the normal ordered offline
  synchronization path.
- A per-user change cursor supports fresh-device restoration, while durable
  deletion tombstones prevent stale devices from resurrecting removed trips.
- Classification corrections preserve timestamps and correction history.
- Manual trips are visibly marked and contain no fabricated GPS route.

## Initial Detection Defaults

- Start displacement: 30.48 meters (100 feet).
- Start speed: 4.4704 meters/second (10 mph).
- Sustained start evidence: three reliable consecutive samples.
- Stop speed: 1.34112 meters/second (3 mph).
- Stop dwell: 180 seconds.
- Maximum horizontal accuracy: 65 meters.

These defaults are versioned engine configuration, not UI constants.

## Delivery Sequence

1. Pure models, state machine, and tests.
2. Local active-trip checkpoint and trip repository.
3. Permission and battery-aware location/motion coordinator.
4. Background and notification lifecycle.
5. Trip queue, map review, classification, history, and manual entry.
6. Tenant/user-private synchronization and CSV reporting.
7. Signed-device accuracy, battery, offline, restart, and privacy acceptance.
