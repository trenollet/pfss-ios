//
//  FieldOperationsEngine.swift
//  PPS Receipt Printer
//
//  Brick 7: Field Operations Engine
//

import Foundation

enum JobWorkflowAction: String, Identifiable {
    case startTravel
    case markArrived
    case startSetup
    case startWork
    case startPackUp
    case finishWork
    case createInvoice
    case recordPayment
    case completeJob
    case viewDetails

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startTravel: return "Start Travel"
        case .markArrived: return "Arrived"
        case .startSetup: return "Start Setup"
        case .startWork: return "Start Work"
        case .startPackUp: return "Start Pack-up"
        case .finishWork: return "Finish Work"
        case .createInvoice: return "Create Invoice"
        case .recordPayment: return "Record Payment"
        case .completeJob: return "Close Job"
        case .viewDetails: return "Details"
        }
    }

    var systemImage: String {
        switch self {
        case .startTravel: return "car.fill"
        case .markArrived: return "mappin.circle.fill"
        case .startSetup: return "wrench.and.screwdriver.fill"
        case .startWork: return "play.fill"
        case .startPackUp: return "shippingbox.fill"
        case .finishWork: return "checkmark.circle.fill"
        case .createInvoice: return "doc.text.fill"
        case .recordPayment: return "creditcard.fill"
        case .completeJob: return "flag.checkered"
        case .viewDetails: return "doc.text.magnifyingglass"
        }
    }
}

struct JobWorkflowContext {
    let currentState: JobWorkflowState
    let timeline: [JobTimelineEvent]
    let nextAction: JobWorkflowAction
    let progressPercentage: Int
    let canCreateInvoice: Bool
    let canCollectPayment: Bool
    let canCompleteJob: Bool
    let isTerminal: Bool
}

struct FieldOperationsEngine {
    func context(
        for job: JobRecord,
        invoice: InvoiceRecord? = nil
    ) -> JobWorkflowContext {
        let state = synchronizedState(
            for: job,
            invoice: invoice
        )

        return JobWorkflowContext(
            currentState: state,
            timeline: job.timelineEvents.sorted {
                $0.timestamp < $1.timestamp
            },
            nextAction: nextAction(
                for: state,
                invoice: invoice
            ),
            progressPercentage: progress(
                for: state
            ),
            canCreateInvoice: state == .workComplete,
            canCollectPayment:
                state == .invoiceCreated &&
                invoice?.status != .paid,
            canCompleteJob:
                state == .paymentReceived ||
                (
                    state == .invoiceCreated &&
                    invoice?.status == .paid
                ),
            isTerminal:
                state == .completed ||
                state == .cancelled
        )
    }

    func transition(
        job: JobRecord,
        action: JobWorkflowAction,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> JobRecord? {
        guard isValid(
            action: action,
            for: job.workflowState
        ) else {
            return nil
        }

        var updated = job
        let transition = transitionDetails(
            for: action
        )

        updated.workflowState = transition.state
        updated.timelineEvents.append(
            JobTimelineEvent(
                type: transition.eventType,
                title: transition.title,
                timestamp: timestamp,
                employeeID: employeeID
            )
        )

        switch transition.state {
        case .traveling, .arrived, .settingUp,
             .working, .packingUp, .workComplete,
             .invoiceCreated, .paymentReceived:
            updated.status = .inProgress

        case .completed:
            updated.status = .completed
            updated.completedDate = timestamp

        case .cancelled:
            updated.status = .cancelled

        case .notStarted:
            break
        }

        return updated
    }

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

    private func synchronizedState(
        for job: JobRecord,
        invoice: InvoiceRecord?
    ) -> JobWorkflowState {
        if job.status == .completed {
            return .completed
        }

        if job.status == .cancelled {
            return .cancelled
        }

        if invoice?.status == .paid {
            return .paymentReceived
        }

        if invoice != nil &&
           job.workflowState == .workComplete {
            return .invoiceCreated
        }

        return job.workflowState
    }

    private func nextAction(
        for state: JobWorkflowState,
        invoice: InvoiceRecord?
    ) -> JobWorkflowAction {
        switch state {
        case .notStarted: return .startTravel
        case .traveling: return .markArrived
        case .arrived: return .startSetup
        case .settingUp: return .startWork
        case .working: return .startPackUp
        case .packingUp: return .finishWork
        case .workComplete: return .createInvoice
        case .invoiceCreated:
            return invoice?.status == .paid
                ? .completeJob
                : .recordPayment
        case .paymentReceived: return .completeJob
        case .completed, .cancelled: return .viewDetails
        }
    }

    private func progress(
        for state: JobWorkflowState
    ) -> Int {
        switch state {
        case .notStarted: return 0
        case .traveling: return 10
        case .arrived: return 20
        case .settingUp: return 30
        case .working: return 50
        case .packingUp: return 70
        case .workComplete: return 80
        case .invoiceCreated: return 90
        case .paymentReceived: return 95
        case .completed: return 100
        case .cancelled: return 0
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
            return (.working, .workStarted, "Work Started")
        case .startPackUp:
            return (.packingUp, .packUpStarted, "Pack-up Started")
        case .finishWork:
            return (.workComplete, .workCompleted, "Work Completed")
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
}
