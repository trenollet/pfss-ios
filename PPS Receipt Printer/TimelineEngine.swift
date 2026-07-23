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
        employees: [EmployeeRecord]
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

        let lanes = board.technicianLanes.map { lane in
            makeLane(
                lane,
                assignmentRecords: assignmentsByID,
                assignmentRecordsByJobID: assignmentsByJobID,
                employee: employeesByID[lane.id]
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
        employee: EmployeeRecord?
    ) -> OperationsTimelineLane {
        let itemsByID = Dictionary(
            uniqueKeysWithValues: lane.assignments.map { ($0.id, $0) }
        )
        let planItems = lane.dailyPlan.items.sorted {
            if $0.occupiedStart != $1.occupiedStart {
                return $0.occupiedStart < $1.occupiedStart
            }
            return $0.id < $1.id
        }

        var entries: [OperationsTimelineEntry] = []
        let workdayStart = lane.dailyPlan.workdayStart
        let workdayEnd = lane.dailyPlan.workdayEnd
        var cursor = workdayStart

        for planItem in planItems {
            if let cursor, planItem.occupiedStart > cursor {
                entries.append(openEntry(
                    technicianID: lane.id,
                    start: cursor,
                    end: planItem.occupiedStart
                ))
            }

            if planItem.occupiedStart < planItem.serviceStart {
                entries.append(transitionEntry(
                    technicianID: lane.id,
                    assignmentID: planItem.assignmentID,
                    start: planItem.occupiedStart,
                    end: planItem.serviceStart
                ))
            }

            if planItem.kind == .lunch {
                entries.append(lunchEntry(
                    technicianID: lane.id,
                    start: planItem.serviceStart,
                    end: planItem.serviceEnd
                ))
            } else if let assignmentID = planItem.assignmentID,
                      let item = itemsByID[assignmentID] {
                entries.append(assignmentEntry(
                    item: item,
                    record: assignmentRecords[assignmentID]
                        ?? assignmentRecordsByJobID[item.jobID],
                    technicianID: lane.id,
                    start: planItem.serviceStart,
                    end: planItem.serviceEnd
                ))
            }

            // Business Operations buffers are operational transition time.
            // Show them explicitly instead of allowing them to look like
            // unexplained open capacity after the service interval.
            if planItem.kind == .assignment,
               planItem.occupiedEnd > planItem.serviceEnd {
                entries.append(transitionEntry(
                    technicianID: lane.id,
                    assignmentID: planItem.assignmentID,
                    start: planItem.serviceEnd,
                    end: planItem.occupiedEnd
                ))
            }

            cursor = maxDate(cursor, planItem.occupiedEnd)
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
        return Array(Set(planningAlerts + boardAlerts)).sorted { $0.id < $1.id }
    }

    private func assignmentEntry(
        item: DispatchBoardAssignmentItem,
        record: Assignment?,
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
            milestones: milestones(for: record)
        )
    }

    private func transitionEntry(
        technicianID: UUID,
        assignmentID: UUID?,
        start: Date,
        end: Date
    ) -> OperationsTimelineEntry {
        intervalEntry(
            kind: .travel,
            technicianID: technicianID,
            assignmentID: assignmentID,
            start: start,
            end: end,
            title: "Travel / Transition",
            detail: "Reserved operational time"
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

    private func milestones(for assignment: Assignment?) -> [OperationsTimelineMilestone] {
        guard let assignment else { return [] }
        let values: [(String, Date?)] = [
            ("Dispatched", assignment.dispatchedDate),
            ("Travel Started", assignment.enRouteDate),
            ("Arrived", assignment.onSiteDate),
            ("Work Completed", assignment.workCompletedDate),
            ("Invoice Ready", assignment.invoiceReadyDate),
            ("Closed", assignment.closedDate),
            ("Cancelled", assignment.cancelledDate)
        ]
        return values.compactMap { title, timestamp in
            timestamp.map { OperationsTimelineMilestone(title: title, timestamp: $0) }
        }
        .sorted { $0.timestamp < $1.timestamp }
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
        case .assignment: return 1
        case .lunch: return 2
        case .openCapacity: return 3
        }
    }
}
