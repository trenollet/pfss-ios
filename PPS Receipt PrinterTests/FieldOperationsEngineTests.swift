//
//  FieldOperationsEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 – Step 1: Field Operations Engine Foundation
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class FieldOperationsEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let jobID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let technicianID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let siteID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!

    func testCanonicalWorkflowVocabularyAndPresentationMetadata() {
        let expected: [(JobWorkflowAction, String, JobWorkflowAccent)] = [
            (.startTravel, "Start Travel", .orange),
            (.markArrived, "Arrived", .orange),
            (.startSetup, "Start Setup", .orange),
            (.startWork, "Start Work", .orange),
            (.pauseWork, "Pause Work", .orange),
            (.resumeWork, "Resume Work", .orange),
            (.startPackUp, "Start Pack-up", .orange),
            (.finishWork, "Complete Work", .orange),
            (.createInvoice, "Create Invoice", .blue),
            (.recordPayment, "Record Payment", .purple),
            (.completeJob, "Complete", .green),
            (.viewDetails, "Details", .secondary)
        ]

        for (action, title, accent) in expected {
            XCTAssertEqual(action.presentation.title, title)
            XCTAssertEqual(action.title, title)
            XCTAssertEqual(action.presentation.accent, accent)
            XCTAssertFalse(action.presentation.systemImage.isEmpty)
        }
    }

    func testSentInvoiceUsesTechnicianCompletePresentationWithoutChangingFinancialState() {
        let context = FieldOperationsEngine().context(
            for: makeJob(workflowState: .invoiceCreated, status: .inProgress),
            invoice: makeInvoice(status: .sent)
        )

        XCTAssertEqual(context.currentState, .invoiceCreated)
        XCTAssertEqual(context.presentation.statusTitle, "Invoice Sent")
        XCTAssertEqual(context.presentation.statusSystemImage, "paperplane.fill")
        XCTAssertEqual(context.presentation.accent, .green)
        XCTAssertEqual(context.presentation.completionTitle, "Job Complete")
        XCTAssertTrue(context.presentation.isTechnicianComplete)
    }

    func testPaidInvoiceUsesSharedPaymentReceivedCompletionPresentation() {
        let context = FieldOperationsEngine().context(
            for: makeJob(workflowState: .invoiceCreated, status: .inProgress),
            invoice: makeInvoice(status: .paid)
        )

        XCTAssertEqual(context.currentState, .paymentReceived)
        XCTAssertEqual(context.presentation.statusTitle, "Payment Received")
        XCTAssertEqual(context.presentation.accent, .green)
        XCTAssertEqual(context.presentation.completionTitle, "Job Complete")
        XCTAssertTrue(context.presentation.isTechnicianComplete)
    }

    func testInitialContextBeginsWithTravelAction() {
        let job = makeJob()

        let context = FieldOperationsEngine().context(for: job)

        XCTAssertEqual(context.currentState, .notStarted)
        XCTAssertEqual(context.nextAction, .startTravel)
        XCTAssertEqual(context.progressPercentage, 0)
        XCTAssertFalse(context.canCreateInvoice)
        XCTAssertFalse(context.canCollectPayment)
        XCTAssertFalse(context.canCompleteJob)
        XCTAssertFalse(context.isTerminal)
    }

    func testTimelineIsSortedInsideContext() {
        var job = makeJob()
        job.timelineEvents = [
            JobTimelineEvent(
                type: .workCompleted,
                title: "Job Completed",
                timestamp: date(hour: 11, minute: 30)
            ),
            JobTimelineEvent(
                type: .travelStarted,
                title: "Travel Started",
                timestamp: date(hour: 8, minute: 5)
            ),
            JobTimelineEvent(
                type: .arrived,
                title: "Arrived On Site",
                timestamp: date(hour: 8, minute: 45)
            )
        ]

        let context = FieldOperationsEngine().context(for: job)

        XCTAssertEqual(
            context.timeline.map(\.title),
            [
                "Travel Started",
                "Arrived On Site",
                "Job Completed"
            ]
        )
    }

    func testTransitionSequenceCoversTravelWorkInvoiceAndCloseout() throws {
        let engine = FieldOperationsEngine()
        var job = makeJob()
        let start = date(hour: 8)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .startTravel,
                employeeID: technicianID,
                at: start
            )
        )
        XCTAssertEqual(job.workflowState, .traveling)
        XCTAssertEqual(job.status, .inProgress)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .markArrived,
                employeeID: technicianID,
                at: date(hour: 8, minute: 15)
            )
        )
        XCTAssertEqual(job.workflowState, .arrived)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .startSetup,
                employeeID: technicianID,
                at: date(hour: 8, minute: 20)
            )
        )
        XCTAssertEqual(job.workflowState, .settingUp)
        XCTAssertEqual(job.setupStartDate, date(hour: 8, minute: 20))

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .startWork,
                employeeID: technicianID,
                at: date(hour: 8, minute: 35)
            )
        )
        XCTAssertEqual(job.workflowState, .working)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .startPackUp,
                employeeID: technicianID,
                at: date(hour: 10, minute: 30)
            )
        )
        XCTAssertEqual(job.workflowState, .packingUp)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .finishWork,
                employeeID: technicianID,
                at: date(hour: 10, minute: 45)
            )
        )
        XCTAssertEqual(job.workflowState, .workComplete)
        XCTAssertEqual(job.status, .inProgress)
        XCTAssertEqual(job.completedDate, date(hour: 10, minute: 45))

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .createInvoice,
                employeeID: technicianID,
                at: date(hour: 11)
            )
        )
        XCTAssertEqual(job.workflowState, .invoiceCreated)
        XCTAssertEqual(job.status, .inProgress)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .recordPayment,
                employeeID: technicianID,
                invoice: makeInvoice(status: .sent),
                at: date(hour: 11, minute: 15)
            )
        )
        XCTAssertEqual(job.workflowState, .paymentReceived)
        XCTAssertEqual(job.status, .inProgress)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .completeJob,
                employeeID: technicianID,
                at: date(hour: 11, minute: 30)
            )
        )
        XCTAssertEqual(job.workflowState, .completed)
        XCTAssertEqual(job.status, .completed)

        XCTAssertEqual(
            job.timelineEvents.map(\.title),
            [
                "Travel Started",
                "Arrived On Site",
                "Setup Started",
                "Job Started",
                "Pack-up Started",
                "Job Completed",
                "Invoice Created",
                "Payment Received",
                "Job Completed"
            ]
        )

        let finalContext = engine.context(
            for: job,
            invoice: makeInvoice(status: .paid)
        )
        XCTAssertEqual(finalContext.currentState, .paymentReceived)
        XCTAssertEqual(finalContext.nextAction, .completeJob)
        XCTAssertTrue(finalContext.canCompleteJob)
        XCTAssertTrue(finalContext.isTerminal == false)
    }

    func testInvoiceHandoffAndPaymentFlagsAreExposed() {
        let engine = FieldOperationsEngine()
        let workCompleteJob = makeJob(workflowState: .workComplete, status: .inProgress)
        let sentInvoice = makeInvoice(status: .sent)
        let paidInvoice = makeInvoice(status: .paid)

        let invoiceContext = engine.context(
            for: workCompleteJob,
            invoice: sentInvoice
        )
        XCTAssertEqual(invoiceContext.currentState, .invoiceCreated)
        XCTAssertTrue(invoiceContext.canCollectPayment)
        XCTAssertFalse(invoiceContext.canCompleteJob)

        let paidContext = engine.context(
            for: workCompleteJob,
            invoice: paidInvoice
        )
        XCTAssertEqual(paidContext.currentState, .paymentReceived)
        XCTAssertEqual(paidContext.nextAction, .completeJob)
        XCTAssertTrue(paidContext.canCompleteJob)
    }

    func testRecordNoteAppendsTimelineEvent() {
        let engine = FieldOperationsEngine()
        let job = engine.recordNote(
            for: makeJob(),
            note: "Customer asked to add screens.",
            employeeID: technicianID,
            at: date(hour: 9, minute: 5)
        )

        XCTAssertEqual(job.timelineEvents.count, 1)
        XCTAssertEqual(job.timelineEvents.first?.type, .note)
        XCTAssertEqual(job.timelineEvents.first?.note, "Customer asked to add screens.")
    }

    func testPauseAndResumePreserveWorkProgressAndAuditDetails() throws {
        let engine = FieldOperationsEngine()
        var job = makeJob(workflowState: .working, status: .inProgress)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .pauseWork,
                employeeID: technicianID,
                note: "Waiting for the customer to move a vehicle.",
                at: date(hour: 9, minute: 15)
            )
        )

        XCTAssertEqual(job.workflowState, .paused)
        XCTAssertEqual(job.status, .inProgress)
        XCTAssertEqual(job.timelineEvents.last?.type, .workPaused)
        XCTAssertEqual(job.timelineEvents.last?.employeeID, technicianID)
        XCTAssertEqual(
            job.timelineEvents.last?.note,
            "Waiting for the customer to move a vehicle."
        )

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .resumeWork,
                employeeID: technicianID,
                at: date(hour: 9, minute: 30)
            )
        )

        XCTAssertEqual(job.workflowState, .working)
        XCTAssertEqual(job.timelineEvents.last?.type, .workResumed)
        XCTAssertEqual(job.timelineEvents.count, 2)
    }

    func testWorkingContextKeepsPackUpPrimaryAndExposesPause() {
        let context = FieldOperationsEngine().context(
            for: makeJob(workflowState: .working, status: .inProgress)
        )

        XCTAssertEqual(context.nextAction, .startPackUp)
        XCTAssertEqual(context.availableActions, [.pauseWork, .startPackUp])
    }

    func testIllegalTransitionIsRejectedWithoutAuditEvent() {
        let engine = FieldOperationsEngine()
        let job = makeJob()

        let validation = engine.validate(job: job, action: .startWork)
        let updated = engine.transition(
            job: job,
            action: .startWork,
            employeeID: technicianID,
            at: date(hour: 8)
        )

        XCTAssertEqual(validation.level, .invalid)
        XCTAssertFalse(validation.canProceed)
        XCTAssertNil(updated)
        XCTAssertTrue(job.timelineEvents.isEmpty)
    }

    func testMissingTechnicianProducesWarningButAllowsTravel() {
        var job = makeJob()
        job.primaryTechnicianID = nil

        let validation = FieldOperationsEngine().validate(
            job: job,
            action: .startTravel
        )

        XCTAssertEqual(validation.level, .warning)
        XCTAssertTrue(validation.canProceed)
        XCTAssertEqual(validation.issues.count, 1)
    }

    func testPaymentWithoutInvoiceIsInvalid() {
        let validation = FieldOperationsEngine().validate(
            job: makeJob(workflowState: .invoiceCreated, status: .inProgress),
            action: .recordPayment
        )

        XCTAssertEqual(validation.level, .invalid)
        XCTAssertFalse(validation.canProceed)
    }

    func testBlankNoteDoesNotCreateAuditNoise() {
        let job = FieldOperationsEngine().recordNote(
            for: makeJob(),
            note: "   \n ",
            employeeID: technicianID,
            at: date(hour: 9)
        )

        XCTAssertTrue(job.timelineEvents.isEmpty)
    }

    func testCancelledWorkReturnsDetailsActionAndTerminalState() {
        var job = makeJob()
        job.status = .cancelled
        job.workflowState = .cancelled

        let context = FieldOperationsEngine().context(for: job)

        XCTAssertEqual(context.currentState, .cancelled)
        XCTAssertEqual(context.nextAction, .viewDetails)
        XCTAssertTrue(context.isTerminal)
        XCTAssertEqual(context.progressPercentage, 0)
    }

    // MARK: - Fixtures

    private func makeJob(
        workflowState: JobWorkflowState = .notStarted,
        status: JobStatus = .scheduled
    ) -> JobRecord {
        JobRecord(
            jobNumber: "JOB-1001",
            customerNumber: "PPS-000123",
            siteID: siteID,
            estimateNumber: "EST-2001",
            serviceType: .windowCleaning,
            otherService: "",
            subtotal: 120,
            discount: 0,
            total: 120,
            primaryTechnicianID: technicianID,
            secondaryTechnicianID: nil,
            scheduledDate: date(hour: 8),
            status: status,
            workflowState: workflowState,
            workNotes: "",
            isRecurring: false,
            createdDate: date(hour: 7)
        )
    }

    private func makeInvoice(status: InvoiceStatus) -> InvoiceRecord {
        InvoiceRecord(
            invoiceNumber: "INV-2001",
            customerNumber: "PPS-000123",
            siteID: siteID,
            jobNumber: "JOB-1001",
            subtotal: 120,
            discount: 0,
            total: 120,
            amountPaid: status == .paid ? 120 : 0,
            balanceDue: status == .paid ? 0 : 120,
            status: status,
            issueDate: date(hour: 11),
            dueDate: date(hour: 12),
            paidDate: status == .paid ? date(hour: 11, minute: 15) : nil,
            notes: ""
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 24,
                hour: hour,
                minute: minute,
                second: 0
            )
        )!
    }
}
