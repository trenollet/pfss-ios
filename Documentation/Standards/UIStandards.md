# PFSS UI Standards

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-08-08

## Purpose

Define reusable interaction and visual rules so PFSS feels predictable across customers, estimates, jobs, invoices, scheduling, reporting, and administration.

## Development Build Identification

- Keep the public marketing version independent from internal development
  tracking.
- Use a three-part numeric build number in the form
  `phase.step.iteration`.
- Example: `18.6.1` means Phase 18, Step 6, first device build.
- Increment only `iteration` for each subsequent device build within the same
  Phase and Step. Reset it to `1` when moving to a new Step.
- Display the full build number in Settings so field testers can immediately
  confirm whether a device is current.
- Before every multi-device push, update both Debug and Release values of the
  primary app target to the same build number.

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
- When an editing screen has unsaved changes, intercept its Back or Cancel
  action and offer exactly three outcomes: Save Changes, Discard Changes, or
  Continue Editing.
- Keep Cancel, Archive, Delete, and other destructive actions visually separate from Save.
- When the keyboard is visible, show its dismissal control in the top-right
  navigation toolbar immediately to the left of Save. Never add a keyboard
  accessory-bar Done button.
- On pages without Save, show the keyboard dismissal control in the top-right
  only while the keyboard is visible.
- Use `EditorKeyboardDismissAction` for this behavior rather than defining a
  screen-specific keyboard button.
- Center every Archive action using `CenteredArchiveActionLabel`, with the
  destructive red treatment supplied by the containing button.
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
- Use the same selection control for a field in both create and edit screens;
  employee and salesperson assignments must use active-employee pickers, not
  free-text entry.
- Right-align picker controls within labeled form rows. Use an explicit
  label, spacer, and labels-hidden picker when a long label would otherwise
  force the control onto a second line.
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
- PFSS owns the five-area primary navigation presentation so Dashboard, Sales,
  My Day, Service, and Settings remain at the bottom on both iPhone and iPad.
- Keep each primary area mounted beneath the PFSS navigation presentation so
  switching areas preserves each area's navigation and presentation state.
- Selecting the already-active primary tab returns that area to its top-level
  landing page. Selecting a different tab preserves the destination state the
  user left in that area.
- When account access is held or suspended, hide operational destinations and
  return selection to an authorized destination immediately.

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

## Diagnostics

- Detailed presentation tracing is opt-in in Debug builds through the
  `PFSSPresentationDebugEnabled` user default.
- Release builds must not emit PFSS presentation tracing.
- Treat a platform-framework console message separately from a PFSS-owned
  invalid frame, constraint, or presentation-state defect; reproduce and trace
  the latter to the owning screen before changing layout code.
