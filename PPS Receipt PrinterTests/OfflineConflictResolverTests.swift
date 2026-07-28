//
//  OfflineConflictResolverTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 5 – Conflict handling coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineConflictResolverTests: XCTestCase {
    func testIndependentFieldChangesMergeAutomatically() throws {
        let conflict = try makeConflict(
            base: ["note": "old", "status": "working"],
            local: ["note": "technician note", "status": "working"],
            remote: ["note": "old", "status": "completed"]
        )

        let evaluation = OfflineConflictResolver().evaluate(
            conflict,
            at: Date(timeIntervalSince1970: 4_000)
        )
        guard case let .automaticallyMerged(resolved) = evaluation else {
            return XCTFail("Independent changes should merge.")
        }

        let merged = try XCTUnwrap(resolved.mergedVersion?.payload)
        let value = try merged.decode([String: String].self)
        XCTAssertEqual(value["note"], "technician note")
        XCTAssertEqual(value["status"], "completed")
        XCTAssertEqual(resolved.resolution, .automaticallyMerged)
        XCTAssertFalse(resolved.requiresHumanReview)
    }

    func testCompetingFieldChangesPreserveBothAndRequireReview() throws {
        let conflict = try makeConflict(
            base: ["note": "old"],
            local: ["note": "field edit"],
            remote: ["note": "office edit"]
        )

        let evaluation = OfflineConflictResolver().evaluate(conflict)
        guard case let .requiresHumanReview(preserved, paths) = evaluation else {
            return XCTFail("Competing edits must require review.")
        }

        XCTAssertEqual(paths, ["note"])
        XCTAssertEqual(preserved.localVersion.payload, conflict.localVersion.payload)
        XCTAssertEqual(preserved.remoteVersion?.payload, conflict.remoteVersion?.payload)
    }

    func testKeepLocalResolutionIsAuditedAndReturnsOperationToQueue() throws {
        let queue = OfflineOperationQueue(
            persistence: ConflictMemoryPersistence()
        )
        let conflict = try makeConflict(
            base: ["note": "old"],
            local: ["note": "field edit"],
            remote: ["note": "office edit"]
        )
        var operation = makeOperation(payload: conflict.localVersion.payload)
        operation.status = .conflicted
        operation.conflict = conflict
        operation.failure = OfflineFailureDetails(
            category: .conflict,
            message: "Review required.",
            isRetryable: false
        )
        let stored = try queue.enqueue(operation)
        let employeeID = UUID()
        let timestamp = Date(timeIntervalSince1970: 5_000)

        try OfflineConflictResolutionService(queue: queue).resolve(
            operationID: stored.id,
            resolution: .keptLocal,
            employeeID: employeeID,
            note: "Technician confirmed the field note.",
            at: timestamp
        )

        let resolved = try XCTUnwrap(queue.operation(id: stored.id))
        XCTAssertEqual(resolved.status, .pending)
        XCTAssertNil(resolved.failure)
        XCTAssertEqual(resolved.conflict?.resolution, .keptLocal)
        XCTAssertEqual(resolved.conflict?.resolvedByEmployeeID, employeeID)
        XCTAssertEqual(resolved.conflict?.resolvedAt, timestamp)
        XCTAssertEqual(resolved.metadata["conflictResolution"], "keptLocal")
    }

    func testSynchronizationServiceResubmitsAutomaticMerge() async throws {
        let queue = OfflineOperationQueue(
            persistence: ConflictMemoryPersistence()
        )
        let operation = try queue.enqueue(makeOperation(payload: try payload(["note": "field"])))
        let conflict = try makeConflict(
            base: ["note": "old", "status": "working"],
            local: ["note": "field", "status": "working"],
            remote: ["note": "old", "status": "completed"]
        )
        let adapter = ConflictTestAdapter(results: [
            .conflicted(conflict),
            .synchronized(remoteRevision: "remote-3")
        ])
        let service = OfflineSynchronizationService(
            queue: queue,
            connectivity: ConflictConnectivityMonitor(),
            adapter: adapter
        )

        await service.processPendingOperations()

        let resolved = try XCTUnwrap(queue.operation(id: operation.id))
        XCTAssertEqual(adapter.receivedPayloads.count, 2)
        XCTAssertEqual(resolved.status, .synchronized)
        XCTAssertEqual(resolved.conflict?.resolution, .automaticallyMerged)
        XCTAssertEqual(resolved.metadata["remoteRevision"], "remote-3")
    }

    private func makeConflict(
        base: [String: String],
        local: [String: String],
        remote: [String: String]
    ) throws -> OfflineConflictInformation {
        OfflineConflictInformation(
            kind: .concurrentModification,
            localVersion: OfflineRecordVersion(
                revision: "local-2",
                modifiedAt: Date(timeIntervalSince1970: 2_000),
                source: .local,
                payload: try payload(local)
            ),
            baseVersion: OfflineRecordVersion(
                revision: "base-1",
                modifiedAt: Date(timeIntervalSince1970: 1_000),
                source: .remote,
                payload: try payload(base)
            ),
            remoteVersion: OfflineRecordVersion(
                revision: "remote-2",
                modifiedAt: Date(timeIntervalSince1970: 3_000),
                source: .remote,
                payload: try payload(remote)
            )
        )
    }

    private func payload(_ value: [String: String]) throws -> OfflineOperationPayload {
        try OfflineOperationPayload(value)
    }

    private func makeOperation(payload: OfflineOperationPayload) -> PendingOfflineOperation {
        PendingOfflineOperation(
            type: .recordMutation,
            entityType: .job,
            entityID: UUID(),
            actionName: "updateJob",
            payload: payload,
            baseRevision: "base-1"
        )
    }
}

private final class ConflictMemoryPersistence: OfflineOperationQueuePersistence {
    private var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}

@MainActor
private final class ConflictConnectivityMonitor: OfflineConnectivityMonitoring {
    var status: OfflineConnectivityStatus = .online
    var onStatusChanged: ((OfflineConnectivityStatus) -> Void)?
    var isConnected: Bool { true }
    func start() {}
    func stop() {}
}

@MainActor
private final class ConflictTestAdapter: OfflineSynchronizationAdapter {
    private(set) var receivedPayloads: [OfflineOperationPayload] = []
    private var results: [OfflineSynchronizationAdapterResult]

    init(results: [OfflineSynchronizationAdapterResult]) {
        self.results = results
    }

    func synchronize(
        operation: PendingOfflineOperation
    ) async -> OfflineSynchronizationAdapterResult {
        receivedPayloads.append(operation.payload)
        return results.removeFirst()
    }
}
