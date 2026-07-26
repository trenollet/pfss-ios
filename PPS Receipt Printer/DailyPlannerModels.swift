//
//  DailyPlannerModels.swift
//  PPS Receipt Printer
//
//  Phase 14.3 – Daily Planner Engine
//

import Foundation

// MARK: - Configuration

/// Deterministic operating rules used when constructing one technician day.
///
/// `transitionBufferMinutes` is configurable operational overhead between
/// stops. It is not a travel estimate. Road-network travel is supplied by the
/// Route Engine and must remain distinct in route and timeline presentation.
struct DailyPlannerConfiguration: Codable, Hashable {
    var slotIntervalMinutes: Int
    var transitionBufferMinutes: Int
    var transitionTravelMinutesOverride: Int?
    var dailyReserveMinutes: Int
    var preferredLunchStartMinutes: Int
    var lunchWindowStartMinutes: Int
    var lunchWindowEndMinutes: Int
    var includeBusinessBuffers: Bool

    init(
        slotIntervalMinutes: Int = 15,
        transitionBufferMinutes: Int = 0,
        transitionTravelMinutesOverride: Int? = nil,
        dailyReserveMinutes: Int = 0,
        preferredLunchStartMinutes: Int = 12 * 60,
        lunchWindowStartMinutes: Int = 11 * 60,
        lunchWindowEndMinutes: Int = 14 * 60,
        includeBusinessBuffers: Bool = true
    ) {
        self.slotIntervalMinutes = max(slotIntervalMinutes, 1)
        self.transitionBufferMinutes = max(transitionBufferMinutes, 0)
        self.transitionTravelMinutesOverride = transitionTravelMinutesOverride.map {
            max($0, 0)
        }
        self.dailyReserveMinutes = max(dailyReserveMinutes, 0)
        self.preferredLunchStartMinutes = min(
            max(preferredLunchStartMinutes, 0),
            24 * 60
        )
        self.lunchWindowStartMinutes = min(
            max(lunchWindowStartMinutes, 0),
            24 * 60
        )
        self.lunchWindowEndMinutes = min(
            max(lunchWindowEndMinutes, self.lunchWindowStartMinutes),
            24 * 60
        )
        self.includeBusinessBuffers = includeBusinessBuffers
    }

    init(
        operations: BusinessOperationsSettings,
        slotIntervalMinutes: Int = 15,
        transitionTravelMinutesOverride: Int? = nil,
        preferredLunchStartMinutes: Int = 12 * 60,
        lunchWindowStartMinutes: Int = 11 * 60,
        lunchWindowEndMinutes: Int = 14 * 60
    ) {
        self.init(
            slotIntervalMinutes: slotIntervalMinutes,
            transitionBufferMinutes: operations.perStopBufferMinutes,
            transitionTravelMinutesOverride: transitionTravelMinutesOverride,
            dailyReserveMinutes: operations.dailyRouteBufferMinutes,
            preferredLunchStartMinutes: preferredLunchStartMinutes,
            lunchWindowStartMinutes: lunchWindowStartMinutes,
            lunchWindowEndMinutes: lunchWindowEndMinutes,
            includeBusinessBuffers: operations.includeBuffersInRouteTime
        )
    }

    var effectiveTransitionBufferMinutes: Int {
        guard includeBusinessBuffers else { return 0 }
        return transitionTravelMinutesOverride ?? transitionBufferMinutes
    }

    var effectiveDailyReserveMinutes: Int {
        includeBusinessBuffers ? dailyReserveMinutes : 0
    }
}

// MARK: - Plan Items

enum DailyPlanItemKind: String, Codable, Hashable {
    case assignment = "Assignment"
    case lunch = "Lunch"
}

/// One placed item in a proposed technician workday.
struct DailyPlanItem: Identifiable, Codable, Hashable {
    let kind: DailyPlanItemKind
    let assignmentID: UUID?
    let jobID: UUID?
    let technicianID: UUID
    let title: String
    let schedulingMode: AssignmentSchedulingMode?
    let serviceStart: Date
    let serviceEnd: Date
    let occupiedStart: Date
    let occupiedEnd: Date
    let isFixedCommitment: Bool
    let explanation: String

    var id: String {
        let source = assignmentID?.uuidString ?? kind.rawValue
        return "\(source)-\(occupiedStart.timeIntervalSinceReferenceDate)"
    }

    var occupiedMinutes: Int {
        max(Int(occupiedEnd.timeIntervalSince(occupiedStart) / 60), 0)
    }

    var serviceMinutes: Int {
        max(Int(serviceEnd.timeIntervalSince(serviceStart) / 60), 0)
    }
}

// MARK: - Planning Windows

enum PlanningWindowKind: String, Codable, Hashable {
    case open = "Open"
    case occupied = "Occupied"
    case lunch = "Lunch"
}

struct PlanningWindow: Identifiable, Codable, Hashable {
    let kind: PlanningWindowKind
    let start: Date
    let end: Date

    var id: String {
        "\(kind.rawValue)-\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)"
    }

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }
}

// MARK: - Conflicts

enum PlanningConflictKind: String, Codable, Hashable {
    case inactiveTechnician = "Inactive Technician"
    case nonWorkingDay = "Non-Working Day"
    case invalidScheduling = "Invalid Scheduling"
    case fixedCommitmentOutsideWorkday = "Fixed Commitment Outside Workday"
    case fixedCommitmentOverlap = "Fixed Commitment Overlap"
    case arrivalWindowUnavailable = "Arrival Window Unavailable"
    case deadlineUnavailable = "Deadline Unavailable"
    case lunchUnavailable = "Lunch Unavailable"
    case insufficientCapacity = "Insufficient Capacity"
    case assignmentNotPlaced = "Assignment Not Placed"
}

enum PlanningConflictSeverity: String, Codable, Hashable {
    case warning = "Warning"
    case error = "Error"
}

struct PlanningConflict: Identifiable, Codable, Hashable {
    let kind: PlanningConflictKind
    let severity: PlanningConflictSeverity
    let message: String
    let assignmentID: UUID?
    let conflictingAssignmentID: UUID?

    var id: String {
        [
            kind.rawValue,
            assignmentID?.uuidString ?? "day",
            conflictingAssignmentID?.uuidString ?? "none",
            message
        ].joined(separator: "|")
    }
}

// MARK: - Recommendations

enum PlanningRecommendationKind: String, Codable, Hashable {
    case preserveFixedCommitment = "Preserve Fixed Commitment"
    case placeWithinArrivalWindow = "Place Within Arrival Window"
    case placeBeforeDeadline = "Place Before Deadline"
    case fillOpenCapacity = "Fill Open Capacity"
    case reviewConflict = "Review Conflict"
}

struct PlanningRecommendation: Identifiable, Codable, Hashable {
    let kind: PlanningRecommendationKind
    let assignmentID: UUID?
    let message: String

    var id: String {
        "\(kind.rawValue)|\(assignmentID?.uuidString ?? "day")|\(message)"
    }
}

// MARK: - Daily Plan

/// Immutable proposal returned by `DailyPlannerEngine`.
///
/// Creating a plan never changes an Assignment. A future UI or operations
/// command must explicitly accept a proposal before committed data changes.
struct DailyPlan: Codable, Hashable {
    let technicianID: UUID
    let date: Date
    let workdayStart: Date?
    let workdayEnd: Date?
    let items: [DailyPlanItem]
    let openWindows: [PlanningWindow]
    let conflicts: [PlanningConflict]
    let recommendations: [PlanningRecommendation]
    let unplacedAssignmentIDs: [UUID]
    let dailyReserveMinutes: Int

    var assignmentItems: [DailyPlanItem] {
        items.filter { $0.kind == .assignment }
    }

    var lunchItem: DailyPlanItem? {
        items.first { $0.kind == .lunch }
    }

    var plannedAssignmentCount: Int {
        assignmentItems.count
    }

    var plannedServiceMinutes: Int {
        assignmentItems.reduce(0) { $0 + $1.serviceMinutes }
    }

    var plannedOccupiedMinutes: Int {
        items.reduce(0) { $0 + $1.occupiedMinutes }
    }

    var hasBlockingConflicts: Bool {
        conflicts.contains { $0.severity == .error }
    }

    var isComplete: Bool {
        unplacedAssignmentIDs.isEmpty && !hasBlockingConflicts
    }
}
