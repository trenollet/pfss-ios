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
            offlineSynchronizationMode: .queueRemoteOperations
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
            offlineSynchronizationMode: .queueRemoteOperations
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

    func testTechnicianNoteUpdatesTimelineAndQueuesExactEvent() throws {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .queueRemoteOperations
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
            offlineSynchronizationMode: .queueRemoteOperations
        )
        // AppDataStore intentionally persists between launches. A unique Job
        // number prevents a prior test run's linked invoice from changing the
        // workflow state resolved for this new fixture.
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

    func testLocalOnlyModeDoesNotCreateFalseRemoteBacklog() {
        let queue = OfflineOperationQueue(persistence: MemoryQueuePersistence())
        let store = AppDataStore(
            offlineOperationQueue: queue,
            offlineSynchronizationMode: .localOnly
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
