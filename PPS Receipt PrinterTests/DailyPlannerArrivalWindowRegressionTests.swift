//
//  DailyPlannerArrivalWindowRegressionTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.8 regression coverage for arrival-window placement and movable lunch.
//

import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct DailyPlannerArrivalWindowRegressionTests {
    private let technicianID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000091"
    )!

    @Test
    func longArrivalWindowIsPlacedBeforeLunchAndLunchMovesAfterWork() throws {
        let assignment = makeArrivalWindowAssignment()
        let planner = DailyPlannerEngine(
            configuration: DailyPlannerConfiguration(
                slotIntervalMinutes: 15,
                transitionBufferMinutes: 3,
                // This regression covers arrival-window placement and a
                // movable lunch. A five-hour daily reserve leaves too little
                // capacity for the 230-minute appointment plus lunch and is
                // correctly rejected by the planner.
                dailyReserveMinutes: 0,
                preferredLunchStartMinutes: 12 * 60,
                lunchWindowStartMinutes: 11 * 60,
                lunchWindowEndMinutes: 14 * 60,
                includeBusinessBuffers: true
            ),
            calendar: testCalendar
        )

        let plan = planner.plan(
            for: makeTechnician(),
            on: makeDate(hour: 0),
            assignments: [assignment]
        )

        let item = try #require(
            plan.assignmentItems.first { $0.assignmentID == assignment.id }
        )
        let lunch = try #require(plan.lunchItem)

        #expect(hour(item.serviceStart) == 9)
        #expect(minute(item.serviceStart) == 0)
        #expect(hour(item.serviceEnd) == 12)
        #expect(minute(item.serviceEnd) == 50)
        #expect(hour(item.occupiedEnd) == 12)
        #expect(minute(item.occupiedEnd) == 53)
        #expect(hour(lunch.serviceStart) == 13)
        #expect(minute(lunch.serviceStart) == 0)
        #expect(hour(lunch.serviceEnd) == 13)
        #expect(minute(lunch.serviceEnd) == 30)
        #expect(plan.unplacedAssignmentIDs.isEmpty)
        #expect(!plan.conflicts.contains {
            $0.assignmentID == assignment.id &&
            $0.kind == .arrivalWindowUnavailable
        })
        #expect(!plan.conflicts.contains {
            $0.kind == .insufficientCapacity
        })
    }

    private func makeTechnician() -> EmployeeRecord {
        EmployeeRecord(
            id: technicianID,
            firstName: "Arrival",
            lastName: "Window Test",
            role: .technician,
            defaultStartMinutes: 8 * 60,
            defaultEndMinutes: 17 * 60,
            lunchDurationMinutes: 30,
            workingDays: [.wednesday],
            isActive: true,
            lifecycleStatus: .active
        )
    }

    private func makeArrivalWindowAssignment() -> Assignment {
        Assignment(
            id: UUID(
                uuidString: "20000000-0000-0000-0000-000000000091"
            )!,
            assignmentNumber: "ASN-ARRIVAL-LUNCH-REGRESSION",
            jobID: UUID(
                uuidString: "30000000-0000-0000-0000-000000000091"
            )!,
            jobNumber: "JOB-ARRIVAL-LUNCH-REGRESSION",
            customerNumber: "PPS-ARRIVAL-LUNCH",
            status: .scheduled,
            priority: .normal,
            scheduling: AssignmentScheduling(
                mode: .arrivalWindow,
                serviceDate: makeDate(hour: 0),
                arrivalWindowStart: makeDate(hour: 9),
                arrivalWindowEnd: makeDate(hour: 14, minute: 45),
                estimatedDurationMinutes: 230
            ),
            crew: AssignmentCrew(
                members: [
                    AssignmentCrewMember(
                        employeeID: technicianID,
                        role: .primary,
                        assignedDate: makeDate(hour: 7)
                    )
                ]
            )
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(hour: Int, minute: Int = 0) -> Date {
        testCalendar.date(from: DateComponents(
            // Keep this regression fixture safely in the future. The planner
            // correctly refuses to create new work in elapsed time, so a past
            // hard-coded date makes the test depend on the day it is run.
            year: 2030,
            month: 1,
            day: 2,
            hour: hour,
            minute: minute
        ))!
    }

    private func hour(_ date: Date) -> Int {
        testCalendar.component(.hour, from: date)
    }

    private func minute(_ date: Date) -> Int {
        testCalendar.component(.minute, from: date)
    }
}
