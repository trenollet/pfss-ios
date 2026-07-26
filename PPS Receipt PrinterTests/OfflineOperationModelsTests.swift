//
//  OfflineOperationModelsTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 15 Step 5 Part 1 – Offline model regression coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineOperationModelsTests: XCTestCase {
    private struct TestPayload: Codable, Equatable {
        var jobID: UUID
        var action: String
        var note: String
    }

    func testOperationRoundTripsWithoutLosingPayloadOrIdentity() throws {
        let value = TestPayload(
            jobID: UUID(),
            action: "startTravel",
            note: "Technician began travel offline."
        )
        let payload = try OfflineOperationPayload(value)
        let operation = PendingOfflineOperation(
            type: .workflowAction,
            entityType: .job,
            entityID: value.jobID,
            actionName: value.action,
            payload: payload
        )

        let encoded = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(
            PendingOfflineOperation.self,
            from: encoded
        )

        XCTAssertEqual(decoded, operation)
        XCTAssertEqual(
            try decoded.payload.decode(TestPayload.self),
            value
        )
        XCTAssertTrue(decoded.idempotencyKey.contains(operation.id.uuidString.lowercased()))
    }

    func testRetryHistoryAndDelayControlReadiness() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let retryDate = now.addingTimeInterval(30)
        let failure = OfflineFailureDetails(
            category: .connectivity,
            message: "Network unavailable.",
            isRetryable: true,
            occurredAt: now
        )
        let attempt = OfflineRetryAttempt(
            attemptNumber: 1,
            startedAt: now,
            completedAt: now,
            outcome: .failed,
            scheduledDelaySeconds: 30,
            failure: failure
        )
        let operation = PendingOfflineOperation(
            type: .jobNote,
            entityType: .job,
            actionName: "addNote",
            payload: try OfflineOperationPayload(["note": "Saved locally"]),
            status: .waitingForRetry,
            createdAt: now,
            nextRetryAt: retryDate,
            retryAttempts: [attempt],
            failure: failure
        )

        XCTAssertEqual(operation.attemptCount, 1)
        XCTAssertFalse(operation.isReadyToSynchronize(at: now))
        XCTAssertTrue(
            operation.isReadyToSynchronize(
                at: retryDate.addingTimeInterval(1)
            )
        )
    }

    func testConflictPreservesLocalAndRemoteVersions() throws {
        let localPayload = try OfflineOperationPayload(["note": "Local note"])
        let remotePayload = try OfflineOperationPayload(["note": "Remote note"])
        let localVersion = OfflineRecordVersion(
            revision: "local-2",
            modifiedAt: Date(timeIntervalSince1970: 2_000),
            source: .local,
            payload: localPayload
        )
        let remoteVersion = OfflineRecordVersion(
            revision: "remote-3",
            modifiedAt: Date(timeIntervalSince1970: 2_100),
            source: .remote,
            payload: remotePayload
        )
        let conflict = OfflineConflictInformation(
            kind: .concurrentModification,
            localVersion: localVersion,
            remoteVersion: remoteVersion
        )

        XCTAssertTrue(conflict.requiresHumanReview)
        XCTAssertEqual(conflict.localVersion.payload, localPayload)
        XCTAssertEqual(conflict.remoteVersion?.payload, remotePayload)
    }

    func testTerminalAndConflictStatusesCannotSynchronize() throws {
        let payload = try OfflineOperationPayload(["value": "test"])

        for status in [
            OfflineOperationStatus.synchronized,
            .cancelled,
            .synchronizing,
            .conflicted
        ] {
            let operation = PendingOfflineOperation(
                type: .recordMutation,
                entityType: .custom,
                actionName: "test",
                payload: payload,
                status: status
            )

            XCTAssertFalse(operation.isReadyToSynchronize(at: Date()))
        }
    }
}
