# ADR-001: Modal Presentation Ownership

- Status: Accepted
- Date: 2026-07-11

## Context

PFSS originally allowed reusable child views such as `WorkOrderEditorView` and `LineItemListView` to own and present SwiftUI sheets directly. Some of those sheet modifiers were attached to `Section` or list-backed content inside a `Form`.

This caused repeated presentation attempts, console warnings such as `which is already presenting`, the Add Line Item picker appearing and immediately dismissing, and a recurring two-tap requirement.

## Decision

Modal presentation state belongs to the nearest stable parent screen or coordinator, not to transient list rows, `Section` views, or reusable child components.

Reusable child views will:

- Render content.
- Raise intent through callbacks such as `onAddLineItem` and `onEditLineItem`.
- Avoid owning `.sheet`, `.fullScreenCover`, or navigation presentation state unless the child itself is the stable screen root.

Stable parent screens will:

- Own one active presentation route.
- Attach sheet modifiers to a stable container such as `NavigationStack`, the screen root, or a dedicated coordinator.
- Present only one modal route at a time.

## Consequences

### Positive

- Eliminates duplicate presentation hosts.
- Prevents two-tap sheet behavior.
- Makes presentation flow easier to debug.
- Keeps reusable views focused on rendering and intent.
- Establishes a scalable pattern for future customer, site, photo, signature, payment, and printer pickers.

### Tradeoffs

- Parent screens require additional routing state and callbacks.
- Some presentation code is repeated until a shared coordinator is introduced.

## Current Application

This decision is implemented in:

- `EstimatesView`
- `EstimateDetailView`
- `JobsView`
- `JobDetailView`
- `WorkOrderEditorView`

`WorkOrderEditorView` now raises add and edit requests. Its parent owns the active sheet route.

## Follow-up

A future `PresentationCoordinator` may centralize modal routing while preserving this ownership rule.
