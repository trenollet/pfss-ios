//
//  RoutePlanningModels.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route Engine Integration
//

import Foundation

// MARK: - Geographic Inputs

/// Codable coordinate used at the Route Engine boundary.
///
/// Core Location and MapKit adapters can convert this value without making the
/// route-domain models depend on either framework.
struct RouteCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) &&
        (-180...180).contains(longitude)
    }
}

/// Resolved service location for one Assignment.
struct RouteAssignmentLocation: Codable, Hashable {
    let assignmentID: UUID
    let coordinate: RouteCoordinate
    let displayAddress: String

    init(
        assignmentID: UUID,
        coordinate: RouteCoordinate,
        displayAddress: String = ""
    ) {
        self.assignmentID = assignmentID
        self.coordinate = coordinate
        self.displayAddress = displayAddress
    }
}

struct RouteOrigin: Codable, Hashable {
    let coordinate: RouteCoordinate
    let label: String

    init(coordinate: RouteCoordinate, label: String = "Route Start") {
        self.coordinate = coordinate
        self.label = label
    }
}

// MARK: - Travel Estimation

enum RouteTravelEstimateSource: String, Codable, Hashable {
    case straightLineEstimate = "Straight-Line Estimate"
    case roadNetwork = "Road Network"
    case cachedRoadNetwork = "Cached Road Network"
    case manual = "Manual"
}

struct RouteTravelEstimate: Codable, Hashable {
    let distanceMeters: Double
    let expectedTravelTimeSeconds: TimeInterval
    let source: RouteTravelEstimateSource

    init(
        distanceMeters: Double,
        expectedTravelTimeSeconds: TimeInterval,
        source: RouteTravelEstimateSource
    ) {
        self.distanceMeters = distanceMeters.isFinite
            ? max(distanceMeters, 0)
            : 0
        self.expectedTravelTimeSeconds = expectedTravelTimeSeconds.isFinite
            ? max(expectedTravelTimeSeconds, 0)
            : 0
        self.source = source
    }

    var distanceMiles: Double {
        distanceMeters / 1_609.344
    }

    var expectedTravelMinutes: Int {
        max(Int((expectedTravelTimeSeconds / 60).rounded()), 0)
    }

    static let zero = RouteTravelEstimate(
        distanceMeters: 0,
        expectedTravelTimeSeconds: 0,
        source: .straightLineEstimate
    )
}

/// Injectable boundary for straight-line, MapKit, cached, or test travel data.
protocol RouteTravelEstimating {
    func estimateTravel(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        departingAt departureDate: Date
    ) async throws -> RouteTravelEstimate
}

// MARK: - Route Configuration

struct RouteEngineConfiguration: Codable, Hashable {
    /// Used by the built-in deterministic estimator until road routing is
    /// supplied by the MapKit adapter.
    var averageDrivingSpeedMPH: Double

    /// Existing Assignment routeSequence values represent reviewed human
    /// choices and remain authoritative by default.
    var preserveHumanRouteSequence: Bool

    /// Allows small routing/clock differences without creating false alarms.
    var constraintToleranceSeconds: TimeInterval

    init(
        averageDrivingSpeedMPH: Double = 30,
        preserveHumanRouteSequence: Bool = true,
        constraintToleranceSeconds: TimeInterval = 60
    ) {
        self.averageDrivingSpeedMPH = min(
            max(averageDrivingSpeedMPH.isFinite ? averageDrivingSpeedMPH : 30, 5),
            80
        )
        self.preserveHumanRouteSequence = preserveHumanRouteSequence
        self.constraintToleranceSeconds = max(
            constraintToleranceSeconds.isFinite ? constraintToleranceSeconds : 0,
            0
        )
    }
}

enum RoutePlanSource: String, Codable, Hashable {
    case recommended = "PFSS Recommended"
    case humanAdjusted = "Human Adjusted"
    case replanned = "Replanned"
}

// MARK: - Constraint Results

enum RouteConstraintKind: String, Codable, Hashable {
    case fixedStart = "Fixed Start"
    case arrivalWindow = "Arrival Window"
    case deadline = "Deadline"
    case workday = "Workday"
}

enum RouteConstraintResult: String, Codable, Hashable {
    case satisfied = "Satisfied"
    case atRisk = "At Risk"
    case violated = "Violated"
    case notApplicable = "Not Applicable"
}

enum RoutePlanningConflictKind: String, Codable, Hashable {
    case missingAssignment = "Missing Assignment"
    case missingLocation = "Missing Location"
    case invalidLocation = "Invalid Location"
    case travelEstimateFailed = "Travel Estimate Failed"
    case fixedStartMissed = "Fixed Start Missed"
    case arrivalWindowMissed = "Arrival Window Missed"
    case deadlineMissed = "Deadline Missed"
    case workdayExceeded = "Workday Exceeded"
    case manualSequenceConstraintConflict = "Manual Sequence Constraint Conflict"
}

enum RoutePlanningConflictSeverity: String, Codable, Hashable {
    case warning = "Warning"
    case error = "Error"
}

struct RoutePlanningConflict: Identifiable, Codable, Hashable {
    let kind: RoutePlanningConflictKind
    let severity: RoutePlanningConflictSeverity
    let message: String
    let assignmentID: UUID?

    var id: String {
        [
            kind.rawValue,
            assignmentID?.uuidString ?? "route",
            message
        ].joined(separator: "|")
    }
}

// MARK: - Route Output

struct RouteStopPlan: Identifiable, Codable, Hashable {
    let sequence: Int
    let assignmentID: UUID
    let jobID: UUID
    let title: String
    let schedulingMode: AssignmentSchedulingMode
    let coordinate: RouteCoordinate
    let displayAddress: String
    let departureDate: Date
    let estimatedArrivalDate: Date
    let serviceStartDate: Date
    let serviceEndDate: Date
    let travel: RouteTravelEstimate
    let constraintResult: RouteConstraintResult
    let isConstraintAnchor: Bool
    let preservesHumanSequence: Bool

    var id: UUID { assignmentID }

    var serviceMinutes: Int {
        max(Int(serviceEndDate.timeIntervalSince(serviceStartDate) / 60), 0)
    }
}

/// Immutable route proposal. Generating this value never changes an
/// Assignment, Job, or routeSequence.
struct RoutePlan: Codable, Hashable {
    let technicianID: UUID
    let date: Date
    let origin: RouteOrigin
    let source: RoutePlanSource
    let stops: [RouteStopPlan]
    let conflicts: [RoutePlanningConflict]
    let unrouteableAssignmentIDs: [UUID]
    let generatedAt: Date

    var stopCount: Int { stops.count }

    var orderedAssignmentIDs: [UUID] {
        stops.sorted { $0.sequence < $1.sequence }.map(\.assignmentID)
    }

    var totalDistanceMeters: Double {
        stops.reduce(0) { $0 + $1.travel.distanceMeters }
    }

    var totalDistanceMiles: Double {
        totalDistanceMeters / 1_609.344
    }

    var totalDriveTimeSeconds: TimeInterval {
        stops.reduce(0) { $0 + $1.travel.expectedTravelTimeSeconds }
    }

    var totalDriveMinutes: Int {
        max(Int((totalDriveTimeSeconds / 60).rounded()), 0)
    }

    var totalServiceMinutes: Int {
        stops.reduce(0) { $0 + $1.serviceMinutes }
    }

    var estimatedCompletionDate: Date? {
        stops.max(by: { $0.serviceEndDate < $1.serviceEndDate })?.serviceEndDate
    }

    var hasBlockingConflicts: Bool {
        conflicts.contains { $0.severity == .error }
    }

    var isComplete: Bool {
        unrouteableAssignmentIDs.isEmpty && !hasBlockingConflicts
    }
}

