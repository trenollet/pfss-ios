import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PFSSWatchWorkflowModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = PFSSWatchSnapshot.empty
    @Published private(set) var isSending = false
    @Published var confirmationAction: PFSSWatchAction?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
    }

    func refresh() {
        send(["type": "snapshotRequest"])
    }

    func request(_ action: PFSSWatchAction) {
        guard snapshot.actions.contains(action), !isSending else { return }
        if action == .completeJob {
            confirmationAction = action
            return
        }
        perform(action)
    }

    func confirmAction() {
        guard let action = confirmationAction else { return }
        confirmationAction = nil
        perform(action)
    }

    private func perform(_ action: PFSSWatchAction) {
        guard let jobID = snapshot.jobID else { return }
        isSending = true
        snapshot.message = "Waiting for iPhone…"
        send([
            "type": "performAction",
            "requestID": UUID().uuidString,
            "jobID": jobID,
            "action": action.rawValue,
        ])
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.default.isReachable else {
            isSending = false
            snapshot.message = "Open PFSS on the paired iPhone."
            return
        }
        WCSession.default.sendMessage(message, replyHandler: { response in
            Task { @MainActor in
                self.isSending = false
                self.apply(response)
            }
        }, errorHandler: { error in
            Task { @MainActor in
                self.isSending = false
                self.snapshot.message = "Unable to reach iPhone. Try again."
            }
        })
    }

    private func apply(_ value: [String: Any]) {
        guard !value.isEmpty else { return }
        snapshot = PFSSWatchSnapshot(value)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in self.apply(message) }
    }
}

enum PFSSWatchAction: String, CaseIterable, Identifiable {
    case startTravel, pauseTravel, resumeTravel, markArrived, startSetup
    case startWork, pauseWork, resumeWork, startPackUp, finishWork, completeJob

    var id: String { rawValue }
    var title: String {
        switch self {
        case .startTravel: "Start Travel"
        case .pauseTravel: "Pause Travel"
        case .resumeTravel: "Resume Travel"
        case .markArrived: "Arrived"
        case .startSetup: "Start Setup"
        case .startWork: "Start Work"
        case .pauseWork: "Pause Work"
        case .resumeWork: "Resume Work"
        case .startPackUp: "Start Pack-up"
        case .finishWork: "Complete Work"
        case .completeJob: "Complete Job"
        }
    }
    var icon: String {
        switch self {
        case .startTravel, .resumeTravel: "car.fill"
        case .pauseTravel, .pauseWork: "pause.fill"
        case .markArrived: "mappin.circle.fill"
        case .startSetup: "wrench.and.screwdriver.fill"
        case .startWork, .resumeWork: "play.fill"
        case .startPackUp: "shippingbox.fill"
        case .finishWork, .completeJob: "checkmark.circle.fill"
        }
    }
}

struct PFSSWatchSnapshot {
    var available: Bool
    var jobID: String?
    var jobNumber: String
    var customerName: String
    var state: String
    var actions: [PFSSWatchAction]
    var primaryAction: PFSSWatchAction?
    var message: String

    static let empty = PFSSWatchSnapshot(
        available: false, jobNumber: "PFSS", customerName: "",
        state: "", actions: [], message: "Connecting to iPhone…"
    )

    init(
        available: Bool,
        jobID: String? = nil,
        jobNumber: String,
        customerName: String,
        state: String,
        actions: [PFSSWatchAction],
        primaryAction: PFSSWatchAction? = nil,
        message: String
    ) {
        self.available = available; self.jobID = jobID
        self.jobNumber = jobNumber; self.customerName = customerName
        self.state = state; self.actions = actions
        self.primaryAction = primaryAction; self.message = message
    }

    init(_ value: [String: Any]) {
        available = value["available"] as? Bool ?? false
        jobID = value["jobID"] as? String
        jobNumber = value["jobNumber"] as? String ?? "PFSS"
        customerName = value["customerName"] as? String ?? ""
        state = value["state"] as? String ?? ""
        actions = (value["actions"] as? [String] ?? [])
            .compactMap(PFSSWatchAction.init(rawValue:))
        primaryAction = (value["primaryAction"] as? String)
            .flatMap(PFSSWatchAction.init(rawValue:))
        message = value["message"] as? String ?? ""
    }
}
