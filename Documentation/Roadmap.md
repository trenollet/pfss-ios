# PFSS Roadmap

## v0.6 - Complete WorkOrder Engine

Status: Completed

Highlights:

- Shared WorkOrder Editor
- Editable line items
- Edit, duplicate, delete line items
- Service Catalog integration
- LineItemListView
- LineItemRowView
- WorkOrderTotalsView

## v0.7 - Intelligent Service Catalog

Status: In Progress

Goals:

- CatalogRankingEngine
- Token-based ranking
- Initialism matching
- Ranking diagnostics
- Smarter search ordering
- Recently used services
- Frequently used services
- Foundation for contextual recommendations

Future v0.7 phases:

- Frequently used together
- Customer history suggestions
- Workflow-context suggestions

## v0.8 - Invoice Engine

Planned goals:

- Invoice model
- Create invoice from job
- Invoice line items from WorkOrder Engine
- Payment status
- Balance due


## v0.9.5 B1-8 - Workflow Improvements

* ✅ Route Optimization
* ✅ Job Log
* ✅ Guided Job Workflow
* ✅ Invoice creation flow
* ✅ Invoice navigation fixes
* ✅ UX polish
* ✅ Parking Lot updated
* ✅ Brick 8 completed




## v0.9.6 B9 - Automatic Time Tracking

Planned goals:
- Use existing job start button to track time on job
- Use existing job finsih to stop timer
- Create a report in Admin tab called Job History Report that include the following information
        - Job Number
        - Customer Name
        - Technician(s)
        - Date
        - Time on job
        - Invoice Payment status


## v0.9.8 - Persona Engine

Planned goals:

- Roles vs personas
- Persona-specific dashboards
- Technician view
- Sales view
- Office view
- Owner view

## v1.0 - First Production Release

Planned goals:

- Stable field workflow
- Estimates
- Jobs
- Invoices
- Payments
- Receipt printing
- Service Catalog
- Technician Action Hub
- Basic roles/personas





## v1.x - Advanced Time Reporting

Vision Model / Goal
• track actual time on a job, this could be used for several data points, including performance, time-cards, and customer billing 
• If you mean where is it collected , like which swift or function then it is definitely in the job schema
• a couple things here, we need to be able to start, stop, and pause the timer as well, we need to have a timer for each technician / worker <-- this is important if we are billing labor on a job.  As well, need to be able to edit those times i case of error.   One thing to distinguish in the timers too, is tracking travel time separately from actual job work time, but having a overall timer total still exist, that way we know how to bill appropriately  <-- travel labor is usually less expensive than job labor.
• Darn right...  tech opens his scshedule, see his job and clicks on it and it is on the existing job card we have now


