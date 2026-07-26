//
//  OperationsTimelineEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.8 – Synchronized Operations Timeline
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OperationsTimelineEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let technicianID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let assignmentID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let jobID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!

    func testEntriesAreChronologicalAndStable() {
        let snapshot = makeTimelineSnapshot()
        let lane = snapshot.lanes[0]

        XCTAssertEqual(lane.entries.map(\.kind), [
            .openCapacity,
            .stopBuffer,
            .assignment,
            .stopBuffer,
            .openCapacity,
            .lunch,
            .openCapacity
        ])
        XCTAssertEqual(lane.entries, lane.entries.sorted { $0.start < $1.start })
    }

    func testPlannerIntervalsExposeBuffersLunchAndOpenCapacity() {
        let snapshot = makeTimelineSnapshot()
        let lane = snapshot.lanes[0]

        XCTAssertEqual(lane.entries.filter { $0.kind == .stopBuffer }.count, 2)
        XCTAssertEqual(lane.entries.filter { $0.kind == .travel }.count, 0)
        XCTAssertTrue(lane.entries.contains { $0.kind == .lunch })
        XCTAssertEqual(
            lane.entries.filter { $0.kind == .openCapacity }.count,
            3
        )
        XCTAssertEqual(lane.scheduledMinutes, 60)
        XCTAssertEqual(lane.openMinutes, 432)
    }

    func testAcceptedRouteCreatesMappedTravelInsteadOfOpenCapacity() throws {
        let stop = RouteStopPlan(
            sequence: 1,
            assignmentID: assignmentID,
            jobID: jobID,
            title: "Customer",
            schedulingMode: .fixedTime,
            coordinate: RouteCoordinate(latitude: 35.5, longitude: -97.5),
            displayAddress: "123 Main Street",
            departureDate: date(hour: 8, minute: 40),
            estimatedArrivalDate: date(hour: 8, minute: 55),
            serviceStartDate: date(hour: 9),
            serviceEndDate: date(hour: 10),
            travel: RouteTravelEstimate(
                distanceMeters: 8_046.72,
                expectedTravelTimeSeconds: 15 * 60,
                source: .roadNetwork
            ),
            constraintResult: .satisfied,
            isConstraintAnchor: true,
            preservesHumanSequence: true
        )
        let route = RoutePlan(
            technicianID: technicianID,
            date: day,
            origin: RouteOrigin(
                coordinate: RouteCoordinate(latitude: 35.4, longitude: -97.4)
            ),
            source: .humanAdjusted,
            stops: [stop],
            conflicts: [],
            unrouteableAssignmentIDs: [],
            generatedAt: date(hour: 7)
        )

        let snapshot = makeEngine().snapshot(
            board: makeBoard(),
            assignments: [],
            jobs: [],
            employees: [makeEmployee()],
            routePlansByTechnicianID: [technicianID: route]
        )
        let travel = try XCTUnwrap(
            snapshot.lanes[0].entries.first { $0.kind == .travel }
        )

        XCTAssertEqual(travel.durationMinutes, 15)
        XCTAssertEqual(travel.title, "Travel")
        XCTAssertTrue(travel.detail.contains("Apple Maps estimate"))
        XCTAssertFalse(
            snapshot.lanes[0].entries.contains {
                $0.kind == .openCapacity &&
                $0.start == stop.departureDate &&
                $0.end == stop.estimatedArrivalDate
            }
        )
    }

    func testEverySchedulingModeMapsToDistinctConstraint() {
        XCTAssertEqual(
            OperationsTimelineConstraint(mode: .fixedTime),
            .fixedTime
        )
        XCTAssertEqual(
            OperationsTimelineConstraint(mode: .arrivalWindow),
            .arrivalWindow
        )
        XCTAssertEqual(
            OperationsTimelineConstraint(mode: .flexibleDay),
            .flexibleDay
        )
        XCTAssertEqual(
            OperationsTimelineConstraint(mode: .deadline),
            .deadline
        )
    }

    func testAssignmentConflictsRemainVisible() {
        var board = makeBoard()
        let conflicted = makeBoardItem(hasConflict: true)
        let lane = board.technicianLanes[0]
        board = DispatchBoardSnapshot(
            date: board.date,
            generatedAt: board.generatedAt,
            technicianLanes: [DispatchBoardTechnicianLane(
                id: lane.id,
                technicianName: lane.technicianName,
                technicianState: .attention,
                assignments: [conflicted],
                currentAssignmentID: nil,
                nextAssignmentID: conflicted.id,
                plannedServiceMinutes: lane.plannedServiceMinutes,
                capacityMinutes: lane.capacityMinutes,
                utilization: lane.utilization,
                dailyPlan: lane.dailyPlan,
                alerts: []
            )],
            unassignedItems: [],
            alerts: []
        )

        let snapshot = makeEngine().snapshot(
            board: board,
            assignments: [],
            jobs: [],
            employees: [makeEmployee()]
        )
        let assignment = snapshot.lanes[0].entries.first {
            $0.kind == .assignment
        }

        XCTAssertEqual(assignment?.hasConflict, true)
        XCTAssertEqual(assignment?.warnings, ["Arrival window conflict"])
    }

    func testEquivalentPlannerAndBoardAlertsAppearOnlyOnce() {
        let board = makeBoard()
        let lane = board.technicianLanes[0]
        let message = "Tim Technician is not scheduled to work on this day."
        let conflict = PlanningConflict(
            kind: .nonWorkingDay,
            severity: .error,
            message: message,
            assignmentID: nil,
            conflictingAssignmentID: nil
        )
        let plan = DailyPlan(
            technicianID: lane.dailyPlan.technicianID,
            date: lane.dailyPlan.date,
            workdayStart: lane.dailyPlan.workdayStart,
            workdayEnd: lane.dailyPlan.workdayEnd,
            items: lane.dailyPlan.items,
            openWindows: lane.dailyPlan.openWindows,
            conflicts: [conflict],
            recommendations: lane.dailyPlan.recommendations,
            unplacedAssignmentIDs: lane.dailyPlan.unplacedAssignmentIDs,
            dailyReserveMinutes: lane.dailyPlan.dailyReserveMinutes
        )
        let duplicate = DispatchBoardAlert(
            severity: .blocking,
            title: PlanningConflictKind.nonWorkingDay.rawValue,
            message: message,
            technicianID: technicianID
        )
        let duplicateBoard = DispatchBoardSnapshot(
            date: board.date,
            generatedAt: board.generatedAt,
            technicianLanes: [DispatchBoardTechnicianLane(
                id: lane.id,
                technicianName: lane.technicianName,
                technicianState: .attention,
                assignments: lane.assignments,
                currentAssignmentID: lane.currentAssignmentID,
                nextAssignmentID: lane.nextAssignmentID,
                plannedServiceMinutes: lane.plannedServiceMinutes,
                capacityMinutes: lane.capacityMinutes,
                utilization: lane.utilization,
                dailyPlan: plan,
                alerts: [duplicate]
            )],
            unassignedItems: [],
            alerts: []
        )

        let snapshot = makeEngine().snapshot(
            board: duplicateBoard,
            assignments: [],
            jobs: [],
            employees: [makeEmployee()]
        )

        XCTAssertEqual(snapshot.lanes[0].alerts.count, 1)
        XCTAssertEqual(snapshot.lanes[0].alerts[0].title, "Non-Working Day")
    }

    func testActualLifecycleMilestonesAppearOnAssignment() {
        let dispatched = date(hour: 8, minute: 5)
        let enRoute = date(hour: 8, minute: 15)
        let record = Assignment(
            id: assignmentID,
            assignmentNumber: "ASN-TEST",
            jobID: jobID,
            jobNumber: "JOB-TEST",
            customerNumber: "PPS-000001",
            status: .enRoute,
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: date(hour: 9),
                estimatedDurationMinutes: 60,
                isCustomerConfirmed: true
            ),
            dispatchedDate: dispatched,
            enRouteDate: enRoute
        )

        let snapshot = makeEngine().snapshot(
            board: makeBoard(),
            assignments: [record],
            jobs: [],
            employees: [makeEmployee()]
        )
        let milestones = snapshot.lanes[0].entries.first {
            $0.kind == .assignment && $0.assignmentID == assignmentID
        }?.milestones

        XCTAssertEqual(record.dispatchedDate, dispatched)
        XCTAssertEqual(record.enRouteDate, enRoute)
        XCTAssertEqual(milestones?.map(\.title), ["Dispatched", "Travel Started"])
        XCTAssertEqual(milestones?.map(\.timestamp), [dispatched, enRoute])
    }

    func testJobLifecycleMilestonesAddDetailWithoutDuplicatingAssignmentEvents() {
        let travel = date(hour: 8, minute: 15)
        let pause = date(hour: 9, minute: 20)
        let resume = date(hour: 9, minute: 35)
        let record = Assignment(
            id: assignmentID,
            assignmentNumber: "ASN-TEST",
            jobID: jobID,
            jobNumber: "JOB-TEST",
            customerNumber: "PPS-000001",
            status: .onSite,
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: date(hour: 9),
                estimatedDurationMinutes: 60,
                isCustomerConfirmed: true
            ),
            enRouteDate: travel
        )
        var job = makeJob()
        job.timelineEvents = [
            JobTimelineEvent(
                type: .travelStarted,
                title: "Travel Started",
                timestamp: travel,
                employeeID: technicianID
            ),
            JobTimelineEvent(
                type: .workPaused,
                title: "Work Paused",
                timestamp: pause,
                employeeID: technicianID
            ),
            JobTimelineEvent(
                type: .workResumed,
                title: "Work Resumed",
                timestamp: resume,
                employeeID: technicianID
            )
        ]

        let snapshot = makeEngine().snapshot(
            board: makeBoard(),
            assignments: [record],
            jobs: [job],
            employees: [makeEmployee()]
        )
        let milestones = snapshot.lanes[0].entries.first {
            $0.kind == .assignment && $0.assignmentID == assignmentID
        }?.milestones ?? []

        XCTAssertEqual(
            milestones.map(\.title),
            ["Travel Started", "Work Paused", "Work Resumed"]
        )
        XCTAssertEqual(
            milestones.filter { $0.title == "Travel Started" }.count,
            1
        )
    }

    // MARK: - Fixtures

    private func makeTimelineSnapshot() -> OperationsTimelineSnapshot {
        makeEngine().snapshot(
            board: makeBoard(),
            assignments: [],
            jobs: [],
            employees: [makeEmployee()]
        )
    }

    private func makeEngine() -> OperationsTimelineEngine {
        OperationsTimelineEngine(calendar: calendar)
    }

    private var day: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 23
        ))!
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func makeBoard() -> DispatchBoardSnapshot {
        let item = makeBoardItem()
        let assignmentPlanItem = DailyPlanItem(
            kind: .assignment,
            assignmentID: assignmentID,
            jobID: jobID,
            technicianID: technicianID,
            title: "Customer",
            schedulingMode: .fixedTime,
            serviceStart: date(hour: 9),
            serviceEnd: date(hour: 10),
            occupiedStart: date(hour: 8, minute: 45),
            occupiedEnd: date(hour: 10, minute: 3),
            isFixedCommitment: true,
            explanation: "Preserved fixed start"
        )
        let lunch = DailyPlanItem(
            kind: .lunch,
            assignmentID: nil,
            jobID: nil,
            technicianID: technicianID,
            title: "Lunch",
            schedulingMode: nil,
            serviceStart: date(hour: 12),
            serviceEnd: date(hour: 12, minute: 30),
            occupiedStart: date(hour: 12),
            occupiedEnd: date(hour: 12, minute: 30),
            isFixedCommitment: false,
            explanation: "Protected break"
        )
        let plan = DailyPlan(
            technicianID: technicianID,
            date: day,
            workdayStart: date(hour: 8),
            workdayEnd: date(hour: 17),
            items: [lunch, assignmentPlanItem],
            openWindows: [],
            conflicts: [],
            recommendations: [],
            unplacedAssignmentIDs: [],
            dailyReserveMinutes: 0
        )
        let lane = DispatchBoardTechnicianLane(
            id: technicianID,
            technicianName: "Tim Technician",
            technicianState: .scheduled,
            assignments: [item],
            currentAssignmentID: nil,
            nextAssignmentID: assignmentID,
            plannedServiceMinutes: 60,
            capacityMinutes: 510,
            utilization: 60.0 / 510.0,
            dailyPlan: plan,
            alerts: []
        )
        return DispatchBoardSnapshot(
            date: day,
            generatedAt: date(hour: 7),
            technicianLanes: [lane],
            unassignedItems: [],
            alerts: []
        )
    }

    private func makeBoardItem(
        hasConflict: Bool = false
    ) -> DispatchBoardAssignmentItem {
        DispatchBoardAssignmentItem(
            id: assignmentID,
            jobID: jobID,
            assignmentNumber: "ASN-TEST",
            jobNumber: "JOB-TEST",
            customerName: "Customer",
            siteName: "Main",
            siteAddress: "123 Main Street",
            serviceName: "Window Cleaning",
            status: .scheduled,
            priority: .normal,
            schedulingMode: .fixedTime,
            scheduleDateText: "Jul 23, 2026",
            scheduleTimeText: "9:00 AM",
            plannedStart: date(hour: 9),
            plannedEnd: date(hour: 10),
            estimatedArrival: date(hour: 8, minute: 45),
            serviceMinutes: 60,
            routeSequence: 1,
            primaryTechnicianID: technicianID,
            supportingTechnicianIDs: [],
            isCurrent: false,
            hasBlockingConflict: hasConflict,
            warnings: hasConflict ? ["Arrival window conflict"] : []
        )
    }

    private func makeEmployee() -> EmployeeRecord {
        EmployeeRecord(
            id: technicianID,
            firstName: "Tim",
            lastName: "Technician",
            role: .technician,
            defaultStartMinutes: 8 * 60,
            defaultEndMinutes: 17 * 60,
            lunchDurationMinutes: 30,
            colorName: "green"
        )
    }

    private func makeJob() -> JobRecord {
        JobRecord(
            id: jobID,
            jobNumber: "JOB-TEST",
            customerNumber: "PPS-000001",
            siteID: nil,
            estimateNumber: "",
            serviceType: .windowCleaning,
            otherService: "",
            subtotal: 100,
            discount: 0,
            total: 100,
            primaryTechnicianID: technicianID,
            scheduledDate: date(hour: 9),
            status: .inProgress,
            workflowState: .working,
            workNotes: "",
            isRecurring: false,
            createdDate: date(hour: 7)
        )
    }
}
