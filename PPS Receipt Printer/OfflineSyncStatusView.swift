//
//  OfflineSyncStatusView.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 6 – Reusable connection and synchronization UI.
//

import SwiftUI

enum OfflineSyncPresentationState: Equatable {
    case savedOnDevice
    case checkingConnection
    case online
    case offlineSavedLocally(pendingCount: Int)
    case synchronizing(pendingCount: Int)
    case changesPending(Int)
    case syncFailed(Int)
    case conflictRequiresReview(Int)
    case accessSuspended
    case cloudUnavailable
    case fullySynchronized

    var title: String {
        switch self {
        case .savedOnDevice: return "Saved on Device"
        case .checkingConnection: return "Checking Connection"
        case .online: return "Online"
        case .offlineSavedLocally: return "Offline — Saved Locally"
        case .synchronizing: return "Synchronizing"
        case let .changesPending(count): return "\(count) Change\(count == 1 ? "" : "s") Pending"
        case let .syncFailed(count): return "Sync Failed (\(count))"
        case let .conflictRequiresReview(count): return "\(count) Conflict\(count == 1 ? "" : "s") Need Review"
        case .accessSuspended: return "Access Suspended"
        case .cloudUnavailable: return "Cloud Sync Unavailable"
        case .fullySynchronized: return "Fully Synchronized"
        }
    }

    var detail: String {
        switch self {
        case .savedOnDevice:
            return "PFSS data is stored locally. Remote synchronization is not configured."
        case .checkingConnection:
            return "PFSS is checking network availability."
        case .online:
            return "A network connection is available."
        case let .offlineSavedLocally(count):
            return count == 0
                ? "Your work remains safe on this device."
                : "\(count) change\(count == 1 ? " is" : "s are") safe on this device and will sync when online."
        case let .synchronizing(count):
            return "PFSS is sending \(count) pending change\(count == 1 ? "" : "s") in order."
        case .changesPending:
            return "Changes are safely queued and waiting to synchronize."
        case .syncFailed:
            return "One or more changes could not synchronize. Your local work is preserved."
        case .conflictRequiresReview:
            return "Local and remote changes are both preserved until reviewed."
        case .accessSuspended:
            return "This employee's company access is suspended. Synchronization will resume only after an Owner or Manager reactivates it."
        case .cloudUnavailable:
            return "PFSS could not complete its latest company synchronization check. Local work remains on this device."
        case .fullySynchronized:
            return "All local changes have synchronized successfully."
        }
    }

    var systemImage: String {
        switch self {
        case .savedOnDevice: return "internaldrive.fill"
        case .checkingConnection: return "network"
        case .online: return "wifi"
        case .offlineSavedLocally: return "wifi.slash"
        case .synchronizing: return "arrow.triangle.2.circlepath"
        case .changesPending: return "clock.arrow.circlepath"
        case .syncFailed: return "exclamationmark.arrow.triangle.2.circlepath"
        case .conflictRequiresReview: return "exclamationmark.triangle.fill"
        case .accessSuspended: return "person.crop.circle.badge.pause"
        case .cloudUnavailable: return "icloud.slash.fill"
        case .fullySynchronized: return "checkmark.icloud.fill"
        }
    }

    var color: Color {
        switch self {
        case .savedOnDevice, .online, .fullySynchronized: return .green
        case .checkingConnection: return .secondary
        case .offlineSavedLocally, .changesPending: return .orange
        case .synchronizing: return .blue
        case .syncFailed: return .red
        case .conflictRequiresReview: return .purple
        case .accessSuspended: return .orange
        case .cloudUnavailable: return .red
        }
    }
}

@MainActor
enum OfflineSyncStatusResolver {
    static func resolve(
        mode: OfflineSynchronizationMode,
        queue: OfflineOperationQueue,
        connectivity: OfflineConnectivityStatus,
        cloudAccessStatus: PFSSCloudSynchronizationAccessStatus = .available
    ) -> OfflineSyncPresentationState {
        switch cloudAccessStatus {
        case .suspended:
            return .accessSuspended
        case .accountHold:
            return .accessSuspended
        case .unavailable where connectivity != .offline:
            return .cloudUnavailable
        case .checking where connectivity == .unknown:
            return .checkingConnection
        case .checking, .available:
            break
        case .unavailable:
            break
        }
        if mode == .localOnly {
            return connectivity == .offline
                ? .offlineSavedLocally(pendingCount: 0)
                : .savedOnDevice
        }

        let operations = queue.actionableOperations
        let conflictCount = operations.filter { $0.status == .conflicted }.count
        if conflictCount > 0 {
            return .conflictRequiresReview(conflictCount)
        }

        let failedCount = operations.filter { $0.status == .failed }.count
        if failedCount > 0 {
            return .syncFailed(failedCount)
        }

        let synchronizingCount = operations.filter { $0.status == .synchronizing }.count
        if synchronizingCount > 0 {
            return .synchronizing(pendingCount: operations.count)
        }

        if connectivity == .offline {
            return .offlineSavedLocally(pendingCount: operations.count)
        }
        if connectivity == .unknown {
            return operations.isEmpty
                ? .checkingConnection
                : .changesPending(operations.count)
        }
        if !operations.isEmpty {
            return .changesPending(operations.count)
        }
        return .fullySynchronized
    }
}

struct OfflineSyncStatusBadge: View {
    @ObservedObject var queue: OfflineOperationQueue
    @ObservedObject var connectivity: OfflineConnectivityMonitor
    let mode: OfflineSynchronizationMode
    var cloudAccessStatus: PFSSCloudSynchronizationAccessStatus = .available

    private var status: OfflineSyncPresentationState {
        OfflineSyncStatusResolver.resolve(
            mode: mode,
            queue: queue,
            connectivity: connectivity.status,
            cloudAccessStatus: cloudAccessStatus
        )
    }

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Synchronization status: \(status.title)")
            .accessibilityHint(status.detail)
    }
}

struct OfflineSyncDetailsView: View {
    @ObservedObject var queue: OfflineOperationQueue
    @ObservedObject var connectivity: OfflineConnectivityMonitor
    let mode: OfflineSynchronizationMode
    var cloudAccessStatus: PFSSCloudSynchronizationAccessStatus = .available
    var canOverrideConflicts = false
    var onSyncNow: (() -> Void)? = nil
    var onResolveConflict: ((UUID, OfflineConflictResolution) throws -> Void)? = nil

    @State private var conflictOperation: PendingOfflineOperation?
    @State private var resolutionError = ""
    @State private var isShowingResolutionError = false

    private var status: OfflineSyncPresentationState {
        OfflineSyncStatusResolver.resolve(
            mode: mode,
            queue: queue,
            connectivity: connectivity.status,
            cloudAccessStatus: cloudAccessStatus
        )
    }

    private var visibleOperations: [PendingOfflineOperation] {
        Array(
            queue.orderedOperations
                .filter { !$0.status.isTerminal || $0.status == .synchronized }
                .reversed()
                .prefix(50)
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(status.title, systemImage: status.systemImage)
                        .font(.headline)
                        .foregroundStyle(status.color)
                    Text(status.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)

                Button {
                    onSyncNow?()
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(
                    mode == .localOnly ||
                    connectivity.status != .online ||
                    onSyncNow == nil
                )
            } footer: {
                if mode == .localOnly {
                    Text("Remote synchronization will become available when PFSS is connected to a CloudKit or server adapter. All current data remains stored locally on this device.")
                } else if connectivity.status != .online {
                    Text("Sync Now becomes available when the device is online.")
                }
            }

            Section("Queue Summary") {
                HStack {
                    Text("Connection")
                    Spacer()
                    Label(
                        connectivity.status == .online ? "Online" :
                            connectivity.status == .offline ? "Offline" : "Checking",
                        systemImage: connectivity.status == .online
                            ? "wifi"
                            : connectivity.status == .offline
                                ? "wifi.slash"
                                : "network"
                    )
                    .foregroundStyle(
                        connectivity.status == .online ? Color.green : Color.secondary
                    )
                }
                syncMetric("Pending", value: queue.actionableOperations.filter {
                    $0.status == .pending || $0.status == .waitingForRetry
                }.count)
                syncMetric("Synchronizing", value: queue.actionableOperations.filter {
                    $0.status == .synchronizing
                }.count)
                syncMetric("Failed", value: queue.actionableOperations.filter {
                    $0.status == .failed
                }.count)
                syncMetric("Conflicts", value: queue.actionableOperations.filter {
                    $0.status == .conflicted
                }.count)

            }

            Section("Synchronization Activity") {
                if visibleOperations.isEmpty {
                    ContentUnavailableView(
                        "No Synchronization Activity",
                        systemImage: "checkmark.circle",
                        description: Text("There are no queued changes or recent synchronized actions.")
                    )
                } else {
                    ForEach(visibleOperations) { operation in
                        operationRow(operation)
                    }
                }
            }
        }
        .navigationTitle("Sync Status")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Choose Which Version to Keep",
            isPresented: Binding(
                get: { conflictOperation != nil },
                set: { if !$0 { conflictOperation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Keep Cloud Version") {
                resolveSelectedConflict(as: .keptRemote)
            }
            if canOverrideConflicts {
                Button("Keep This Device's Version") {
                    resolveSelectedConflict(as: .keptLocal)
                }
            }
            Button("Cancel", role: .cancel) {
                conflictOperation = nil
            }
        } message: {
            Text(conflictResolutionMessage)
        }
        .alert("Unable to Resolve Conflict", isPresented: $isShowingResolutionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resolutionError)
        }
    }

    private func syncMetric(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
        }
    }

    private func operationRow(_ operation: PendingOfflineOperation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(operation.actionName)
                    .font(.headline)
                Spacer()
                Text(operation.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(operation.status.displayColor)
            }
            Text("\(operation.entityType.rawValue.capitalized) • \(operation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let failure = operation.failure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let conflict = operation.conflict,
               conflict.requiresHumanReview {
                Text("Local and remote versions are preserved for review.")
                    .font(.caption)
                    .foregroundStyle(.purple)
                if let paths = operation.metadata["conflictingPaths"],
                   !paths.isEmpty {
                    Text("Conflicting fields: " + paths)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if canOverrideConflicts {
                    Text("Review this item in the centralized Conflict Inbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This change was sent to a Manager or Owner for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if operation.metadata["conflictDeliveryStatus"] ==
                        "deliveryFailed" {
                        Text(
                            operation.metadata["conflictDeliveryError"]
                                ?? "PFSS could not send this conflict for review."
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func resolveSelectedConflict(
        as resolution: OfflineConflictResolution
    ) {
        guard let operation = conflictOperation,
              let onResolveConflict else { return }
        conflictOperation = nil
        do {
            try onResolveConflict(operation.id, resolution)
        } catch {
            resolutionError = error.localizedDescription
            isShowingResolutionError = true
        }
    }

    private var conflictResolutionMessage: String {
        if canOverrideConflicts {
            return "PFSS preserved both versions. The cloud version is the latest accepted company record; keeping this device's version will submit it again as a reviewed replacement."
        }
        return "PFSS preserved both versions. Members may accept the latest company version; a Manager or Owner must review any request to replace it."
    }
}

private extension OfflineOperationStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .synchronizing: return "Synchronizing"
        case .waitingForRetry: return "Waiting to Retry"
        case .failed: return "Failed"
        case .conflicted: return "Conflict"
        case .synchronized: return "Synchronized"
        case .cancelled: return "Cancelled"
        }
    }

    var displayColor: Color {
        switch self {
        case .pending, .waitingForRetry: return .orange
        case .synchronizing: return .blue
        case .failed: return .red
        case .conflicted: return .purple
        case .synchronized: return .green
        case .cancelled: return .secondary
        }
    }
}
