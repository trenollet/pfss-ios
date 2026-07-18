# PFSS v0.9.1 – Workforce Management & Scheduling Foundation

## Overview

Version **0.9.1** marks a major architectural milestone for PFSS. This release introduced the foundation of Workforce Management and moved the application from simple record management toward operational planning.

Employee records became first-class entities, and jobs became linked to employees by persistent identifiers rather than free-text names. This established the groundwork for capacity planning, dispatch, calendars, route optimization, productivity reporting, and intelligent scheduling.

## New Features

### Workforce Management

- Employee management
- Create, edit, archive, and restore employees
- Employee search and filtering
- Employee detail view and persistent storage
- Configurable employee roles and work schedules
- Working-day and lunch-duration configuration
- Daily capacity calculation
- Employee schedule color assignment

### Job Scheduling

- Technician assignment using employee UUID relationships
- Primary and secondary technician selectors
- Duplicate-assignment prevention
- Persistent technician assignments
- Foundation for workload planning

## Architecture Improvements

- Relationship-based employee assignments
- Workforce persistence integrated into `AppDataStore`
- Capacity-engine foundation
- Separation between employee creation and employee management

## Foundation for Upcoming Features

- Technician calendars
- Manager scheduling dashboard
- Capacity planning and workload balancing
- Dispatch board and route optimization
- Vacation and availability tracking
- Productivity and estimated-versus-actual labor reporting
- AI-assisted scheduling

## Historical Significance

This milestone supplied the durable relationships required for PFSS to evolve from basic CRM functionality into a broader field-service operations platform.
