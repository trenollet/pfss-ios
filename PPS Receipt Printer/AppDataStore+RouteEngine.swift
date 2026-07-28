//
//  AppDataStore+RouteEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route Engine integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
    func rememberAcceptedRoutePlan(
        _ routePlan: RoutePlan,
        calendar: Calendar = .current
    ) {
        acceptedRoutePlans[routePlanKey(
            technicianID: routePlan.technicianID,
            date: routePlan.date,
            calendar: calendar
        )] = routePlan
    }

    func acceptedRoutePlan(
        for technicianID: UUID,
        on date: Date,
        calendar: Calendar = .current
    ) -> RoutePlan? {
        acceptedRoutePlans[routePlanKey(
            technicianID: technicianID,
            date: date,
            calendar: calendar
        )]
    }

    /// Refreshes road travel for the saved route sequence. When no live
    /// technician coordinate is available, the first stop is used as the
    /// route origin; this intentionally makes the first leg zero while keeping
    /// every between-job MapKit leg accurate.
    func refreshTimelineRoutePlan(
        for technician: EmployeeRecord,
        on date: Date,
        calendar: Calendar = .current
    ) async {
        let dayAssignments = assignmentEngine.activeAssignments.filter {
            $0.crew.containsActiveEmployee(technician.id) &&
            $0.scheduling.operationalDate.map {
                calendar.isDate($0, inSameDayAs: date)
            } == true
        }
        guard !dayAssignments.isEmpty else { return }

        let locations = await RouteLocationResolver().resolveLocations(
            for: dayAssignments,
            sites: sites
        )
        let locationsByID = Dictionary(
            uniqueKeysWithValues: locations.map { ($0.assignmentID, $0) }
        )
        let firstAssignment = dayAssignments.sorted {
            let left = $0.routeSequence ?? Int.max
            let right = $1.routeSequence ?? Int.max
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }.first { locationsByID[$0.id] != nil }

        guard let firstAssignment,
              let firstLocation = locationsByID[firstAssignment.id] else {
            return
        }

        let plan = await routePlan(
            for: technician,
            on: date,
            origin: RouteOrigin(
                coordinate: firstLocation.coordinate,
                label: "First Scheduled Stop"
            ),
            source: .replanned,
            preferRoadNetwork: true,
            preserveHumanRouteSequence: true,
            calendar: calendar
        )
        rememberAcceptedRoutePlan(plan, calendar: calendar)
    }

    private func routePlanKey(
        technicianID: UUID,
        date: Date,
        calendar: Calendar
    ) -> String {
        "\(technicianID.uuidString)|\(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate)"
    }

    /// Builds a non-mutating road-route proposal for one technician and day.
    ///
    /// The accepted Daily Planner proposal remains the scheduling authority.
    /// RouteEngine may reorder Flexible Day stops between constraint anchors,
    /// but it cannot silently update Assignment.routeSequence or Job records.
    func routePlan(
        for technician: EmployeeRecord,
        on date: Date,
        origin: RouteOrigin,
        source: RoutePlanSource = .recommended,
        preferRoadNetwork: Bool = true,
        preserveHumanRouteSequence: Bool = true,
        calendar: Calendar = .current,
        generatedAt: Date = Date()
    ) async -> RoutePlan {
        let dailyPlan = dailyPlan(
            for: technician,
            on: date,
            calendar: calendar
        )

        return await routePlan(
            from: dailyPlan,
            origin: origin,
            source: source,
            preferRoadNetwork: preferRoadNetwork,
            preserveHumanRouteSequence: preserveHumanRouteSequence,
            generatedAt: generatedAt
        )
    }

    /// Routes an already-generated Daily Plan. This overload lets the visual
    /// preview use the exact proposal currently on screen rather than quietly
    /// regenerating it before routing.
    func routePlan(
        from dailyPlan: DailyPlan,
        origin: RouteOrigin,
        source: RoutePlanSource = .recommended,
        preferRoadNetwork: Bool = true,
        preserveHumanRouteSequence: Bool = true,
        generatedAt: Date = Date()
    ) async -> RoutePlan {
        let plannedIDs = Set(
            dailyPlan.assignmentItems.compactMap(\.assignmentID)
        )
        let assignments = assignmentEngine.assignments
            .filter { plannedIDs.contains($0.id) }

        let resolver = RouteLocationResolver()
        let locations = await resolver.resolveLocations(
            for: assignments,
            sites: sites
        )

        var operations = businessProfile.operations
        operations.normalize()

        let fallback = StraightLineRouteTravelEstimator(
            averageDrivingSpeedMPH: operations.averageDrivingSpeedMPH
        )
        let estimator: RouteTravelEstimating = preferRoadNetwork
            ? MapKitRouteTravelEstimator(fallbackEstimator: fallback)
            : fallback

        let engine = RouteEngine(
            configuration: RouteEngineConfiguration(
                averageDrivingSpeedMPH: operations.averageDrivingSpeedMPH,
                preserveHumanRouteSequence: preserveHumanRouteSequence,
                constraintToleranceSeconds: 60
            ),
            travelEstimator: estimator
        )

        return await engine.planRoute(
            from: dailyPlan,
            assignments: assignments,
            locations: locations,
            origin: origin,
            source: source,
            generatedAt: generatedAt
        )
    }
}
