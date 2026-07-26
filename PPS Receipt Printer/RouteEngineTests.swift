//
//  RouteEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.4 – Route Engine Integration
//

import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct RouteEngineTests {
    private let technicianID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let origin = RouteOrigin(
        coordinate: RouteCoordinate(latitude: 35.4676, longitude: -97.5164),
        label: "Shop"
    )

    @Test func fixedCommitmentRemainsAnAnchor() async throws {
        let day = makeDate(hour: 0)
        let flexible = makeAssignment(
            idSeed: 1,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 8)
        )
        let fixed = makeAssignment(
            idSeed: 2,
            mode: .fixedTime,
            serviceDate: day,
            start: makeDate(hour: 10)
        )
        let plan = makePlan(day: day, assignments: [flexible, fixed])

        let route = await makeEngine().planRoute(
            from: plan,
            assignments: [flexible, fixed],
            locations: locations(for: [flexible, fixed]),
            origin: origin,
            generatedAt: day
        )

        let fixedStop = try #require(
            route.stops.first { $0.assignmentID == fixed.id }
        )
        #expect(fixedStop.serviceStartDate == makeDate(hour: 10))
        #expect(fixedStop.isConstraintAnchor)
        #expect(fixedStop.constraintResult == .satisfied)
    }

    @Test func flexibleRunUsesNearestNeighborOrder() async {
        let day = makeDate(hour: 0)
        let far = makeAssignment(
            idSeed: 1,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 8)
        )
        let near = makeAssignment(
            idSeed: 2,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 9)
        )
        let estimator = MatrixEstimator(
            secondsByDestinationLatitude: [
                1: 1_800,
                2: 300
            ]
        )

        let route = await RouteEngine(travelEstimator: estimator).planRoute(
            from: makePlan(day: day, assignments: [far, near]),
            assignments: [far, near],
            locations: [
                location(for: far, latitude: 1),
                location(for: near, latitude: 2)
            ],
            origin: origin,
            generatedAt: day
        )

        #expect(route.orderedAssignmentIDs.first == near.id)
    }

    @Test func generousDeadlineDoesNotOverrideGeographicOrder() async {
        let day = makeDate(hour: 0)
        let deadline = makeAssignment(
            idSeed: 1,
            mode: .deadline,
            serviceDate: day,
            start: makeDate(hour: 8),
            deadline: makeDate(hour: 17)
        )
        let nearbyFlexible = makeAssignment(
            idSeed: 2,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 9)
        )
        let estimator = MatrixEstimator(
            secondsByDestinationLatitude: [
                1: 1_800,
                2: 300
            ]
        )

        let route = await RouteEngine(travelEstimator: estimator).planRoute(
            from: makePlan(day: day, assignments: [deadline, nearbyFlexible]),
            assignments: [deadline, nearbyFlexible],
            locations: [
                location(for: deadline, latitude: 1),
                location(for: nearbyFlexible, latitude: 2)
            ],
            origin: origin,
            generatedAt: day
        )

        #expect(route.orderedAssignmentIDs == [nearbyFlexible.id, deadline.id])
        #expect(route.conflicts.contains { $0.kind == .deadlineMissed } == false)
    }

    @Test func lateArrivalProducesFixedStartConflict() async throws {
        let day = makeDate(hour: 0)
        let fixed = makeAssignment(
            idSeed: 1,
            mode: .fixedTime,
            serviceDate: day,
            start: makeDate(hour: 8)
        )
        let estimator = ConstantEstimator(travelSeconds: 30 * 60)

        let route = await RouteEngine(travelEstimator: estimator).planRoute(
            from: makePlan(day: day, assignments: [fixed]),
            assignments: [fixed],
            locations: locations(for: [fixed]),
            origin: origin,
            generatedAt: day
        )

        let stop = try #require(route.stops.first)
        #expect(stop.constraintResult == .violated)
        #expect(route.conflicts.contains {
            $0.kind == .fixedStartMissed && $0.assignmentID == fixed.id
        })
    }

    @Test func arrivalWindowAndDeadlineAreValidated() async {
        let day = makeDate(hour: 0)
        let window = makeAssignment(
            idSeed: 1,
            mode: .arrivalWindow,
            serviceDate: day,
            start: makeDate(hour: 8),
            windowEnd: makeDate(hour: 8, minute: 15)
        )
        let deadline = makeAssignment(
            idSeed: 2,
            mode: .deadline,
            serviceDate: day,
            start: makeDate(hour: 9),
            deadline: makeDate(hour: 9, minute: 30)
        )
        let estimator = ConstantEstimator(travelSeconds: 60 * 60)

        let route = await RouteEngine(travelEstimator: estimator).planRoute(
            from: makePlan(day: day, assignments: [window, deadline]),
            assignments: [window, deadline],
            locations: locations(for: [window, deadline]),
            origin: origin,
            generatedAt: day
        )

        #expect(route.conflicts.contains { $0.kind == .arrivalWindowMissed })
        #expect(route.conflicts.contains { $0.kind == .deadlineMissed })
    }

    @Test func humanRouteSequenceIsPreservedAndIdentified() async {
        let day = makeDate(hour: 0)
        var first = makeAssignment(
            idSeed: 1,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 8)
        )
        var second = makeAssignment(
            idSeed: 2,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 9)
        )
        first.routeSequence = 2
        second.routeSequence = 1

        let route = await makeEngine().planRoute(
            from: makePlan(day: day, assignments: [first, second]),
            assignments: [first, second],
            locations: locations(for: [first, second]),
            origin: origin,
            generatedAt: day
        )

        #expect(route.source == .humanAdjusted)
        #expect(route.orderedAssignmentIDs == [second.id, first.id])
        #expect(route.stops.allSatisfy { $0.preservesHumanSequence })
    }

    @Test func missingLocationRemainsVisibleAsUnrouteable() async {
        let day = makeDate(hour: 0)
        let assignment = makeAssignment(
            idSeed: 1,
            mode: .flexibleDay,
            serviceDate: day,
            start: makeDate(hour: 8)
        )

        let route = await makeEngine().planRoute(
            from: makePlan(day: day, assignments: [assignment]),
            assignments: [assignment],
            locations: [],
            origin: origin,
            generatedAt: day
        )

        #expect(route.stops.isEmpty)
        #expect(route.unrouteableAssignmentIDs == [assignment.id])
        #expect(route.conflicts.contains { $0.kind == .missingLocation })
    }

    @Test func identicalInputsProduceIdenticalRoute() async {
        let day = makeDate(hour: 0)
        let assignments = [
            makeAssignment(
                idSeed: 1,
                mode: .flexibleDay,
                serviceDate: day,
                start: makeDate(hour: 8)
            ),
            makeAssignment(
                idSeed: 2,
                mode: .flexibleDay,
                serviceDate: day,
                start: makeDate(hour: 9)
            )
        ]
        let plan = makePlan(day: day, assignments: assignments)
        let engine = makeEngine()
        let routeLocations = locations(for: assignments)

        let first = await engine.planRoute(
            from: plan,
            assignments: assignments,
            locations: routeLocations,
            origin: origin,
            generatedAt: day
        )
        let second = await engine.planRoute(
            from: plan,
            assignments: assignments.reversed(),
            locations: routeLocations.reversed(),
            origin: origin,
            generatedAt: day
        )

        #expect(first == second)
    }

    // MARK: - Fixtures

    private func makeEngine() -> RouteEngine {
        RouteEngine(travelEstimator: ConstantEstimator(travelSeconds: 5 * 60))
    }

    private func makeAssignment(
        idSeed: Int,
        mode: AssignmentSchedulingMode,
        serviceDate: Date,
        start: Date,
        windowEnd: Date? = nil,
        deadline: Date? = nil
    ) -> Assignment {
        let id = UUID(
            uuidString: String(
                format: "20000000-0000-0000-0000-%012d",
                idSeed
            )
        )!
        let scheduling = AssignmentScheduling(
            mode: mode,
            serviceDate: serviceDate,
            fixedStartDate: mode == .fixedTime ? start : nil,
            arrivalWindowStart: mode == .arrivalWindow ? start : nil,
            arrivalWindowEnd: mode == .arrivalWindow
                ? (windowEnd ?? start.addingTimeInterval(60 * 60))
                : nil,
            completionDeadline: mode == .deadline
                ? (deadline ?? start.addingTimeInterval(60 * 60))
                : nil,
            estimatedDurationMinutes: 30,
            isCustomerConfirmed: mode == .fixedTime
        )

        return Assignment(
            id: id,
            assignmentNumber: "ASN-\(idSeed)",
            jobID: UUID(),
            jobNumber: "JOB-\(idSeed)",
            customerNumber: "CUS-\(idSeed)",
            status: .scheduled,
            scheduling: scheduling
        )
    }

    private func makePlan(
        day: Date,
        assignments: [Assignment]
    ) -> DailyPlan {
        let sorted = assignments.sorted {
            ($0.scheduling.operationalDate ?? day) <
            ($1.scheduling.operationalDate ?? day)
        }
        let items = sorted.enumerated().map { index, assignment in
            let start = plannedStart(for: assignment, fallbackIndex: index)
            let end = start.addingTimeInterval(
                TimeInterval(assignment.scheduling.estimatedDurationMinutes * 60)
            )
            return DailyPlanItem(
                kind: .assignment,
                assignmentID: assignment.id,
                jobID: assignment.jobID,
                technicianID: technicianID,
                title: assignment.assignmentNumber,
                schedulingMode: assignment.scheduling.mode,
                serviceStart: start,
                serviceEnd: end,
                occupiedStart: start,
                occupiedEnd: end,
                isFixedCommitment: assignment.scheduling.mode == .fixedTime,
                explanation: "Test"
            )
        }

        return DailyPlan(
            technicianID: technicianID,
            date: day,
            workdayStart: makeDate(hour: 8),
            workdayEnd: makeDate(hour: 17),
            items: items,
            openWindows: [],
            conflicts: [],
            recommendations: [],
            unplacedAssignmentIDs: [],
            dailyReserveMinutes: 0
        )
    }

    private func plannedStart(
        for assignment: Assignment,
        fallbackIndex: Int
    ) -> Date {
        switch assignment.scheduling.mode {
        case .fixedTime:
            return assignment.scheduling.fixedStartDate!
        case .arrivalWindow:
            return assignment.scheduling.arrivalWindowStart!
        case .flexibleDay:
            return makeDate(hour: 8 + fallbackIndex)
        case .deadline:
            return makeDate(hour: 8 + fallbackIndex)
        }
    }

    private func locations(
        for assignments: [Assignment]
    ) -> [RouteAssignmentLocation] {
        assignments.enumerated().map { index, assignment in
            location(
                for: assignment,
                latitude: 35.47 + Double(index) * 0.01
            )
        }
    }

    private func location(
        for assignment: Assignment,
        latitude: Double
    ) -> RouteAssignmentLocation {
        RouteAssignmentLocation(
            assignmentID: assignment.id,
            coordinate: RouteCoordinate(
                latitude: latitude,
                longitude: -97.52
            ),
            displayAddress: "Test Address"
        )
    }

    private func makeDate(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = testCalendar
        components.timeZone = testCalendar.timeZone
        components.year = 2026
        components.month = 7
        components.day = 22
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct ConstantEstimator: RouteTravelEstimating {
    let travelSeconds: TimeInterval

    func estimateTravel(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        departingAt departureDate: Date
    ) async throws -> RouteTravelEstimate {
        RouteTravelEstimate(
            distanceMeters: travelSeconds,
            expectedTravelTimeSeconds: travelSeconds,
            source: .manual
        )
    }
}

private struct MatrixEstimator: RouteTravelEstimating {
    let secondsByDestinationLatitude: [Double: TimeInterval]

    func estimateTravel(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        departingAt departureDate: Date
    ) async throws -> RouteTravelEstimate {
        let seconds = secondsByDestinationLatitude[destination.latitude] ?? 600
        return RouteTravelEstimate(
            distanceMeters: seconds,
            expectedTravelTimeSeconds: seconds,
            source: .manual
        )
    }
}
