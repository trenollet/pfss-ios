# ADR-001: Modal Presentation Ownership

- Status: Accepted
- Date: 2026-07-11
- Last Reviewed: 2026-07-18

## Context

PFSS originally allowed reusable child views such as `WorkOrderEditorView` and `LineItemListView` to own and present SwiftUI sheets directly. Some sheet modifiers were attached to `Section` or list-backed content inside a `Form`.

This caused repeated presentation attempts, console warnings such as `which is already presenting`, Add Line Item appearing and immediately dismissing, and a recurring two-tap requirement.

## Decision

Modal presentation state belongs to the nearest stable parent screen or coordinator, not to transient list rows, `Section` views, or reusable child components.

Reusable child views will:

- Render content.
- Raise intent through callbacks such as `onAddLineItem` and `onEditLineItem`.
- Avoid owning `.sheet`, `.fullScreenCover`, or navigation presentation state unless the child is the stable screen root.

Stable parent screens will:

- Own one active presentation route.
- Attach presentation modifiers to a stable container such as `NavigationStack`, the screen root, or a dedicated coordinator.
- Present only one modal route at a time.

## Consequences

### Positive

- Eliminates duplicate presentation hosts.
- Prevents two-tap sheet behavior.
- Makes presentation flow easier to debug.
- Keeps reusable views focused on rendering and intent.
- Establishes a scalable pattern for future pickers and editors.

### Tradeoffs

- Parent screens require additional routing state and callbacks.
- Some presentation code may repeat until a shared coordinator is justified.

## Current Application

This decision is implemented in `EstimatesView`, `EstimateDetailView`, `JobsView`, `JobDetailView`, and `WorkOrderEditorView`.

## Follow-up

A future `PresentationCoordinator` may centralize modal routing while preserving this ownership rule.

## Related Documents

- `../Standards/UIStandards.md`
- `../Standards/ProjectPrinciples.md`
- `../Architecture/AppArchitecture.md`