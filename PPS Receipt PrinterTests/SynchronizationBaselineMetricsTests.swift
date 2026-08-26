//
//  SynchronizationBaselineMetricsTests.swift
//  PPS Receipt PrinterTests
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

final class SynchronizationBaselineMetricsTests: XCTestCase {
    func testCapturesQueueAgeStatusEntityRetriesAndFailures() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        var failed = operation(
            sequence: 1,
            entity: .job,
            entityID: UUID(),
            createdAt: now.addingTimeInterval(-120)
        )
        failed.status = .failed
        failed.failure = OfflineFailureDetails(
            category: .decoding,
            code: "invalid_payload",
            message: "Invalid payload",
            isRetryable: false,
            occurredAt: now
        )
        failed.retryAttempts = [
            OfflineRetryAttempt(attemptNumber: 1, startedAt: now)
        ]
        let pending = operation(
            sequence: 2,
            entity: .customer,
            entityID: UUID(),
            createdAt: now.addingTimeInterval(-30)
        )

        let snapshot = SynchronizationBaselineMetrics.capture(
            operations: [pending, failed],
            at: now
        )

        XCTAssertEqual(snapshot.totalOperations, 2)
        XCTAssertEqual(snapshot.actionableOperations, 2)
        XCTAssertEqual(snapshot.countsByStatus["failed"], 1)
        XCTAssertEqual(snapshot.countsByStatus["pending"], 1)
        XCTAssertEqual(snapshot.countsByEntity["job"], 1)
        XCTAssertEqual(snapshot.countsByEntity["customer"], 1)
        XCTAssertEqual(snapshot.countsByFailureCategory["decoding"], 1)
        XCTAssertEqual(snapshot.oldestActionableAgeSeconds, 120)
        XCTAssertEqual(snapshot.retryAttemptCount, 1)
        XCTAssertEqual(snapshot.schemaDecodeFailureCount, 1)
    }

    func testEstimatesOnlyUnrelatedWorkBlockedBehindPermanentFailure() throws {
        let jobID = UUID()
        var blocker = operation(
            sequence: 1,
            entity: .job,
            entityID: jobID
        )
        blocker.status = .failed
        blocker.failure = OfflineFailureDetails(
            category: .validation,
            message: "Rejected",
            isRetryable: false
        )
        let sameRecord = operation(
            sequence: 2,
            entity: .job,
            entityID: jobID
        )
        let unrelatedJob = operation(
            sequence: 3,
            entity: .job,
            entityID: UUID()
        )
        let unrelatedCustomer = operation(
            sequence: 4,
            entity: .customer,
            entityID: UUID()
        )

        let snapshot = SynchronizationBaselineMetrics.capture(
            operations: [blocker, sameRecord, unrelatedJob, unrelatedCustomer]
        )

        XCTAssertEqual(snapshot.estimatedHeadOfLineBlockedCount, 2)
    }

    func testTerminalHistoryDoesNotIncreaseActionableAgeOrBlockCount() throws {
        var synchronized = operation(
            sequence: 1,
            entity: .job,
            entityID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        synchronized.status = .synchronized
        let pending = operation(
            sequence: 2,
            entity: .site,
            entityID: UUID(),
            createdAt: Date(timeIntervalSince1970: 90)
        )

        let snapshot = SynchronizationBaselineMetrics.capture(
            operations: [synchronized, pending],
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.actionableOperations, 1)
        XCTAssertEqual(snapshot.oldestActionableAgeSeconds, 10)
        XCTAssertEqual(snapshot.estimatedHeadOfLineBlockedCount, 0)
    }

    private func operation(
        sequence: UInt64,
        entity: OfflineEntityType,
        entityID: UUID,
        createdAt: Date = Date()
    ) -> PendingOfflineOperation {
        PendingOfflineOperation(
            sequenceNumber: sequence,
            type: .recordMutation,
            entityType: entity,
            entityID: entityID,
            actionName: "upsertRecord",
            payload: OfflineOperationPayload(
                contentType: "application/json",
                body: Data("{}".utf8)
            ),
            createdAt: createdAt
        )
    }
}
