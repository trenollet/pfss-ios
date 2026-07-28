//
//  DispatchBoardModels.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Technician Dispatch Board
//

import Foundation

/// Read-only state shown for a technician lane on the Dispatch Board.
enum DispatchBoardTechnicianState: String, Codable, Hashable {
    case available = "Available"
    case scheduled = "Scheduled"
    case traveling = "Traveling"
    case working = "Working"
    case attention = "Needs Attention"
    case offline = "Off Duty"
}

enum DispatchBoardAlertSeverity: String, Codable, Hashable {
    case information = "Information"
    case warning = "Warning"
    case blocking = "Blocking"
}

/// Explainable warning surfaced by the board. The engine intentionally keeps
/// the related Assignment and technician identifiers so future Timeline and
/// Map views can present the same operational evidence.
struct DispatchBoardAlert: Identifiable, Codable, Hashable {
    let id: String
    let severity: DispatchBoardAlertSeverity
    let title: String
    let message: String
    let assignmentID: UUID?
    let technicianID: UUID?

    init(
        severity: DispatchBoardAlertSeverity,
        title: String,
        message: String,
        assignmentID: UUID? = nil,
        technicianID: UUID? = nil
    ) {
        self.severity = severity
        self.title = title
        self.message = message
        self.assignmentID = assignmentID
        self.technicianID = technicianID
        self.id = [
            severity.rawValue,
            assignmentID?.uuidString ?? "board",
            technicianID?.uuidString ?? "unassigned",
            title,
            message
        ].joined(separator: "|")
    }
}

/// A resolved, presentation-safe Assignment. No view needs to look up customer,
/// site, Job, crew, or Daily Planner information independently.
struct DispatchBoardAssignmentItem: Identifiable, Codable, Hashable {
    let id: UUID
    let jobID: UUID
    let assignmentNumber: String
    let jobNumber: String
    let customerName: String
    let siteName: String
    let siteAddress: String
    let serviceName: String
    let status: AssignmentStatus
    let priority: AssignmentPriority
    let schedulingMode: AssignmentSchedulingMode
    let scheduleDateText: String
    let scheduleTimeText: String
    let plannedStart: Date?
    let plannedEnd: Date?
    let estimatedArrival: Date?
    let serviceMinutes: Int
    let routeSequence: Int?
    let primaryTechnicianID: UUID?
    let supportingTechnicianIDs: [UUID]
    let isCurrent: Bool
    let hasBlockingConflict: Bool
    let warnings: [String]
}

/// One technician-centric lane. `dailyPlan` is retained so the UI can open the
/// existing Route Preview using the exact plan represented by this snapshot.
struct DispatchBoardTechnicianLane: Identifiable, Hashable {
    let id: UUID
    let technicianName: String
    let technicianState: DispatchBoardTechnicianState
    let assignments: [DispatchBoardAssignmentItem]
    let currentAssignmentID: UUID?
    let nextAssignmentID: UUID?
    let plannedServiceMinutes: Int
    let capacityMinutes: Int
    let utilization: Double
    let dailyPlan: DailyPlan
    let alerts: [DispatchBoardAlert]

    var currentAssignment: DispatchBoardAssignmentItem? {
        guard let currentAssignmentID else { return nil }
        return assignments.first { $0.id == currentAssignmentID }
    }

    var nextAssignment: DispatchBoardAssignmentItem? {
        guard let nextAssignmentID else { return nil }
        return assignments.first { $0.id == nextAssignmentID }
    }
}

/// Immutable board output. Building or refreshing a snapshot never changes an
/// Assignment; all operational mutations remain in AssignmentEngine and
/// DispatchEngine.
struct DispatchBoardSnapshot: Hashable {
    let date: Date
    let generatedAt: Date
    let technicianLanes: [DispatchBoardTechnicianLane]
    let unassignedItems: [DispatchBoardAssignmentItem]
    let alerts: [DispatchBoardAlert]

    var activeTechnicianCount: Int { technicianLanes.count }

    var assignedCount: Int {
        technicianLanes.reduce(0) { $0 + $1.assignments.count }
    }

    var unassignedCount: Int { unassignedItems.count }

    var emergencyCount: Int {
        technicianLanes.reduce(0) { total, lane in
            total + lane.assignments.filter { $0.priority == .emergency }.count
        } + unassignedItems.filter { $0.priority == .emergency }.count
    }

    var blockingAlertCount: Int {
        alerts.filter { $0.severity == .blocking }.count
    }
}
