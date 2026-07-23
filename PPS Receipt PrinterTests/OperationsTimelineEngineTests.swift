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
            .travel,
            .assignment,
            .travel,
            .openCapacity,
            .lunch,
            .openCapacity
        ])
        XCTAssertEqual(lane.entries, lane.entries.sorted { $0.start < $1.start })
    }

    func testPlannerIntervalsExposeTravelLunchAndOpenCapacity() {
        let snapshot = makeTimelineSnapshot()
        let lane = snapshot.lanes[0]

        XCTAssertEqual(lane.entries.filter { $0.kind == .travel }.count, 2)
        XCTAssertTrue(lane.entries.contains { $0.kind == .lunch })
        XCTAssertEqual(
            lane.entries.filter { $0.kind == .openCapacity }.count,
            3
        )
        XCTAssertEqual(lane.scheduledMinutes, 60)
        XCTAssertEqual(lane.openMinutes, 432)
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
            employees: [makeEmployee()]
        )
        let assignment = snapshot.lanes[0].entries.first {
            $0.kind == .assignment
        }

        XCTAssertEqual(assignment?.hasConflict, true)
        XCTAssertEqual(assignment?.warnings, ["Arrival window conflict"])
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

    // MARK: - Fixtures

    private func makeTimelineSnapshot() -> OperationsTimelineSnapshot {
        makeEngine().snapshot(
            board: makeBoard(),
            assignments: [],
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
}
