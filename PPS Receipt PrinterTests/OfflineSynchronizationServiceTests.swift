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

    func testPermanentFailureStopsLaterOperations() async throws {
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
                )
            ]
        )
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: connectivity,
            adapter: adapter
        )

        await service.processPendingOperations()

        XCTAssertEqual(adapter.receivedIDs, [first.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .failed)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .pending)
        XCTAssertEqual(service.state, .failed)
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
        XCTAssertEqual(queue.operation(id: second.id)?.status, .pending)

        service.syncNow()
        for _ in 0..<40 where queue.operation(id: second.id)?.status != .synchronized {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(adapter.receivedIDs, [first.id, first.id, second.id])
        XCTAssertEqual(queue.operation(id: first.id)?.status, .synchronized)
        XCTAssertEqual(queue.operation(id: first.id)?.retryAttempts.count, 2)
        XCTAssertEqual(queue.operation(id: second.id)?.status, .synchronized)
    }

    private func makeQueue() -> OfflineOperationQueue {
        OfflineOperationQueue(persistence: SynchronizationMemoryPersistence())
    }

    private func makeOperation(action: String) -> PendingOfflineOperation {
        PendingOfflineOperation(
            type: .workflowAction,
            entityType: .job,
            entityID: UUID(),
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

    init(results: [OfflineSynchronizationAdapterResult] = []) {
        self.results = results
    }

    func synchronize(
        operation: PendingOfflineOperation
    ) async -> OfflineSynchronizationAdapterResult {
        receivedOperations.append(operation)
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
