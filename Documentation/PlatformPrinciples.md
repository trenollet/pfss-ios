# PFSS Platform Principles

## 1. Workflow First

PFSS is designed around what the user is trying to accomplish, not around static records.

Every screen should answer:

> What does the user need to do next?

## 2. Optimize for Time-to-Completion

PFSS should compete on speed and clarity, not raw feature count.

The goal is not to have every feature imaginable. The goal is to help users complete field service workflows quickly and correctly.

## 3. Never Interrupt the Workflow

Users should not be forced to leave their current task to create related data.

Examples:

- Create customer from estimate
- Create site from customer
- Create job from site
- Create catalog item while adding work
- Create invoice from completed job

## 4. Personas Adapt the UI

Roles determine permissions. Personas determine experience.

A user may have multiple roles and may switch personas based on what they are doing at that moment.

## 5. Business Logic Lives in Engines

Views should display and orchestrate. Engines should decide.

Examples:

- PricingCalculator
- CatalogRankingEngine
- Future RecommendationEngine
- Future RoutingEngine
- Future SchedulingEngine

## 6. Explainable Engines

Every engine should eventually be able to explain its decisions.

Examples:

- Why did this catalog item rank first?
- Why was this technician suggested?
- Why was this route chosen?
- Why was this recommendation shown?

## 7. Rule of Three

Do not generalize because something might be reused.

Generalize after the same pattern appears three times and the abstraction has earned its place.

## 8. Small Commits, Big Milestones

Commits should be focused. Milestones should represent complete capabilities.

## 9. Every Feature Should Make the Next Feature Easier

Reusable architecture compounds. Each feature should strengthen the platform rather than create isolated complexity.
