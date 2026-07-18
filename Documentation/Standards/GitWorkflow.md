# PFSS Git and Documentation Workflow

- Status: Active
- Owner: PFSS Project
- Applies To: All Development Work
- Last Updated: 2026-07-18

## Standard Sequence

```text
Decision
  ↓
Documentation
  ↓
Code
  ↓
Build and Test
  ↓
Commit and Push
  ↓
Release Documentation
```

## Beginning a Session

Review the active roadmap, parking lot, applicable standards, architecture documents, ADRs, and feature specifications before changing code.

## During Design

Use discussion to explore the problem. Once direction is approved, update the correct permanent document before implementation:

- New capability → Feature specification
- Release sequencing → Roadmap
- Deferred idea → Parking Lot
- Reusable UI rule → UI Standards
- Engineering rule → Coding or Project Principles
- Significant architectural choice → ADR

## Implementation Rhythm

1. Make one logical change.
2. Build.
3. Test the affected workflow.
4. Inspect warnings and regressions.
5. Commit when the change is coherent and stable.
6. Pull with rebase before pushing when required.
7. Push at a meaningful checkpoint.

Suggested commands:

```bash
git status
git add .
git commit -m "Meaningful commit message"
git pull --rebase origin main
git push origin main
```

## Commit Guidance

- Keep commits focused.
- Use messages that describe the durable result.
- Do not mix unrelated cleanup with feature work.
- Milestone tags represent completed capabilities, not arbitrary checkpoints.

## Completing a Brick

Update the roadmap status, release notes, changelog or release history, applicable feature documents, standards, and ADRs. Remove completed items from the parking lot or mark them as scheduled elsewhere.

## Verification Rule

Before ending a substantial session, confirm:

> Does GitHub now reflect what we decided and what was actually built?

The session is not complete until the answer is yes.