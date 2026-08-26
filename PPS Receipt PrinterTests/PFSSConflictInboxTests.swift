//
//  PFSSConflictInboxTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 16 – Central conflict inbox coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSConflictInboxTests: XCTestCase {
    func testInboxIncludesOnlyUnresolvedConflictsOldestFirst() {
        let older = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: "businessName, email"
        )
        let newer = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 200),
            fields: "phone"
        )
        var resolved = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 50),
            fields: "contactName"
        )
        resolved.conflict?.resolution = .keptRemote
        resolved.status = .synchronized

        let items = PFSSConflictInbox.unresolvedItems(
            in: [newer, resolved, older]
        )

        XCTAssertEqual(items.map(\.id), [older.id, newer.id])
        XCTAssertEqual(items[0].conflictingFields, ["businessName", "email"])
    }

    func testInboxUsesRecordFallbackWhenFieldMetadataIsUnavailable() {
        let operation = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: nil
        )

        let item = PFSSConflictInbox.unresolvedItems(in: [operation]).first

        XCTAssertEqual(item?.recordTitle, "Customer")
        XCTAssertEqual(item?.conflictingFields, [])
    }

    func testComparisonShowsDeviceAndCloudValuesForChangedFields() throws {
        struct Record: Codable {
            var name: String
            var phone: String
            var active: Bool
        }
        let entityID = UUID()
        let device = try recordPayload(
            Record(name: "Patriot Pool", phone: "555-1000", active: true),
            id: entityID
        )
        let cloud = try recordPayload(
            Record(name: "Patriot Pool", phone: "555-2000", active: false),
            id: entityID
        )
        var operation = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: nil
        )
        operation.payload = device
        operation.conflict = OfflineConflictInformation(
            kind: .concurrentModification,
            localVersion: OfflineRecordVersion(
                modifiedAt: Date(timeIntervalSince1970: 100),
                source: .local,
                payload: device
            ),
            remoteVersion: OfflineRecordVersion(
                modifiedAt: Date(timeIntervalSince1970: 100),
                source: .remote,
                payload: cloud
            )
        )

        let comparisons = PFSSConflictComparisonEngine.comparisons(
            for: operation
        )

        XCTAssertEqual(comparisons.map(\.fieldPath), ["active", "phone"])
        XCTAssertEqual(comparisons[0].deviceValue, "Yes")
        XCTAssertEqual(comparisons[0].cloudValue, "No")
        XCTAssertEqual(comparisons[1].deviceValue, "555-1000")
        XCTAssertEqual(comparisons[1].cloudValue, "555-2000")
    }

    func testComparisonUsesCommonBaseAndHidesIndependentCloudChange() throws {
        struct Record: Codable {
            var name: String
            var phone: String
        }
        let entityID = UUID()
        let base = Record(name: "Original", phone: "555-1000")
        let device = try versionedRecordPayload(
            Record(name: "Original", phone: "555-2000"),
            base: base,
            id: entityID,
            changedFields: ["phone"]
        )
        let cloud = try recordPayload(
            Record(name: "Cloud Name", phone: "555-3000"),
            id: entityID
        )
        var operation = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: "phone"
        )
        operation.entityID = entityID
        operation.payload = device
        operation.conflict = OfflineConflictInformation(
            kind: .concurrentModification,
            localVersion: OfflineRecordVersion(
                modifiedAt: Date(timeIntervalSince1970: 100),
                source: .local,
                payload: device
            ),
            remoteVersion: OfflineRecordVersion(
                modifiedAt: Date(timeIntervalSince1970: 100),
                source: .remote,
                payload: cloud
            )
        )

        let comparisons = PFSSConflictComparisonEngine.comparisons(for: operation)

        XCTAssertEqual(comparisons.map(\.fieldPath), ["phone"])
        XCTAssertEqual(comparisons[0].baseValue, "555-1000")
        XCTAssertEqual(comparisons[0].deviceValue, "555-2000")
        XCTAssertEqual(comparisons[0].cloudValue, "555-3000")
        XCTAssertFalse(comparisons[0].operationalImpact.isEmpty)
    }

    func testQuarantineInboxContainsOnlyServerBackedUnresolvedItems() {
        var serverItem = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: nil
        )
        serverItem.status = .failed
        serverItem.metadata["serverQuarantineID"] = UUID().uuidString
        serverItem.metadata["serverQuarantineStatus"] = "unresolved"
        serverItem.metadata["quarantinedAt"] = "1970-01-01T00:01:40Z"
        var localOnly = serverItem
        localOnly.id = UUID()
        localOnly.metadata.removeValue(forKey: "serverQuarantineID")
        var resolved = serverItem
        resolved.id = UUID()
        resolved.metadata["serverQuarantineID"] = UUID().uuidString
        resolved.metadata["serverQuarantineStatus"] = "resolved"
        resolved.metadata["quarantineResolvedAt"] = "1970-01-01T00:02:00Z"

        let items = PFSSQuarantineInbox.unresolvedItems(
            in: [localOnly, resolved, serverItem]
        )

        XCTAssertEqual(items.map(\.id), [serverItem.id])
    }

    func testManagerOnlyAssignmentFailureUsesPlainLanguageExplanation() {
        let explanation = SynchronizationIssueExplanation.explain(
            failure: OfflineFailureDetails(
                category: .authorization,
                code: "technician_assignment_change_requires_manager",
                message: "PFSS rejected this change: technician_assignment_change_requires_manager.",
                isRetryable: false
            ),
            entityType: .assignment
        )

        XCTAssertEqual(
            explanation.title,
            "A Manager Must Approve This Assignment Change"
        )
        XCTAssertTrue(explanation.summary.contains("who is assigned"))
        XCTAssertFalse(explanation.summary.contains("technician_assignment"))
        XCTAssertEqual(
            explanation.technicalCode,
            "technician_assignment_change_requires_manager"
        )
    }

    func testQuarantineDetectsRecordThatAlreadyMatchesCloud() {
        let entityID = UUID()
        let payload = OfflineOperationPayload(
            contentType: "application/json",
            body: Data(#"{"priority":2}"#.utf8)
        )
        let deviceOperation = PendingOfflineOperation(
            type: .recordMutation,
            entityType: .assignment,
            entityID: entityID,
            actionName: "upsertRecord",
            payload: payload
        )
        let cloudOperation = PendingOfflineOperation(
            type: .recordMutation,
            entityType: .assignment,
            entityID: entityID,
            actionName: "upsertRecord",
            payload: payload
        )
        let quarantine = PFSSCloudflareSynchronizationQuarantine(
            id: UUID().uuidString,
            operationID: deviceOperation.id,
            entityType: .assignment,
            entityID: entityID,
            sourceMemberID: UUID().uuidString,
            sourceDeviceID: UUID().uuidString,
            operation: deviceOperation,
            cloudOperation: cloudOperation,
            cloudRevision: "revision-1",
            failure: .init(reason: "Manager approval required."),
            policyVersion: 1,
            detectedAt: Date(),
            affectedFields: ["crew"],
            operationalImpact: "Assignment review"
        )

        XCTAssertTrue(quarantine.alreadyMatchesCloudRecord)
    }

    @MainActor
    func testSourceRetryReceiptClearsDeliveryIdentityAndIsAppliedOnlyOnce() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quarantine-\(UUID()).json")
            )
        )
        let store = AppDataStore(
            offlineOperationQueue: queue,
            persistenceEnabled: false
        )
        var operation = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: nil
        )
        operation.status = .failed
        operation.metadata["quarantinedAt"] = "1970-01-01T00:01:40Z"
        operation.metadata["serverQuarantineID"] = UUID().uuidString
        let stored = try queue.enqueue(operation)
        let receipt = PFSSCloudflareQuarantineResolutionReceipt(
            id: UUID().uuidString,
            operationID: stored.id,
            action: "retry",
            reason: "Manager requested another validated synchronization attempt.",
            resolvedAt: Date(timeIntervalSince1970: 200)
        )

        store.applyServerQuarantineResolutionReceipts([receipt])
        store.applyServerQuarantineResolutionReceipts([receipt])

        let resolved = try XCTUnwrap(queue.operation(id: stored.id))
        XCTAssertEqual(resolved.status, .pending)
        XCTAssertNil(resolved.metadata["serverQuarantineID"])
        XCTAssertEqual(
            resolved.metadata["appliedQuarantineResolutionID"],
            receipt.id
        )
    }

    @MainActor
    func testServerQuarantinePreservesOperationIdentityForRetry() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quarantine-identity-\(UUID()).json")
            )
        )
        let store = AppDataStore(
            offlineOperationQueue: queue,
            persistenceEnabled: false
        )
        var deviceOperation = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: "scheduling,updatedDate"
        )
        deviceOperation.payload = try OfflineRecordMutationCodec.envelopePayload(
            operationID: deviceOperation.id,
            entityType: deviceOperation.entityType,
            entityID: try XCTUnwrap(deviceOperation.entityID),
            recordData: Data("{}".utf8),
            modifiedAt: Date(timeIntervalSince1970: 100),
            baseRevision: nil,
            mutationKind: .domainCommand,
            changedFields: ["scheduling", "updatedDate"],
            commandName: "assignment.reschedule",
            encoder: AppDataStore.recordSynchronizationEncoder
        )
        let originalOperationID = deviceOperation.id
        let originalIdempotencyKey = deviceOperation.idempotencyKey
        var corruptedOperation = deviceOperation
        corruptedOperation.id = UUID()
        corruptedOperation.idempotencyKey =
            "server-quarantine-\(corruptedOperation.id.uuidString.lowercased())"
        let quarantineID = UUID().uuidString
        let item = PFSSCloudflareSynchronizationQuarantine(
            id: quarantineID,
            operationID: corruptedOperation.id,
            entityType: corruptedOperation.entityType,
            entityID: corruptedOperation.entityID,
            sourceMemberID: UUID().uuidString,
            sourceDeviceID: UUID().uuidString,
            operation: corruptedOperation,
            cloudOperation: nil,
            cloudRevision: nil,
            failure: .init(reason: "Manager approval required."),
            policyVersion: 1,
            detectedAt: Date(timeIntervalSince1970: 200),
            affectedFields: ["scheduling", "updatedDate"],
            operationalImpact: "Assignment review"
        )

        try store.reconcileServerQuarantineInbox([item])

        let quarantined = try XCTUnwrap(queue.operation(id: originalOperationID))
        XCTAssertEqual(quarantined.id, originalOperationID)
        XCTAssertEqual(quarantined.idempotencyKey, originalIdempotencyKey)
        XCTAssertEqual(quarantined.metadata["serverQuarantineID"], quarantineID)

        store.applyServerQuarantineResolutionReceipts([
            PFSSCloudflareQuarantineResolutionReceipt(
                id: quarantineID,
                operationID: originalOperationID,
                action: "retry",
                reason: "Manager requested another synchronization attempt.",
                resolvedAt: Date(timeIntervalSince1970: 300)
            )
        ])

        let retried = try XCTUnwrap(queue.operation(id: originalOperationID))
        XCTAssertEqual(retried.status, .pending)
        XCTAssertEqual(retried.id, originalOperationID)
        XCTAssertEqual(retried.idempotencyKey, originalIdempotencyKey)
    }

    @MainActor
    func testSourceReceiptFallsBackToServerQuarantineIdentity() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quarantine-fallback-\(UUID()).json")
            )
        )
        let store = AppDataStore(
            offlineOperationQueue: queue,
            persistenceEnabled: false
        )
        var operation = makeConflict(
            detectedAt: Date(timeIntervalSince1970: 100),
            fields: nil
        )
        operation.status = .failed
        let quarantineID = UUID().uuidString
        operation.metadata["quarantinedAt"] = "1970-01-01T00:01:40Z"
        operation.metadata["serverQuarantineID"] = quarantineID
        operation.metadata["appliedQuarantineResolutionID"] = quarantineID
        let stored = try queue.enqueue(operation)
        let receipt = PFSSCloudflareQuarantineResolutionReceipt(
            id: quarantineID,
            operationID: UUID(),
            action: "discard",
            reason: "Manager confirmed this duplicate change is unnecessary.",
            resolvedAt: Date(timeIntervalSince1970: 200)
        )

        store.applyServerQuarantineResolutionReceipts([receipt])

        let resolved = try XCTUnwrap(queue.operation(id: stored.id))
        XCTAssertEqual(resolved.status, .cancelled)
        XCTAssertEqual(resolved.metadata["quarantineResolution"], "discarded")
        XCTAssertEqual(
            resolved.metadata["appliedQuarantineResolutionID"],
            quarantineID
        )
    }

    private func makeConflict(
        detectedAt: Date,
        fields: String?
    ) -> PendingOfflineOperation {
        let payload = OfflineOperationPayload(
            contentType: "application/json",
            body: Data("{}".utf8)
        )
        var metadata: [String: String] = [:]
        metadata["conflictingPaths"] = fields
        return PendingOfflineOperation(
            type: .recordMutation,
            entityType: .customer,
            entityID: UUID(),
            actionName: "upsertRecord",
            payload: payload,
            status: .conflicted,
            conflict: OfflineConflictInformation(
                kind: .concurrentModification,
                detectedAt: detectedAt,
                localVersion: OfflineRecordVersion(
                    modifiedAt: detectedAt,
                    source: .local,
                    payload: payload
                ),
                remoteVersion: OfflineRecordVersion(
                    modifiedAt: detectedAt,
                    source: .remote,
                    payload: payload
                )
            ),
            metadata: metadata
        )
    }

    private func recordPayload<Record: Encodable>(
        _ record: Record,
        id: UUID
    ) throws -> OfflineOperationPayload {
        let recordData = try AppDataStore.recordSynchronizationEncoder.encode(
            record
        )
        return try OfflineOperationPayload(
            OfflineRecordMutationPayload(
                entityType: .customer,
                entityID: id,
                recordData: recordData,
                modifiedAt: Date(timeIntervalSince1970: 100)
            ),
            encoder: AppDataStore.recordSynchronizationEncoder
        )
    }

    private func versionedRecordPayload<Record: Encodable>(
        _ record: Record,
        base: Record,
        id: UUID,
        changedFields: [String]
    ) throws -> OfflineOperationPayload {
        let operationID = UUID()
        return try OfflineRecordMutationCodec.envelopePayload(
            operationID: operationID,
            entityType: .customer,
            entityID: id,
            recordData: AppDataStore.recordSynchronizationEncoder.encode(record),
            baseRecordData: AppDataStore.recordSynchronizationEncoder.encode(base),
            modifiedAt: Date(timeIntervalSince1970: 100),
            baseRevision: "base-revision",
            mutationKind: .fieldPatch,
            changedFields: changedFields,
            encoder: AppDataStore.recordSynchronizationEncoder
        )
    }
}
