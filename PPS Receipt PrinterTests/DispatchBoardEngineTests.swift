//
//  DispatchBoardEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.7 – Technician Dispatch Board
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class DispatchBoardEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTechnicianLanesAreStableAndAlphabetical() {
        let result = makeEngine().snapshot(
            on: day,
            generatedAt: date(hour: 7),
            employees: [
                makeEmployee(id: id(2), firstName: "Zoe"),
                makeEmployee(id: id(1), firstName: "Avery")
            ],
            assignments: [],
            jobs: [],
            customers: [],
            sites: [],
            dailyPlans: []
        )

        XCTAssertEqual(
            result.technicianLanes.map(\.technicianName),
            ["Avery Technician", "Zoe Technician"]
        )
    }

    func testAssignmentsGroupByPrimaryTechnicianAndPreserveUnassignedQueue() {
        let technician = makeEmployee(id: id(1), firstName: "Avery")
        let assigned = makeAssignment(
            id: id(11),
            technicianID: technician.id,
            startHour: 8
        )
        let unassigned = makeAssignment(
            id: id(12),
            technicianID: nil,
            startHour: 10
        )

        let result = makeEngine().snapshot(
            on: day,
            generatedAt: date(hour: 7),
            employees: [technician],
            assignments: [unassigned, assigned],
            jobs: [
                makeJob(for: assigned, startHour: 8),
                makeJob(for: unassigned, startHour: 10)
            ],
            customers: [makeCustomer()],
            sites: [makeSite()],
            dailyPlans: []
        )

        XCTAssertEqual(result.technicianLanes[0].assignments.map(\.id), [assigned.id])
        XCTAssertEqual(result.unassignedItems.map(\.id), [unassigned.id])
        XCTAssertEqual(result.assignedCount, 1)
        XCTAssertEqual(result.unassignedCount, 1)
    }

    func testRouteSequenceControlsLaneOrderBeforeScheduledTime() {
        let technician = makeEmployee(id: id(1), firstName: "Avery")
        var laterFirst = makeAssignment(
            id: id(11),
            technicianID: technician.id,
            startHour: 11
        )
        laterFirst.routeSequence = 1
        var earlierSecond = makeAssignment(
            id: id(12),
            technicianID: technician.id,
            startHour: 8
        )
        earlierSecond.routeSequence = 2

        let result = makeEngine().snapshot(
            on: day,
            generatedAt: date(hour: 7),
            employees: [technician],
            assignments: [earlierSecond, laterFirst],
            jobs: [
                makeJob(for: laterFirst, startHour: 11),
                makeJob(for: earlierSecond, startHour: 8)
            ],
            customers: [makeCustomer()],
            sites: [makeSite()],
            dailyPlans: []
        )

        XCTAssertEqual(
            result.technicianLanes[0].assignments.map(\.id),
            [laterFirst.id, earlierSecond.id]
        )
    }

    func testCurrentAndNextAssignmentsAreIdentified() {
        let technician = makeEmployee(id: id(1), firstName: "Avery")
        let current = makeAssignment(
            id: id(11),
            technicianID: technician.id,
            status: .enRoute,
            startHour: 8
        )
        let next = makeAssignment(
            id: id(12),
            technicianID: technician.id,
            startHour: 10
        )

        let result = makeEngine().snapshot(
            on: day,
            generatedAt: date(hour: 8),
            employees: [technician],
            assignments: [next, current],
            jobs: [
                makeJob(for: current, startHour: 8),
                makeJob(for: next, startHour: 10)
            ],
            customers: [makeCustomer()],
            sites: [makeSite()],
            dailyPlans: []
        )

        let lane = result.technicianLanes[0]
        XCTAssertEqual(lane.currentAssignmentID, current.id)
        XCTAssertEqual(lane.nextAssignmentID, next.id)
        XCTAssertEqual(lane.technicianState, .traveling)
    }

    func testOverCapacityAndPlanningConflictProduceVisibleAlerts() {
        let technician = makeEmployee(
            id: id(1),
            firstName: "Avery",
            startMinutes: 8 * 60,
            endMinutes: 10 * 60,
            lunchMinutes: 60
        )
        let assignment = makeAssignment(
            id: id(11),
            technicianID: technician.id,
            startHour: 8,
            durationMinutes: 120
        )
        let conflict = PlanningConflict(
            kind: .insufficientCapacity,
            severity: .error,
            message: "Assignment exceeds remaining capacity.",
            assignmentID: assignment.id,
            conflictingAssignmentID: nil
        )
        let plan = DailyPlan(
            technicianID: technician.id,
            date: day,
            workdayStart: date(hour: 8),
            workdayEnd: date(hour: 10),
            items: [],
            openWindows: [],
            conflicts: [conflict],
            recommendations: [],
            unplacedAssignmentIDs: [assignment.id],
            dailyReserveMinutes: 0
        )

        let result = makeEngine().snapshot(
            on: day,
            generatedAt: date(hour: 7),
            employees: [technician],
            assignments: [assignment],
            jobs: [makeJob(for: assignment, startHour: 8)],
            customers: [makeCustomer()],
            sites: [makeSite()],
            dailyPlans: [plan]
        )

        let lane = result.technicianLanes[0]
        XCTAssertEqual(lane.technicianState, .attention)
        XCTAssertGreaterThan(lane.utilization, 1)
        XCTAssertTrue(lane.alerts.contains { $0.severity == .blocking })
        XCTAssertTrue(lane.alerts.contains { $0.title == "Over capacity" })
    }

    func testIdenticalInputsProduceIdenticalSnapshot() {
        let technician = makeEmployee(id: id(1), firstName: "Avery")
        let assignment = makeAssignment(
            id: id(11),
            technicianID: technician.id,
            startHour: 8
        )
        let engine = makeEngine()

        let first = engine.snapshot(
            on: day,
            generatedAt: date(hour: 7),
            employees: [technician],
            assignments: [assignment],
            jobs: [makeJob(for: assignment, startHour: 8)],
            customers: [makeCustomer()],
            sites: [makeSite()],
            dailyPlans: []
        )
        let second = engine.snapshot(
            on: day,
            generatedAt: date(hour: 7),
            employees: [technician],
            assignments: [assignment],
            jobs: [makeJob(for: assignment, startHour: 8)],
            customers: [makeCustomer()],
            sites: [makeSite()],
            dailyPlans: []
        )

        XCTAssertEqual(first, second)
    }

    // MARK: - Fixtures

    private var day: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 27
        ))!
    }

    private func date(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            value
        ))!
    }

    private func makeEngine() -> DispatchBoardEngine {
        DispatchBoardEngine(calendar: calendar)
    }

    private func makeEmployee(
        id: UUID,
        firstName: String,
        startMinutes: Int = 8 * 60,
        endMinutes: Int = 17 * 60,
        lunchMinutes: Int = 30
    ) -> EmployeeRecord {
        EmployeeRecord(
            id: id,
            firstName: firstName,
            lastName: "Technician",
            role: .technician,
            defaultStartMinutes: startMinutes,
            defaultEndMinutes: endMinutes,
            lunchDurationMinutes: lunchMinutes,
            workingDays: Workday.standardWorkweek
        )
    }

    private func makeAssignment(
        id assignmentID: UUID,
        technicianID: UUID?,
        status: AssignmentStatus = .scheduled,
        startHour: Int,
        durationMinutes: Int = 60
    ) -> Assignment {
        let sequence = Int(assignmentID.uuidString.suffix(2)) ?? 1
        let jobID = id(100 + sequence)
        let crew = technicianID.map {
            AssignmentCrew(members: [
                AssignmentCrewMember(
                    employeeID: $0,
                    role: .primary,
                    assignedDate: date(hour: 7)
                )
            ])
        } ?? AssignmentCrew()

        return Assignment(
            id: assignmentID,
            assignmentNumber: "ASN-\(sequence)",
            jobID: jobID,
            jobNumber: "JOB-\(sequence)",
            customerNumber: "CUST-1",
            siteID: id(500),
            status: status,
            priority: .normal,
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: date(hour: startHour),
                estimatedDurationMinutes: durationMinutes,
                isCustomerConfirmed: true
            ),
            crew: crew,
            createdDate: day,
            updatedDate: day
        )
    }

    private func makeJob(
        for assignment: Assignment,
        startHour: Int
    ) -> JobRecord {
        JobRecord(
            id: assignment.jobID,
            jobNumber: assignment.jobNumber,
            customerNumber: assignment.customerNumber,
            siteID: assignment.siteID,
            estimateNumber: "",
            serviceType: .windowCleaning,
            otherService: "",
            lineItems: [],
            subtotal: 0,
            discount: 0,
            total: 0,
            primaryTechnicianID: assignment.primaryTechnicianID,
            secondaryTechnicianID: nil,
            scheduledDate: date(hour: startHour),
            status: .scheduled,
            workNotes: "",
            isRecurring: false,
            createdDate: day
        )
    }

    private func makeCustomer() -> Customer {
        Customer(
            id: id(400),
            customerNumber: "CUST-1",
            businessName: "Acme Services",
            contactName: "Alex Customer",
            phone: "",
            email: "",
            leadSource: .referral,
            estimateStatus: .jobScheduled,
            assignedEmployee: "",
            followUpDate: day
        )
    }

    private func makeSite() -> CustomerSite {
        CustomerSite(
            id: id(500),
            customerNumber: "CUST-1",
            siteName: "Main Office",
            serviceAddress: "123 Main Street",
            propertyType: "Office",
            accessNotes: "",
            workNotes: ""
        )
    }
}
