//
//  FieldOperationsEngine.swift
//  PPS Receipt Printer
//
//  Phase 15 – Step 1: Field Operations Engine Foundation
//

import Foundation

/// The technician-facing lifecycle action set used by the consolidated
/// field operations engine.
///
/// This keeps the app's primary field workflow in one place so My Day,
/// Assignment Detail, Dispatch, and Timeline can all ask the same engine
/// what comes next.
enum JobWorkflowAction: String, Identifiable, CaseIterable {
    case startTravel
    case markArrived
    case startSetup
    case startWork
    case pauseWork
    case resumeWork
    case startPackUp
    case finishWork
    case createInvoice
    case recordPayment
    case completeJob
    case viewDetails

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startTravel:
            return "Start Travel"
        case .markArrived:
            return "Arrived"
        case .startSetup:
            return "Start Setup"
        case .startWork:
            return "Start Job"
        case .pauseWork:
            return "Pause Work"
        case .resumeWork:
            return "Resume Work"
        case .startPackUp:
            return "Start Pack-up"
        case .finishWork:
            return "Complete Job"
        case .createInvoice:
            return "Create Invoice"
        case .recordPayment:
            return "Record Payment"
        case .completeJob:
            return "Close Job"
        case .viewDetails:
            return "Details"
        }
    }

    var systemImage: String {
        switch self {
        case .startTravel:
            return "car.fill"
        case .markArrived:
            return "mappin.circle.fill"
        case .startSetup:
            return "wrench.and.screwdriver.fill"
        case .startWork:
            return "play.fill"
        case .pauseWork:
            return "pause.fill"
        case .resumeWork:
            return "play.fill"
        case .startPackUp:
            return "shippingbox.fill"
        case .finishWork:
            return "checkmark.circle.fill"
        case .createInvoice:
            return "doc.text.fill"
        case .recordPayment:
            return "creditcard.fill"
        case .completeJob:
            return "flag.checkered"
        case .viewDetails:
            return "doc.text.magnifyingglass"
        }
    }
}

/// Shared workflow snapshot for the live field operation currently in progress.
///
/// The snapshot is intentionally small and reusable so that multiple screens
/// can present the same state without duplicating workflow rules.
struct JobWorkflowContext {
    let currentState: JobWorkflowState
    let timeline: [JobTimelineEvent]
    let nextAction: JobWorkflowAction
    let availableActions: [JobWorkflowAction]
    let progressPercentage: Int
    let canCreateInvoice: Bool
    let canCollectPayment: Bool
    let canCompleteJob: Bool
    let isTerminal: Bool
}

enum WorkflowValidationLevel: String, Codable {
    case ready
    case warning
    case invalid
}

struct WorkflowValidationIssue: Identifiable, Codable, Equatable {
    let id: UUID
    let message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
}

struct WorkflowValidationResult: Codable, Equatable {
    let level: WorkflowValidationLevel
    let issues: [WorkflowValidationIssue]

    var canProceed: Bool { level != .invalid }
}

/// Foundation engine for the consolidated field workflow.
///
/// The engine is intentionally stateless. It accepts a job, calculates the
/// current operational snapshot, and returns updated job copies when lifecycle
/// actions are applied.
struct FieldOperationsEngine {
    func context(
        for job: JobRecord,
        invoice: InvoiceRecord? = nil
    ) -> JobWorkflowContext {
        let currentState = synchronizedState(
            for: job,
            invoice: invoice
        )

        let orderedTimeline = job.timelineEvents.sorted {
            $0.timestamp < $1.timestamp
        }

        return JobWorkflowContext(
            currentState: currentState,
            timeline: orderedTimeline,
            nextAction: nextAction(
                for: currentState,
                invoice: invoice
            ),
            availableActions: availableActions(
                for: currentState,
                invoice: invoice
            ),
            progressPercentage: progress(for: currentState),
            canCreateInvoice: currentState == .workComplete,
            canCollectPayment:
                currentState == .invoiceCreated &&
                invoice?.status != .paid,
            canCompleteJob:
                currentState == .paymentReceived ||
                (
                    currentState == .invoiceCreated &&
                    invoice?.status == .paid
                ),
            isTerminal:
                currentState == .completed ||
                currentState == .cancelled
        )
    }

    func nextAction(
        for job: JobRecord,
        invoice: InvoiceRecord? = nil
    ) -> JobWorkflowAction {
        context(for: job, invoice: invoice).nextAction
    }

    func workflowState(
        for job: JobRecord,
        invoice: InvoiceRecord? = nil
    ) -> JobWorkflowState {
        context(for: job, invoice: invoice).currentState
    }

    func availableActions(
        for job: JobRecord,
        invoice: InvoiceRecord? = nil
    ) -> [JobWorkflowAction] {
        let state = synchronizedState(for: job, invoice: invoice)
        return availableActions(for: state, invoice: invoice)
    }

    func validate(
        job: JobRecord,
        action: JobWorkflowAction,
        invoice: InvoiceRecord? = nil
    ) -> WorkflowValidationResult {
        let state = synchronizedState(for: job, invoice: invoice)
        var issues: [WorkflowValidationIssue] = []

        guard action != .viewDetails else {
            return WorkflowValidationResult(level: .ready, issues: [])
        }

        guard availableActions(for: state, invoice: invoice).contains(action) else {
            issues.append(
                WorkflowValidationIssue(
                    message: "\(action.title) is not available while the job is \(state.rawValue)."
                )
            )
            return WorkflowValidationResult(level: .invalid, issues: issues)
        }

        if action == .startTravel && job.primaryTechnicianID == nil {
            issues.append(
                WorkflowValidationIssue(
                    message: "No primary technician is assigned to this job."
                )
            )
        }

        if action == .recordPayment && invoice == nil {
            issues.append(
                WorkflowValidationIssue(
                    message: "An invoice must exist before payment can be recorded."
                )
            )
            return WorkflowValidationResult(level: .invalid, issues: issues)
        }

        return WorkflowValidationResult(
            level: issues.isEmpty ? .ready : .warning,
            issues: issues
        )
    }

    @discardableResult
    func transition(
        job: JobRecord,
        action: JobWorkflowAction,
        employeeID: UUID? = nil,
        note: String? = nil,
        invoice: InvoiceRecord? = nil,
        at timestamp: Date = Date()
    ) -> JobRecord? {
        let validation = validate(job: job, action: action, invoice: invoice)
        guard validation.canProceed,
              isValid(action: action, for: job.workflowState) else {
            return nil
        }

        var updated = job
        let transition = transitionDetails(for: action)

        updated.workflowState = transition.state

        if action == .startSetup,
           updated.setupStartDate == nil {
            updated.setupStartDate = timestamp
        }

        if action == .finishWork,
           updated.completedDate == nil {
            updated.completedDate = timestamp
        }

        updated.timelineEvents.append(
            JobTimelineEvent(
                type: transition.eventType,
                title: transition.title,
                timestamp: timestamp,
                employeeID: employeeID,
                note: normalizedNote(note)
            )
        )

        switch transition.state {
        case .traveling,
             .arrived,
             .settingUp,
             .working,
             .paused,
             .packingUp,
             .workComplete,
             .invoiceCreated,
             .paymentReceived:
            updated.status = .inProgress

        case .completed:
            updated.status = .completed
            if updated.completedDate == nil {
                updated.completedDate = timestamp
            }

        case .cancelled:
            updated.status = .cancelled

        case .notStarted:
            break
        }

        return updated
    }

    @discardableResult
    func recordNote(
        for job: JobRecord,
        note: String,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> JobRecord {
        var updated = job
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return updated }
        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .note,
                title: "Note Added",
                timestamp: timestamp,
                employeeID: employeeID,
                note: trimmed
            )
        )
        return updated
    }

    @discardableResult
    func recordInvoiceCreated(
        for job: JobRecord,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> JobRecord {
        var updated = job

        guard updated.workflowState != .invoiceCreated,
              updated.workflowState != .paymentReceived,
              updated.workflowState != .completed
        else {
            return updated
        }

        updated.workflowState = .invoiceCreated
        updated.status = .inProgress
        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .invoiceCreated,
                title: "Invoice Created",
                timestamp: timestamp,
                employeeID: employeeID
            )
        )

        return updated
    }

    @discardableResult
    func recordPaymentReceived(
        for job: JobRecord,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> JobRecord {
        var updated = job

        guard updated.workflowState != .paymentReceived,
              updated.workflowState != .completed
        else {
            return updated
        }

        updated.workflowState = .paymentReceived
        updated.status = .inProgress
        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .paymentReceived,
                title: "Payment Received",
                timestamp: timestamp,
                employeeID: employeeID
            )
        )

        return updated
    }

    // MARK: - State resolution

    private func synchronizedState(
        for job: JobRecord,
        invoice: InvoiceRecord?
    ) -> JobWorkflowState {
        if job.status == .cancelled ||
           job.workflowState == .cancelled {
            return .cancelled
        }

        if invoice?.status == .paid {
            return .paymentReceived
        }

        if invoice != nil {
            return .invoiceCreated
        }

        if job.workflowState != .notStarted {
            return job.workflowState
        }

        // Historical compatibility for jobs created before the workflow state
        // was tracked explicitly.
        if job.status == .completed {
            return .completed
        }

        return .notStarted
    }

    private func nextAction(
        for state: JobWorkflowState,
        invoice: InvoiceRecord?
    ) -> JobWorkflowAction {
        switch state {
        case .notStarted:
            return .startTravel
        case .traveling:
            return .markArrived
        case .arrived:
            return .startSetup
        case .settingUp:
            return .startWork
        case .working:
            return .startPackUp
        case .paused:
            return .resumeWork
        case .packingUp:
            return .finishWork
        case .workComplete:
            return .createInvoice
        case .invoiceCreated:
            return invoice?.status == .paid
                ? .completeJob
                : .recordPayment
        case .paymentReceived:
            return .completeJob
        case .completed, .cancelled:
            return .viewDetails
        }
    }

    private func progress(
        for state: JobWorkflowState
    ) -> Int {
        switch state {
        case .notStarted:
            return 0
        case .traveling:
            return 10
        case .arrived:
            return 20
        case .settingUp:
            return 30
        case .working:
            return 50
        case .paused:
            return 50
        case .packingUp:
            return 70
        case .workComplete:
            return 80
        case .invoiceCreated:
            return 90
        case .paymentReceived:
            return 95
        case .completed:
            return 100
        case .cancelled:
            return 0
        }
    }

    private func isValid(
        action: JobWorkflowAction,
        for state: JobWorkflowState
    ) -> Bool {
        switch (state, action) {
        case (.notStarted, .startTravel),
             (.traveling, .markArrived),
             (.arrived, .startSetup),
             (.settingUp, .startWork),
             (.working, .pauseWork),
             (.paused, .resumeWork),
             (.working, .startPackUp),
             (.packingUp, .finishWork),
             (.workComplete, .createInvoice),
             (.invoiceCreated, .recordPayment),
             (.invoiceCreated, .completeJob),
             (.paymentReceived, .completeJob):
            return true

        default:
            return false
        }
    }

    private func transitionDetails(
        for action: JobWorkflowAction
    ) -> (
        state: JobWorkflowState,
        eventType: JobTimelineEventType,
        title: String
    ) {
        switch action {
        case .startTravel:
            return (.traveling, .travelStarted, "Travel Started")
        case .markArrived:
            return (.arrived, .arrived, "Arrived On Site")
        case .startSetup:
            return (.settingUp, .setupStarted, "Setup Started")
        case .startWork:
            return (.working, .workStarted, "Job Started")
        case .pauseWork:
            return (.paused, .workPaused, "Work Paused")
        case .resumeWork:
            return (.working, .workResumed, "Work Resumed")
        case .startPackUp:
            return (.packingUp, .packUpStarted, "Pack-up Started")
        case .finishWork:
            return (.workComplete, .workCompleted, "Job Completed")
        case .createInvoice:
            return (.invoiceCreated, .invoiceCreated, "Invoice Created")
        case .recordPayment:
            return (.paymentReceived, .paymentReceived, "Payment Received")
        case .completeJob:
            return (.completed, .jobCompleted, "Job Completed")
        case .viewDetails:
            return (.notStarted, .note, "Viewed Details")
        }
    }

    private func availableActions(
        for state: JobWorkflowState,
        invoice: InvoiceRecord?
    ) -> [JobWorkflowAction] {
        switch state {
        case .notStarted: return [.startTravel]
        case .traveling: return [.markArrived]
        case .arrived: return [.startSetup]
        case .settingUp: return [.startWork]
        case .working: return [.pauseWork, .startPackUp]
        case .paused: return [.resumeWork]
        case .packingUp: return [.finishWork]
        case .workComplete: return [.createInvoice]
        case .invoiceCreated:
            return invoice?.status == .paid ? [.completeJob] : [.recordPayment]
        case .paymentReceived: return [.completeJob]
        case .completed, .cancelled: return [.viewDetails]
        }
    }

    private func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
