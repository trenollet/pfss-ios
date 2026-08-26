//
//  OfflineSynchronizationServiceTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 4 – Connectivity and processor coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineSynchronizationServiceTests: XCTestCase {
    func testPhase20QueueSurvivesReloadWithoutLosingSynchronizationEvidence() throws {
        let persistence = SynchronizationMemoryPersistence()
        let queue = OfflineOperationQueue(persistence: persistence)
        let pending = try queue.enqueue(makeOperation(action: "pending-change"))
        let retrying = try queue.enqueue(makeOperation(action: "retrying-change"))
        let conflicted = try queue.enqueue(makeOperation(action: "conflicted-change"))
        let retryDate = Date(timeIntervalSince1970: 1_786_000_000)

        try queue.mutate(id: retrying.id) { operation in
            let failure = OfflineFailureDetails(
                category: .server,
                code: "migration-fixture-retry",
                message: "Preserved retry evidence.",
                isRetryable: true,
                occurredAt: retryDate
            )
            operation.status = .waitingForRetry
            operation.baseRevision = "revision-before-retry"
            operation.failure = failure
            operation.nextRetryAt = retryDate.addingTimeInterval(60)
            operation.retryAttempts = [
                OfflineRetryAttempt(
                    attemptNumber: 1,
                    startedAt: retryDate,
                    completedAt: retryDate,
                    outcome: .deferred,
                    scheduledDelaySeconds: 60,
                    failure: failure
                )
            ]
            operation.metadata["dependencyKey"] = "job:migration-retry"
        }

        try queue.mutate(id: conflicted.id) { operation in
            let payload = OfflineOperationPayload(
                contentType: "migration-conflict",
                body: Data("preserved-conflict-version".utf8)
            )
            operation.status = .conflicted
            operation.baseRevision = "revision-before-conflict"
            operation.conflict = OfflineConflictInformation(
                kind: .concurrentModification,
                detectedAt: retryDate,
                localVersion: OfflineRecordVersion(
                    revision: "device-revision",
                    modifiedAt: retryDate,
                    source: .local,
                    payload: payload
                ),
                remoteVersion: OfflineRecordVersion(
                    revision: "server-revision",
                    modifiedAt: retryDate,
                    source: .remote,
                    payload: payload
                )
            )
            operation.metadata["prerequisiteOperationIDs"] = pending.id.uuidString
        }

        let beforeReload = queue.orderedOperations
        let reloaded = OfflineOperationQueue(persistence: persistence)

        XCTAssertNil(reloaded.lastPersistenceError)
        XCTAssertEqual(reloaded.orderedOperations, beforeReload)
        XCTAssertEqual(reloaded.operation(id: pending.id)?.idempotencyKey,
                       pending.idempotencyKey)
        XCTAssertEqual(reloaded.operation(id: retrying.id)?.retryAttempts.count, 1)
        XCTAssertEqual(reloaded.operation(id: retrying.id)?.baseRevision,
                       "revision-before-retry")
        XCTAssertEqual(reloaded.operation(id: conflicted.id)?.conflict?.remoteVersion?.revision,
                       "server-revision")
        XCTAssertEqual(reloaded.operation(id: conflicted.id)?.prerequisiteOperationIDs,
                       [pending.id])

        let afterMigration = try reloaded.enqueue(
            makeOperation(action: "created-after-reload")
        )
        XCTAssertEqual(afterMigration.sequenceNumber, 4)
        XCTAssertEqual(reloaded.orderedOperations.map(\.id), [
            pending.id, retrying.id, conflicted.id, afterMigration.id
        ])
    }

    func testProcessorSynchronizesOperationsInOriginalOrder() async throws {
        let queue = makeQueue()
        let first = try queue.enqueue(makeOperation(action: "travel"))
        let second = try queue.enqueue(makeOperation(action: "arrive"))
        let connectivity = TestConnectivityMonitor(status: .online)
        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, [first.id, second.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .synchronized)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .synchronized)
        XCTAssertEqual(service.state, .idle)
    }

    func testLaterMutationUsesRevisionReturnedForSameRecord() async throws {
        let queue = makeQueue()
        let entityID = UUID()
        let first = try queue.enqueue(PendingOfflineOperation(
            type: .recordMutation,
            entityType: .catalog,
            entityID: entityID,
            actionName: "upsertRecord",
            payload: OfflineOperationPayload(
                contentType: "test",
                body: Data("first".utf8)
            ),
            baseRevision: "original-revision"
        ))
        let second = try queue.enqueue(PendingOfflineOperation(
            type: .recordMutation,
            entityType: .catalog,
            entityID: entityID,
            actionName: "upsertRecord",
            payload: OfflineOperationPayload(
                contentType: "test",
                body: Data("second".utf8)
            ),
            baseRevision: "original-revision"
        ))
        let adapter = TestSynchronizationAdapter(results: [
            .synchronized(remoteRevision: "revision-after-first"),
            .synchronized(remoteRevision: "revision-after-second")
        ])
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedOperations.map(\.id), [first.id, second.id])
        XCTAssertEqual(
            adapter.receivedOperations.map(\.baseRevision),
            ["original-revision", "revision-after-first"]
        )
        XCTAssertEqual(
            queue.operation(id: second.id)?.metadata["remoteRevision"],
            "revision-after-second"
        )
    }

    func testOfflineProcessorLeavesPendingWorkUntouched() async throws {
        let queue = makeQueue()
        let operation = try queue.enqueue(makeOperation(action: "startWork"))
        let connectivity = TestConnectivityMonitor(status: .offline)
        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertTrue(adapter.receivedIDs.isEmpty)
        XCTAssertEqual(queue.operation(id: operation.id)?.status, .pending)
        XCTAssertEqual(service.state, .offline)
    }

    func testAuthoritativePullGateBlocksRetainedUploadUntilPullCompletes() async throws {
        let queue = makeQueue()
        let retained = try queue.enqueue(makeOperation(action: "retained-enrollment-work"))
        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter
        )

        service.requireAuthoritativePull()
        service.start()
        await service.processPendingOperations(forceRetry: true)

        XCTAssertTrue(adapter.receivedIDs.isEmpty)
        XCTAssertEqual(queue.operation(id: retained.id)?.status, .pending)

        service.completeAuthoritativePull()
        await service.processPendingOperations(forceRetry: true)

        XCTAssertEqual(adapter.receivedIDs, [retained.id])
        XCTAssertEqual(queue.operation(id: retained.id)?.status, .synchronized)
        service.stop()
    }

    func testReturningOnlineAutomaticallyProcessesPendingWork() async throws {
        let queue = makeQueue()
        let operation = try queue.enqueue(makeOperation(action: "arrive"))
        let connectivity = TestConnectivityMonitor(status: .offline)
        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )
        service.start()

        connectivity.setStatus(.online)
        for _ in 0..<20 where queue.operation(id: operation.id)?.status != .synchronized {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(adapter.receivedIDs, [operation.id])
        XCTAssertEqual(queue.operation(id: operation.id)?.status, .synchronized)
        service.stop()
    }

    func testRetryFailureIsDurableAndManualSyncCanRecover() async throws {
        let queue = makeQueue()
        let operation = try queue.enqueue(makeOperation(action: "pauseWork"))
        let connectivity = TestConnectivityMonitor(status: .online)
        let adapter = TestSynchronizationAdapter(
            results: [
                .failed(
                    OfflineFailureDetails(
                        category: .server,
                        code: "503",
                        message: "Temporarily unavailable.",
                        isRetryable: true
                    )
                ),
                .synchronized(remoteRevision: "revision-2")
            ]
        )
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter,
            retryPolicy: OfflineRetryPolicy(
                delays: [60],
                maximumAttempts: 3
            )
        )

        await service.processPendingOperations()
        var stored = try XCTUnwrap(queue.operation(id: operation.id))
        XCTAssertEqual(stored.status, .waitingForRetry)
        XCTAssertEqual(stored.retryAttempts.count, 1)
        XCTAssertEqual(stored.retryAttempts.first?.scheduledDelaySeconds, 60)
        XCTAssertNotNil(stored.nextRetryAt)

        await service.processPendingOperations(forceRetry: true)
        stored = try XCTUnwrap(queue.operation(id: operation.id))
        XCTAssertEqual(stored.status, .synchronized)
        XCTAssertEqual(stored.retryAttempts.count, 2)
        XCTAssertEqual(stored.metadata["remoteRevision"], "revision-2")
    }

    func testPermanentFailureDoesNotStopUnrelatedRecord() async throws {
        let queue = makeQueue()
        let first = try queue.enqueue(makeOperation(action: "completeWork"))
        let second = try queue.enqueue(makeOperation(action: "invoiceHandoff"))
        let connectivity = TestConnectivityMonitor(status: .online)
        let adapter = TestSynchronizationAdapter(
            results: [
                .failed(
                    OfflineFailureDetails(
                        category: .validation,
                        message: "Remote validation failed.",
                        isRetryable: false
                    )
                ),
                .synchronized(remoteRevision: "unrelated-revision")
            ]
        )
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, [first.id, second.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .failed)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .synchronized)
        XCTAssertEqual(
            queue.operation(id: first.id)?.metadata["quarantineActions"],
            "repair,retry,supersede,discard"
        )
        XCTAssertEqual(service.state, .failed)
    }

    func testPermanentFailureBlocksOnlyLaterOperationsForSameRecord() async throws {
        let queue = makeQueue()
        let recordID = UUID()
        let first = try queue.enqueue(makeOperation(action: "first", entityID: recordID))
        let sameRecord = try queue.enqueue(makeOperation(action: "same", entityID: recordID))
        let unrelated = try queue.enqueue(makeOperation(action: "other"))
        let adapter = TestSynchronizationAdapter(results: [
            .failed(OfflineFailureDetails(
                category: .validation,
                message: "Malformed operation.",
                isRetryable: false
            )),
            .synchronized(remoteRevision: "other-revision")
        ])
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, [first.id, unrelated.id])
        XCTAssertEqual(queue.operation(id: sameRecord.id)?.status, .pending)
        XCTAssertEqual(queue.operation(id: unrelated.id)?.status, .synchronized)
    }

    func testRetryDelayBlocksOnlyItsDependencyGroup() async throws {
        let queue = makeQueue()
        let recordID = UUID()
        var waiting = makeOperation(action: "waiting", entityID: recordID)
        waiting.status = .waitingForRetry
        waiting.nextRetryAt = Date().addingTimeInterval(3_600)
        let first = try queue.enqueue(waiting)
        let sameRecord = try queue.enqueue(makeOperation(action: "same", entityID: recordID))
        let unrelated = try queue.enqueue(makeOperation(action: "other"))
        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter
        )

        await service.processPendingOperations(now: Date())

        XCTAssertEqual(adapter.receivedIDs, [unrelated.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .waitingForRetry)
        XCTAssertEqual(queue.operation(id: sameRecord.id)?.status, .pending)
        XCTAssertEqual(service.state, .waitingForRetry(waiting.nextRetryAt!))
    }

    func testQuarantinedOperationCanBeExplicitlyDiscarded() throws {
        let queue = makeQueue()
        var operation = makeOperation(action: "invalid")
        operation.status = .failed
        operation.failure = OfflineFailureDetails(
            category: .validation,
            message: "Invalid data.",
            isRetryable: false
        )
        let stored = try queue.enqueue(operation)

        try queue.resolveQuarantinedOperation(
            id: stored.id,
            resolution: .discard,
            reason: "Confirmed obsolete during support review."
        )

        let discarded = try XCTUnwrap(queue.operation(id: stored.id))
        XCTAssertEqual(discarded.status, .cancelled)
        XCTAssertEqual(discarded.metadata["quarantineResolution"], "discarded")
        XCTAssertEqual(
            discarded.metadata["quarantineResolutionReason"],
            "Confirmed obsolete during support review."
        )
    }

    func testRepeatedManualSyncNeverDuplicatesSuccessfulOperation() async throws {
        let queue = makeQueue()
        let operation = try queue.enqueue(makeOperation(action: "routeChange"))
        let connectivity = TestConnectivityMonitor(status: .online)
        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )

        await service.processPendingOperations()
        await service.processPendingOperations(forceRetry: true)

        XCTAssertEqual(adapter.receivedIDs, [operation.id])
        XCTAssertEqual(queue.operation(id: operation.id)?.attemptCount, 1)
    }

    func testConcurrentSynchronizationSignalsSubmitEachOperationOnlyOnce() async throws {
        let queue = makeQueue()
        let operation = try queue.enqueue(makeOperation(action: "concurrent-signal"))
        let adapter = TestSynchronizationAdapter(delayNanoseconds: 20_000_000)
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter
        )

        async let launchSignal: Void = service.processPendingOperations()
        async let foregroundSignal: Void = service.processPendingOperations()
        _ = await (launchSignal, foregroundSignal)

        XCTAssertEqual(adapter.receivedIDs, [operation.id])
        XCTAssertEqual(queue.operation(id: operation.id)?.status, .synchronized)
        XCTAssertEqual(queue.operation(id: operation.id)?.attemptCount, 1)
    }

    func testExtendedOfflineQueueReloadsAndSynchronizesInStableOrder() async throws {
        let persistence = SynchronizationMemoryPersistence()
        let offlineQueue = OfflineOperationQueue(persistence: persistence)
        var expectedIDs: [UUID] = []
        for index in 0..<250 {
            let operation = try offlineQueue.enqueue(
                makeOperation(action: "offline-change-\(index)")
            )
            expectedIDs.append(operation.id)
        }

        let reloaded = OfflineOperationQueue(persistence: persistence)
        XCTAssertEqual(reloaded.orderedOperations.map(\.id), expectedIDs)
        XCTAssertEqual(Set(reloaded.orderedOperations.map(\.idempotencyKey)).count, 250)

        let adapter = TestSynchronizationAdapter()
        let service = OfflineSynchronizationService(
            queue: reloaded,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter
        )
        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, expectedIDs)
        XCTAssertTrue(reloaded.orderedOperations.allSatisfy { $0.status == .synchronized })
        XCTAssertTrue(reloaded.orderedOperations.allSatisfy { $0.attemptCount == 1 })
    }

    func testManualSyncRequeuesTransientTerminalFailureAndUnblocksQueue() async throws {
        let queue = makeQueue()
        let first = try queue.enqueue(makeOperation(action: "catalogUsage"))
        let second = try queue.enqueue(makeOperation(action: "jobUpdate"))
        let adapter = TestSynchronizationAdapter(results: [
            .failed(OfflineFailureDetails(
                category: .server,
                code: "403",
                message: "Operation synchronization failed (403).",
                isRetryable: true
            )),
            .synchronized(remoteRevision: "catalog-revision"),
            .synchronized(remoteRevision: "job-revision")
        ])
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: TestConnectivityMonitor(status: .online),
            adapter: adapter,
            retryPolicy: OfflineRetryPolicy(delays: [], maximumAttempts: 1)
        )

        await service.processPendingOperations()
        XCTAssertEqual(queue.operation(id: first.id)?.status, .failed)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .synchronized)

        service.syncNow()
        for _ in 0..<40 where queue.operation(id: first.id)?.status != .synchronized {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(adapter.receivedIDs, [first.id, second.id, first.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .synchronized)
        XCTAssertEqual(queue.operation(id: first.id)?.retryAttempts.count, 2)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .synchronized)
    }

    private func makeQueue() -> OfflineOperationQueue {
        OfflineOperationQueue(persistence: SynchronizationMemoryPersistence())
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
                contentType: "test",
                body: Data(action.utf8)
            )
        )
    }
}

@MainActor
private final class TestConnectivityMonitor: OfflineConnectivityMonitoring {
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
private final class TestSynchronizationAdapter: OfflineSynchronizationAdapter {
    private(set) var receivedOperations: [PendingOfflineOperation] = []
    var receivedIDs: [UUID] { receivedOperations.map(\.id) }
    private var results: [OfflineSynchronizationAdapterResult]
    private let delayNanoseconds: UInt64

    init(
        results: [OfflineSynchronizationAdapterResult] = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func synchronize(
        operation: PendingOfflineOperation
    ) async -> OfflineSynchronizationAdapterResult {
        receivedOperations.append(operation)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if results.isEmpty {
            return .synchronized(remoteRevision: nil)
        }
        return results.removeFirst()
    }
}

private final class SynchronizationMemoryPersistence: OfflineOperationQueuePersistence {
    private var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}
