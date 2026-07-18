# PFSS Documentation

- Status: Active
- Owner: PFSS Project
- Applies To: v0.9+
- Last Updated: 2026-07-18

## Purpose

This folder is the permanent system of record for PFSS product direction, architecture, engineering standards, feature behavior, and important decisions.

## Sections

- `Product/` — vision, roadmap, parking lot, and release planning.
- `Architecture/` — system structure, durable technical boundaries, and platform design.
- `Standards/` — rules for implementation, user experience, naming, and Git workflow.
- `Features/` — detailed subsystem and workflow specifications.
- `Decisions/` — Architecture Decision Records (ADRs) explaining why significant choices were made.
- `ReleaseNotes/` — release-by-release user and developer notes.
- `ReleaseHistory/` — durable milestone snapshots and historical release records.

## Documentation Workflow

Every significant PFSS change follows this sequence:

1. Discuss the idea.
2. Record the decision in the appropriate document.
3. Implement the code.
4. Test the affected workflow.
5. Update roadmap, parking lot, release notes, and changelog as applicable.
6. Verify GitHub reflects the final decision.

## Classification Rule

Every durable document should primarily answer one question:

- Product — What are we building?
- Architecture — How is it built?
- Standards — How do we build it?
- Features — How does a capability behave?
- Decisions — Why was an important choice made?

Chat conversations are a design workspace. GitHub documentation is the long-term source of truth.