# PFSS UI Standards

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-07-18

## Purpose

Define reusable interaction and visual rules so PFSS feels predictable across customers, estimates, jobs, invoices, scheduling, reporting, and administration.

## Core Experience

- Mobile-first and technician-first.
- Minimize taps and duplicate entry.
- Keep the next logical action obvious.
- Prefer consistency over cleverness.
- Preserve workflow context when creating related records.
- Support light and dark appearance with accessible contrast.

## Editing Screens

- Place the primary Save action in the top-right navigation toolbar.
- Keep Save visible while content scrolls.
- Disable Save when data is invalid or unchanged where practical.
- Handle unsaved changes consistently when leaving a screen.
- Keep Cancel, Archive, Delete, and other destructive actions visually separate from Save.
- Use clear navigation titles that identify the record or task.
- Avoid multiple competing primary actions.

## Action Roles

- Primary: advances or completes the current task.
- Secondary: optional supporting action.
- Success: confirms completion or payment.
- Warning: requires attention but is not destructive.
- Destructive: removes, archives, cancels, or irreversibly changes data.

Button meaning must not rely on color alone. Use labels, icons, placement, and confirmation where appropriate.

## Forms

- Group related fields into clear sections.
- Use concise labels and practical defaults.
- Keep common field order consistent across create and edit screens.
- Show validation near the affected field or action.
- Avoid burying required actions at the bottom of long forms.
- Use inline creation when leaving the workflow would create unnecessary friction.

## Lists and Rows

- Rows should communicate identity, status, and the most useful next information at a glance.
- Customer names should be shown where known; record numbers may appear as supporting context.
- Status indicators must be consistent across list and detail screens.
- Closed or completed work should be visually distinguishable without opening the record.
- Swipe and contextual actions should not duplicate or contradict visible primary actions.

## Navigation and Presentation

- Stable parent screens or coordinators own sheets and navigation presentation.
- Reusable child views raise intent through callbacks.
- Present one modal route at a time.
- Do not attach modal presentation to transient rows or list-backed sections.
- Preserve the user's current workflow when dismissing a picker or editor.

## Typography, Spacing, and Icons

- Use system typography and Dynamic Type.
- Establish a clear hierarchy for screen titles, section headings, labels, values, and supporting text.
- Use consistent form and card spacing.
- Use familiar SF Symbols and pair ambiguous icons with text.
- Avoid decorative shadows, corner radii, or color treatments that do not communicate hierarchy or state.

## Accessibility

- Support Dynamic Type and VoiceOver labels.
- Maintain adequate tap targets.
- Do not communicate state by color alone.
- Verify important actions and status treatments in light and dark appearance.
- Keep wording direct and understandable in field conditions.

## Adoption

Brick 10 will review existing editable screens and migrate them toward these standards. Reusable components should be introduced only after repeated patterns prove the abstraction.