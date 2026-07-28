//
//  OfflineRecoveryTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 7 – Offline recovery and field resilience coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineRecoveryTests: XCTestCase {
    func testCompleteFieldWorkflowSurvivesOfflineRestartAndSynchronizesInOrder() async throws {
        let persistence = RecoveryMemoryPersistence()
        let firstQueue = OfflineOperationQueue(persistence: persistence)
        let jobID = UUID()
        let actions = [
            "startTravel",
            "markArrived",
            "startSetup",
            "startWork",
            "pauseWork",
            "resumeWork",
            "startPackUp",
            "finishWork",
            "createInvoice",
            "recordPayment",
            "completeJob"
        ]

        for action in actions {
            try firstQueue.enqueue(makeOperation(action: action, entityID: jobID))
        }

        let restoredQueue = OfflineOperationQueue(persistence: persistence)
        XCTAssertEqual(restoredQueue.orderedOperations.map(\.actionName), actions)

        let adapter = RecoveryAdapter()
        let service = OfflineSynchronizationService(
            queue: restoredQueue,
            connectivity: RecoveryConnectivity(status: .online),
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedActions, actions)
        XCTAssertTrue(restoredQueue.operations.allSatisfy { $0.status == .synchronized })
    }

    func testConnectionLossBetweenActionsResumesWithoutRepeatingCompletedWork() async throws {
        let queue = OfflineOperationQueue(persistence: RecoveryMemoryPersistence())
        let jobID = UUID()
        let first = try queue.enqueue(makeOperation(action: "startTravel", entityID: jobID))
        let second = try queue.enqueue(makeOperation(action: "markArrived", entityID: jobID))
        let third = try queue.enqueue(makeOperation(action: "startSetup", entityID: jobID))
        let connectivity = RecoveryConnectivity(status: .online)
        let adapter = RecoveryAdapter(connectivityToDropAfterFirstSubmission: connectivity)
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, [first.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .synchronized)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .pending)
        XCTAssertEqual(queue.operation(id: third.id)?.status, .pending)

        connectivity.setStatus(.online)
        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, [first.id, second.id, third.id])
        XCTAssertEqual(adapter.receivedIDs.filter { $0 == first.id }.count, 1)
        XCTAssertTrue(queue.operations.allSatisfy { $0.status == .synchronized })
    }

    func testInterruptedSynchronizationRecoversAfterAppRestart() throws {
        let persistence = RecoveryMemoryPersistence()
        let firstQueue = OfflineOperationQueue(persistence: persistence)
        let operation = try firstQueue.enqueue(makeOperation(action: "pauseWork"))
        let attemptStartedAt = Date(timeIntervalSince1970: 10_000)

        try firstQueue.mutate(id: operation.id) { stored in
            stored.status = .synchronizing
            stored.firstAttemptAt = attemptStartedAt
            stored.lastAttemptAt = attemptStartedAt
            stored.retryAttempts.append(
                OfflineRetryAttempt(
                    attemptNumber: 1,
                    startedAt: attemptStartedAt
                )
            )
        }

        let restoredQueue = OfflineOperationQueue(persistence: persistence)
        let recoveryTime = Date(timeIntervalSince1970: 10_030)
        XCTAssertEqual(
            try restoredQueue.recoverInterruptedSynchronizations(at: recoveryTime),
            1
        )

        let recovered = try XCTUnwrap(restoredQueue.operation(id: operation.id))
        XCTAssertEqual(recovered.status, .waitingForRetry)
        XCTAssertEqual(recovered.nextRetryAt, recoveryTime)
        XCTAssertEqual(recovered.failure?.code, "interrupted")
        XCTAssertEqual(recovered.retryAttempts.last?.outcome, .deferred)
        XCTAssertEqual(recovered.idempotencyKey, operation.idempotencyKey)
        XCTAssertEqual(recovered.sequenceNumber, operation.sequenceNumber)
    }

    func testRetryAfterRestartUsesSameIdentityAndCreatesNoDuplicateQueueEntry() async throws {
        let persistence = RecoveryMemoryPersistence()
        let firstQueue = OfflineOperationQueue(persistence: persistence)
        let operation = try firstQueue.enqueue(makeOperation(action: "routeChange"))
        let adapter = RecoveryAdapter(results: [
            .failed(
                OfflineFailureDetails(
                    category: .connectivity,
                    message: "Connection lost.",
                    isRetryable: true
                )
            ),
            .synchronized(remoteRevision: "remote-2")
        ])

        let firstService = OfflineSynchronizationService(
            queue: firstQueue,
            connectivity: RecoveryConnectivity(status: .online),
            adapter: adapter,
            retryPolicy: OfflineRetryPolicy(delays: [3_600], maximumAttempts: 3)
        )
        await firstService.processPendingOperations()

        let restoredQueue = OfflineOperationQueue(persistence: persistence)
        let restored = try XCTUnwrap(restoredQueue.operation(id: operation.id))
        XCTAssertEqual(restored.status, .waitingForRetry)
        XCTAssertEqual(restored.idempotencyKey, operation.idempotencyKey)

        let restoredService = OfflineSynchronizationService(
            queue: restoredQueue,
            connectivity: RecoveryConnectivity(status: .online),
            adapter: adapter
        )
        await restoredService.processPendingOperations(forceRetry: true)

        let synchronized = try XCTUnwrap(restoredQueue.operation(id: operation.id))
        XCTAssertEqual(restoredQueue.operations.count, 1)
        XCTAssertEqual(synchronized.status, .synchronized)
        XCTAssertEqual(synchronized.attemptCount, 2)
        XCTAssertEqual(synchronized.idempotencyKey, operation.idempotencyKey)
        XCTAssertEqual(adapter.receivedKeys, [operation.idempotencyKey, operation.idempotencyKey])
    }

    func testConflictAndBothRecordVersionsSurviveRestart() throws {
        let persistence = RecoveryMemoryPersistence()
        let firstQueue = OfflineOperationQueue(persistence: persistence)
        let operation = try firstQueue.enqueue(makeOperation(action: "updateNote"))
        let localPayload = try OfflineOperationPayload(["note": "Technician version"])
        let remotePayload = try OfflineOperationPayload(["note": "Office version"])
        let conflict = OfflineConflictInformation(
            kind: .concurrentModification,
            localVersion: OfflineRecordVersion(
                revision: "local-2",
                modifiedAt: Date(timeIntervalSince1970: 2_000),
                source: .local,
                payload: localPayload
            ),
            remoteVersion: OfflineRecordVersion(
                revision: "remote-3",
                modifiedAt: Date(timeIntervalSince1970: 2_100),
                source: .remote,
                payload: remotePayload
            )
        )

        try firstQueue.mutate(id: operation.id) { stored in
            stored.status = .conflicted
            stored.conflict = conflict
            stored.failure = OfflineFailureDetails(
                category: .conflict,
                message: "Human review required.",
                isRetryable: false
            )
        }

        let restoredQueue = OfflineOperationQueue(persistence: persistence)
        let restored = try XCTUnwrap(restoredQueue.operation(id: operation.id))
        XCTAssertEqual(restored.status, .conflicted)
        XCTAssertTrue(restored.conflict?.requiresHumanReview == true)
        XCTAssertEqual(restored.conflict?.localVersion.payload, localPayload)
        XCTAssertEqual(restored.conflict?.remoteVersion?.payload, remotePayload)
    }

    func testRepeatedQueueRestorePreservesStableOrderAndIdentity() throws {
        let persistence = RecoveryMemoryPersistence()
        var expectedIDs: [UUID] = []
        var queue = OfflineOperationQueue(persistence: persistence)

        for action in ["travel", "arrive", "work", "invoice", "payment"] {
            expectedIDs.append(try queue.enqueue(makeOperation(action: action)).id)
        }

        for _ in 0..<5 {
            queue = OfflineOperationQueue(persistence: persistence)
            XCTAssertEqual(queue.orderedOperations.map(\.id), expectedIDs)
            XCTAssertEqual(Set(queue.operations.map(\.id)).count, expectedIDs.count)
            XCTAssertEqual(Set(queue.operations.map(\.idempotencyKey)).count, expectedIDs.count)
        }
    }

    private func makeOperation(
        action: String,
        entityID: UUID = UUID()
    ) -> PendingOfflineOperation {
        PendingOfflineOperation(
            type: .workflowAction,
            entityType: .job,
            entityID: entityID,
            actionName: action,
            payload: OfflineOperationPayload(
                contentType: "phase15.recovery-test",
                body: Data(action.utf8)
            )
        )
    }
}

private final class RecoveryMemoryPersistence: OfflineOperationQueuePersistence {
    private var data: Data?

    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}

@MainActor
private final class RecoveryConnectivity: OfflineConnectivityMonitoring {
    private(set) var status: OfflineConnectivityStatus
    var onStatusChanged: ((OfflineConnectivityStatus) -> Void)?
    var isConnected: Bool { status == .online }

    init(status: OfflineConnectivityStatus) {
        self.status = status
    }

    func start() {}
    func stop() {}

    func setStatus(_ status: OfflineConnectivityStatus) {
        self.status = status
        onStatusChanged?(status)
    }
}

@MainActor
private final class RecoveryAdapter: OfflineSynchronizationAdapter {
    private(set) var receivedIDs: [UUID] = []
    private(set) var receivedActions: [String] = []
    private(set) var receivedKeys: [String] = []
    private var results: [OfflineSynchronizationAdapterResult]
    private weak var connectivityToDropAfterFirstSubmission: RecoveryConnectivity?

    init(
        results: [OfflineSynchronizationAdapterResult] = [],
        connectivityToDropAfterFirstSubmission: RecoveryConnectivity? = nil
    ) {
        self.results = results
        self.connectivityToDropAfterFirstSubmission = connectivityToDropAfterFirstSubmission
    }

    func synchronize(
        operation: PendingOfflineOperation
    ) async -> OfflineSynchronizationAdapterResult {
        receivedIDs.append(operation.id)
        receivedActions.append(operation.actionName)
        receivedKeys.append(operation.idempotencyKey)

        if receivedIDs.count == 1 {
            connectivityToDropAfterFirstSubmission?.setStatus(.offline)
        }

        if results.isEmpty {
            return .synchronized(remoteRevision: nil)
        }
        return results.removeFirst()
    }
}
