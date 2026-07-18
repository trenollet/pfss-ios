# PFSS Parking Lot

This document captures important improvements and future capabilities that are intentionally deferred so current releases can stay focused.

## Priority Before v1.0

### Persistent Save Actions

**Problem**

Save buttons are currently embedded inside long, scrollable forms. When a user makes a simple change, the Save action may be off-screen or difficult to locate, forcing the user to scroll up and down through the form.

**Target experience**

- Every editable screen should expose a consistent Save action in the top-right navigation toolbar.
- The Save action should remain visible while the form scrolls.
- Long forms should not require users to hunt for the Save button.
- The button should be disabled when the form is invalid or when there are no changes, where practical.
- Unsaved changes should be handled consistently when leaving a screen.
- Destructive actions such as Archive, Delete, or Cancel should remain visually separate from Save.

**Implementation direction**

Prefer a shared edit-screen pattern using a trailing navigation toolbar action, for example:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button("Save") {
            saveChanges()
        }
    }
}
```

Review all editable views before v1.0 and move their primary Save action into a persistent top-right toolbar position. Bottom form buttons may be removed or retained only when they provide useful redundancy without creating confusion.

**Priority**

High — complete before v1.0.

**Reason**

This is a cross-application usability issue affecting frequent, everyday editing workflows. A consistent persistent Save action will reduce friction, prevent missed saves, and make PFSS feel more predictable and professional.

---

### Closed Job Visual Status

**Problem**

Once a job reaches the final workflow state (**Invoice Complete**), it still appears visually similar to jobs that are merely scheduled, in progress, or awaiting invoicing. Users must open the record to determine whether the workflow is truly finished.

**Target experience**

- Jobs that have reached the **Invoice Complete** state should be visually identified as **Closed** throughout the application.
- Display a distinct badge, icon, color treatment, or other visual indicator that immediately communicates the job is fully complete.
- The indicator should be visible anywhere jobs are listed, including technician and office views.
- Closed jobs should remain searchable and viewable but be instantly distinguishable from active work.

**Implementation direction**

Introduce a dedicated visual "Closed" status that is derived from the existing workflow rather than creating another workflow step. When a linked invoice reaches the completed state, the job should automatically display as Closed anywhere it appears in the UI.

Possible visual treatments include:

- Gray "Closed" badge
- Checkmark icon
- Completed folder/archive icon
- Optional muted row styling

The underlying workflow remains:

```
Scheduled
↓
In Progress
↓
Completed
↓
Invoice Complete
```

The **Closed** indicator is simply the visual representation of the final workflow state.

**Priority**

Medium — after v1.0.

**Reason**

Technicians and office staff frequently scan job lists rather than opening individual jobs. Providing an immediate visual indicator reduces unnecessary navigation, improves workflow awareness, and gives the application a more polished, professional feel.
