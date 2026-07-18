# PFSS Project Principles

- Status: Active
- Owner: PFSS Project
- Applies To: All PFSS Work
- Last Updated: 2026-07-18

## Product Principles

### Workflow First

Design around what the user is trying to accomplish, not around static records. Every screen should answer: What does the user need to do next?

### Optimize for Time-to-Completion

PFSS competes on speed and clarity rather than raw feature count. Minimize taps, duplicate entry, visual clutter, and workflow interruption.

### Technician-First and Mobile-First

The phone is the primary workplace. Field workflows must remain obvious, fast, readable, and practical while moving, wearing gloves, working outdoors, or handling customer conversations.

### Never Interrupt the Workflow

Users should be able to create related data without abandoning the task in progress, such as creating a customer from an estimate or a catalog item while adding work.

### Personas Adapt the Experience

Roles determine permissions. Personas determine the visible experience and action emphasis. Shared business data remains consistent beneath adaptive presentation.

## Engineering Principles

### Preserve Existing Data

Every model evolution must remain migration-safe. Provide defaults, use backward-compatible decoding, restart the app during verification, and confirm existing records still load.

### Business Logic Lives Outside Views

Views collect input and present output. Engines perform durable business logic. Models store business data. Pricing, tax, ranking, scheduling, recommendation, and workflow rules do not belong in SwiftUI view bodies.

### Stable Parents Own Presentation

Modal presentation belongs to stable parent screens or coordinators. Reusable children render content and raise intent. See `../Decisions/ADR-001-Presentation-Ownership.md`.

### Store Business Intent Before Automating It

Capture durable classifications before adding complex automation. Item type and tax treatment are examples of intent that future engines can interpret.

### Explainable Engines

Where practical, engines should expose why they produced a result. Ranking, recommendation, scheduling, routing, and tax decisions should become inspectable rather than opaque.

### One Logical Change, Then Build

Make one coherent change, build, test the affected workflow, commit when stable, and push at a meaningful checkpoint.

### Fix Root Causes

Use instrumentation to gather evidence, but do not preserve architectural defects with timing delays, duplicate state, or repeated workarounds.

### Rule of Three

Do not generalize because something might be reused. Generalize after repeated patterns prove the abstraction is needed.

### Global State Has One Owner

Application-wide dependencies are created once at the application root and injected into descendants. Child views must not create duplicate global stores.

### Design for the Platform

Names, models, and engines should remain meaningful across multiple field-service industries.

### Every Feature Should Make the Next Feature Easier

Reusable architecture compounds. Each feature should strengthen the platform instead of creating isolated complexity.

## Documentation Principle

Documentation is part of the product. Durable decisions must be captured in GitHub; chat is not the system of record.