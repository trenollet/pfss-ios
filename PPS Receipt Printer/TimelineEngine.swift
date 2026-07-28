//
//  TimelineEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.8 – Synchronized Operations Timeline
//

import Foundation

/// Converts the Dispatch Board and Daily Planner snapshot into a deterministic
/// chronological lens. It never mutates an Assignment or accepts a plan.
@MainActor
struct OperationsTimelineEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func snapshot(
        board: DispatchBoardSnapshot,
        assignments: [Assignment],
        jobs: [JobRecord],
        employees: [EmployeeRecord],
        routePlansByTechnicianID: [UUID: RoutePlan] = [:]
    ) -> OperationsTimelineSnapshot {
        let assignmentsByID = Dictionary(
            uniqueKeysWithValues: assignments.map { ($0.id, $0) }
        )
        let assignmentsByJobID = Dictionary(
            uniqueKeysWithValues: assignments.map { ($0.jobID, $0) }
        )
        let employeesByID = Dictionary(
            uniqueKeysWithValues: employees.map { ($0.id, $0) }
        )
        let jobsByID = Dictionary(
            uniqueKeysWithValues: jobs.map { ($0.id, $0) }
        )

        let lanes = board.technicianLanes.map { lane in
            makeLane(
                lane,
                assignmentRecords: assignmentsByID,
                assignmentRecordsByJobID: assignmentsByJobID,
                jobsByID: jobsByID,
                employee: employeesByID[lane.id],
                routePlan: routePlansByTechnicianID[lane.id]
            )
        }
        .sorted {
            let comparison = $0.technicianName.localizedCaseInsensitiveCompare(
                $1.technicianName
            )
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : comparison == .orderedAscending
        }

        return OperationsTimelineSnapshot(
            date: board.date,
            generatedAt: board.generatedAt,
            lanes: lanes,
            unassignedItems: board.unassignedItems
        )
    }

    private func makeLane(
        _ lane: DispatchBoardTechnicianLane,
        assignmentRecords: [UUID: Assignment],
        assignmentRecordsByJobID: [UUID: Assignment],
        jobsByID: [UUID: JobRecord],
        employee: EmployeeRecord?,
        routePlan: RoutePlan?
    ) -> OperationsTimelineLane {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: lane.assignments.map { ($0.id, $0) }
        )
        let routeStopsByAssignmentID = Dictionary(
            uniqueKeysWithValues: (routePlan?.stops ?? []).map {
                ($0.assignmentID, $0)
            }
        )
        let planItems = lane.dailyPlan.items.sorted {
            let firstStart = $0.assignmentID
                .flatMap { routeStopsByAssignmentID[$0]?.departureDate }
                ?? $0.occupiedStart
            let secondStart = $1.assignmentID
                .flatMap { routeStopsByAssignmentID[$0]?.departureDate }
                ?? $1.occupiedStart
            if firstStart != secondStart {
                return firstStart < secondStart
            }
            return $0.id < $1.id
        }

        var entries: [OperationsTimelineEntry] = []
        let workdayStart = lane.dailyPlan.workdayStart
        let workdayEnd = lane.dailyPlan.workdayEnd
        var cursor = workdayStart

        for planItem in planItems {
            let routeStop = planItem.assignmentID.flatMap {
                routeStopsByAssignmentID[$0]
            }
            let occupiedStart = routeStop?.departureDate
                ?? planItem.occupiedStart
            let serviceStart = routeStop?.serviceStartDate
                ?? planItem.serviceStart
            let serviceEnd = routeStop?.serviceEndDate
                ?? planItem.serviceEnd
            let postBufferMinutes = max(
                Int(planItem.occupiedEnd.timeIntervalSince(planItem.serviceEnd) / 60),
                0
            )
            let occupiedEnd = calendar.date(
                byAdding: .minute,
                value: postBufferMinutes,
                to: serviceEnd
            ) ?? serviceEnd

            if let cursor, occupiedStart > cursor {
                entries.append(openEntry(
                    technicianID: lane.id,
                    start: cursor,
                    end: occupiedStart
                ))
            }

            if let routeStop,
               routeStop.estimatedArrivalDate > routeStop.departureDate {
                entries.append(roadTravelEntry(
                    technicianID: lane.id,
                    assignmentID: planItem.assignmentID,
                    stop: routeStop
                ))
            } else if occupiedStart < serviceStart {
                entries.append(transitionEntry(
                    technicianID: lane.id,
                    assignmentID: planItem.assignmentID,
                    start: occupiedStart,
                    end: serviceStart
                ))
            }

            if planItem.kind == .lunch {
                entries.append(lunchEntry(
                    technicianID: lane.id,
                    start: serviceStart,
                    end: serviceEnd
                ))
            } else if let assignmentID = planItem.assignmentID,
                      let item = itemsByID[assignmentID] {
                entries.append(assignmentEntry(
                    item: item,
                    record: assignmentRecords[assignmentID]
                        ?? assignmentRecordsByJobID[item.jobID],
                    job: jobsByID[item.jobID],
                    technicianID: lane.id,
                    start: serviceStart,
                    end: serviceEnd
                ))
            }

            // Business Operations buffers are configurable stop overhead, not
            // road-network travel. Label them honestly so a three-minute
            // buffer is never mistaken for the drive to the next appointment.
            if planItem.kind == .assignment,
               occupiedEnd > serviceEnd {
                entries.append(transitionEntry(
                    technicianID: lane.id,
                    assignmentID: planItem.assignmentID,
                    start: serviceEnd,
                    end: occupiedEnd
                ))
            }

            cursor = maxDate(cursor, occupiedEnd)
        }

        // Assignments not placed by the Daily Planner remain visible using
        // their best operational time, with conflicts clearly identified.
        let representedIDs = Set(entries.compactMap(\.assignmentID))
        for item in lane.assignments where !representedIDs.contains(item.id) {
            let start = item.plannedStart
                ?? item.estimatedArrival
                ?? lane.dailyPlan.workdayStart
                ?? boardDayStart(lane.dailyPlan.date)
            let end = item.plannedEnd
                ?? calendar.date(
                    byAdding: .minute,
                    value: max(item.serviceMinutes, 1),
                    to: start
                )
                ?? start
            entries.append(assignmentEntry(
                item: item,
                record: assignmentRecords[item.id]
                    ?? assignmentRecordsByJobID[item.jobID],
                job: jobsByID[item.jobID],
                technicianID: lane.id,
                start: start,
                end: end
            ))
        }

        if let cursor, let workdayEnd, workdayEnd > cursor {
            entries.append(openEntry(
                technicianID: lane.id,
                start: cursor,
                end: workdayEnd
            ))
        }

        entries.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.kind != $1.kind { return entryOrder($0.kind) < entryOrder($1.kind) }
            return $0.id < $1.id
        }

        let scheduledMinutes = entries
            .filter { $0.kind == .assignment }
            .reduce(0) { $0 + $1.durationMinutes }
        let openMinutes = entries
            .filter { $0.kind == .openCapacity }
            .reduce(0) { $0 + $1.durationMinutes }

        let alerts = timelineAlerts(for: lane)

        return OperationsTimelineLane(
            id: lane.id,
            technicianName: lane.technicianName,
            technicianColorName: employee?.colorName ?? "blue",
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            entries: entries,
            alerts: alerts,
            conflictCount: entries.filter(\.hasConflict).count + alerts.count,
            scheduledMinutes: scheduledMinutes,
            openMinutes: openMinutes
        )
    }

    private func timelineAlerts(
        for lane: DispatchBoardTechnicianLane
    ) -> [OperationsTimelineAlert] {
        let planningAlerts = lane.dailyPlan.conflicts.map { conflict in
            OperationsTimelineAlert(
                id: "plan|\(conflict.id)",
                title: conflict.kind.rawValue,
                message: conflict.message,
                assignmentID: conflict.assignmentID,
                isBlocking: conflict.severity == .error
            )
        }
        let boardAlerts = lane.alerts.map { alert in
            OperationsTimelineAlert(
                id: "board|\(alert.id)",
                title: alert.title,
                message: alert.message,
                assignmentID: alert.assignmentID,
                isBlocking: alert.severity == .blocking
            )
        }
        var uniqueAlerts: [String: OperationsTimelineAlert] = [:]
        for alert in planningAlerts + boardAlerts {
            let key = [
                alert.assignmentID?.uuidString ?? "none",
                alert.title,
                alert.message,
                alert.isBlocking ? "blocking" : "warning"
            ].joined(separator: "|")
            if uniqueAlerts[key] == nil {
                uniqueAlerts[key] = alert
            }
        }
        return uniqueAlerts.values.sorted { $0.id < $1.id }
    }

    private func assignmentEntry(
        item: DispatchBoardAssignmentItem,
        record: Assignment?,
        job: JobRecord?,
        technicianID: UUID,
        start: Date,
        end: Date
    ) -> OperationsTimelineEntry {
        OperationsTimelineEntry(
            id: "assignment|\(item.id.uuidString)|\(start.timeIntervalSinceReferenceDate)",
            kind: .assignment,
            technicianID: technicianID,
            assignmentID: item.id,
            start: start,
            end: maxDate(start, end),
            title: item.customerName,
            subtitle: item.siteName,
            detail: item.serviceName,
            constraint: OperationsTimelineConstraint(mode: item.schedulingMode),
            status: item.status,
            priority: item.priority,
            hasConflict: item.hasBlockingConflict,
            warnings: item.warnings,
            milestones: milestones(for: record, job: job)
        )
    }

    private func transitionEntry(
        technicianID: UUID,
        assignmentID: UUID?,
        start: Date,
        end: Date
    ) -> OperationsTimelineEntry {
        intervalEntry(
            kind: .stopBuffer,
            technicianID: technicianID,
            assignmentID: assignmentID,
            start: start,
            end: end,
            title: "Stop Buffer",
            detail: "Configured operational overhead"
        )
    }

    private func roadTravelEntry(
        technicianID: UUID,
        assignmentID: UUID?,
        stop: RouteStopPlan
    ) -> OperationsTimelineEntry {
        let miles = stop.travel.distanceMiles.formatted(
            .number.precision(.fractionLength(1))
        )
        return intervalEntry(
            kind: .travel,
            technicianID: technicianID,
            assignmentID: assignmentID,
            start: stop.departureDate,
            end: stop.estimatedArrivalDate,
            title: "Travel",
            detail: "Apple Maps estimate · \(miles) mi"
        )
    }

    private func lunchEntry(
        technicianID: UUID,
        start: Date,
        end: Date
    ) -> OperationsTimelineEntry {
        intervalEntry(
            kind: .lunch,
            technicianID: technicianID,
            start: start,
            end: end,
            title: "Lunch",
            detail: "Protected break"
        )
    }

    private func openEntry(
        technicianID: UUID,
        start: Date,
        end: Date
    ) -> OperationsTimelineEntry {
        intervalEntry(
            kind: .openCapacity,
            technicianID: technicianID,
            start: start,
            end: end,
            title: "Open Capacity",
            detail: "Available for flexible or emergency work"
        )
    }

    private func intervalEntry(
        kind: OperationsTimelineEntryKind,
        technicianID: UUID,
        assignmentID: UUID? = nil,
        start: Date,
        end: Date,
        title: String,
        detail: String
    ) -> OperationsTimelineEntry {
        OperationsTimelineEntry(
            id: "\(kind.rawValue)|\(technicianID.uuidString)|\(start.timeIntervalSinceReferenceDate)|\(end.timeIntervalSinceReferenceDate)",
            kind: kind,
            technicianID: technicianID,
            assignmentID: assignmentID,
            start: start,
            end: maxDate(start, end),
            title: title,
            subtitle: "",
            detail: detail,
            constraint: .operational,
            status: nil,
            priority: nil,
            hasConflict: false,
            warnings: [],
            milestones: []
        )
    }

    private func milestones(
        for assignment: Assignment?,
        job: JobRecord?
    ) -> [OperationsTimelineMilestone] {
        struct Candidate {
            let key: String
            let title: String
            let timestamp: Date
        }

        let jobCandidates = (job?.timelineEvents ?? []).compactMap { event -> Candidate? in
            guard let key = milestoneKey(for: event.type) else { return nil }
            return Candidate(key: key, title: event.title, timestamp: event.timestamp)
        }
        let jobKeys = Set(jobCandidates.map(\.key))

        let assignmentValues: [(String, String, Date?)] = [
            ("dispatched", "Dispatched", assignment?.dispatchedDate),
            ("travel", "Travel Started", assignment?.enRouteDate),
            ("arrived", "Arrived", assignment?.onSiteDate),
            ("workComplete", "Work Completed", assignment?.workCompletedDate),
            ("invoice", "Invoice Ready", assignment?.invoiceReadyDate),
            ("closed", "Closed", assignment?.closedDate),
            ("cancelled", "Cancelled", assignment?.cancelledDate)
        ]
        let assignmentCandidates: [Candidate] = assignmentValues.compactMap { value in
            let (key, title, timestamp) = value
            guard let timestamp, !jobKeys.contains(key) else { return nil }
            return Candidate(key: key, title: title, timestamp: timestamp)
        }

        return (jobCandidates + assignmentCandidates)
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                OperationsTimelineMilestone(
                    title: $0.title,
                    timestamp: $0.timestamp
                )
            }
    }

    private func milestoneKey(
        for type: JobTimelineEventType
    ) -> String? {
        switch type {
        case .assigned: return "assigned"
        case .travelStarted: return "travel"
        case .travelPaused: return "travelPaused"
        case .travelResumed: return "travelResumed"
        case .arrived: return "arrived"
        case .setupStarted: return "setup"
        case .workStarted: return "workStarted"
        case .workPaused: return "workPaused"
        case .workResumed: return "workResumed"
        case .packUpStarted: return "packUp"
        case .workCompleted: return "workComplete"
        case .invoiceCreated: return "invoice"
        case .invoiceSent: return "invoiceSent"
        case .paymentReceived: return "payment"
        case .jobCompleted: return "closed"
        case .cancelled: return "cancelled"
        case .note: return nil
        case .timelineCorrected: return nil
        }
    }

    private func boardDayStart(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func maxDate(_ first: Date?, _ second: Date) -> Date {
        guard let first else { return second }
        return first > second ? first : second
    }

    private func maxDate(_ first: Date, _ second: Date) -> Date {
        first > second ? first : second
    }

    private func entryOrder(_ kind: OperationsTimelineEntryKind) -> Int {
        switch kind {
        case .travel: return 0
        case .stopBuffer: return 1
        case .assignment: return 2
        case .lunch: return 3
        case .openCapacity: return 4
        }
    }
}
