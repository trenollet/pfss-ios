import Foundation
import WatchConnectivity

@MainActor
final class PFSSWatchWorkflowBridge: NSObject, WCSessionDelegate {
    static let shared = PFSSWatchWorkflowBridge()

    private weak var store: AppDataStore?
    private var processedRequestIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "pfss.watch.processedRequests") ?? []
    )

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func bind(store: AppDataStore) {
        self.store = store
        publishSnapshot()
    }

    func publishSnapshot() {
        guard WCSession.isSupported() else { return }
        try? WCSession.default.updateApplicationContext(snapshot())
    }

    private func snapshot() -> [String: Any] {
        guard let store,
              let employee = store.authenticatedCloudEmployee else {
            return ["type": "snapshot", "available": false,
                    "message": "Open PFSS on the paired iPhone."]
        }

        let jobs = SchedulingEngine.dailyAgenda(
            for: employee,
            on: Date(),
            from: store.jobs
        ).jobs.filter { $0.status != .completed && $0.status != .cancelled }

        let coordinator = FieldOperationsWorkflowCoordinator(store: store)
        let job = jobs.first(where: {
            ![JobWorkflowState.notStarted, .completed, .cancelled]
                .contains(coordinator.workflowState(for: $0))
        }) ?? jobs.first

        guard let job else {
            return ["type": "snapshot", "available": false,
                    "message": "No active jobs today."]
        }

        let context = coordinator.workflowContext(for: job)
        let watchActions = context.availableActions.filter(Self.isWatchAction)
        let primary = watchActions.contains(context.nextAction)
            ? context.nextAction
            : watchActions.first
        let customer = store.customers.first { $0.customerNumber == job.customerNumber }
        let customerName = customer.map {
            $0.businessName.isEmpty ? $0.contactName : $0.businessName
        } ?? job.customerNumber

        var value: [String: Any] = [
            "type": "snapshot",
            "available": true,
            "jobID": job.id.uuidString,
            "jobNumber": job.jobNumber,
            "customerName": customerName,
            "state": context.currentState.rawValue,
            "actions": watchActions.map(\.rawValue),
        ]
        if let primary {
            value["primaryAction"] = primary.rawValue
            value["primaryTitle"] = primary.title
        } else {
            value["message"] = "Continue this job on the iPhone."
        }
        return value
    }

    private static func isWatchAction(_ action: JobWorkflowAction) -> Bool {
        switch action {
        case .startTravel, .pauseTravel, .resumeTravel, .markArrived,
             .startSetup, .startWork, .pauseWork, .resumeWork,
             .startPackUp, .finishWork, .completeJob:
            return true
        case .createInvoice, .recordPayment, .viewDetails:
            return false
        }
    }

    private func handle(
        _ message: [String: Any],
        reply: @escaping ([String: Any]) -> Void
    ) {
        guard message["type"] as? String == "performAction" else {
            reply(snapshot())
            return
        }
        guard let requestID = message["requestID"] as? String,
              let jobRaw = message["jobID"] as? String,
              let jobID = UUID(uuidString: jobRaw),
              let actionRaw = message["action"] as? String,
              let action = JobWorkflowAction(rawValue: actionRaw),
              Self.isWatchAction(action),
              let store else {
            reply(["success": false, "message": "The request was not valid."])
            return
        }

        if processedRequestIDs.contains(requestID) {
            var response = snapshot()
            response["success"] = true
            response["message"] = "Already saved on iPhone."
            reply(response)
            return
        }

        guard let context = store.workflowContext(for: jobID),
              context.availableActions.contains(action) else {
            var response = snapshot()
            response["success"] = false
            response["message"] = "The job changed. Review the current action."
            reply(response)
            return
        }

        let coordinator = FieldOperationsWorkflowCoordinator(store: store)
        let succeeded = coordinator.performWorkflowAction(
            jobID: jobID,
            action: action,
            employeeID: store.authenticatedCloudEmployee?.id
        )
        if succeeded {
            processedRequestIDs.insert(requestID)
            persistProcessedRequests()
        }
        var response = snapshot()
        response["success"] = succeeded
        response["message"] = succeeded
            ? "Saved on iPhone."
            : (coordinator.lastErrorMessage ?? "Unable to complete this action.")
        publishSnapshot()
        reply(response)
    }

    private func persistProcessedRequests() {
        let retained = Array(processedRequestIDs.suffix(100))
        processedRequestIDs = Set(retained)
        UserDefaults.standard.set(retained, forKey: "pfss.watch.processedRequests")
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.publishSnapshot() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in self.handle(message, reply: replyHandler) }
    }
}
