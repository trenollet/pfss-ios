import Combine
import Foundation

/// Step 10 – Field Operations Engine and Workflow Consolidation
///
/// This façade keeps the technician-facing workflow calls in one place while
/// still using the existing `AppDataStore`, `FieldOperationsEngine`, and
/// workflow helpers already present in the app.
///
/// The coordinator is intentionally thin:
/// - it exposes the current workflow context for UI surfaces,
/// - it routes the primary action for a job,
/// - it offers direct helpers for the current step-based workflow,
/// - and it gives us one place to extend the field workflow later without
///   reintroducing duplicate logic in each screen.
@MainActor
final class FieldOperationsWorkflowCoordinator: ObservableObject {
    @Published private(set) var lastActionJobID: UUID?
    @Published private(set) var lastAction: JobWorkflowAction?
    @Published private(set) var lastEmployeeID: UUID?
    @Published private(set) var lastErrorMessage: String?

    private let store: AppDataStore
    private let fallbackEngine = FieldOperationsEngine()

    init(store: AppDataStore) {
        self.store = store
    }

    // MARK: - Context

    func workflowContext(for jobID: UUID) -> JobWorkflowContext? {
        store.workflowContext(for: jobID)
    }

    func workflowContext(for job: JobRecord) -> JobWorkflowContext {
        store.workflowContext(for: job.id)
        ?? fallbackContext(for: job)
    }

    func workflowState(for job: JobRecord) -> JobWorkflowState {
        workflowContext(for: job).currentState
    }

    func nextAction(for job: JobRecord) -> JobWorkflowAction {
        workflowContext(for: job).nextAction
    }

    func nextAction(for jobID: UUID) -> JobWorkflowAction? {
        workflowContext(for: jobID)?.nextAction
    }

    func hasInvoice(for jobID: UUID) -> Bool {
        store.invoice(forJobID: jobID) != nil
    }

    func invoice(for jobID: UUID) -> InvoiceRecord? {
        store.invoice(forJobID: jobID)
    }

    func job(for jobID: UUID) -> JobRecord? {
        store.jobs.first(where: { $0.id == jobID })
    }

    // MARK: - Consolidated workflow entry points

    @discardableResult
    func performWorkflowAction(
        jobID: UUID,
        action: JobWorkflowAction,
        employeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        let succeeded = store.performWorkflowAction(
            jobID: jobID,
            action: action,
            employeeID: employeeID,
            note: note,
            at: timestamp
        )

        updateOutcome(
            succeeded: succeeded,
            jobID: jobID,
            action: action,
            employeeID: employeeID
        )

        return succeeded
    }

    @discardableResult
    func performNextWorkflowAction(
        for job: JobRecord,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        let action = nextAction(for: job)
        guard action != .viewDetails else {
            lastErrorMessage = "No executable workflow action is available."
            return false
        }

        return performWorkflowAction(
            jobID: job.id,
            action: action,
            employeeID: employeeID ?? job.primaryTechnicianID,
            at: timestamp
        )
    }

    /// Mirrors the current Job Detail behavior while keeping the branching in
    /// one reusable place for the consolidation step.
    @discardableResult
    func performGuidedPrimaryAction(
        for job: JobRecord,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        performNextWorkflowAction(
            for: job,
            employeeID: employeeID ?? job.primaryTechnicianID,
            at: timestamp
        )
    }

    @discardableResult
    func performGuidedPrimaryAction(
        for jobID: UUID,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        guard let job = job(for: jobID) else {
            lastErrorMessage = "Unable to find the requested job."
            return false
        }

        return performGuidedPrimaryAction(
            for: job,
            employeeID: employeeID,
            at: timestamp
        )
    }

    // MARK: - Direct wrappers for the current workflow helpers

    @discardableResult
    func pauseWork(
        jobID: UUID,
        employeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        performWorkflowAction(
            jobID: jobID,
            action: .pauseWork,
            employeeID: employeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func resumeWork(
        jobID: UUID,
        employeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        performWorkflowAction(
            jobID: jobID,
            action: .resumeWork,
            employeeID: employeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func startSetup(
        jobID: UUID,
        employeeID: UUID? = nil,
        startedAt: Date = Date()
    ) -> Bool {
        let succeeded = store.startSetup(
            jobID: jobID,
            employeeID: employeeID,
            startedAt: startedAt
        )
        updateOutcome(
            succeeded: succeeded,
            jobID: jobID,
            action: .startSetup,
            employeeID: employeeID
        )
        return succeeded
    }

    @discardableResult
    func startJob(
        jobID: UUID,
        employeeID: UUID? = nil,
        startedAt: Date = Date()
    ) -> Bool {
        let succeeded = store.startJob(
            jobID: jobID,
            employeeID: employeeID,
            startedAt: startedAt
        )
        updateOutcome(
            succeeded: succeeded,
            jobID: jobID,
            action: .startWork,
            employeeID: employeeID
        )
        return succeeded
    }

    @discardableResult
    func completeJob(
        jobID: UUID,
        employeeID: UUID? = nil,
        completedAt: Date = Date()
    ) -> Bool {
        let succeeded = store.completeJob(
            jobID: jobID,
            employeeID: employeeID,
            completedAt: completedAt
        )
        updateOutcome(
            succeeded: succeeded,
            jobID: jobID,
            action: .finishWork,
            employeeID: employeeID
        )
        return succeeded
    }

    @discardableResult
    func createInvoiceFromJob(
        _ job: JobRecord
    ) -> InvoiceRecord? {
        let invoice = store.createInvoiceFromJob(job)
        updateOutcome(
            succeeded: invoice != nil,
            jobID: job.id,
            action: .createInvoice,
            employeeID: job.primaryTechnicianID
        )
        return invoice
    }

    // MARK: - Internal helpers

    private func fallbackContext(
        for job: JobRecord
    ) -> JobWorkflowContext {
        fallbackEngine.context(
            for: job,
            invoice: store.invoice(forJobID: job.id)
        )
    }

    private func updateOutcome(
        succeeded: Bool,
        jobID: UUID,
        action: JobWorkflowAction,
        employeeID: UUID?
    ) {
        if succeeded {
            lastActionJobID = jobID
            lastAction = action
            lastEmployeeID = employeeID
            lastErrorMessage = nil
        } else {
            lastErrorMessage = "Unable to perform \(action.title) for the selected job."
        }
    }
}
