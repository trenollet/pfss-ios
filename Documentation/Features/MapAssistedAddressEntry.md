# PFSS Map-Assisted Address Entry

- Status: Approved for Phase 18
- Owner: PFSS Project
- Last Updated: 2026-08-07

## User Goal

A field user standing near a property can select the building or map point and
use its address in a Lead, Customer, or Site without manually typing every
field.

## Workflow

1. Choose the map action beside an address editor.
2. Optionally center on the current location after granting permission.
3. Select or adjust the intended building or map point.
4. Review the reverse-geocoded structured address.
5. Correct any field and explicitly apply the result.
6. Save through the normal record workflow.

## Behavior

- Manual entry always remains available.
- Denying location permission does not block record creation.
- Weak accuracy, no result, multiple candidates, network failure, and offline
  conditions receive clear fallbacks.
- PFSS never treats a geocoder result as confirmed until the user accepts it.
- Existing addresses without coordinates remain valid.
- This feature does not enable background or continuous employee tracking.

## Privacy and Sync

PFSS requests the minimum foreground location permission only in response to a
user action. Confirmed address and optional coordinate metadata synchronize
inside the existing tenant and conflict boundaries.

## Completion Criteria

- Lead, Customer, and Site editors support the shared selection workflow.
- Permission-denied and geocoder-failure tests preserve manual entry.
- Existing data migrates without requiring coordinates.
- Signed iPhone and iPad map-selection tests pass.

## Related Documents

- `../Architecture/AddressSelectionService.md`
- `../Phase Development/Phase_18_Project_Workbook.md`
