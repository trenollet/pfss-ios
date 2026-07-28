//
//  OfflineWorkflowIntegrationTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 3 – Local-first workflow integration coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineWorkflowIntegrationTests: XCTestCase {
    private let technicianID = UUID()
    private let siteID = UUID()

    func testSuccessfulWorkflowActionUpdatesLocallyAndQueuesIntent() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-OFFLINE-WORKFLOW")
        store.addJob(job)
        let timestamp = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(
            store.performWorkflowAction(
                jobID: job.id,
                action: .startTravel,
                employeeID: technicianID,
                note: "Leaving the shop.",
                at: timestamp
            )
        )

        XCTAssertEqual(
            store.jobs.first(where: { $0.id == job.id })?.workflowState,
            .traveling
        )
        let operation = try XCTUnwrap(queue.orderedOperations.last)
        XCTAssertEqual(operation.type, .workflowAction)
        XCTAssertEqual(operation.entityID, job.id)
        XCTAssertEqual(operation.actionName, JobWorkflowAction.startTravel.rawValue)
        let payload = try operation.payload.decode(OfflineWorkflowActionPayload.self)
        XCTAssertEqual(payload.jobID, job.id)
        XCTAssertEqual(payload.resultingWorkflowState, JobWorkflowState.traveling.rawValue)
        XCTAssertEqual(payload.occurredAt, timestamp)
    }

    func testInvalidWorkflowActionDoesNotEnterQueue() {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-OFFLINE-INVALID")
        store.addJob(job)

        XCTAssertFalse(
            store.performWorkflowAction(
                jobID: job.id,
                action: .startWork,
                employeeID: technicianID
            )
        )
        XCTAssertTrue(queue.operations.isEmpty)
    }

    func testTravelPauseAndResumeUpdateLocallyAndRemainInOfflineOrder() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-OFFLINE-TRAVEL-PAUSE")
        store.addJob(job)

        let actions: [JobWorkflowAction] = [
            .startTravel,
            .pauseTravel,
            .resumeTravel,
            .markArrived
        ]

        for (offset, action) in actions.enumerated() {
            XCTAssertTrue(store.performWorkflowAction(
                jobID: job.id,
                action: action,
                employeeID: technicianID,
                at: Date(timeIntervalSince1970: 15_000 + Double(offset))
            ))
        }

        XCTAssertEqual(
            store.jobs.first(where: { $0.id == job.id })?.workflowState,
            .arrived
        )
        XCTAssertEqual(
            queue.orderedOperations
                .filter { $0.entityID == job.id }
                .map(\.actionName),
            actions.map(\.rawValue)
        )
    }

    func testTechnicianNoteUpdatesTimelineAndQueuesExactEvent() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-OFFLINE-NOTE")
        store.addJob(job)
        let timestamp = Date(timeIntervalSince1970: 20_000)

        let event = try XCTUnwrap(
            store.addTechnicianNote(
                jobID: job.id,
                text: "  Customer approved the additional screen.  ",
                employeeID: technicianID,
                at: timestamp
            )
        )

        XCTAssertEqual(
            store.jobs.first(where: { $0.id == job.id })?.timelineEvents.last?.id,
            event.id
        )
        let operation = try XCTUnwrap(queue.orderedOperations.last)
        XCTAssertEqual(operation.type, .jobNote)
        let payload = try operation.payload.decode(OfflineTechnicianNotePayload.self)
        XCTAssertEqual(payload.timelineEventID, event.id)
        XCTAssertEqual(payload.text, "Customer approved the additional screen.")
    }

    func testInvoiceStatusChangeQueuesPaymentIntentAndCompletesLocalJob() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        // Keep the fixture identity unique so invoice lookup behavior is also
        // independent within this in-memory test store.
        let job = makeJob(
            number: "JOB-OFFLINE-PAYMENT-\(UUID().uuidString)"
        )
        store.addJob(job)

        let actions: [JobWorkflowAction] = [
            .startTravel,
            .markArrived,
            .startSetup,
            .startWork,
            .startPackUp,
            .finishWork,
            .createInvoice
        ]
        for (offset, action) in actions.enumerated() {
            XCTAssertTrue(
                store.performWorkflowAction(
                    jobID: job.id,
                    action: action,
                    employeeID: technicianID,
                    at: Date(timeIntervalSince1970: 25_000 + Double(offset))
                ),
                "Expected \(action.rawValue) to succeed in the real workflow."
            )
        }

        var invoice = try XCTUnwrap(store.invoice(forJobID: job.id))

        invoice.status = .paid
        invoice.amountPaid = invoice.total
        invoice.balanceDue = 0
        invoice.paidDate = Date(timeIntervalSince1970: 30_000)
        store.updateInvoice(invoice)

        XCTAssertEqual(
            store.jobs.first(where: { $0.id == job.id })?.workflowState,
            .completed
        )
        XCTAssertTrue(queue.operations.contains(where: {
            $0.type == .paymentRecording && $0.entityID == invoice.id
        }))
        XCTAssertTrue(queue.operations.contains(where: {
            $0.type == .workflowAction &&
            $0.actionName == JobWorkflowAction.completeJob.rawValue
        }))
    }

    func testPartialPaymentRecalculatesBalanceAndStatus() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        var invoice = InvoiceRecord(
            invoiceNumber: "INV-PARTIAL-PAYMENT",
            customerNumber: "PPS-OFFLINE-TEST",
            siteID: nil,
            jobNumber: "",
            lineItems: [],
            subtotal: 60,
            discount: 0,
            total: 60,
            amountPaid: 0,
            balanceDue: 60,
            status: .sent,
            issueDate: Date(timeIntervalSince1970: 40_000),
            dueDate: Date(timeIntervalSince1970: 50_000),
            paidDate: nil,
            notes: ""
        )
        store.addInvoice(invoice)

        invoice.amountPaid = 20
        store.updateInvoice(invoice)

        let savedInvoice = try XCTUnwrap(
            store.invoices.first(where: { $0.id == invoice.id })
        )
        XCTAssertEqual(savedInvoice.amountPaid, 20)
        XCTAssertEqual(savedInvoice.balanceDue, 40)
        XCTAssertEqual(savedInvoice.status, .partiallyPaid)
        XCTAssertNil(savedInvoice.paidDate)
        XCTAssertTrue(queue.operations.contains(where: {
            $0.type == .paymentRecording && $0.entityID == invoice.id
        }))
    }

    func testLocalOnlyModeDoesNotCreateFalseRemoteBacklog() {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .localOnly,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-LOCAL-ONLY")
        store.addJob(job)

        XCTAssertTrue(
            store.performWorkflowAction(
                jobID: job.id,
                action: .startTravel,
                employeeID: technicianID
            )
        )
        XCTAssertEqual(
            store.jobs.first(where: { $0.id == job.id })?.workflowState,
            .traveling
        )
        XCTAssertTrue(queue.operations.isEmpty)
    }

    func testManagerCorrectionPreservesOriginalTimeAndQueuesAuditIntent() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let manager = EmployeeRecord(
            firstName: "Pat",
            lastName: "Manager",
            role: .manager,
            roles: [.manager]
        )
        store.addEmployee(manager)

        var job = makeJob(number: "JOB-TIMELINE-CORRECTION")
        let originalTimestamp = Date(timeIntervalSince1970: 60_000)
        let correctedTimestamp = Date(timeIntervalSince1970: 59_100)
        let event = JobTimelineEvent(
            type: .setupStarted,
            title: "Setup Started",
            timestamp: originalTimestamp,
            employeeID: technicianID
        )
        job.timelineEvents = [event]
        store.addJob(job)

        let audit = try XCTUnwrap(store.correctTimelineTimestamp(
            jobID: job.id,
            eventID: event.id,
            correctedTimestamp: correctedTimestamp,
            reason: "Technician forgot to tap after setup.",
            actorEmployeeID: manager.id,
            correctedAt: Date(timeIntervalSince1970: 61_000)
        ))

        let savedJob = try XCTUnwrap(store.jobs.first { $0.id == job.id })
        XCTAssertEqual(
            savedJob.timelineEvents.first { $0.id == event.id }?.timestamp,
            correctedTimestamp
        )
        XCTAssertEqual(savedJob.setupStartDate, correctedTimestamp)
        XCTAssertEqual(audit.type, .timelineCorrected)
        XCTAssertEqual(audit.correctedEventID, event.id)
        XCTAssertEqual(audit.originalTimestamp, originalTimestamp)
        XCTAssertEqual(audit.correctedTimestamp, correctedTimestamp)
        XCTAssertEqual(audit.employeeID, manager.id)

        let operation = try XCTUnwrap(queue.orderedOperations.last)
        XCTAssertEqual(operation.type, .jobTimestamp)
        XCTAssertEqual(operation.actionName, "correctTimelineTimestamp")
        let payload = try operation.payload.decode(
            OfflineTimelineCorrectionPayload.self
        )
        XCTAssertEqual(payload.eventID, event.id)
        XCTAssertEqual(payload.originalTimestamp, originalTimestamp)
        XCTAssertEqual(payload.correctedTimestamp, correctedTimestamp)
        XCTAssertEqual(payload.actorEmployeeID, manager.id)
    }

    func testTechnicianCannotCorrectTimeline() {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let technician = EmployeeRecord(
            firstName: "Field",
            lastName: "Technician",
            role: .technician,
            roles: [.technician]
        )
        store.addEmployee(technician)

        var job = makeJob(number: "JOB-TIMELINE-UNAUTHORIZED")
        let event = JobTimelineEvent(
            type: .workStarted,
            title: "Work Started",
            timestamp: Date(timeIntervalSince1970: 70_000)
        )
        job.timelineEvents = [event]
        store.addJob(job)

        XCTAssertNil(store.correctTimelineTimestamp(
            jobID: job.id,
            eventID: event.id,
            correctedTimestamp: Date(timeIntervalSince1970: 69_000),
            reason: "Unauthorized correction",
            actorEmployeeID: technician.id
        ))
        XCTAssertEqual(
            store.jobs.first { $0.id == job.id }?.timelineEvents,
            [event]
        )
        XCTAssertTrue(queue.operations.isEmpty)
    }

    func testSharedScreenCoordinatorsObserveOneWorkflowAndOfflineHistory() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-CROSS-ENTRY-POINT")
        store.addJob(job)

        // My Day and Job Detail each create a coordinator, but both must read
        // and mutate the same store-backed workflow rather than keeping their
        // own screen-specific lifecycle state.
        let myDayCoordinator = FieldOperationsWorkflowCoordinator(store: store)
        let jobDetailCoordinator = FieldOperationsWorkflowCoordinator(store: store)
        let actions: [JobWorkflowAction] = [
            .startTravel,
            .pauseTravel,
            .resumeTravel,
            .markArrived
        ]

        XCTAssertTrue(myDayCoordinator.performWorkflowAction(
            jobID: job.id,
            action: .startTravel,
            employeeID: technicianID,
            at: Date(timeIntervalSince1970: 80_000)
        ))
        XCTAssertEqual(
            jobDetailCoordinator.workflowContext(for: job.id)?.currentState,
            .traveling
        )

        XCTAssertTrue(jobDetailCoordinator.pauseTravel(
            jobID: job.id,
            employeeID: technicianID,
            at: Date(timeIntervalSince1970: 80_001)
        ))
        XCTAssertEqual(
            myDayCoordinator.workflowContext(for: job.id)?.currentState,
            .travelPaused
        )

        XCTAssertTrue(myDayCoordinator.resumeTravel(
            jobID: job.id,
            employeeID: technicianID,
            at: Date(timeIntervalSince1970: 80_002)
        ))
        XCTAssertTrue(jobDetailCoordinator.performWorkflowAction(
            jobID: job.id,
            action: .markArrived,
            employeeID: technicianID,
            at: Date(timeIntervalSince1970: 80_003)
        ))

        let savedJob = try XCTUnwrap(store.jobs.first { $0.id == job.id })
        XCTAssertEqual(savedJob.workflowState, .arrived)
        XCTAssertEqual(
            myDayCoordinator.workflowContext(for: job.id)?.currentState,
            jobDetailCoordinator.workflowContext(for: job.id)?.currentState
        )
        XCTAssertEqual(
            queue.orderedOperations
                .filter { $0.entityID == job.id }
                .map(\.actionName),
            actions.map(\.rawValue)
        )
        XCTAssertEqual(
            savedJob.timelineEvents.suffix(actions.count).map(\.type),
            [.travelStarted, .travelPaused, .travelResumed, .arrived]
        )
    }

    func testFullSharedLifecycleKeepsJobAssignmentInvoiceTimelineAndQueueAligned() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let job = makeJob(number: "JOB-STEP-6-ACCEPTANCE")
        store.addJob(job)
        let coordinator = FieldOperationsWorkflowCoordinator(store: store)
        let actions: [JobWorkflowAction] = [
            .startTravel,
            .pauseTravel,
            .resumeTravel,
            .markArrived,
            .startSetup,
            .startWork,
            .pauseWork,
            .resumeWork,
            .startPackUp,
            .finishWork,
            .createInvoice
        ]

        for (offset, action) in actions.enumerated() {
            XCTAssertTrue(
                coordinator.performWorkflowAction(
                    jobID: job.id,
                    action: action,
                    employeeID: technicianID,
                    at: Date(timeIntervalSince1970: 90_000 + Double(offset))
                ),
                "Expected the shared Operations API to perform \(action.rawValue)."
            )
        }

        let savedJob = try XCTUnwrap(store.jobs.first { $0.id == job.id })
        let assignment = try XCTUnwrap(store.assignment(forJobID: job.id))
        let invoice = try XCTUnwrap(store.invoice(forJobID: job.id))

        XCTAssertEqual(savedJob.workflowState, .invoiceCreated)
        XCTAssertEqual(assignment.status, .invoiceReady)
        XCTAssertEqual(invoice.jobNumber, savedJob.jobNumber)
        XCTAssertEqual(coordinator.workflowContext(for: job.id)?.currentState, .invoiceCreated)
        XCTAssertEqual(
            queue.orderedOperations
                .filter { $0.entityID == job.id }
                .map(\.actionName),
            actions.map(\.rawValue)
        )
        XCTAssertEqual(
            savedJob.timelineEvents.suffix(actions.count).map(\.type),
            [
                .travelStarted,
                .travelPaused,
                .travelResumed,
                .arrived,
                .setupStarted,
                .workStarted,
                .workPaused,
                .workResumed,
                .packUpStarted,
                .workCompleted,
                .invoiceCreated
            ]
        )
    }

    func testInterruptedFieldDayKeepsEachJobIndependentAndAuditable() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false
        )
        let manager = EmployeeRecord(
            firstName: "Morgan",
            lastName: "Manager",
            role: .manager,
            roles: [.manager]
        )
        store.addEmployee(manager)

        let scheduledJob = makeJob(number: "JOB-FIELD-DAY-SCHEDULED")
        let interruptionJob = makeJob(number: "JOB-FIELD-DAY-INTERRUPTION")
        store.addJob(scheduledJob)
        store.addJob(interruptionJob)
        let coordinator = FieldOperationsWorkflowCoordinator(store: store)

        XCTAssertTrue(coordinator.performWorkflowAction(
            jobID: scheduledJob.id,
            action: .startTravel,
            employeeID: technicianID,
            at: Date(timeIntervalSince1970: 100_000)
        ))
        XCTAssertTrue(coordinator.pauseTravel(
            jobID: scheduledJob.id,
            employeeID: technicianID,
            note: "Paused for an impromptu estimate.",
            at: Date(timeIntervalSince1970: 100_001)
        ))

        let interruptionActions: [JobWorkflowAction] = [
            .startTravel,
            .markArrived,
            .startSetup,
            .startWork,
            .startPackUp,
            .finishWork,
            .createInvoice
        ]
        for (offset, action) in interruptionActions.enumerated() {
            XCTAssertTrue(coordinator.performWorkflowAction(
                jobID: interruptionJob.id,
                action: action,
                employeeID: technicianID,
                at: Date(timeIntervalSince1970: 100_010 + Double(offset))
            ))
        }

        let resumedActions: [JobWorkflowAction] = [
            .resumeTravel,
            .markArrived,
            .startSetup,
            .startWork,
            .pauseWork,
            .resumeWork
        ]
        for (offset, action) in resumedActions.enumerated() {
            XCTAssertTrue(coordinator.performWorkflowAction(
                jobID: scheduledJob.id,
                action: action,
                employeeID: technicianID,
                at: Date(timeIntervalSince1970: 100_020 + Double(offset))
            ))
        }

        var savedScheduledJob = try XCTUnwrap(
            store.jobs.first { $0.id == scheduledJob.id }
        )
        let setupEvent = try XCTUnwrap(
            savedScheduledJob.timelineEvents.first { $0.type == .setupStarted }
        )
        let correctedSetupTime = setupEvent.timestamp.addingTimeInterval(-300)
        XCTAssertNotNil(store.correctTimelineTimestamp(
            jobID: scheduledJob.id,
            eventID: setupEvent.id,
            correctedTimestamp: correctedSetupTime,
            reason: "Setup began five minutes before the technician remembered to tap.",
            actorEmployeeID: manager.id,
            correctedAt: Date(timeIntervalSince1970: 100_030)
        ))

        savedScheduledJob = try XCTUnwrap(
            store.jobs.first { $0.id == scheduledJob.id }
        )
        let savedInterruptionJob = try XCTUnwrap(
            store.jobs.first { $0.id == interruptionJob.id }
        )

        XCTAssertEqual(savedScheduledJob.workflowState, .working)
        XCTAssertEqual(savedScheduledJob.setupStartDate, correctedSetupTime)
        XCTAssertTrue(savedScheduledJob.timelineEvents.contains {
            $0.type == .timelineCorrected && $0.correctedEventID == setupEvent.id
        })
        XCTAssertEqual(savedInterruptionJob.workflowState, .invoiceCreated)
        XCTAssertNotNil(store.invoice(forJobID: interruptionJob.id))
        XCTAssertNil(store.invoice(forJobID: scheduledJob.id))

        XCTAssertEqual(
            queue.orderedOperations.filter {
                $0.entityID == scheduledJob.id && $0.type == .workflowAction
            }.map(\.actionName),
            ([.startTravel, .pauseTravel] + resumedActions).map(\.rawValue)
        )
        XCTAssertEqual(
            queue.orderedOperations.filter {
                $0.entityID == interruptionJob.id && $0.type == .workflowAction
            }.map(\.actionName),
            interruptionActions.dropLast().map(\.rawValue)
        )
        XCTAssertTrue(
            queue.orderedOperations.contains {
                $0.entityID == interruptionJob.id &&
                $0.type == .invoiceHandoff &&
                $0.actionName == JobWorkflowAction.createInvoice.rawValue
            }
        )
        XCTAssertTrue(queue.orderedOperations.contains {
            $0.entityID == scheduledJob.id &&
            $0.type == .jobTimestamp &&
            $0.actionName == "correctTimelineTimestamp"
        })
    }

    private func makeJob(
        number: String,
        workflowState: JobWorkflowState = .notStarted,
        status: JobStatus = .scheduled
    ) -> JobRecord {
        JobRecord(
            jobNumber: number,
            customerNumber: "PPS-OFFLINE-TEST",
            siteID: siteID,
            estimateNumber: "",
            serviceType: .windowCleaning,
            otherService: "",
            subtotal: 100,
            discount: 0,
            total: 100,
            primaryTechnicianID: technicianID,
            secondaryTechnicianID: nil,
            scheduledDate: Date(timeIntervalSince1970: 9_000),
            status: status,
            workflowState: workflowState,
            workNotes: "",
            isRecurring: false,
            createdDate: Date(timeIntervalSince1970: 8_000)
        )
    }

}

private final class MemoryQueuePersistence: OfflineOperationQueuePersistence {
    private var data: Data?

    func load() throws -> Data? { data }

    func save(_ data: Data) throws {
        self.data = data
    }
}
