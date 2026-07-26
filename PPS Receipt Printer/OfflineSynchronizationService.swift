//
//  OfflineSynchronizationService.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 4 – Ordered synchronization and retry processing.
//

import Combine
import Foundation

enum OfflineSynchronizationAdapterResult {
    case synchronized(remoteRevision: String?)
    case failed(OfflineFailureDetails)
    /// Part 5 will add merge and human-review policies around this result.
    case conflicted(OfflineConflictInformation)
}

/// CloudKit or a future PFSS server implements this contract. The queue and
/// technician workflow do not need to change when that adapter is selected.
@MainActor
protocol OfflineSynchronizationAdapter {
    func synchronize(
        operation: PendingOfflineOperation
    ) async -> OfflineSynchronizationAdapterResult
}

struct OfflineRetryPolicy: Equatable {
    var delays: [TimeInterval]
    var maximumAttempts: Int

    static let standard = OfflineRetryPolicy(
        delays: [5, 15, 60, 5 * 60, 15 * 60],
        maximumAttempts: 6
    )

    func delay(afterFailedAttempt attemptNumber: Int) -> TimeInterval {
        guard !delays.isEmpty else { return 0 }
        let index = min(max(attemptNumber - 1, 0), delays.count - 1)
        return max(delays[index], 0)
    }
}

enum OfflineSynchronizationProcessorState: Equatable {
    case idle
    case offline
    case synchronizing
    case waitingForRetry(Date)
    case failed
    case conflict
}

/// Processes durable operations one at a time in their original queue order.
/// A failed earlier operation blocks later work, preserving causal ordering.
@MainActor
final class OfflineSynchronizationService: ObservableObject {
    @Published private(set) var state: OfflineSynchronizationProcessorState = .idle
    @Published private(set) var lastProcessedOperationID: UUID?

    let queue: OfflineOperationQueue
    let connectivity: any OfflineConnectivityMonitoring
    let adapter: any OfflineSynchronizationAdapter

    private let retryPolicy: OfflineRetryPolicy
    private let conflictResolver = OfflineConflictResolver()
    private var isStarted = false
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var pendingProcessingRequest = false

    init(
        queue: OfflineOperationQueue,
        connectivity: any OfflineConnectivityMonitoring,
        adapter: any OfflineSynchronizationAdapter,
        retryPolicy: OfflineRetryPolicy? = nil
    ) {
        self.queue = queue
        self.connectivity = connectivity
        self.adapter = adapter
        self.retryPolicy = retryPolicy ?? .standard
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        _ = try? queue.recoverInterruptedSynchronizations()
        connectivity.onStatusChanged = { [weak self] status in
            self?.connectivityChanged(to: status)
        }
        connectivity.start()
        connectivityChanged(to: connectivity.status)
    }

    func stop() {
        isStarted = false
        connectivity.onStatusChanged = nil
        connectivity.stop()
        processingTask?.cancel()
        retryTask?.cancel()
        pendingProcessingRequest = false
        retryTask = nil
        state = .idle
    }

    /// User-initiated synchronization ignores scheduled backoff but still
    /// requires connectivity and never submits an operation concurrently.
    func syncNow() {
        scheduleProcessing(forceRetry: true)
    }

    /// Exposed for deterministic tests and app lifecycle refreshes.
    func processPendingOperations(
        forceRetry: Bool = false,
        now: Date = Date()
    ) async {
        guard connectivity.isConnected else {
            state = .offline
            return
        }
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        retryTask?.cancel()
        retryTask = nil
        state = .synchronizing

        for candidate in queue.orderedOperations where !candidate.status.isTerminal {
            guard !Task.isCancelled else {
                state = connectivity.isConnected ? .idle : .offline
                return
            }

            if candidate.status == .conflicted {
                state = .conflict
                return
            }
            if candidate.status == .failed,
               candidate.failure?.isRetryable == false {
                state = .failed
                return
            }
            guard forceRetry || candidate.isReadyToSynchronize(at: now) else {
                let retryDate = candidate.nextRetryAt ?? now
                state = .waitingForRetry(retryDate)
                scheduleRetry(at: retryDate)
                return
            }
            guard connectivity.isConnected else {
                state = .offline
                return
            }

            let shouldContinue = await process(candidate, now: now)
            guard shouldContinue else { return }
        }

        state = queue.hasPendingChanges ? .failed : .idle
    }

    private func process(
        _ candidate: PendingOfflineOperation,
        now: Date
    ) async -> Bool {
        var operation = candidate
        let attemptNumber = operation.attemptCount + 1
        operation.status = .synchronizing
        operation.firstAttemptAt = operation.firstAttemptAt ?? now
        operation.lastAttemptAt = now
        operation.updatedAt = now
        operation.failure = nil
        operation.nextRetryAt = nil
        operation.retryAttempts.append(
            OfflineRetryAttempt(
                attemptNumber: attemptNumber,
                startedAt: now
            )
        )

        do {
            try queue.update(operation)
        } catch {
            state = .failed
            return false
        }

        let result = await adapter.synchronize(operation: operation)
        let completedAt = Date()
        operation.updatedAt = completedAt
        operation.retryAttempts[operation.retryAttempts.count - 1].completedAt = completedAt

        switch result {
        case let .synchronized(remoteRevision):
            operation.status = .synchronized
            operation.synchronizedAt = completedAt
            operation.failure = nil
            operation.nextRetryAt = nil
            operation.retryAttempts[operation.retryAttempts.count - 1].outcome = .succeeded
            if let remoteRevision {
                operation.metadata["remoteRevision"] = remoteRevision
            }
            do {
                try queue.update(operation)
                lastProcessedOperationID = operation.id
                return true
            } catch {
                state = .failed
                return false
            }

        case let .failed(failure):
            let reachedLimit = attemptNumber >= retryPolicy.maximumAttempts
            let canRetry = failure.isRetryable && !reachedLimit
            let delay = canRetry
                ? retryPolicy.delay(afterFailedAttempt: attemptNumber)
                : nil
            let durableFailure = OfflineFailureDetails(
                category: failure.category,
                code: failure.code,
                message: failure.message,
                isRetryable: canRetry,
                occurredAt: failure.occurredAt,
                underlyingDescription: failure.underlyingDescription,
                metadata: failure.metadata
            )
            operation.failure = durableFailure
            operation.status = canRetry ? .waitingForRetry : .failed
            operation.nextRetryAt = delay.map { completedAt.addingTimeInterval($0) }
            operation.retryAttempts[operation.retryAttempts.count - 1].outcome = .failed
            operation.retryAttempts[operation.retryAttempts.count - 1].failure = durableFailure
            operation.retryAttempts[operation.retryAttempts.count - 1].scheduledDelaySeconds = delay

            do {
                try queue.update(operation)
            } catch {
                state = .failed
                return false
            }

            if let retryDate = operation.nextRetryAt {
                state = .waitingForRetry(retryDate)
                scheduleRetry(at: retryDate)
            } else {
                state = .failed
            }
            return false

        case let .conflicted(conflict):
            let automaticMergeCount = Int(
                operation.metadata["automaticConflictMergeCount"] ?? "0"
            ) ?? 0
            if case let .automaticallyMerged(resolvedConflict) =
                conflictResolver.evaluate(conflict, at: completedAt),
               let mergedVersion = resolvedConflict.mergedVersion,
               automaticMergeCount == 0 {
                operation.payload = mergedVersion.payload
                operation.baseRevision = resolvedConflict.remoteVersion?.revision
                operation.conflict = resolvedConflict
                operation.status = .pending
                operation.failure = nil
                operation.nextRetryAt = nil
                operation.retryAttempts[operation.retryAttempts.count - 1].outcome = .deferred
                operation.metadata["automaticConflictMerge"] = "true"
                operation.metadata["automaticConflictMergeCount"] = "1"
                do {
                    try queue.update(operation)
                } catch {
                    state = .failed
                    return false
                }
                return await process(operation, now: completedAt)
            }

            operation.status = .conflicted
            operation.conflict = conflict
            if case let .requiresHumanReview(_, conflictingPaths) =
                conflictResolver.evaluate(conflict, at: completedAt) {
                operation.metadata["conflictingPaths"] = conflictingPaths.joined(separator: ",")
            }
            operation.failure = OfflineFailureDetails(
                category: .conflict,
                message: "A synchronization conflict requires review.",
                isRetryable: false,
                occurredAt: completedAt
            )
            operation.retryAttempts[operation.retryAttempts.count - 1].outcome = .failed
            operation.retryAttempts[operation.retryAttempts.count - 1].failure = operation.failure
            do {
                try queue.update(operation)
            } catch {
                state = .failed
                return false
            }
            state = .conflict
            return false
        }
    }

    private func connectivityChanged(to status: OfflineConnectivityStatus) {
        switch status {
        case .online:
            scheduleProcessing(forceRetry: false)
        case .offline:
            pendingProcessingRequest = false
            processingTask?.cancel()
            retryTask?.cancel()
            retryTask = nil
            state = .offline
        case .unknown:
            state = .idle
        }
    }

    private func scheduleProcessing(forceRetry: Bool) {
        guard connectivity.isConnected else {
            state = .offline
            return
        }
        guard processingTask == nil else {
            pendingProcessingRequest = true
            return
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.processPendingOperations(forceRetry: forceRetry)
            self.processingTask = nil
            if self.pendingProcessingRequest {
                self.pendingProcessingRequest = false
                self.scheduleProcessing(forceRetry: false)
            }
        }
    }

    private func scheduleRetry(at date: Date) {
        guard isStarted else { return }
        retryTask?.cancel()
        let delay = max(date.timeIntervalSinceNow, 0)
        retryTask = Task { [weak self] in
            let nanoseconds = UInt64(min(delay, 86_400) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.scheduleProcessing(forceRetry: false)
        }
    }
}
