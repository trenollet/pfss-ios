//
//  RouteEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route Engine Integration
//

import Foundation

/// Produces a constraint-aware, non-mutating route proposal from an accepted
/// Daily Plan.
///
/// The engine deliberately does not update Assignment.routeSequence. Part 2
/// will expose an explicit, human-reviewed apply command through DispatchEngine.
struct RouteEngine {
    let configuration: RouteEngineConfiguration
    private let travelEstimator: RouteTravelEstimating

    init(
        configuration: RouteEngineConfiguration = RouteEngineConfiguration(),
        travelEstimator: RouteTravelEstimating? = nil
    ) {
        self.configuration = configuration
        self.travelEstimator = travelEstimator ?? StraightLineRouteTravelEstimator(
            averageDrivingSpeedMPH: configuration.averageDrivingSpeedMPH
        )
    }

    func planRoute(
        from dailyPlan: DailyPlan,
        assignments: [Assignment],
        locations: [RouteAssignmentLocation],
        origin: RouteOrigin,
        source: RoutePlanSource = .recommended,
        generatedAt: Date = Date()
    ) async -> RoutePlan {
        let assignmentLookup = Dictionary(
            uniqueKeysWithValues: assignments.map { ($0.id, $0) }
        )
        let locationLookup = Dictionary(
            uniqueKeysWithValues: locations.map { ($0.assignmentID, $0) }
        )

        var conflicts: [RoutePlanningConflict] = []
        var nodes: [RouteNode] = []
        var unrouteableIDs: [UUID] = []

        for item in dailyPlan.assignmentItems.sorted(by: timelineOrder) {
            guard let assignmentID = item.assignmentID,
                  let assignment = assignmentLookup[assignmentID] else {
                conflicts.append(
                    RoutePlanningConflict(
                        kind: .missingAssignment,
                        severity: .error,
                        message: "A Daily Plan item no longer has a matching Assignment.",
                        assignmentID: item.assignmentID
                    )
                )
                if let assignmentID = item.assignmentID {
                    unrouteableIDs.append(assignmentID)
                }
                continue
            }

            guard let location = locationLookup[assignmentID] else {
                conflicts.append(
                    RoutePlanningConflict(
                        kind: .missingLocation,
                        severity: .error,
                        message: "\(assignment.assignmentNumber) has no resolved service location and remains visible as unrouteable.",
                        assignmentID: assignmentID
                    )
                )
                unrouteableIDs.append(assignmentID)
                continue
            }

            guard location.coordinate.isValid else {
                conflicts.append(
                    RoutePlanningConflict(
                        kind: .invalidLocation,
                        severity: .error,
                        message: "\(assignment.assignmentNumber) has an invalid service coordinate.",
                        assignmentID: assignmentID
                    )
                )
                unrouteableIDs.append(assignmentID)
                continue
            }

            nodes.append(
                RouteNode(
                    assignment: assignment,
                    item: item,
                    location: location
                )
            )
        }

        let hasHumanSequence = configuration.preserveHumanRouteSequence &&
            nodes.contains { $0.assignment.routeSequence != nil }

        let orderedNodes: [RouteNode]
        if hasHumanSequence {
            orderedNodes = humanSequenceOrder(nodes)
        } else {
            orderedNodes = await constraintPreservingOrder(
                nodes,
                origin: origin,
                startingDate: dailyPlan.workdayStart ?? dailyPlan.date,
                conflicts: &conflicts
            )
        }

        let routed = await buildTimeline(
            orderedNodes,
            dailyPlan: dailyPlan,
            origin: origin,
            preservesHumanSequence: hasHumanSequence,
            conflicts: &conflicts
        )

        if hasHumanSequence && routed.contains(where: {
            $0.constraintResult == .violated
        }) {
            conflicts.append(
                RoutePlanningConflict(
                    kind: .manualSequenceConstraintConflict,
                    severity: .warning,
                    message: "The human-adjusted route was preserved, but it conflicts with at least one scheduling constraint.",
                    assignmentID: nil
                )
            )
        }

        let uniqueUnrouteableIDs = Array(Set(unrouteableIDs)).sorted {
            $0.uuidString < $1.uuidString
        }

        return RoutePlan(
            technicianID: dailyPlan.technicianID,
            date: dailyPlan.date,
            origin: origin,
            source: hasHumanSequence ? .humanAdjusted : source,
            stops: routed,
            conflicts: deduplicated(conflicts),
            unrouteableAssignmentIDs: uniqueUnrouteableIDs,
            generatedAt: generatedAt
        )
    }

    // MARK: - Ordering

    /// Reorders Flexible Day runs only. Fixed Time, Arrival Window, Deadline,
    /// and lunch positions remain anchors from the accepted Daily Plan.
    private func constraintPreservingOrder(
        _ nodes: [RouteNode],
        origin: RouteOrigin,
        startingDate: Date,
        conflicts: inout [RoutePlanningConflict]
    ) async -> [RouteNode] {
        guard !nodes.isEmpty else { return [] }

        var result: [RouteNode] = []
        var flexibleRun: [RouteNode] = []
        var currentCoordinate = origin.coordinate
        var departureDate = startingDate

        func appendAnchor(_ node: RouteNode) {
            result.append(node)
            currentCoordinate = node.location.coordinate
            departureDate = node.item.occupiedEnd
        }

        for node in nodes {
            if node.isFlexible {
                flexibleRun.append(node)
                continue
            }

            if !flexibleRun.isEmpty {
                let optimized = await nearestNeighborOrder(
                    flexibleRun,
                    startingAt: currentCoordinate,
                    departingAt: departureDate,
                    conflicts: &conflicts
                )
                result.append(contentsOf: optimized)
                if let last = optimized.last {
                    currentCoordinate = last.location.coordinate
                    departureDate = last.item.occupiedEnd
                }
                flexibleRun.removeAll(keepingCapacity: true)
            }

            appendAnchor(node)
        }

        if !flexibleRun.isEmpty {
            result.append(
                contentsOf: await nearestNeighborOrder(
                    flexibleRun,
                    startingAt: currentCoordinate,
                    departingAt: departureDate,
                    conflicts: &conflicts
                )
            )
        }

        return result
    }

    private func nearestNeighborOrder(
        _ nodes: [RouteNode],
        startingAt coordinate: RouteCoordinate,
        departingAt initialDeparture: Date,
        conflicts: inout [RoutePlanningConflict]
    ) async -> [RouteNode] {
        var remaining = nodes
        var ordered: [RouteNode] = []
        var currentCoordinate = coordinate
        var departureDate = initialDeparture

        while !remaining.isEmpty {
            var candidates: [(index: Int, estimate: RouteTravelEstimate)] = []

            for index in remaining.indices {
                do {
                    let estimate = try await travelEstimator.estimateTravel(
                        from: currentCoordinate,
                        to: remaining[index].location.coordinate,
                        departingAt: departureDate
                    )
                    candidates.append((index, estimate))
                } catch {
                    conflicts.append(
                        travelFailureConflict(
                            node: remaining[index],
                            error: error
                        )
                    )
                }
            }

            let selectedIndex = candidates.min { first, second in
                if first.estimate.expectedTravelTimeSeconds ==
                    second.estimate.expectedTravelTimeSeconds {
                    return stableNodeOrder(
                        remaining[first.index],
                        remaining[second.index]
                    )
                }
                return first.estimate.expectedTravelTimeSeconds <
                    second.estimate.expectedTravelTimeSeconds
            }?.index ?? 0

            let selected = remaining.remove(at: selectedIndex)
            ordered.append(selected)
            currentCoordinate = selected.location.coordinate
            departureDate = selected.item.occupiedEnd
        }

        return ordered
    }

    private func humanSequenceOrder(_ nodes: [RouteNode]) -> [RouteNode] {
        nodes.sorted { first, second in
            switch (first.assignment.routeSequence, second.assignment.routeSequence) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return timelineOrder(first.item, second.item)
            }
        }
    }

    // MARK: - Timeline and Constraint Validation

    private func buildTimeline(
        _ nodes: [RouteNode],
        dailyPlan: DailyPlan,
        origin: RouteOrigin,
        preservesHumanSequence: Bool,
        conflicts: inout [RoutePlanningConflict]
    ) async -> [RouteStopPlan] {
        var stops: [RouteStopPlan] = []
        var currentCoordinate = origin.coordinate
        var availableDate = dailyPlan.workdayStart ?? dailyPlan.date

        for (index, node) in nodes.enumerated() {
            let travel: RouteTravelEstimate
            do {
                travel = try await travelEstimator.estimateTravel(
                    from: currentCoordinate,
                    to: node.location.coordinate,
                    departingAt: availableDate
                )
            } catch {
                travel = .zero
                conflicts.append(travelFailureConflict(node: node, error: error))
            }

            let arrival = availableDate.addingTimeInterval(
                travel.expectedTravelTimeSeconds
            )
            let timing = timingFor(node: node, arrival: arrival)

            if let conflict = timing.conflict {
                conflicts.append(conflict)
            }

            if let workdayEnd = dailyPlan.workdayEnd,
               timing.serviceEnd > workdayEnd.addingTimeInterval(
                    configuration.constraintToleranceSeconds
               ) {
                conflicts.append(
                    RoutePlanningConflict(
                        kind: .workdayExceeded,
                        severity: .warning,
                        message: "\(node.assignment.assignmentNumber) is projected to finish after the technician's workday.",
                        assignmentID: node.assignment.id
                    )
                )
            }

            stops.append(
                RouteStopPlan(
                    sequence: index + 1,
                    assignmentID: node.assignment.id,
                    jobID: node.assignment.jobID,
                    title: node.item.title,
                    schedulingMode: node.assignment.scheduling.mode,
                    coordinate: node.location.coordinate,
                    displayAddress: node.location.displayAddress,
                    departureDate: availableDate,
                    estimatedArrivalDate: arrival,
                    serviceStartDate: timing.serviceStart,
                    serviceEndDate: timing.serviceEnd,
                    travel: travel,
                    constraintResult: timing.result,
                    isConstraintAnchor: !node.isFlexible,
                    preservesHumanSequence: preservesHumanSequence &&
                        node.assignment.routeSequence != nil
                )
            )

            currentCoordinate = node.location.coordinate
            availableDate = timing.serviceEnd.addingTimeInterval(
                TimeInterval(node.postServiceMinutes * 60)
            )
        }

        return stops
    }

    private func timingFor(
        node: RouteNode,
        arrival: Date
    ) -> RouteTimingResult {
        let duration = TimeInterval(node.item.serviceMinutes * 60)
        let tolerance = configuration.constraintToleranceSeconds
        let scheduling = node.assignment.scheduling

        switch scheduling.mode {
        case .fixedTime:
            let fixedStart = scheduling.fixedStartDate ?? node.item.serviceStart
            let projectedStart = max(arrival, fixedStart)
            let end = projectedStart.addingTimeInterval(duration)
            let isLate = arrival > fixedStart.addingTimeInterval(tolerance)
            return RouteTimingResult(
                serviceStart: projectedStart,
                serviceEnd: end,
                result: isLate ? .violated : .satisfied,
                conflict: isLate
                    ? RoutePlanningConflict(
                        kind: .fixedStartMissed,
                        severity: .error,
                        message: "Travel projects arrival after the fixed start for \(node.assignment.assignmentNumber).",
                        assignmentID: node.assignment.id
                    )
                    : nil
            )

        case .arrivalWindow:
            let windowStart = scheduling.arrivalWindowStart ?? node.item.serviceStart
            let windowEnd = scheduling.arrivalWindowEnd ?? node.item.serviceStart
            let start = max(arrival, windowStart)
            let end = start.addingTimeInterval(duration)
            let missed = start > windowEnd.addingTimeInterval(tolerance)
            return RouteTimingResult(
                serviceStart: start,
                serviceEnd: end,
                result: missed ? .violated : .satisfied,
                conflict: missed
                    ? RoutePlanningConflict(
                        kind: .arrivalWindowMissed,
                        severity: .error,
                        message: "The projected arrival for \(node.assignment.assignmentNumber) falls after its arrival window.",
                        assignmentID: node.assignment.id
                    )
                    : nil
            )

        case .flexibleDay:
            let start = max(arrival, node.item.serviceStart)
            return RouteTimingResult(
                serviceStart: start,
                serviceEnd: start.addingTimeInterval(duration),
                result: .notApplicable,
                conflict: nil
            )

        case .deadline:
            let start = max(arrival, node.item.serviceStart)
            let end = start.addingTimeInterval(duration)
            let deadline = scheduling.completionDeadline ?? node.item.serviceEnd
            let missed = end > deadline.addingTimeInterval(tolerance)
            return RouteTimingResult(
                serviceStart: start,
                serviceEnd: end,
                result: missed ? .violated : .satisfied,
                conflict: missed
                    ? RoutePlanningConflict(
                        kind: .deadlineMissed,
                        severity: .error,
                        message: "The projected completion for \(node.assignment.assignmentNumber) falls after its deadline.",
                        assignmentID: node.assignment.id
                    )
                    : nil
            )
        }
    }

    // MARK: - Helpers

    private func timelineOrder(_ first: DailyPlanItem, _ second: DailyPlanItem) -> Bool {
        if first.occupiedStart != second.occupiedStart {
            return first.occupiedStart < second.occupiedStart
        }
        return (first.assignmentID?.uuidString ?? first.id) <
            (second.assignmentID?.uuidString ?? second.id)
    }

    private func stableNodeOrder(_ first: RouteNode, _ second: RouteNode) -> Bool {
        if first.item.occupiedStart != second.item.occupiedStart {
            return first.item.occupiedStart < second.item.occupiedStart
        }
        return first.assignment.id.uuidString < second.assignment.id.uuidString
    }

    private func travelFailureConflict(
        node: RouteNode,
        error: Error
    ) -> RoutePlanningConflict {
        RoutePlanningConflict(
            kind: .travelEstimateFailed,
            severity: .warning,
            message: "Travel could not be estimated for \(node.assignment.assignmentNumber): \(error.localizedDescription)",
            assignmentID: node.assignment.id
        )
    }

    private func deduplicated(
        _ conflicts: [RoutePlanningConflict]
    ) -> [RoutePlanningConflict] {
        var seen = Set<String>()
        return conflicts.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Built-In Deterministic Estimator

/// Offline estimator retained as a safe fallback and deterministic testable
/// implementation. A MapKit provider can replace it through dependency
/// injection without changing RouteEngine.
struct StraightLineRouteTravelEstimator: RouteTravelEstimating {
    let averageDrivingSpeedMPH: Double

    init(averageDrivingSpeedMPH: Double = 30) {
        self.averageDrivingSpeedMPH = min(
            max(averageDrivingSpeedMPH.isFinite ? averageDrivingSpeedMPH : 30, 5),
            80
        )
    }

    func estimateTravel(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        departingAt departureDate: Date
    ) async throws -> RouteTravelEstimate {
        guard origin.isValid, destination.isValid else {
            throw RouteEngineError.invalidCoordinate
        }

        let distance = haversineDistance(from: origin, to: destination)
        let metersPerSecond = averageDrivingSpeedMPH * 0.44704
        return RouteTravelEstimate(
            distanceMeters: distance,
            expectedTravelTimeSeconds: metersPerSecond > 0
                ? distance / metersPerSecond
                : 0,
            source: .straightLineEstimate
        )
    }

    private func haversineDistance(
        from first: RouteCoordinate,
        to second: RouteCoordinate
    ) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let firstLatitude = first.latitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180

        let value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(firstLatitude) * cos(secondLatitude) *
            sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let arc = 2 * atan2(sqrt(value), sqrt(max(1 - value, 0)))
        return earthRadiusMeters * arc
    }
}

enum RouteEngineError: LocalizedError {
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "The route contains an invalid coordinate."
        }
    }
}

// MARK: - Private Types

private extension RouteEngine {
    struct RouteNode {
        let assignment: Assignment
        let item: DailyPlanItem
        let location: RouteAssignmentLocation

        var isFlexible: Bool {
            assignment.scheduling.mode == .flexibleDay &&
            !item.isFixedCommitment
        }

        var postServiceMinutes: Int {
            max(item.occupiedMinutes - item.serviceMinutes, 0)
        }
    }

    struct RouteTimingResult {
        let serviceStart: Date
        let serviceEnd: Date
        let result: RouteConstraintResult
        let conflict: RoutePlanningConflict?
    }
}

