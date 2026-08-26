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
    case supersededByCloud(
        remoteRevision: String,
        operation: PendingOfflineOperation
    )
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

/// Processes durable operations one at a time while preserving order inside
/// each real dependency group. A blocked record never stalls unrelated work.
@MainActor
final class OfflineSynchronizationService: ObservableObject {
    @Published private(set) var state: OfflineSynchronizationProcessorState = .idle
    @Published private(set) var lastProcessedOperationID: UUID?

    let queue: OfflineOperationQueue
    let connectivity: any OfflineConnectivityMonitoring
    let adapter: any OfflineSynchronizationAdapter

    var onOperationSupersededByCloud: ((PendingOfflineOperation, String) -> Void)?

    private let retryPolicy: OfflineRetryPolicy
    private let conflictResolver = OfflineConflictResolver()
    private var isStarted = false
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var pendingProcessingRequest = false
    private var requiresAuthoritativePullBeforeUpload = false

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

    /// Cloud-backed sessions close this gate before connectivity starts. It
    /// prevents retained work from a prior enrollment from racing ahead of the
    /// first authoritative tenant pull.
    func requireAuthoritativePull() {
        requiresAuthoritativePullBeforeUpload = true
        processingTask?.cancel()
        processingTask = nil
        pendingProcessingRequest = false
        state = .idle
    }

    /// Opens the upload path only after the current session has established a
    /// complete baseline and successfully pulled through its server cursor.
    func completeAuthoritativePull() {
        requiresAuthoritativePullBeforeUpload = false
    }

    /// User-initiated synchronization ignores scheduled backoff but still
    /// requires connectivity and never submits an operation concurrently.
    func syncNow() {
        _ = try? queue.requeueTransientFailures()
        scheduleProcessing(forceRetry: true)
    }

    /// Exposed for deterministic tests and app lifecycle refreshes.
    func processPendingOperations(
        forceRetry: Bool = false,
        now: Date = Date()
    ) async {
        guard !requiresAuthoritativePullBeforeUpload else {
            state = .idle
            return
        }
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

        var blockedDependencyKeys: Set<String> = []
        var blockedOperationIDs: Set<UUID> = []
        var earliestRetryDate: Date?
        var encounteredFailure = false
        var encounteredConflict = false

        for candidate in queue.orderedOperations where !candidate.status.isTerminal {
            guard !Task.isCancelled else {
                state = connectivity.isConnected ? .idle : .offline
                return
            }

            let dependencyKeys = candidate.synchronizationDependencyKeys
            let hasBlockedDependency = !dependencyKeys.isDisjoint(with: blockedDependencyKeys)
            let hasBlockedPrerequisite = !candidate.prerequisiteOperationIDs
                .isDisjoint(with: blockedOperationIDs)
            if hasBlockedDependency || hasBlockedPrerequisite {
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
                continue
            }

            if candidate.status == .conflicted {
                encounteredConflict = true
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
                continue
            }
            if candidate.status == .failed,
               candidate.failure?.isRetryable == false {
                encounteredFailure = true
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
                continue
            }
            guard forceRetry || candidate.isReadyToSynchronize(at: now) else {
                let retryDate = candidate.nextRetryAt ?? now
                earliestRetryDate = min(earliestRetryDate ?? retryDate, retryDate)
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
                continue
            }
            guard connectivity.isConnected else {
                state = .offline
                return
            }

            switch await process(candidate, now: now) {
            case .completed:
                continue
            case .blockedForRetry(let retryDate):
                earliestRetryDate = min(earliestRetryDate ?? retryDate, retryDate)
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
            case .blockedByFailure:
                encounteredFailure = true
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
            case .blockedByConflict:
                encounteredConflict = true
                blockedDependencyKeys.formUnion(dependencyKeys)
                blockedOperationIDs.insert(candidate.id)
            case .fatalProcessorFailure:
                state = .failed
                return
            }
        }

        if encounteredConflict {
            state = .conflict
        } else if encounteredFailure {
            state = .failed
        } else if let earliestRetryDate {
            state = .waitingForRetry(earliestRetryDate)
            scheduleRetry(at: earliestRetryDate)
        } else {
            state = queue.hasPendingChanges ? .failed : .idle
        }
    }

    private enum ProcessingOutcome {
        case completed
        case blockedForRetry(Date)
        case blockedByFailure
        case blockedByConflict
        case fatalProcessorFailure
    }

    private func process(
        _ candidate: PendingOfflineOperation,
        now: Date
    ) async -> ProcessingOutcome {
        var operation = candidate
        if operation.type == .recordMutation,
           let entityID = operation.entityID,
           let predecessor = queue.orderedOperations.last(where: {
               $0.sequenceNumber < operation.sequenceNumber &&
               $0.type == .recordMutation &&
               $0.entityType == operation.entityType &&
               $0.entityID == entityID &&
               $0.status == .synchronized &&
               $0.metadata["remoteRevision"] != nil
           }),
           let remoteRevision = predecessor.metadata["remoteRevision"] {
            // Multiple local saves can be queued before the first reaches the
            // server. Preserve their causal order by building each later save
            // on the revision returned for the preceding save.
            operation.baseRevision = remoteRevision
            do {
                operation.payload = try OfflineRecordMutationCodec.rebasingBaseRevision(
                    operation.payload,
                    to: remoteRevision,
                    decoder: Self.recordMutationDecoder,
                    encoder: Self.recordMutationEncoder
                )
            } catch {
                operation.status = .failed
                operation.failure = OfflineFailureDetails(
                    category: .validation,
                    code: "mutation_rebase_failed",
                    message: "PFSS could not safely prepare this queued change.",
                    isRetryable: false,
                    underlyingDescription: error.localizedDescription
                )
                operation.metadata["quarantinedAt"] = ISO8601DateFormatter()
                    .string(from: now)
                operation.metadata["quarantineReason"] =
                    "The mutation envelope could not be rebased."
                operation.metadata["quarantineActions"] =
                    "repair,retry,supersede,discard"
                try? queue.update(operation)
                return .blockedByFailure
            }
        }
        let attemptNumber = operation.attemptCount + 1
        let retryCycleBaseline = Int(
            operation.metadata["retryCycleBaseline"] ?? "0"
        ) ?? 0
        let retryCycleAttemptNumber = max(
            operation.attemptCount - retryCycleBaseline + 1,
            1
        )
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
            return .fatalProcessorFailure
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
                return .completed
            } catch {
                return .fatalProcessorFailure
            }

        case let .supersededByCloud(remoteRevision, cloudOperation):
            onOperationSupersededByCloud?(cloudOperation, remoteRevision)
            operation.status = .synchronized
            operation.synchronizedAt = completedAt
            operation.failure = nil
            operation.conflict = nil
            operation.nextRetryAt = nil
            operation.metadata["remoteRevision"] = remoteRevision
            operation.metadata["staleDeviceChangeDiscarded"] = "true"
            operation.retryAttempts[operation.retryAttempts.count - 1].outcome = .succeeded
            do {
                try queue.update(operation)
                lastProcessedOperationID = operation.id
                return .completed
            } catch {
                return .fatalProcessorFailure
            }

        case let .failed(failure):
            let reachedLimit = retryCycleAttemptNumber >= retryPolicy.maximumAttempts
            let canRetry = failure.isRetryable && !reachedLimit
            let delay = canRetry
                ? retryPolicy.delay(afterFailedAttempt: retryCycleAttemptNumber)
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
            if !canRetry {
                operation.metadata["quarantinedAt"] = ISO8601DateFormatter().string(from: completedAt)
                operation.metadata["quarantineReason"] = durableFailure.message
                operation.metadata["quarantineActions"] = "repair,retry,supersede,discard"
            }

            do {
                try queue.update(operation)
            } catch {
                return .fatalProcessorFailure
            }

            if let retryDate = operation.nextRetryAt {
                return .blockedForRetry(retryDate)
            } else {
                return .blockedByFailure
            }

        case let .conflicted(conflict):
            let automaticMergeCount = Int(
                operation.metadata["automaticConflictMergeCount"] ?? "0"
            ) ?? 0
            if case let .automaticallyMerged(resolvedConflict) =
                conflictResolver.evaluate(conflict, at: completedAt),
               let mergedVersion = resolvedConflict.mergedVersion,
               automaticMergeCount == 0 {
                operation.payload = mergedVersion.payload
                do {
                    try OfflineRecordMutationCodec.rebase(
                        &operation,
                        to: resolvedConflict.remoteVersion?.revision,
                        decoder: Self.recordMutationDecoder,
                        encoder: Self.recordMutationEncoder
                    )
                } catch {
                    operation.status = .failed
                    operation.failure = OfflineFailureDetails(
                        category: .validation,
                        code: "mutation_rebase_failed",
                        message: "PFSS could not safely prepare the merged change.",
                        isRetryable: false,
                        underlyingDescription: error.localizedDescription
                    )
                    try? queue.update(operation)
                    return .blockedByFailure
                }
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
                    return .fatalProcessorFailure
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
            operation.metadata["quarantinedAt"] = ISO8601DateFormatter().string(from: completedAt)
            operation.metadata["quarantineReason"] = "Synchronization conflict requires review."
            operation.metadata["quarantineActions"] = "repair,retry,supersede,discard"
            do {
                try queue.update(operation)
            } catch {
                return .fatalProcessorFailure
            }
            return .blockedByConflict
        }
    }

    private static let recordMutationEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let recordMutationDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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
