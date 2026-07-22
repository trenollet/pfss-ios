import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct DispatchEngineTests {
    @Test
    func hybridTechnicianMaySelfAssignButNotAssignAnotherTechnician() throws {
        let fixture = try makeFixture()
        let technician = makeEmployee(firstName: "Alex")
        let otherTechnician = makeEmployee(firstName: "Blake")
        let actor = DispatchActor.employee(technician)

        let selfAuthorization = fixture.dispatchEngine.authorization(
            for: .assignPrimaryTechnician,
            actor: actor,
            assignmentID: fixture.assignment.id,
            affectedTechnicianID: technician.id
        )
        let otherAuthorization = fixture.dispatchEngine.authorization(
            for: .assignPrimaryTechnician,
            actor: actor,
            assignmentID: fixture.assignment.id,
            affectedTechnicianID: otherTechnician.id
        )

        #expect(selfAuthorization.isAllowed)
        #expect(!otherAuthorization.isAllowed)
    }

    @Test
    func dispatcherManagedModePreventsTechnicianSelfDispatch() throws {
        let fixture = try makeFixture(
            policy: DispatchPolicy(operatingMode: .dispatcherManaged)
        )
        let technician = makeEmployee(firstName: "Alex")
        let assigned = try fixture.assignmentEngine.assignPrimaryTechnician(
            assignmentID: fixture.assignment.id,
            employeeID: technician.id
        )

        let authorization = fixture.dispatchEngine.authorization(
            for: .dispatchAssignment,
            actor: .employee(technician),
            assignmentID: assigned.id,
            affectedTechnicianID: technician.id
        )

        #expect(!authorization.isAllowed)
    }

    @Test
    func assignmentAndDispatchCreateDurableHistory() throws {
        let fixture = try makeFixture()
        let technician = makeEmployee(firstName: "Alex")

        let assigned = try fixture.dispatchEngine.assignPrimaryTechnician(
            assignmentID: fixture.assignment.id,
            technician: technician,
            actor: .system,
            note: "Dispatcher selected Alex."
        )
        let dispatched = try fixture.dispatchEngine.dispatch(
            assignmentID: fixture.assignment.id,
            actor: .system
        )

        #expect(assigned.assignment.primaryTechnicianID == technician.id)
        #expect(dispatched.assignment.status == .dispatched)
        #expect(
            dispatched.assignment.history.events.contains {
                $0.type == .primaryTechnicianAssigned
            }
        )
        #expect(
            dispatched.assignment.history.events.contains {
                $0.type == .dispatched
            }
        )
    }

    @Test
    func reassignmentPreservesSupportingTechnician() throws {
        let primary = makeEmployee(firstName: "Alex")
        let replacement = makeEmployee(firstName: "Blake")
        let supporting = makeEmployee(firstName: "Casey")
        let fixture = try makeFixture(
            primaryTechnicianID: primary.id,
            supportingTechnicianIDs: [supporting.id]
        )

        let result = try fixture.dispatchEngine.assignPrimaryTechnician(
            assignmentID: fixture.assignment.id,
            technician: replacement,
            actor: .system,
            note: "Customer requested a different crew lead."
        )

        #expect(result.assignment.primaryTechnicianID == replacement.id)
        #expect(result.assignment.supportingTechnicianIDs == [supporting.id])
        #expect(
            result.assignment.history.events.contains {
                $0.title == "Primary technician replaced"
            }
        )
    }

    @Test
    func supportingTechnicianCanBeReplacedWithAuditHistory() throws {
        let primary = makeEmployee(firstName: "Alex")
        let supporting = makeEmployee(firstName: "Casey")
        let replacement = makeEmployee(firstName: "Drew")
        let fixture = try makeFixture(
            primaryTechnicianID: primary.id,
            supportingTechnicianIDs: [supporting.id]
        )

        let result = try fixture.dispatchEngine.replaceSupportingTechnician(
            assignmentID: fixture.assignment.id,
            technician: replacement,
            actor: .system,
            reason: "Crew availability changed."
        )

        #expect(result.assignment.supportingTechnicianIDs == [replacement.id])
        #expect(result.event.action == .replaceSupportingTechnician)
        #expect(
            result.assignment.history.events.contains {
                $0.type == .supportingTechnicianReplaced
            }
        )
    }

    @Test
    func emergencyInsertionProducesOptionsAndAppliesSelectedPlan() throws {
        let date = testDate()
        let technician = makeEmployee(firstName: "Alex")
        let fixture = try makeFixture(serviceDate: date)
        let job = makeJob(id: fixture.assignment.jobID, scheduledDate: date)
        let request = EmergencyInsertionRequest(
            assignmentID: fixture.assignment.id,
            requestedStart: date,
            reason: "Active roof leak",
            dispatchImmediately: true
        )

        let plan = try fixture.dispatchEngine.prepareEmergencyInsertion(
            request: request,
            actor: .system,
            job: job,
            employees: [technician],
            jobs: [job]
        )
        let option = try #require(plan.recommendedOption)
        let result = try fixture.dispatchEngine.applyEmergencyInsertion(
            plan: plan,
            optionID: option.id,
            employees: [technician],
            actor: .system
        )

        #expect(option.technicianID == technician.id)
        #expect(result.assignment.priority == .emergency)
        #expect(result.assignment.primaryTechnicianID == technician.id)
        #expect(result.assignment.status == .dispatched)
        #expect(result.event.action == .insertEmergencyWork)
    }

    @Test
    func officeDispatcherMayOverrideStatusAndHistoryIsPreserved() throws {
        let fixture = try makeFixture()
        let dispatcher = EmployeeRecord(
            firstName: "Dana",
            lastName: "Dispatcher",
            role: .office
        )

        let result = try fixture.dispatchEngine.overrideStatus(
            assignmentID: fixture.assignment.id,
            to: .onSite,
            actor: .employee(dispatcher),
            reason: "Technician called in an arrival update."
        )

        #expect(result.assignment.status == .onSite)
        #expect(result.event.action == .overrideStatus)
        #expect(result.event.wasHumanOverride)
        #expect(
            result.assignment.history.events.contains {
                $0.type == .overrideApplied
            }
        )
    }

    @Test
    func assignedTechnicianMayReorderOwnRouteInHybridMode() throws {
        let technician = makeEmployee(firstName: "Alex")
        let fixture = try makeFixture(primaryTechnicianID: technician.id)

        let result = try fixture.dispatchEngine.reorderRoute(
            assignmentID: fixture.assignment.id,
            routeSequence: 3,
            actor: .employee(technician),
            reason: "Customer requested a later arrival."
        )

        #expect(result.assignment.routeSequence == 3)
        #expect(result.event.action == .reorderRoute)
        #expect(
            result.assignment.history.events.contains {
                $0.type == .routeOrderChanged
            }
        )
    }

    private func makeFixture(
        policy: DispatchPolicy? = nil,
        serviceDate: Date? = nil,
        primaryTechnicianID: UUID? = nil,
        supportingTechnicianIDs: [UUID] = []
    ) throws -> Fixture {
        let resolvedDate = serviceDate ?? testDate()
        let store = AssignmentStore()
        let assignmentEngine = AssignmentEngine(store: store)
        let dispatchEngine = DispatchEngine(
            assignmentEngine: assignmentEngine,
            policy: policy ?? DispatchPolicy()
        )
        let jobID = UUID()
        let assignment = try assignmentEngine.createAssignment(
            assignmentNumber: "ASN-TEST-001",
            jobID: jobID,
            jobNumber: "JOB-TEST-001",
            customerNumber: "PPS-TEST-001",
            scheduling: AssignmentScheduling(
                mode: .fixedTime,
                serviceDate: resolvedDate,
                fixedStartDate: resolvedDate,
                estimatedDurationMinutes: 60,
                isCustomerConfirmed: true
            ),
            primaryTechnicianID: primaryTechnicianID,
            supportingTechnicianIDs: supportingTechnicianIDs
        )

        return Fixture(
            assignmentEngine: assignmentEngine,
            dispatchEngine: dispatchEngine,
            assignment: assignment
        )
    }

    private func makeEmployee(firstName: String) -> EmployeeRecord {
        EmployeeRecord(
            firstName: firstName,
            lastName: "Technician",
            role: .technician,
            workingDays: Set(Workday.allCases)
        )
    }

    private func makeJob(id: UUID, scheduledDate: Date) -> JobRecord {
        JobRecord(
            id: id,
            jobNumber: "JOB-TEST-001",
            customerNumber: "PPS-TEST-001",
            siteID: nil,
            estimateNumber: "",
            serviceType: .other,
            otherService: "Emergency Service",
            subtotal: 100,
            discount: 0,
            total: 100,
            primaryTechnicianID: nil,
            secondaryTechnicianID: nil,
            scheduledDate: scheduledDate,
            completedDate: nil,
            status: .toBeScheduled,
            workNotes: "",
            isRecurring: false,
            createdDate: scheduledDate
        )
    }

    private func testDate() -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 27,
                hour: 9
            )
        )!
    }
}

@MainActor
private struct Fixture {
    let assignmentEngine: AssignmentEngine
    let dispatchEngine: DispatchEngine
    let assignment: Assignment
}
