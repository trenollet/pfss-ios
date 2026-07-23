//
//  LiveMapEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.9 – Live Map View
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class LiveMapEngineTests: XCTestCase {
    private let technicianID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let firstAssignmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let secondAssignmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    func testResolvedAssignmentsAndLiveTechnicianProducePinsAndRoute() {
        let now = date(hour: 8)
        let board = makeBoard(generatedAt: now)
        let observation = LiveTechnicianLocationObservation(
            technicianID: technicianID,
            coordinate: RouteCoordinate(latitude: 35.45, longitude: -97.52),
            recordedAt: now.addingTimeInterval(-30),
            horizontalAccuracyMeters: 8,
            state: .live
        )

        let snapshot = LiveMapEngine().snapshot(
            board: board,
            assignmentLocations: makeLocations(),
            technicianObservations: [observation],
            technicianColorNames: [technicianID: "orange"],
            generatedAt: now
        )

        XCTAssertEqual(snapshot.assignmentPins.map(\.id), [firstAssignmentID, secondAssignmentID])
        XCTAssertEqual(snapshot.technicianPins.first?.locationState, .live)
        XCTAssertEqual(snapshot.technicianPins.first?.destinationAssignmentID, firstAssignmentID)
        XCTAssertEqual(snapshot.routeSegments.count, 2)
        XCTAssertEqual(snapshot.routeSegments.map(\.destinationAssignmentID), [firstAssignmentID, secondAssignmentID])
        XCTAssertTrue(snapshot.alerts.isEmpty)
    }

    func testMissingObservationDoesNotFabricateTechnicianCoordinate() {
        let now = date(hour: 8)
        let snapshot = LiveMapEngine().snapshot(
            board: makeBoard(generatedAt: now),
            assignmentLocations: makeLocations(),
            technicianObservations: [],
            technicianColorNames: [:],
            generatedAt: now
        )

        XCTAssertNil(snapshot.technicianPins.first?.coordinate)
        XCTAssertEqual(snapshot.technicianPins.first?.locationState, .notReported)
        XCTAssertEqual(snapshot.reportingTechnicianCount, 0)
        XCTAssertTrue(snapshot.alerts.contains { $0.kind == .technicianNotReporting })
    }

    func testOldObservationIsMarkedStaleButRetainsLastKnownCoordinate() {
        let now = date(hour: 8)
        let observation = LiveTechnicianLocationObservation(
            technicianID: technicianID,
            coordinate: RouteCoordinate(latitude: 35.45, longitude: -97.52),
            recordedAt: now.addingTimeInterval(-10 * 60),
            horizontalAccuracyMeters: 12,
            state: .live
        )

        let snapshot = LiveMapEngine(staleLocationInterval: 5 * 60).snapshot(
            board: makeBoard(generatedAt: now),
            assignmentLocations: makeLocations(),
            technicianObservations: [observation],
            technicianColorNames: [:],
            generatedAt: now
        )

        XCTAssertEqual(snapshot.technicianPins.first?.locationState, .stale)
        XCTAssertNotNil(snapshot.technicianPins.first?.coordinate)
        XCTAssertTrue(snapshot.alerts.contains { $0.kind == .staleTechnicianLocation })
    }

    func testPermissionDeniedIsSafeAndExplainable() {
        let now = date(hour: 8)
        let denied = LiveTechnicianLocationObservation(
            technicianID: technicianID,
            coordinate: nil,
            recordedAt: nil,
            horizontalAccuracyMeters: nil,
            state: .permissionDenied
        )

        let snapshot = LiveMapEngine().snapshot(
            board: makeBoard(generatedAt: now),
            assignmentLocations: makeLocations(),
            technicianObservations: [denied],
            technicianColorNames: [:],
            generatedAt: now
        )

        XCTAssertNil(snapshot.technicianPins.first?.coordinate)
        XCTAssertEqual(snapshot.technicianPins.first?.locationState, .permissionDenied)
        XCTAssertTrue(snapshot.alerts.contains { $0.kind == .technicianLocationUnavailable })
    }

    func testMissingServiceLocationNamesTheCustomerAndAssignment() {
        let now = date(hour: 8)
        let snapshot = LiveMapEngine().snapshot(
            board: makeBoard(generatedAt: now),
            assignmentLocations: [makeLocations()[0]],
            technicianObservations: [],
            technicianColorNames: [:],
            generatedAt: now
        )

        let alert = snapshot.alerts.first {
            $0.kind == .missingAssignmentLocation &&
            $0.assignmentID == secondAssignmentID
        }
        XCTAssertEqual(alert?.title, "Beta Customer · South Site")
        XCTAssertEqual(snapshot.locatedAssignmentCount, 1)
    }

    private func makeBoard(generatedAt: Date) -> DispatchBoardSnapshot {
        let first = makeItem(
            id: firstAssignmentID,
            customerName: "Alpha Customer",
            siteName: "North Site",
            routeSequence: 1,
            start: date(hour: 9),
            isCurrent: true
        )
        let second = makeItem(
            id: secondAssignmentID,
            customerName: "Beta Customer",
            siteName: "South Site",
            routeSequence: 2,
            start: date(hour: 11),
            isCurrent: false
        )
        let plan = DailyPlan(
            technicianID: technicianID,
            date: generatedAt,
            workdayStart: date(hour: 8),
            workdayEnd: date(hour: 17),
            items: [],
            openWindows: [],
            conflicts: [],
            recommendations: [],
            unplacedAssignmentIDs: [],
            dailyReserveMinutes: 0
        )
        let lane = DispatchBoardTechnicianLane(
            id: technicianID,
            technicianName: "Taylor Tech",
            technicianState: .scheduled,
            assignments: [second, first],
            currentAssignmentID: firstAssignmentID,
            nextAssignmentID: secondAssignmentID,
            plannedServiceMinutes: 120,
            capacityMinutes: 540,
            utilization: 0.22,
            dailyPlan: plan,
            alerts: []
        )
        return DispatchBoardSnapshot(
            date: generatedAt,
            generatedAt: generatedAt,
            technicianLanes: [lane],
            unassignedItems: [],
            alerts: []
        )
    }

    private func makeItem(
        id: UUID,
        customerName: String,
        siteName: String,
        routeSequence: Int,
        start: Date,
        isCurrent: Bool
    ) -> DispatchBoardAssignmentItem {
        DispatchBoardAssignmentItem(
            id: id,
            jobID: UUID(),
            assignmentNumber: "ASN-\(routeSequence)",
            jobNumber: "JOB-\(routeSequence)",
            customerName: customerName,
            siteName: siteName,
            siteAddress: "Oklahoma City, OK",
            serviceName: "Window Cleaning",
            status: .scheduled,
            priority: .normal,
            schedulingMode: .fixedTime,
            scheduleDateText: "Jul 23, 2026",
            scheduleTimeText: "9:00 AM",
            plannedStart: start,
            plannedEnd: start.addingTimeInterval(60 * 60),
            estimatedArrival: start,
            serviceMinutes: 60,
            routeSequence: routeSequence,
            primaryTechnicianID: technicianID,
            supportingTechnicianIDs: [],
            isCurrent: isCurrent,
            hasBlockingConflict: false,
            warnings: []
        )
    }

    private func makeLocations() -> [RouteAssignmentLocation] {
        [
            RouteAssignmentLocation(
                assignmentID: firstAssignmentID,
                coordinate: RouteCoordinate(latitude: 35.50, longitude: -97.50),
                displayAddress: "North Site, Oklahoma City"
            ),
            RouteAssignmentLocation(
                assignmentID: secondAssignmentID,
                coordinate: RouteCoordinate(latitude: 35.55, longitude: -97.45),
                displayAddress: "South Site, Oklahoma City"
            )
        ]
    }

    private func date(hour: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 23,
                hour: hour
            )
        )!
    }
}
