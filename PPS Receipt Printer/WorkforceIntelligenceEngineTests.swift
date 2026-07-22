//
//  WorkforceIntelligenceEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.5 — Workforce Intelligence
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class WorkforceIntelligenceEngineTests: XCTestCase {
    private var calendar: Calendar {
        var fixedCalendar = Calendar(identifier: .gregorian)
        fixedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return fixedCalendar
    }

    private var engine: WorkforceIntelligenceEngine {
        WorkforceIntelligenceEngine(calendar: calendar)
    }

    func testLegacyEmployeeDecodesWithEmptyWorkforceProfile() throws {
        let legacy = LegacyEmployeeRecord(
            id: technicianID(1),
            firstName: "Legacy",
            lastName: "Technician",
            phone: "",
            email: "",
            role: .technician,
            defaultStartMinutes: 480,
            defaultEndMinutes: 1020,
            lunchDurationMinutes: 30,
            workingDays: Workday.standardWorkweek,
            colorName: "blue",
            isActive: true,
            createdDate: makeDate(day: 20, hour: 8),
            lifecycleStatus: .active
        )

        let decoded = try JSONDecoder().decode(
            EmployeeRecord.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.displayName, "Legacy Technician")
        XCTAssertFalse(decoded.workforceProfile.hasIntelligenceData)
        XCTAssertTrue(decoded.workforceProfile.skills.isEmpty)
    }

    func testMatchingSkillCertificationResourceAndVehicleQualify() {
        let date = makeDate(day: 22, hour: 8)
        let profile = WorkforceOperationalProfile(
            skills: [
                WorkforceSkill(
                    name: "Window Cleaning",
                    serviceType: .windowCleaning,
                    proficiency: .expert,
                    isVerified: true
                ),
                WorkforceSkill(
                    name: "Ladder Safety",
                    proficiency: .proficient
                )
            ],
            certifications: [
                WorkforceCertification(
                    name: "OSHA 10",
                    expirationDate: makeDate(day: 22, hour: 8, year: 2027)
                )
            ],
            resourceAccess: [
                WorkforceResourceAccess(
                    name: "24 Foot Ladder",
                    type: .equipment
                ),
                WorkforceResourceAccess(
                    name: "Service Van 1",
                    type: .vehicle
                )
            ]
        )
        let employee = makeEmployee(profile: profile)
        let requirements = WorkforceCapabilityRequirements(
            requiredServiceType: .windowCleaning,
            minimumProficiency: .proficient,
            requiredSkillNames: ["Ladder Safety"],
            requiredCertificationNames: ["OSHA 10"],
            requiredResourceNames: ["24 Foot Ladder"],
            requiresVehicleAccess: true
        )

        let result = engine.evaluateCapability(
            of: employee,
            for: requirements,
            on: date
        )

        XCTAssertEqual(result.state, .qualified)
        XCTAssertTrue(result.meetsRequirements)
        XCTAssertTrue(result.blockers.isEmpty)
        XCTAssertEqual(result.evidence.count, 5)
    }

    func testExpiredRequiredCertificationBlocksQualification() {
        let date = makeDate(day: 22, hour: 8)
        let employee = makeEmployee(
            profile: WorkforceOperationalProfile(
                certifications: [
                    WorkforceCertification(
                        name: "Roof Safety",
                        expirationDate: makeDate(
                            day: 21,
                            hour: 8
                        )
                    )
                ]
            )
        )
        let result = engine.evaluateCapability(
            of: employee,
            for: WorkforceCapabilityRequirements(
                requiredCertificationNames: ["Roof Safety"]
            ),
            on: date
        )

        XCTAssertEqual(result.state, .notQualified)
        XCTAssertFalse(result.meetsRequirements)
        XCTAssertEqual(result.blockers.count, 1)
        XCTAssertTrue(result.blockers[0].message.contains("expired"))
    }

    func testMissingOptionalIntelligenceDoesNotBlockUnrestrictedWork() {
        let employee = makeEmployee()
        let result = engine.evaluateCapability(
            of: employee,
            for: WorkforceCapabilityRequirements()
        )

        XCTAssertEqual(result.state, .qualified)
        XCTAssertTrue(result.meetsRequirements)
    }

    func testUnavailableExceptionOverridesNormalWorkday() {
        let date = makeDate(day: 22, hour: 10)
        let employee = makeEmployee(
            profile: WorkforceOperationalProfile(
                availabilityExceptions: [
                    WorkforceAvailabilityException(
                        kind: .unavailable,
                        startDate: makeDate(day: 22, hour: 0),
                        endDate: makeDate(day: 23, hour: 0),
                        reason: "Approved time off"
                    )
                ]
            )
        )

        let availability = engine.evaluateAvailability(
            of: employee,
            on: date
        )

        XCTAssertEqual(availability.state, .unavailable)
        XCTAssertEqual(availability.reason, "Approved time off")
        XCTAssertNil(availability.availableInterval)
    }

    func testAvailableOverrideAllowsNormallyUnscheduledDay() {
        let saturday = makeDate(day: 25, hour: 10)
        let employee = makeEmployee(
            profile: WorkforceOperationalProfile(
                availabilityExceptions: [
                    WorkforceAvailabilityException(
                        kind: .available,
                        startDate: makeDate(day: 25, hour: 9),
                        endDate: makeDate(day: 25, hour: 13),
                        reason: "Emergency coverage"
                    )
                ]
            )
        )

        let availability = engine.evaluateAvailability(
            of: employee,
            on: saturday
        )

        XCTAssertEqual(availability.state, .availableOverride)
        XCTAssertTrue(availability.state.isAvailable)
        XCTAssertEqual(
            availability.availableInterval?.duration,
            4 * 60 * 60
        )
    }

    func testWorkloadCountsPrimaryAndSupportingAssignments() {
        let date = makeDate(day: 22, hour: 8)
        let employee = makeEmployee(
            profile: WorkforceOperationalProfile(
                maximumDailyAssignments: 1
            )
        )
        let primary = makeAssignment(
            number: "ASN-PRIMARY",
            date: date,
            durationMinutes: 120,
            primaryID: employee.id
        )
        let supporting = makeAssignment(
            number: "ASN-SUPPORT",
            date: makeDate(day: 22, hour: 11),
            durationMinutes: 60,
            primaryID: technicianID(2),
            supportingID: employee.id
        )
        let otherDay = makeAssignment(
            number: "ASN-TOMORROW",
            date: makeDate(day: 23, hour: 8),
            durationMinutes: 300,
            primaryID: employee.id
        )

        let workload = engine.workload(
            for: employee,
            on: date,
            assignments: [primary, supporting, otherDay]
        )

        XCTAssertEqual(workload.assignmentCount, 2)
        XCTAssertEqual(workload.assignedMinutes, 180)
        XCTAssertEqual(workload.capacityMinutes, 510)
        XCTAssertEqual(workload.remainingCapacityMinutes, 330)
        XCTAssertTrue(workload.exceedsMaximumDailyAssignments)
    }

    func testHistoricalMetricsUseTechnicianSpecificLabor() {
        let employee = makeEmployee()
        var first = makeAssignment(
            number: "ASN-1",
            date: makeDate(day: 20, hour: 8),
            durationMinutes: 60,
            primaryID: employee.id,
            primaryLaborMinutes: 50,
            status: .closed
        )
        first.workCompletedDate = makeDate(day: 20, hour: 9)

        var second = makeAssignment(
            number: "ASN-2",
            date: makeDate(day: 21, hour: 8),
            durationMinutes: 90,
            primaryID: employee.id,
            primaryLaborMinutes: 70,
            status: .workComplete
        )
        second.workCompletedDate = makeDate(day: 21, hour: 10)

        let metrics = engine.historicalMetrics(
            for: employee,
            assignments: [first, second]
        )

        XCTAssertEqual(metrics.completedAssignmentCount, 2)
        XCTAssertEqual(metrics.totalRecordedLaborMinutes, 120)
        XCTAssertEqual(metrics.averageAssignmentMinutes, 60)
        XCTAssertEqual(
            metrics.lastCompletedAssignmentDate,
            makeDate(day: 21, hour: 10)
        )
    }

    func testUnifiedSnapshotRequiresCapabilityAndAvailability() {
        let date = makeDate(day: 22, hour: 8)
        let employee = makeEmployee(
            profile: WorkforceOperationalProfile(
                skills: [
                    WorkforceSkill(
                        name: "Gutter Cleaning",
                        serviceType: .gutterCleaning,
                        proficiency: .expert
                    )
                ]
            )
        )

        let snapshot = engine.snapshot(
            for: employee,
            on: date,
            assignments: [],
            requirements: WorkforceCapabilityRequirements(
                requiredServiceType: .gutterCleaning,
                minimumProficiency: .proficient
            )
        )

        XCTAssertTrue(snapshot.isOperationallyEligible)
        XCTAssertEqual(snapshot.capability.state, .qualified)
        XCTAssertEqual(snapshot.availability.state, .available)
        XCTAssertEqual(snapshot.workload.assignmentCount, 0)
    }

    // MARK: - Fixtures

    private func makeEmployee(
        profile: WorkforceOperationalProfile? = nil
    ) -> EmployeeRecord {
        EmployeeRecord(
            id: technicianID(1),
            firstName: "Tim",
            lastName: "Technician",
            role: .technician,
            defaultStartMinutes: 8 * 60,
            defaultEndMinutes: 17 * 60,
            lunchDurationMinutes: 30,
            workingDays: Workday.standardWorkweek,
            workforceProfile: profile ?? WorkforceOperationalProfile()
        )
    }

    private func makeAssignment(
        number: String,
        date: Date,
        durationMinutes: Int,
        primaryID: UUID,
        supportingID: UUID? = nil,
        primaryLaborMinutes: Int = 0,
        status: AssignmentStatus = .scheduled
    ) -> Assignment {
        var members = [
            AssignmentCrewMember(
                employeeID: primaryID,
                role: .primary,
                laborMinutes: primaryLaborMinutes
            )
        ]

        if let supportingID {
            members.append(
                AssignmentCrewMember(
                    employeeID: supportingID,
                    role: .supporting
                )
            )
        }

        return Assignment(
            id: UUID(),
            assignmentNumber: number,
            jobID: UUID(),
            jobNumber: "JOB-\(number)",
            customerNumber: "PPS-000001",
            status: status,
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: date,
                fixedStartDate: date,
                estimatedDurationMinutes: durationMinutes
            ),
            crew: AssignmentCrew(members: members)
        )
    }

    private func technicianID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "10000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private func makeDate(
        day: Int,
        hour: Int,
        year: Int = 2026
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: 7,
                day: day,
                hour: hour
            )
        )!
    }
}

private struct LegacyEmployeeRecord: Codable {
    var id: UUID
    var firstName: String
    var lastName: String
    var phone: String
    var email: String
    var role: EmployeeRole
    var defaultStartMinutes: Int
    var defaultEndMinutes: Int
    var lunchDurationMinutes: Int
    var workingDays: Set<Workday>
    var colorName: String
    var isActive: Bool
    var createdDate: Date
    var lifecycleStatus: RecordLifecycleStatus
}
