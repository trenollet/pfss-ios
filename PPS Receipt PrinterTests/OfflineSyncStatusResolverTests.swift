//
//  OfflineSyncStatusResolverTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 6 – Status presentation coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineSyncStatusResolverTests: XCTestCase {
    func testLocalOnlyModeNeverClaimsRemoteSynchronization() {
        let queue = makeQueue()
        XCTAssertEqual(
            OfflineSyncStatusResolver.resolve(
                mode: .localOnly,
                queue: queue,
                connectivity: .online
            ),
            .savedOnDevice
        )
    }

    func testOfflinePendingChangesAreReportedAsSavedLocally() throws {
        let queue = makeQueue()
        try queue.enqueue(makeOperation(status: .pending))
        XCTAssertEqual(
            OfflineSyncStatusResolver.resolve(
                mode: .queueRemoteOperations,
                queue: queue,
                connectivity: .offline
            ),
            .offlineSavedLocally(pendingCount: 1)
        )
    }

    func testConflictTakesPriorityOverOtherQueueStates() throws {
        let queue = makeQueue()
        try queue.enqueue(makeOperation(status: .pending))
        try queue.enqueue(makeOperation(status: .conflicted))
        XCTAssertEqual(
            OfflineSyncStatusResolver.resolve(
                mode: .queueRemoteOperations,
                queue: queue,
                connectivity: .online
            ),
            .conflictRequiresReview(1)
        )
    }

    func testEmptyOnlineRemoteQueueIsFullySynchronized() {
        XCTAssertEqual(
            OfflineSyncStatusResolver.resolve(
                mode: .queueRemoteOperations,
                queue: makeQueue(),
                connectivity: .online
            ),
            .fullySynchronized
        )
    }

    private func makeQueue() -> OfflineOperationQueue {
        OfflineOperationQueue(persistence: SyncStatusMemoryPersistence())
    }

    private func makeOperation(
        status: OfflineOperationStatus
    ) -> PendingOfflineOperation {
        PendingOfflineOperation(
            type: .recordMutation,
            entityType: .job,
            entityID: UUID(),
            actionName: "test",
            payload: OfflineOperationPayload(
                contentType: "test",
                body: Data("test".utf8)
            ),
            status: status
        )
    }
}

private final class SyncStatusMemoryPersistence: OfflineOperationQueuePersistence {
    private var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}
