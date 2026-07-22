//
//  DailyPlannerEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.3 – Daily Planner Engine
//

import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct DailyPlannerEngineTests {
    private let technicianID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    @Test func fixedCommitmentIsPreservedAndFlexibleWorkFillsFirstGap() throws {
        let day = makeDate(hour: 0)
        let technician = makeTechnician()
        let fixed = makeAssignment(
            number: "ASN-FIXED",
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: makeDate(hour: 10),
                estimatedDurationMinutes: 60,
                isCustomerConfirmed: true
            )
        )
        let flexible = makeAssignment(
            number: "ASN-FLEX",
            scheduling: AssignmentScheduling(
                mode: .flexibleDay,
                serviceDate: day,
                estimatedDurationMinutes: 60
            )
        )

        let plan = makeEngine().plan(
            for: technician,
            on: day,
            assignments: [flexible, fixed]
        )

        let fixedItem = try #require(
            plan.assignmentItems.first { $0.assignmentID == fixed.id }
        )
        let flexibleItem = try #require(
            plan.assignmentItems.first { $0.assignmentID == flexible.id }
        )

        #expect(hour(fixedItem.serviceStart) == 10)
        #expect(hour(flexibleItem.serviceStart) == 8)
        #expect(plan.unplacedAssignmentIDs.isEmpty)
    }

    @Test func arrivalWindowStartsAfterBlockingFixedCommitment() throws {
        let day = makeDate(hour: 0)
        let technician = makeTechnician(lunchMinutes: 0)
        let fixed = makeAssignment(
            number: "ASN-FIXED",
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: makeDate(hour: 9),
                estimatedDurationMinutes: 60
            )
        )
        let window = makeAssignment(
            number: "ASN-WINDOW",
            scheduling: AssignmentScheduling(
                mode: .arrivalWindow,
                serviceDate: day,
                arrivalWindowStart: makeDate(hour: 9),
                arrivalWindowEnd: makeDate(hour: 11),
                estimatedDurationMinutes: 60
            )
        )

        let plan = makeEngine().plan(
            for: technician,
            on: day,
            assignments: [window, fixed]
        )
        let item = try #require(
            plan.assignmentItems.first { $0.assignmentID == window.id }
        )

        #expect(hour(item.serviceStart) == 10)
        #expect(plan.unplacedAssignmentIDs.isEmpty)
    }

    @Test func deadlineWorkCompletesBeforeDeadline() throws {
        let day = makeDate(hour: 0)
        let deadline = makeDate(hour: 11)
        let assignment = makeAssignment(
            number: "ASN-DEADLINE",
            scheduling: AssignmentScheduling(
                mode: .deadline,
                serviceDate: day,
                completionDeadline: deadline,
                estimatedDurationMinutes: 90
            )
        )

        let plan = makeEngine().plan(
            for: makeTechnician(lunchMinutes: 0),
            on: day,
            assignments: [assignment]
        )
        let item = try #require(plan.assignmentItems.first)

        #expect(item.serviceEnd <= deadline)
        #expect(plan.unplacedAssignmentIDs.isEmpty)
    }

    @Test func overCapacityWorkIsReturnedAsUnplacedConflict() {
        let day = makeDate(hour: 0)
        let technician = makeTechnician(
            endMinutes: 10 * 60,
            lunchMinutes: 0
        )
        let fixed = makeAssignment(
            number: "ASN-LONG-FIXED",
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: makeDate(hour: 8),
                estimatedDurationMinutes: 90
            )
        )
        let flexible = makeAssignment(
            number: "ASN-NO-ROOM",
            scheduling: AssignmentScheduling(
                mode: .flexibleDay,
                serviceDate: day,
                estimatedDurationMinutes: 60
            )
        )

        let plan = makeEngine().plan(
            for: technician,
            on: day,
            assignments: [fixed, flexible]
        )

        #expect(plan.unplacedAssignmentIDs.contains(flexible.id))
        #expect(plan.conflicts.contains {
            $0.assignmentID == flexible.id &&
            $0.kind == .assignmentNotPlaced
        })
    }

    @Test func lunchMovesAroundFixedMiddayWork() throws {
        let day = makeDate(hour: 0)
        let fixed = makeAssignment(
            number: "ASN-NOON",
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: day,
                fixedStartDate: makeDate(hour: 12),
                estimatedDurationMinutes: 60
            )
        )

        let plan = makeEngine().plan(
            for: makeTechnician(lunchMinutes: 30),
            on: day,
            assignments: [fixed]
        )
        let lunch = try #require(plan.lunchItem)

        #expect(hour(lunch.serviceStart) == 11)
        #expect(minute(lunch.serviceStart) == 30)
        #expect(lunch.serviceEnd <= makeDate(hour: 12))
    }

    @Test func businessTransitionBufferIsReservedAfterEachStop() throws {
        let day = makeDate(hour: 0)
        let assignment = makeAssignment(
            number: "ASN-BUFFER",
            scheduling: AssignmentScheduling(
                mode: .flexibleDay,
                serviceDate: day,
                estimatedDurationMinutes: 60
            )
        )
        let engine = DailyPlannerEngine(
            configuration: DailyPlannerConfiguration(
                slotIntervalMinutes: 15,
                transitionBufferMinutes: 15,
                dailyReserveMinutes: 20,
                includeBusinessBuffers: true
            ),
            calendar: testCalendar
        )

        let plan = engine.plan(
            for: makeTechnician(lunchMinutes: 0),
            on: day,
            assignments: [assignment]
        )
        let item = try #require(plan.assignmentItems.first)

        #expect(item.occupiedMinutes == 75)
        #expect(plan.dailyReserveMinutes == 20)
    }

    @Test func identicalInputsProduceIdenticalPlan() {
        let day = makeDate(hour: 0)
        let assignments = [
            makeAssignment(
                number: "ASN-B",
                scheduling: AssignmentScheduling(
                    mode: .flexibleDay,
                    serviceDate: day,
                    estimatedDurationMinutes: 45
                )
            ),
            makeAssignment(
                number: "ASN-A",
                scheduling: AssignmentScheduling(
                    mode: .flexibleDay,
                    serviceDate: day,
                    estimatedDurationMinutes: 30
                )
            )
        ]
        let engine = makeEngine()
        let technician = makeTechnician()

        let first = engine.plan(
            for: technician,
            on: day,
            assignments: assignments
        )
        let second = engine.plan(
            for: technician,
            on: day,
            assignments: Array(assignments.reversed())
        )

        #expect(first == second)
    }

    // MARK: - Fixtures

    private func makeEngine() -> DailyPlannerEngine {
        DailyPlannerEngine(
            configuration: DailyPlannerConfiguration(
                slotIntervalMinutes: 15,
                transitionBufferMinutes: 0,
                dailyReserveMinutes: 0,
                includeBusinessBuffers: false
            ),
            calendar: testCalendar
        )
    }

    private func makeTechnician(
        endMinutes: Int = 17 * 60,
        lunchMinutes: Int = 30
    ) -> EmployeeRecord {
        EmployeeRecord(
            id: technicianID,
            firstName: "Test",
            lastName: "Technician",
            role: .technician,
            defaultStartMinutes: 8 * 60,
            defaultEndMinutes: endMinutes,
            lunchDurationMinutes: lunchMinutes,
            workingDays: [.wednesday],
            isActive: true,
            lifecycleStatus: .active
        )
    }

    private func makeAssignment(
        number: String,
        scheduling: AssignmentScheduling,
        priority: AssignmentPriority = .normal
    ) -> Assignment {
        let stableID = UUID(
            uuidString: stableUUIDString(for: number)
        )!
        return Assignment(
            id: stableID,
            assignmentNumber: number,
            jobID: UUID(),
            jobNumber: "JOB-\(number)",
            customerNumber: "PPS-TEST",
            status: .scheduled,
            priority: priority,
            scheduling: scheduling,
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

    private func stableUUIDString(for value: String) -> String {
        let scalarTotal = value.unicodeScalars.reduce(0) {
            ($0 + Int($1.value)) % 999_999_999_999
        }
        return String(
            format: "20000000-0000-0000-0000-%012d",
            scalarTotal
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(hour: Int, minute: Int = 0) -> Date {
        testCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 22,
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
