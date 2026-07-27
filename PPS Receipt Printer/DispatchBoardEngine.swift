//
//  DispatchBoardEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Technician Dispatch Board
//

import Foundation

/// Produces a deterministic, read-only technician-centric board snapshot.
///
/// This engine resolves operational records for presentation only. It never
/// assigns, dispatches, reorders, or mutates work. Board actions must continue
/// to flow through `AssignmentEngine` and `DispatchEngine`.
@MainActor
struct DispatchBoardEngine {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func snapshot(
        on date: Date,
        generatedAt: Date = Date(),
        employees: [EmployeeRecord],
        assignments: [Assignment],
        jobs: [JobRecord],
        customers: [Customer],
        sites: [CustomerSite],
        dailyPlans: [DailyPlan]
    ) -> DispatchBoardSnapshot {
        let day = calendar.startOfDay(for: date)
        let technicians = employees
            .filter {
                $0.isActive &&
                $0.lifecycleStatus == .active &&
                $0.hasRole(.technician)
            }
            .sorted(by: stableEmployeeOrder)

        let relevantAssignments = assignments
            .filter {
                $0.lifecycleStatus == .active &&
                $0.status.isActive &&
                occurs($0, on: day)
            }

        let jobsByID = Dictionary(
            uniqueKeysWithValues: jobs.map { ($0.id, $0) }
        )
        let customersByNumber = Dictionary(
            uniqueKeysWithValues: customers.map { ($0.customerNumber, $0) }
        )
        let sitesByID = Dictionary(
            uniqueKeysWithValues: sites.map { ($0.id, $0) }
        )
        let plansByTechnician = Dictionary(
            uniqueKeysWithValues: dailyPlans.map { ($0.technicianID, $0) }
        )

        let lanes = technicians.map { technician in
            let plan = plansByTechnician[technician.id]
                ?? emptyPlan(for: technician, on: day)
            let laneAssignments = relevantAssignments.filter {
                $0.primaryTechnicianID == technician.id
            }

            return makeLane(
                technician: technician,
                assignments: laneAssignments,
                plan: plan,
                generatedAt: generatedAt,
                jobsByID: jobsByID,
                customersByNumber: customersByNumber,
                sitesByID: sitesByID
            )
        }

        let unassigned = relevantAssignments
            .filter { $0.primaryTechnicianID == nil }
            .map {
                makeItem(
                    assignment: $0,
                    planItem: nil,
                    planningConflicts: [],
                    jobsByID: jobsByID,
                    customersByNumber: customersByNumber,
                    sitesByID: sitesByID
                )
            }
            .sorted(by: stableItemOrder)

        var alerts = lanes.flatMap(\.alerts)
        alerts.append(contentsOf: unassigned.flatMap { item in
            item.warnings.map {
                DispatchBoardAlert(
                    severity: item.hasBlockingConflict ? .blocking : .warning,
                    title: item.customerName,
                    message: $0,
                    assignmentID: item.id
                )
            }
        })

        if unassigned.isEmpty == false {
            alerts.append(
                DispatchBoardAlert(
                    severity: .warning,
                    title: "Unassigned work",
                    message: "\(unassigned.count) assignment\(unassigned.count == 1 ? "" : "s") still require a Primary Technician."
                )
            )
        }

        return DispatchBoardSnapshot(
            date: day,
            generatedAt: generatedAt,
            technicianLanes: lanes,
            unassignedItems: unassigned,
            alerts: alerts.sorted(by: stableAlertOrder)
        )
    }

    // MARK: - Technician Lanes

    private func makeLane(
        technician: EmployeeRecord,
        assignments: [Assignment],
        plan: DailyPlan,
        generatedAt: Date,
        jobsByID: [UUID: JobRecord],
        customersByNumber: [String: Customer],
        sitesByID: [UUID: CustomerSite]
    ) -> DispatchBoardTechnicianLane {
        let planItemsByAssignment = Dictionary(
            uniqueKeysWithValues: plan.assignmentItems.compactMap { item in
                item.assignmentID.map { ($0, item) }
            }
        )

        let items = assignments.map { assignment in
            makeItem(
                assignment: assignment,
                planItem: planItemsByAssignment[assignment.id],
                planningConflicts: plan.conflicts.filter {
                    $0.assignmentID == assignment.id ||
                    $0.conflictingAssignmentID == assignment.id
                },
                jobsByID: jobsByID,
                customersByNumber: customersByNumber,
                sitesByID: sitesByID
            )
        }
        .sorted(by: stableItemOrder)

        let current = items.first { $0.isCurrent }
        let next = items.first { item in
            guard item.id != current?.id else { return false }
            guard let start = item.plannedStart ?? item.estimatedArrival else {
                return current == nil
            }
            return start >= generatedAt || !calendar.isDateInToday(plan.date)
        } ?? items.first { $0.id != current?.id }

        let capacity = max(technician.dailyCapacityMinutes, 0)
        let serviceMinutes = items.reduce(0) { $0 + $1.serviceMinutes }
        let utilization = capacity > 0
            ? Double(serviceMinutes) / Double(capacity)
            : (serviceMinutes > 0 ? 1 : 0)

        var alerts = plan.conflicts.map {
            DispatchBoardAlert(
                severity: $0.severity == .error ? .blocking : .warning,
                title: $0.kind.rawValue,
                message: $0.message,
                assignmentID: $0.assignmentID,
                technicianID: technician.id
            )
        }

        if utilization > 1 {
            alerts.append(
                DispatchBoardAlert(
                    severity: .warning,
                    title: "Over capacity",
                    message: "\(technician.displayName) has \(serviceMinutes) service minutes planned against \(capacity) available minutes.",
                    technicianID: technician.id
                )
            )
        }

        return DispatchBoardTechnicianLane(
            id: technician.id,
            technicianName: technician.displayName,
            technicianState: technicianState(
                technician: technician,
                items: items,
                hasBlockingConflict: alerts.contains {
                    $0.severity == .blocking
                },
                utilization: utilization,
                date: plan.date
            ),
            assignments: items,
            currentAssignmentID: current?.id,
            nextAssignmentID: next?.id,
            plannedServiceMinutes: serviceMinutes,
            capacityMinutes: capacity,
            utilization: utilization.isFinite ? max(utilization, 0) : 0,
            dailyPlan: plan,
            alerts: alerts.sorted(by: stableAlertOrder)
        )
    }

    private func technicianState(
        technician: EmployeeRecord,
        items: [DispatchBoardAssignmentItem],
        hasBlockingConflict: Bool,
        utilization: Double,
        date: Date
    ) -> DispatchBoardTechnicianState {
        if hasBlockingConflict || utilization > 1 {
            return .attention
        }
        if items.contains(where: { $0.status == .onSite }) {
            return .working
        }
        if items.contains(where: { $0.status == .enRoute }) {
            return .traveling
        }
        if SchedulingCalculator.isWorkingDay(
            date,
            for: technician,
            calendar: calendar
        ) == false {
            return .offline
        }
        return items.isEmpty ? .available : .scheduled
    }

    // MARK: - Assignment Resolution

    private func makeItem(
        assignment: Assignment,
        planItem: DailyPlanItem?,
        planningConflicts: [PlanningConflict],
        jobsByID: [UUID: JobRecord],
        customersByNumber: [String: Customer],
        sitesByID: [UUID: CustomerSite]
    ) -> DispatchBoardAssignmentItem {
        let job = jobsByID[assignment.jobID]
        let customer = customersByNumber[assignment.customerNumber]
        let site = assignment.siteID.flatMap { sitesByID[$0] }

        var warnings = planningConflicts.map(\.message)
        warnings.append(contentsOf: assignment.scheduling.validationIssues.map(\.rawValue))

        if job == nil {
            warnings.append("The related Job record could not be resolved.")
        }
        if assignment.siteID == nil || site == nil {
            warnings.append("A valid service site is required for route planning.")
        }
        if assignment.primaryTechnicianID == nil {
            warnings.append("A Primary Technician has not been assigned.")
        }

        let serviceName: String
        if let job {
            let other = job.otherService.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            serviceName = job.serviceType == .other && other.isEmpty == false
                ? other
                : job.serviceType.rawValue
        } else {
            serviceName = "Service"
        }

        return DispatchBoardAssignmentItem(
            id: assignment.id,
            jobID: assignment.jobID,
            assignmentNumber: assignment.assignmentNumber,
            jobNumber: assignment.jobNumber,
            customerName: customerDisplayName(
                customer,
                fallback: assignment.customerNumber
            ),
            siteName: siteDisplayName(site),
            siteAddress: site?.serviceAddress ?? "",
            serviceName: serviceName,
            status: assignment.status,
            priority: assignment.priority,
            schedulingMode: assignment.scheduling.mode,
            scheduleDateText: assignment.scheduling.displayDateText,
            scheduleTimeText: assignment.scheduling.displayTimeText,
            plannedStart: planItem?.serviceStart
                ?? assignment.scheduling.operationalDate,
            plannedEnd: planItem?.serviceEnd,
            estimatedArrival: planItem?.serviceStart
                ?? assignment.scheduling.earliestPermittedStart,
            serviceMinutes: planItem?.serviceMinutes
                ?? max(assignment.scheduling.estimatedDurationMinutes, 0),
            routeSequence: assignment.routeSequence,
            primaryTechnicianID: assignment.primaryTechnicianID,
            supportingTechnicianIDs: assignment.supportingTechnicianIDs,
            isCurrent: assignment.status == .enRoute ||
                assignment.status == .onSite,
            hasBlockingConflict: planningConflicts.contains {
                $0.severity == .error
            } || assignment.scheduling.isValid == false,
            warnings: Array(Set(warnings)).sorted()
        )
    }

    // MARK: - Helpers

    private func occurs(_ assignment: Assignment, on date: Date) -> Bool {
        guard let operationalDate = assignment.scheduling.operationalDate else {
            return false
        }
        return calendar.isDate(operationalDate, inSameDayAs: date)
    }

    private func emptyPlan(
        for technician: EmployeeRecord,
        on date: Date
    ) -> DailyPlan {
        DailyPlan(
            technicianID: technician.id,
            date: date,
            workdayStart: nil,
            workdayEnd: nil,
            items: [],
            openWindows: [],
            conflicts: [],
            recommendations: [],
            unplacedAssignmentIDs: [],
            dailyReserveMinutes: 0
        )
    }

    private func customerDisplayName(
        _ customer: Customer?,
        fallback: String
    ) -> String {
        guard let customer else {
            return fallback.isEmpty ? "Unknown Customer" : fallback
        }
        let business = customer.businessName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let contact = customer.contactName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if business.isEmpty == false { return business }
        if contact.isEmpty == false { return contact }
        return customer.customerNumber
    }

    private func siteDisplayName(_ site: CustomerSite?) -> String {
        guard let site else { return "No Site" }
        let name = site.siteName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return name.isEmpty ? "Unnamed Site" : name
    }

    private func stableEmployeeOrder(
        _ first: EmployeeRecord,
        _ second: EmployeeRecord
    ) -> Bool {
        let comparison = first.displayName.localizedCaseInsensitiveCompare(
            second.displayName
        )
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return first.id.uuidString < second.id.uuidString
    }

    private func stableItemOrder(
        _ first: DispatchBoardAssignmentItem,
        _ second: DispatchBoardAssignmentItem
    ) -> Bool {
        switch (first.routeSequence, second.routeSequence) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        switch (first.plannedStart, second.plannedStart) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if first.priority.sortOrder != second.priority.sortOrder {
            return first.priority.sortOrder > second.priority.sortOrder
        }
        let customerComparison = first.customerName
            .localizedCaseInsensitiveCompare(second.customerName)
        if customerComparison != .orderedSame {
            return customerComparison == .orderedAscending
        }
        return first.id.uuidString < second.id.uuidString
    }

    private func stableAlertOrder(
        _ first: DispatchBoardAlert,
        _ second: DispatchBoardAlert
    ) -> Bool {
        let severityRank: [DispatchBoardAlertSeverity: Int] = [
            .blocking: 0,
            .warning: 1,
            .information: 2
        ]
        let firstRank = severityRank[first.severity] ?? Int.max
        let secondRank = severityRank[second.severity] ?? Int.max
        if firstRank != secondRank { return firstRank < secondRank }
        return first.id < second.id
    }
}
