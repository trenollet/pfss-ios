//
//  SynchronizationBaselineMetrics.swift
//  PPS Receipt Printer
//
//  Phase 20 Step 1 – Repeatable pre-migration synchronization baseline.
//

import Foundation

struct SynchronizationBaselineSnapshot: Codable, Equatable {
    var capturedAt: Date
    var totalOperations: Int
    var actionableOperations: Int
    var countsByStatus: [String: Int]
    var countsByEntity: [String: Int]
    var countsByFailureCategory: [String: Int]
    var oldestActionableAgeSeconds: TimeInterval?
    var retryAttemptCount: Int
    var conflictCount: Int
    var schemaDecodeFailureCount: Int
    var estimatedHeadOfLineBlockedCount: Int
}

enum SynchronizationBaselineMetrics {
    nonisolated static func capture(
        operations: [PendingOfflineOperation],
        at timestamp: Date = Date()
    ) -> SynchronizationBaselineSnapshot {
        let ordered = operations.sorted {
            if $0.sequenceNumber != $1.sequenceNumber {
                return $0.sequenceNumber < $1.sequenceNumber
            }
            return $0.createdAt < $1.createdAt
        }
        let actionable = ordered.filter {
            $0.status != .synchronized && $0.status != .cancelled
        }

        let statusCounts = Dictionary(
            grouping: ordered,
            by: { $0.status.rawValue }
        ).mapValues(\.count)
        let entityCounts = Dictionary(
            grouping: ordered,
            by: { $0.entityType.rawValue }
        ).mapValues(\.count)
        let failureCounts = Dictionary(
            grouping: ordered.compactMap(\.failure?.category.rawValue),
            by: { $0 }
        ).mapValues(\.count)

        let oldestAge = actionable.map {
            max(timestamp.timeIntervalSince($0.createdAt), 0)
        }.max()
        let schemaFailures = actionable.filter {
            $0.failure?.category == .decoding ||
            $0.conflict?.kind == .incompatibleSchema
        }.count

        return SynchronizationBaselineSnapshot(
            capturedAt: timestamp,
            totalOperations: ordered.count,
            actionableOperations: actionable.count,
            countsByStatus: statusCounts,
            countsByEntity: entityCounts,
            countsByFailureCategory: failureCounts,
            oldestActionableAgeSeconds: oldestAge,
            retryAttemptCount: ordered.reduce(0) {
                $0 + $1.retryAttempts.count
            },
            conflictCount: actionable.filter {
                $0.status == .conflicted
            }.count,
            schemaDecodeFailureCount: schemaFailures,
            estimatedHeadOfLineBlockedCount: blockedCount(in: actionable)
        )
    }

    /// Measures the cost of the current global queue rule. It intentionally
    /// counts only later operations that do not target the blocking record.
    nonisolated private static func blockedCount(
        in operations: [PendingOfflineOperation]
    ) -> Int {
        guard let blockerIndex = operations.firstIndex(where: isBlocker),
              blockerIndex < operations.index(before: operations.endIndex) else {
            return 0
        }
        let blocker = operations[blockerIndex]
        return operations[operations.index(after: blockerIndex)...].filter {
            $0.entityType != blocker.entityType ||
            $0.entityID != blocker.entityID
        }.count
    }

    nonisolated private static func isBlocker(
        _ operation: PendingOfflineOperation
    ) -> Bool {
        if operation.status == .conflicted { return true }
        if operation.status == .failed,
           operation.failure?.isRetryable == false {
            return true
        }
        return false
    }
}
