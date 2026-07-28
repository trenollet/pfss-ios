//
//  OfflineConnectivityMonitor.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 4 – Connectivity monitoring boundary.
//

import Combine
import Foundation
import Network

enum OfflineConnectivityStatus: String, Codable, Equatable {
    case unknown
    case offline
    case online
}

@MainActor
protocol OfflineConnectivityMonitoring: AnyObject {
    var status: OfflineConnectivityStatus { get }
    var isConnected: Bool { get }
    var onStatusChanged: ((OfflineConnectivityStatus) -> Void)? { get set }

    func start()
    func stop()
}

/// A lightweight wrapper around `NWPathMonitor`. It reports reachability only;
/// the remote adapter remains responsible for authentication and server health.
@MainActor
final class OfflineConnectivityMonitor: ObservableObject, OfflineConnectivityMonitoring {
    @Published private(set) var status: OfflineConnectivityStatus = .unknown
    var onStatusChanged: ((OfflineConnectivityStatus) -> Void)?

    var isConnected: Bool { status == .online }

    private let monitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var isStarted = false

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        monitorQueue: DispatchQueue = DispatchQueue(
            label: "com.pfss.offline-connectivity"
        )
    ) {
        self.monitor = monitor
        self.monitorQueue = monitorQueue
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus: OfflineConnectivityStatus =
                path.status == .satisfied ? .online : .offline
            Task { @MainActor [weak self] in
                self?.setStatus(newStatus)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func stop() {
        guard isStarted else { return }
        monitor.cancel()
        isStarted = false
        setStatus(.unknown)
    }

    private func setStatus(_ newStatus: OfflineConnectivityStatus) {
        guard status != newStatus else { return }
        status = newStatus
        onStatusChanged?(newStatus)
    }
}
