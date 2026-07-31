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
}
