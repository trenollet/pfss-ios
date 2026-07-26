//
//  OfflineOperationQueueTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 2 – Persistent queue regression coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineOperationQueueTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("queue.json")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        directoryURL = nil
        fileURL = nil
    }

    func testQueueSurvivesNewInstanceAndPreservesOrder() throws {
        let persistence = DiskOfflineOperationQueuePersistence(fileURL: fileURL)
        let firstQueue = OfflineOperationQueue(persistence: persistence)
        let first = try firstQueue.enqueue(makeOperation(action: "arrive"))
        let second = try firstQueue.enqueue(makeOperation(action: "startWork"))

        let restoredQueue = OfflineOperationQueue(persistence: persistence)

        XCTAssertEqual(restoredQueue.orderedOperations.map(\.id), [first.id, second.id])
        XCTAssertEqual(restoredQueue.orderedOperations.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(restoredQueue.pendingCount, 2)
    }

    func testDuplicateIdempotencyKeyDoesNotCreateSecondOperation() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(fileURL: fileURL)
        )
        let original = makeOperation(
            action: "startTravel",
            idempotencyKey: "job-1-start-travel"
        )
        let duplicate = makeOperation(
            action: "startTravel",
            idempotencyKey: "job-1-start-travel"
        )

        let firstResult = try queue.enqueue(original)
        let duplicateResult = try queue.enqueue(duplicate)

        XCTAssertEqual(firstResult.id, duplicateResult.id)
        XCTAssertEqual(queue.operations.count, 1)
    }

    func testFailedPersistenceDoesNotPublishUnstoredMutation() throws {
        let persistence = ControllableQueuePersistence()
        let queue = OfflineOperationQueue(persistence: persistence)
        _ = try queue.enqueue(makeOperation(action: "arrive"))
        persistence.shouldFailSave = true

        XCTAssertThrowsError(
            try queue.enqueue(makeOperation(action: "startSetup"))
        )
        XCTAssertEqual(queue.operations.count, 1)
        XCTAssertNotNil(queue.lastPersistenceError)
    }

    func testMutableStateCanChangeButIdentityCannot() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(fileURL: fileURL)
        )
        var operation = try queue.enqueue(makeOperation(action: "pauseWork"))
        operation.status = .waitingForRetry
        operation.updatedAt = Date()
        try queue.update(operation)

        XCTAssertEqual(queue.operation(id: operation.id)?.status, .waitingForRetry)

        operation.idempotencyKey = "changed-key"
        XCTAssertThrowsError(try queue.update(operation)) { error in
            XCTAssertEqual(error as? OfflineOperationQueueError, .identityMismatch)
        }
    }

    func testCleanupOnlyRemovesOldTerminalOperations() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(fileURL: fileURL)
        )
        let oldDate = Date(timeIntervalSince1970: 1_000)
        var completed = try queue.enqueue(
            makeOperation(action: "complete", createdAt: oldDate)
        )
        completed.status = .synchronized
        completed.synchronizedAt = oldDate
        try queue.update(completed)
        _ = try queue.enqueue(makeOperation(action: "pending"))

        let removed = try queue.removeTerminalOperations(
            olderThan: oldDate.addingTimeInterval(1)
        )

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(queue.operations.count, 1)
        XCTAssertEqual(queue.operations.first?.actionName, "pending")
    }

    func testInterruptedSynchronizationReturnsToRetryableQueue() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(fileURL: fileURL)
        )
        var operation = try queue.enqueue(makeOperation(action: "arrive"))
        operation.status = .synchronizing
        operation.retryAttempts = [
            OfflineRetryAttempt(attemptNumber: 1)
        ]
        try queue.update(operation)
        let recoveryDate = Date(timeIntervalSince1970: 50_000)

        XCTAssertEqual(
            try queue.recoverInterruptedSynchronizations(at: recoveryDate),
            1
        )

        let recovered = try XCTUnwrap(queue.operation(id: operation.id))
        XCTAssertEqual(recovered.status, .waitingForRetry)
        XCTAssertEqual(recovered.nextRetryAt, recoveryDate)
        XCTAssertEqual(recovered.retryAttempts.last?.outcome, .deferred)
        XCTAssertTrue(recovered.failure?.isRetryable == true)
    }

    private func makeOperation(
        action: String,
        idempotencyKey: String? = nil,
        createdAt: Date = Date()
    ) -> PendingOfflineOperation {
        PendingOfflineOperation(
            idempotencyKey: idempotencyKey,
            type: .workflowAction,
            entityType: .job,
            entityID: UUID(),
            actionName: action,
            payload: OfflineOperationPayload(
                contentType: "test",
                body: Data(action.utf8)
            ),
            createdAt: createdAt
        )
    }
}

private final class ControllableQueuePersistence: OfflineOperationQueuePersistence {
    var data: Data?
    var shouldFailSave = false

    func load() throws -> Data? {
        data
    }

    func save(_ data: Data) throws {
        if shouldFailSave {
            throw OfflineOperationQueueError.unableToWrite("Test failure")
        }
        self.data = data
    }
}
