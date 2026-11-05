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
            (.pauseTravel, "Pause Travel", .orange),
            (.resumeTravel, "Resume Travel", .orange),
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

    func testSentInvoiceUsesClosedPresentationWithoutChangingFinancialState() {
        let context = FieldOperationsEngine().context(
            for: makeJob(workflowState: .invoiceCreated, status: .inProgress),
            invoice: makeInvoice(status: .sent)
        )

        XCTAssertEqual(context.currentState, .invoiceCreated)
        XCTAssertEqual(context.presentation.statusTitle, "Closed")
        XCTAssertEqual(context.presentation.statusSystemImage, "checkmark.seal.fill")
        XCTAssertEqual(context.presentation.accent, .green)
        XCTAssertEqual(context.presentation.completionTitle, "Invoice Sent")
        XCTAssertTrue(context.presentation.isTechnicianComplete)
        XCTAssertTrue(context.presentation.isClosed)
    }

    func testPaidInvoiceUsesSharedClosedPresentation() {
        let context = FieldOperationsEngine().context(
            for: makeJob(workflowState: .invoiceCreated, status: .inProgress),
            invoice: makeInvoice(status: .paid)
        )

        XCTAssertEqual(context.currentState, .paymentReceived)
        XCTAssertEqual(context.presentation.statusTitle, "Closed")
        XCTAssertEqual(context.presentation.accent, .green)
        XCTAssertEqual(context.presentation.completionTitle, "Paid")
        XCTAssertTrue(context.presentation.isTechnicianComplete)
        XCTAssertTrue(context.presentation.isClosed)
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
        XCTAssertEqual(job.workflowState, .settingUp)
        XCTAssertEqual(job.setupStartDate, date(hour: 8, minute: 15))
        XCTAssertEqual(job.timelineEvents.suffix(2).map(\.type), [.arrived, .setupStarted])
        XCTAssertEqual(engine.context(for: job).nextAction, .startWork)

        job = try XCTUnwrap(
            engine.transition(
                job: job,
                action: .startWork,
                employeeID: technicianID,
                at: date(hour: 8, minute: 35)
            )
        )
        XCTAssertEqual(job.workflowState, .working)
        XCTAssertEqual(job.workStartDate, date(hour: 8, minute: 35))

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

    func testTravelMayPauseAndResumeWithoutInflatingActiveTravelTime() throws {
        let engine = FieldOperationsEngine()
        var job = makeJob()

        job = try XCTUnwrap(engine.transition(
            job: job,
            action: .startTravel,
            employeeID: technicianID,
            at: date(hour: 8)
        ))

        job = try XCTUnwrap(engine.transition(
            job: job,
            action: .pauseTravel,
            employeeID: technicianID,
            note: "Stopped for an impromptu estimate.",
            at: date(hour: 8, minute: 15)
        ))
        XCTAssertEqual(job.workflowState, .travelPaused)
        XCTAssertEqual(job.timelineEvents.last?.type, .travelPaused)

        job = try XCTUnwrap(engine.transition(
            job: job,
            action: .resumeTravel,
            employeeID: technicianID,
            at: date(hour: 8, minute: 45)
        ))
        XCTAssertEqual(job.workflowState, .traveling)
        XCTAssertEqual(job.timelineEvents.last?.type, .travelResumed)

        job = try XCTUnwrap(engine.transition(
            job: job,
            action: .markArrived,
            employeeID: technicianID,
            at: date(hour: 9)
        ))

        XCTAssertEqual(
            engine.activeTravelDuration(for: job, through: date(hour: 10)),
            30 * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(
            job.timelineEvents.map(\.type),
            [.travelStarted, .travelPaused, .travelResumed, .arrived, .setupStarted]
        )
    }

    func testLegacyArrivedJobCanStartWorkWithoutAnotherSetupAction() throws {
        let engine = FieldOperationsEngine()
        var job = makeJob()
        job.workflowState = .arrived
        XCTAssertEqual(engine.context(for: job).nextAction, .startWork)
        XCTAssertEqual(engine.availableActions(for: job), [.startWork])
        let updated = try XCTUnwrap(engine.transition(job: job, action: .startWork,
            employeeID: technicianID, at: date(hour: 9)))
        XCTAssertEqual(updated.workflowState, .working)
        XCTAssertEqual(updated.workStartDate, date(hour: 9))
    }

    func testTravelingContextKeepsArrivePrimaryAndExposesPause() {
        let context = FieldOperationsEngine().context(
            for: makeJob(workflowState: .traveling, status: .inProgress)
        )

        XCTAssertEqual(context.nextAction, .markArrived)
        XCTAssertEqual(context.availableActions, [.pauseTravel, .markArrived])
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

    func testLifecycleTimeDetailsPreferDedicatedTimestamps() {
        var job = makeJob(workflowState: .completed, status: .completed)
        job.setupStartDate = date(hour: 8, minute: 10)
        job.workStartDate = date(hour: 8, minute: 25)
        job.completedDate = date(hour: 10, minute: 40)

        let details = FieldOperationsEngine().context(for: job).timeDetails

        XCTAssertEqual(details.setupStarted, date(hour: 8, minute: 10))
        XCTAssertEqual(details.workStarted, date(hour: 8, minute: 25))
        XCTAssertEqual(details.completed, date(hour: 10, minute: 40))
        XCTAssertEqual(details.timeOnJob ?? -1, 150 * 60, accuracy: 0.001)
    }

    func testLifecycleTimeDetailsRecoverLegacyTimelineValues() {
        var job = makeJob(workflowState: .completed, status: .completed)
        job.timelineEvents = [
            JobTimelineEvent(type: .setupStarted, title: "Setup Started", timestamp: date(hour: 8)),
            JobTimelineEvent(type: .workStarted, title: "Job Started", timestamp: date(hour: 8, minute: 20)),
            JobTimelineEvent(type: .workCompleted, title: "Job Completed", timestamp: date(hour: 9, minute: 30))
        ]

        let details = FieldOperationsEngine().context(for: job).timeDetails

        XCTAssertEqual(details.setupStarted, date(hour: 8))
        XCTAssertEqual(details.workStarted, date(hour: 8, minute: 20))
        XCTAssertEqual(details.completed, date(hour: 9, minute: 30))
        XCTAssertEqual(details.timeOnJob ?? -1, 90 * 60, accuracy: 0.001)
    }

    func testCompletedJobOverridesStaleWorkflowStateForClosedPresentation() {
        let job = makeJob(workflowState: .workComplete, status: .completed)
        let context = FieldOperationsEngine().context(for: job)

        XCTAssertEqual(context.currentState, .completed)
        XCTAssertEqual(context.presentation.statusTitle, "Closed")
        XCTAssertTrue(context.presentation.isClosed)
        XCTAssertTrue(context.isTerminal)
        XCTAssertEqual(context.progressPercentage, 100)
    }

    func testMultiDayJobAppearsOnEveryScheduledDayWithoutDuplicatingJobIdentity() {
        var job = makeJob()
        let secondDay = calendar.date(byAdding: .day, value: 1, to: job.scheduledDate)!
        let thirdDay = calendar.date(byAdding: .day, value: 2, to: job.scheduledDate)!
        job.additionalScheduledDates = [secondDay, thirdDay, secondDay]
        job.normalizeAdditionalScheduledDates(calendar: calendar)

        for expected in [job.scheduledDate, secondDay, thirdDay] {
            let matches = SchedulingCalculator.scheduledJobs(
                for: EmployeeRecord(id: technicianID, firstName: "Test", lastName: "Tech", role: .technician),
                on: expected,
                from: [job],
                calendar: calendar
            )
            XCTAssertEqual(matches.count, 1)
            XCTAssertEqual(matches.first?.id, job.id)
            XCTAssertEqual(matches.first?.scheduledDate, expected)
        }
    }

    func testLegacyJobDecodesWithNoAdditionalWorkdays() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(makeJob())) as? [String: Any])
        object.removeValue(forKey: "additionalScheduledDates")
        object.removeValue(forKey: "additionalWorkdaySchedules")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertTrue(try decoder.decode(JobRecord.self, from: data).additionalScheduledDates.isEmpty)
    }

    func testPausedJobCanScheduleContinuationWithoutCreatingAnotherJob() throws {
        let store = AppDataStore(persistenceEnabled: false)
        let employee = EmployeeRecord(id: technicianID, firstName: "Test", lastName: "Tech")
        store.employees = [employee]
        let job = makeJob()
        store.addJob(job)
        for (offset, action) in [JobWorkflowAction.startTravel, .markArrived, .startWork, .pauseWork].enumerated() {
            XCTAssertTrue(store.performWorkflowAction(
                jobID: job.id,
                action: action,
                employeeID: technicianID,
                at: date(hour: 8).addingTimeInterval(Double(offset))
            ))
        }
        let continuation = calendar.date(byAdding: .day, value: 2, to: job.scheduledDate)!
        XCTAssertTrue(store.addJobContinuationDate(jobID: job.id, scheduledDate: continuation))
        XCTAssertFalse(store.addJobContinuationDate(jobID: job.id, scheduledDate: continuation))
        XCTAssertEqual(store.jobs.count, 1)
        let saved = try XCTUnwrap(store.jobs.first)
        XCTAssertEqual(saved.workflowState, .paused)
        XCTAssertEqual(saved.additionalScheduledDates.count, 1)
        XCTAssertEqual(SchedulingCalculator.scheduledJobs(
            for: employee,
            on: continuation,
            from: store.jobs,
            calendar: calendar
        ).first?.id, job.id)
    }

    func testPausedJobAdditionalWorkdayCanMoveWithoutChangingPrimaryDate() throws {
        let store = AppDataStore(persistenceEnabled: false)
        let job = makeJob()
        let primaryDate = job.scheduledDate
        let incorrectDate = calendar.date(byAdding: .day, value: 2, to: primaryDate)!
        let correctedDate = calendar.date(byAdding: .day, value: 3, to: primaryDate)!
        store.addJob(job)
        for (offset, action) in [JobWorkflowAction.startTravel, .markArrived, .startWork, .pauseWork].enumerated() {
            XCTAssertTrue(store.performWorkflowAction(
                jobID: job.id,
                action: action,
                employeeID: technicianID,
                at: date(hour: 8).addingTimeInterval(Double(offset))
            ))
        }
        XCTAssertTrue(store.addJobContinuationDate(jobID: job.id, scheduledDate: incorrectDate))
        let beforeMove = try XCTUnwrap(store.jobs.first)

        var occurrence = beforeMove
        occurrence.scheduledDate = correctedDate
        XCTAssertTrue(store.updateJobWorkdaySchedule(
            jobID: job.id,
            originalDate: incorrectDate,
            updatedJob: occurrence
        ))

        let saved = try XCTUnwrap(store.jobs.first)
        XCTAssertEqual(saved.scheduledDate, primaryDate)
        XCTAssertEqual(saved.additionalScheduledDates, [correctedDate])
        XCTAssertEqual(saved.workflowState, beforeMove.workflowState)
        XCTAssertEqual(saved.status, beforeMove.status)
    }

    func testMovingWorkdayOntoExistingWorkdayIsRejected() throws {
        let store = AppDataStore(persistenceEnabled: false)
        var job = makeJob(workflowState: .paused, status: .inProgress)
        let additionalDate = calendar.date(byAdding: .day, value: 2, to: job.scheduledDate)!
        job.additionalScheduledDates = [additionalDate]
        store.addJob(job)

        var occurrence = job
        occurrence.scheduledDate = job.scheduledDate
        XCTAssertFalse(store.updateJobWorkdaySchedule(
            jobID: job.id,
            originalDate: additionalDate,
            updatedJob: occurrence
        ))
        XCTAssertEqual(try XCTUnwrap(store.jobs.first).additionalScheduledDates, [additionalDate])
    }

    func testAddedWorkdayKeepsItsOwnArrivalWindowAndProjectsItOnMyDay() throws {
        let store = AppDataStore(persistenceEnabled: false)
        let employee = EmployeeRecord(id: technicianID, firstName: "Test", lastName: "Tech")
        store.employees = [employee]
        let job = makeJob()
        store.addJob(job)
        let start = calendar.date(byAdding: .day, value: 2, to: job.scheduledDate)!
        let end = calendar.date(byAdding: .hour, value: 3, to: start)!

        XCTAssertTrue(store.addJobContinuationWorkday(
            jobID: job.id,
            schedule: JobScheduledWorkday(
                scheduledDate: start,
                schedulingMode: .arrivalWindow,
                arrivalWindowEnd: end
            )
        ))

        let saved = try XCTUnwrap(store.jobs.first?.effectiveAdditionalWorkdaySchedules.first)
        XCTAssertEqual(saved.schedulingMode, .arrivalWindow)
        XCTAssertEqual(saved.arrivalWindowEnd, end)
        let occurrence = try XCTUnwrap(SchedulingCalculator.scheduledJobs(
            for: employee,
            on: start,
            from: store.jobs,
            calendar: calendar
        ).first)
        XCTAssertEqual(occurrence.assignmentSchedulingMode, .arrivalWindow)
        XCTAssertEqual(occurrence.arrivalWindowEnd, end)
    }

    func testAllAddedWorkdayTimeOptionsSurviveSynchronizationRoundTrip() throws {
        var job = makeJob()
        let fixed = calendar.date(byAdding: .day, value: 1, to: job.scheduledDate)!
        let window = calendar.date(byAdding: .day, value: 2, to: job.scheduledDate)!
        let flexible = calendar.date(byAdding: .day, value: 3, to: job.scheduledDate)!
        let deadlineDay = calendar.date(byAdding: .day, value: 4, to: job.scheduledDate)!
        let windowEnd = calendar.date(byAdding: .hour, value: 2, to: window)!
        let deadline = calendar.date(byAdding: .hour, value: 5, to: deadlineDay)!
        job.additionalWorkdaySchedules = [
            JobScheduledWorkday(scheduledDate: fixed, schedulingMode: .fixedTime),
            JobScheduledWorkday(
                scheduledDate: window,
                schedulingMode: .arrivalWindow,
                arrivalWindowEnd: windowEnd
            ),
            JobScheduledWorkday(scheduledDate: flexible, schedulingMode: .flexibleDay),
            JobScheduledWorkday(
                scheduledDate: deadlineDay,
                schedulingMode: .deadline,
                completionDeadline: deadline
            )
        ]
        job.normalizeAdditionalScheduledDates(calendar: calendar)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JobRecord.self, from: encoder.encode(job))

        XCTAssertEqual(
            Set(decoded.additionalWorkdaySchedules.map(\.schedulingMode)),
            Set(AssignmentSchedulingMode.allCases)
        )
        XCTAssertEqual(
            decoded.additionalWorkdaySchedules.first(where: { $0.schedulingMode == .arrivalWindow })?.arrivalWindowEnd,
            windowEnd
        )
        XCTAssertEqual(
            decoded.additionalWorkdaySchedules.first(where: { $0.schedulingMode == .deadline })?.completionDeadline,
            deadline
        )
    }

    func testMyDayMovesInProgressJobAheadOfEarlierScheduledJobs() {
        var earlier = makeJob()
        earlier.id = UUID(uuidString: "10000000-0000-0000-0000-000000000010")!
        earlier.scheduledDate = date(hour: 8)

        var active = makeJob(workflowState: .working, status: .inProgress)
        active.id = UUID(uuidString: "10000000-0000-0000-0000-000000000020")!
        active.scheduledDate = date(hour: 11)

        let ordered = TechnicianAgendaOrdering.orderedJobs(
            [earlier, active],
            plannedStart: \.scheduledDate,
            routeSequence: { _ in nil },
            isFinished: { $0.status == .completed },
            completionDate: { $0.completedDate ?? .distantPast }
        )

        XCTAssertEqual(ordered.map(\.id), [active.id, earlier.id])
    }

    func testMyDayMovesCompletedJobBehindRemainingScheduledJobs() {
        var completed = makeJob(workflowState: .completed, status: .completed)
        completed.id = UUID(uuidString: "10000000-0000-0000-0000-000000000030")!
        completed.scheduledDate = date(hour: 8)
        completed.completedDate = date(hour: 9)

        var remaining = makeJob()
        remaining.id = UUID(uuidString: "10000000-0000-0000-0000-000000000040")!
        remaining.scheduledDate = date(hour: 11)

        let ordered = TechnicianAgendaOrdering.orderedJobs(
            [completed, remaining],
            plannedStart: \.scheduledDate,
            routeSequence: { _ in nil },
            isFinished: { $0.status == .completed },
            completionDate: { $0.completedDate ?? .distantPast }
        )

        XCTAssertEqual(ordered.map(\.id), [remaining.id, completed.id])
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
