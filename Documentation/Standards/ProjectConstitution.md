# PFSS Project Constitution

- Status: Active
- Owner: PFSS Project
- Applies To: All Product, Design, and Engineering Work
- Last Updated: 2026-07-18

## Purpose

This constitution defines the durable principles that guide PFSS when requirements, designs, or implementation options compete. It is intentionally concise and should change rarely.

## Principles

### 1. Mobile-First, Technician-First

The phone is the primary workplace. Core field workflows must remain fast, readable, and practical in real working conditions.

### 2. Workflow Over Record Management

PFSS exists to help people complete work, not merely store data. Every screen should make the next useful action clear.

### 3. Time-to-Completion Over Feature Count

A smaller, clearer workflow is better than a larger, slower one. Reduce taps, duplicate entry, unnecessary navigation, and avoidable decisions.

### 4. Consistency Over Cleverness

Common tasks should behave the same throughout the application. Familiar patterns are preferred over isolated custom interactions.

### 5. Preserve Business History

Existing data must remain readable after model changes. Historical transactions retain the values, rates, assignments, and decisions that were true when they occurred.

### 6. Business Logic Belongs in Engines

Views collect input and present results. Models preserve durable data. Engines make reusable, testable, and explainable business decisions.

### 7. One Owner for Every State

Application-wide dependencies have one root owner. Workflow and presentation state belong to the nearest stable parent or coordinator capable of managing them correctly.

### 8. Reuse Must Be Earned

Do not generalize based on speculation. Extract reusable components and engines after repeated patterns demonstrate a real shared responsibility.

### 9. Every Feature Strengthens the Platform

New work should make later capabilities easier to build. Avoid isolated solutions that duplicate records, calculations, or workflow rules.

### 10. Documentation Is Part of the Product

Approved behavior, architecture, standards, and decisions belong in the repository. Chat supports design; GitHub is the permanent system of record.

### 11. Build, Test, and Preserve Trust

Make coherent changes, verify the affected workflow, inspect regressions and warnings, and preserve user confidence through predictable behavior.

## Decision Rule

When two valid approaches compete, prefer the one that better supports this constitution and document any significant exception in an ADR.

## Related Documents

- `ProjectPrinciples.md`
- `CodingStandards.md`
- `UIStandards.md`
- `GitWorkflow.md`
- `../Product/Vision.md`
