# PFSS Developer Notes

## Development Rhythm

PFSS uses a three-sprint rhythm:

1. Feature Sprint
2. Architecture Sprint
3. Polish Sprint

A milestone release should follow once the feature is stable, the architecture is clean, and the user experience is acceptable.

## Current Engineering Direction

PFSS is moving toward a platform of reusable engines and focused SwiftUI components.

## Current Key Decisions

### WorkOrder Engine

Estimates, jobs, invoices, and receipts should share the same WorkOrder Engine wherever possible.

### Service Catalog

The Service Catalog provides defaults, not restrictions. Users must be able to adjust quantity, price, and description in the field.

### Catalog Ranking

Catalog search is evolving into ranking. Ranking answers:

> Which result is most useful right now?

### Explainable Engines

Engines should expose diagnostic output where useful. `CatalogRankingEngine.debugRanking()` is the first example.

## Notes for Future Refactors

- Move WorkOrder components into a feature folder.
- Create an Engines folder.
- Create a Documentation folder in the repository.
- Replace callback chains with a coordinator when workflow complexity increases.
- Consider unit tests for CatalogRankingEngine.
