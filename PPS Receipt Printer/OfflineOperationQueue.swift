//
//  OfflineOperationQueue.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 5 Part 2 – Atomically persisted offline operation queue.
//

import Combine
import Foundation

enum OfflineOperationQueueError: LocalizedError, Equatable {
    case duplicateIdentifier(UUID)
    case identityMismatch
    case operationNotFound(UUID)
    case unableToCreateStorageDirectory(String)
    case unableToRead(String)
    case unableToDecode(String)
    case unableToEncode(String)
    case unableToWrite(String)

    var errorDescription: String? {
        switch self {
        case let .duplicateIdentifier(id):
            return "An offline operation already uses identifier \(id)."
        case .identityMismatch:
            return "An offline operation's durable identity cannot be changed."
        case let .operationNotFound(id):
            return "Offline operation \(id) was not found."
        case let .unableToCreateStorageDirectory(message):
            return "Unable to create offline queue storage: \(message)"
        case let .unableToRead(message):
            return "Unable to read the offline queue: \(message)"
        case let .unableToDecode(message):
            return "Unable to decode the offline queue: \(message)"
        case let .unableToEncode(message):
            return "Unable to encode the offline queue: \(message)"
        case let .unableToWrite(message):
            return "Unable to save the offline queue: \(message)"
        }
    }
}

/// Queue persistence is isolated behind a protocol so tests and future storage
/// migrations do not change the public queue API.
protocol OfflineOperationQueuePersistence {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct DiskOfflineOperationQueuePersistence: OfflineOperationQueuePersistence {
    static let defaultFileName = "pfss-offline-operation-queue.json"

    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw OfflineOperationQueueError.unableToRead(
                error.localizedDescription
            )
        }
    }

    func save(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw OfflineOperationQueueError.unableToCreateStorageDirectory(
                error.localizedDescription
            )
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw OfflineOperationQueueError.unableToWrite(
                error.localizedDescription
            )
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupport
            .appendingPathComponent("PFSS", isDirectory: true)
            .appendingPathComponent(defaultFileName)
    }
}

private struct OfflineOperationQueueSnapshot: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var savedAt: Date
    var nextSequenceNumber: UInt64
    var operations: [PendingOfflineOperation]

    init(
        savedAt: Date = Date(),
        nextSequenceNumber: UInt64,
        operations: [PendingOfflineOperation]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.nextSequenceNumber = nextSequenceNumber
        self.operations = operations
    }
}

/// Single source of truth for actions awaiting remote synchronization.
/// Every successful mutation is written atomically before the method returns.
@MainActor
final class OfflineOperationQueue: ObservableObject {
    @Published private(set) var operations: [PendingOfflineOperation] = []
    @Published private(set) var lastPersistenceError: OfflineOperationQueueError?

    private let persistence: any OfflineOperationQueuePersistence
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var nextSequenceNumber: UInt64 = 1

    init(
        persistence: (any OfflineOperationQueuePersistence)? = nil
    ) {
        self.persistence = persistence ?? DiskOfflineOperationQueuePersistence()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        loadPersistedQueue()
    }

    var orderedOperations: [PendingOfflineOperation] {
        operations.sorted(by: Self.queueOrder)
    }

    var actionableOperations: [PendingOfflineOperation] {
        orderedOperations.filter { !$0.status.isTerminal }
    }

    var pendingCount: Int {
        actionableOperations.count
    }

    var hasPendingChanges: Bool {
        !actionableOperations.isEmpty
    }

    func operation(id: UUID) -> PendingOfflineOperation? {
        operations.first { $0.id == id }
    }

    func operation(idempotencyKey: String) -> PendingOfflineOperation? {
        operations.first { $0.idempotencyKey == idempotencyKey }
    }

    /// Adds an operation exactly once. Re-enqueuing the same idempotency key
    /// returns the existing operation without modifying or duplicating it.
    @discardableResult
    func enqueue(
        _ operation: PendingOfflineOperation
    ) throws -> PendingOfflineOperation {
        if let existing = self.operation(
            idempotencyKey: operation.idempotencyKey
        ) {
            return existing
        }

        guard self.operation(id: operation.id) == nil else {
            throw OfflineOperationQueueError.duplicateIdentifier(operation.id)
        }

        var queued = operation
        queued.sequenceNumber = nextSequenceNumber
        nextSequenceNumber += 1

        var candidate = operations
        candidate.append(queued)
        try commit(candidate)
        return queued
    }

    /// Replaces mutable synchronization state while protecting the operation's
    /// id, idempotency key, and queue order.
    func update(_ operation: PendingOfflineOperation) throws {
        guard let index = operations.firstIndex(where: {
            $0.id == operation.id
        }) else {
            throw OfflineOperationQueueError.operationNotFound(operation.id)
        }

        let existing = operations[index]
        guard existing.idempotencyKey == operation.idempotencyKey,
              existing.sequenceNumber == operation.sequenceNumber else {
            throw OfflineOperationQueueError.identityMismatch
        }

        var candidate = operations
        candidate[index] = operation
        try commit(candidate)
    }

    func mutate(
        id: UUID,
        _ mutation: (inout PendingOfflineOperation) -> Void
    ) throws {
        guard var operation = operation(id: id) else {
            throw OfflineOperationQueueError.operationNotFound(id)
        }

        mutation(&operation)
        try update(operation)
    }

    func remove(id: UUID) throws {
        guard operations.contains(where: { $0.id == id }) else {
            throw OfflineOperationQueueError.operationNotFound(id)
        }

        try commit(operations.filter { $0.id != id })
    }

    /// Replaces the complete durable queue during a validated backup restore.
    /// Identity and idempotency checks run before the persisted queue changes.
    func replaceAll(
        with restoredOperations: [PendingOfflineOperation]
    ) throws {
        let duplicateIDs = Dictionary(
            grouping: restoredOperations,
            by: \.id
        ).filter { $0.value.count > 1 }
        guard duplicateIDs.isEmpty else {
            throw OfflineOperationQueueError.duplicateIdentifier(
                duplicateIDs.keys.first!
            )
        }

        let duplicateKeys = Dictionary(
            grouping: restoredOperations,
            by: \.idempotencyKey
        ).filter { $0.value.count > 1 }
        guard duplicateKeys.isEmpty else {
            throw OfflineOperationQueueError.identityMismatch
        }

        let previousNextSequence = nextSequenceNumber
        let highestSequence = restoredOperations
            .map(\.sequenceNumber)
            .max() ?? 0
        nextSequenceNumber = highestSequence + 1
        do {
            try commit(restoredOperations)
        } catch {
            nextSequenceNumber = previousNextSequence
            throw error
        }
    }

    /// Removes completed queue history older than the supplied date. Active,
    /// failed, and conflicted operations are never removed by this cleanup.
    @discardableResult
    func removeTerminalOperations(olderThan date: Date) throws -> Int {
        let retained = operations.filter { operation in
            guard operation.status.isTerminal else { return true }
            let terminalDate = operation.synchronizedAt ?? operation.updatedAt
            return terminalDate >= date
        }
        let removedCount = operations.count - retained.count

        if removedCount > 0 {
            try commit(retained)
        }

        return removedCount
    }

    /// Reloads the durable snapshot. Primarily useful for recovery diagnostics;
    /// normal app startup loads automatically in `init`.
    func reload() {
        loadPersistedQueue()
    }

    /// Returns operations left in-flight by an app termination or connectivity
    /// interruption to a retryable state without changing their identity/order.
    @discardableResult
    func recoverInterruptedSynchronizations(
        at timestamp: Date = Date()
    ) throws -> Int {
        var candidate = operations
        var recoveredCount = 0

        for index in candidate.indices where candidate[index].status == .synchronizing {
            recoveredCount += 1
            candidate[index].status = .waitingForRetry
            candidate[index].updatedAt = timestamp
            candidate[index].nextRetryAt = timestamp
            let failure = OfflineFailureDetails(
                category: .connectivity,
                code: "interrupted",
                message: "Synchronization was interrupted and will be retried.",
                isRetryable: true,
                occurredAt: timestamp
            )
            candidate[index].failure = failure
            if let attemptIndex = candidate[index].retryAttempts.indices.last,
               candidate[index].retryAttempts[attemptIndex].completedAt == nil {
                candidate[index].retryAttempts[attemptIndex].completedAt = timestamp
                candidate[index].retryAttempts[attemptIndex].outcome = .deferred
                candidate[index].retryAttempts[attemptIndex].failure = failure
            }
        }

        if recoveredCount > 0 {
            try commit(candidate)
        }
        return recoveredCount
    }

    /// Reopens transient terminal failures for a user-requested retry. The
    /// existing attempts remain intact for support/audit history, while the
    /// retry baseline starts a fresh bounded retry cycle.
    @discardableResult
    func requeueTransientFailures(
        at timestamp: Date = Date()
    ) throws -> Int {
        let transientCategories: Set<OfflineFailureCategory> = [
            .connectivity,
            .timeout,
            .authentication,
            .authorization,
            .server,
            .decoding,
            .unknown
        ]
        var candidate = operations
        var requeuedCount = 0

        for index in candidate.indices where candidate[index].status == .failed {
            guard let failure = candidate[index].failure,
                  transientCategories.contains(failure.category) else {
                continue
            }

            requeuedCount += 1
            candidate[index].status = .pending
            candidate[index].updatedAt = timestamp
            candidate[index].nextRetryAt = nil
            candidate[index].failure = nil
            candidate[index].metadata["retryCycleBaseline"] = String(
                candidate[index].retryAttempts.count
            )
        }

        if requeuedCount > 0 {
            try commit(candidate)
        }
        return requeuedCount
    }

    private func commit(
        _ candidate: [PendingOfflineOperation]
    ) throws {
        let ordered = candidate.sorted(by: Self.queueOrder)
        let snapshot = OfflineOperationQueueSnapshot(
            nextSequenceNumber: nextSequenceNumber,
            operations: ordered
        )

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            let queueError = OfflineOperationQueueError.unableToEncode(
                error.localizedDescription
            )
            lastPersistenceError = queueError
            throw queueError
        }

        do {
            try persistence.save(data)
        } catch let queueError as OfflineOperationQueueError {
            lastPersistenceError = queueError
            throw queueError
        } catch {
            let queueError = OfflineOperationQueueError.unableToWrite(
                error.localizedDescription
            )
            lastPersistenceError = queueError
            throw queueError
        }

        operations = ordered
        lastPersistenceError = nil
    }

    private func loadPersistedQueue() {
        do {
            guard let data = try persistence.load() else {
                operations = []
                nextSequenceNumber = 1
                lastPersistenceError = nil
                return
            }

            let snapshot: OfflineOperationQueueSnapshot
            do {
                snapshot = try decoder.decode(
                    OfflineOperationQueueSnapshot.self,
                    from: data
                )
            } catch {
                throw OfflineOperationQueueError.unableToDecode(
                    error.localizedDescription
                )
            }

            operations = snapshot.operations.sorted(by: Self.queueOrder)
            let highestSequence = operations.map(\.sequenceNumber).max() ?? 0
            nextSequenceNumber = max(
                snapshot.nextSequenceNumber,
                highestSequence + 1
            )
            lastPersistenceError = nil
        } catch let queueError as OfflineOperationQueueError {
            operations = []
            nextSequenceNumber = 1
            lastPersistenceError = queueError
        } catch {
            operations = []
            nextSequenceNumber = 1
            lastPersistenceError = .unableToRead(error.localizedDescription)
        }
    }

    private static func queueOrder(
        _ lhs: PendingOfflineOperation,
        _ rhs: PendingOfflineOperation
    ) -> Bool {
        if lhs.sequenceNumber != rhs.sequenceNumber {
            return lhs.sequenceNumber < rhs.sequenceNumber
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
