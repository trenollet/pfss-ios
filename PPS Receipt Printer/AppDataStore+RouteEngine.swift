//
//  AppDataStore+RouteEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route Engine integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
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
                preserveHumanRouteSequence: true,
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

