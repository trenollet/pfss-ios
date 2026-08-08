# PFSS Address Selection Service Architecture

- Status: Approved for Phase 18
- Owner: PFSS Project
- Applies To: Phase 18+
- Last Updated: 2026-08-07

## Responsibility

The Address Selection Service coordinates optional current-location access, map
point selection, geocoding, structured address candidates, and confirmation. It
does not continuously track employees or save records directly.

## Boundary

```text
Lead / Customer / Site Address UI
                 ↓ intent
        AddressSelectionService
                 ↓ candidate
Location Authorization + Map Selection + Geocoder
```

## Core Concepts

- `SelectedMapPoint`: coordinate selected by the user with optional accuracy.
- `AddressCandidate`: structured postal address, coordinate, source, and
  confidence or accuracy metadata.
- `AddressSelectionResult`: confirmed candidate or explicit cancellation.
- `AddressSelectionFailure`: permission, unavailable location, geocoder,
  network, or no-result failure suitable for user presentation.

## Rules

- Manual entry always remains available.
- Request current-location permission only after a user action that requires it.
- Map browsing and point selection should remain useful without current-location
  permission where platform services permit.
- A geocoded result is a candidate, never an automatically saved fact.
- The user must review and may correct the structured address before applying.
- Location capture does not activate job-scoped or background tracking.
- Views consume results; the service does not mutate `AppDataStore` directly.

## Persistence and Synchronization

Confirmed structured address fields remain authoritative business data.
Coordinates, selection source, and accuracy may be stored as optional metadata
when operationally useful. Existing records require no coordinate. Changes use
normal tenant-scoped offline synchronization and conflict review.

## Testing

Cover authorized, denied, restricted, and undetermined permission; weak or
missing location; successful and failed reverse geocoding; correction;
cancellation; offline fallback; existing records; and tenant-isolated sync.

## Related Documents

- `AppArchitecture.md`
- `../Features/MapAssistedAddressEntry.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
