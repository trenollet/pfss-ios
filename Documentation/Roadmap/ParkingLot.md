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
