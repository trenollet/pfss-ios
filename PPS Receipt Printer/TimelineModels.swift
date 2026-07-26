//
//  TimelineModels.swift
//  PPS Receipt Printer
//
//  Phase 14.8 – Synchronized Operations Timeline
//

import Foundation

enum OperationsTimelineEntryKind: String, Codable, Hashable {
    case assignment = "Assignment"
    case travel = "Travel"
    case stopBuffer = "Stop Buffer"
    case lunch = "Lunch"
    case openCapacity = "Open Capacity"
}

enum OperationsTimelineConstraint: String, Codable, Hashable {
    case fixedTime = "Fixed Time"
    case arrivalWindow = "Arrival Window"
    case flexibleDay = "Flexible Day"
    case deadline = "Deadline"
    case operational = "Operational"

    init(mode: AssignmentSchedulingMode?) {
        switch mode {
        case .fixedTime: self = .fixedTime
        case .arrivalWindow: self = .arrivalWindow
        case .flexibleDay: self = .flexibleDay
        case .deadline: self = .deadline
        case nil: self = .operational
        }
    }
}

struct OperationsTimelineMilestone: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let timestamp: Date

    init(title: String, timestamp: Date) {
        self.title = title
        self.timestamp = timestamp
        self.id = "\(title)|\(timestamp.timeIntervalSinceReferenceDate)"
    }
}

struct OperationsTimelineAlert: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let message: String
    let assignmentID: UUID?
    let isBlocking: Bool
}

/// One chronological interval in a technician lane.
struct OperationsTimelineEntry: Identifiable, Codable, Hashable {
    let id: String
    let kind: OperationsTimelineEntryKind
    let technicianID: UUID
    let assignmentID: UUID?
    let start: Date
    let end: Date
    let title: String
    let subtitle: String
    let detail: String
    let constraint: OperationsTimelineConstraint
    let status: AssignmentStatus?
    let priority: AssignmentPriority?
    let hasConflict: Bool
    let warnings: [String]
    let milestones: [OperationsTimelineMilestone]

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }
}

struct OperationsTimelineLane: Identifiable, Codable, Hashable {
    let id: UUID
    let technicianName: String
    let technicianColorName: String
    let workdayStart: Date?
    let workdayEnd: Date?
    let entries: [OperationsTimelineEntry]
    let alerts: [OperationsTimelineAlert]
    let conflictCount: Int
    let scheduledMinutes: Int
    let openMinutes: Int
}

struct OperationsTimelineSnapshot: Codable, Hashable {
    let date: Date
    let generatedAt: Date
    let lanes: [OperationsTimelineLane]
    let unassignedItems: [DispatchBoardAssignmentItem]

    var scheduledAssignmentCount: Int {
        lanes.reduce(0) { total, lane in
            total + lane.entries.filter { $0.kind == .assignment }.count
        }
    }

    var conflictCount: Int {
        lanes.reduce(0) { $0 + $1.conflictCount }
    }

    var openMinutes: Int {
        lanes.reduce(0) { $0 + $1.openMinutes }
    }
}
