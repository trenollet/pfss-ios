import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSSynchronizationDiagnosticsTests: XCTestCase {
    func testCollectorIncludesIdentifiersButNeverRecordPayload() throws {
        let queue = OfflineOperationQueue(
            persistence: DiskOfflineOperationQueuePersistence(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("diagnostics-\(UUID()).json")
            )
        )
        let store = AppDataStore(
            offlineOperationQueue: queue,
            persistenceEnabled: false
        )
        let recordID = UUID()
        var operation = PendingOfflineOperation(
            type: .recordMutation,
            entityType: .customer,
            entityID: recordID,
            actionName: "upsertRecord",
            payload: OfflineOperationPayload(
                contentType: "application/json",
                body: Data(#"{"customerName":"Must Never Leave Device"}"#.utf8)
            ),
            status: .failed,
            failure: OfflineFailureDetails(
                category: .validation,
                code: "invalid_domain_command",
                message: "Technical failure.",
                isRetryable: false
            )
        )
        operation.metadata["serverQuarantineID"] = "quarantine-123"
        operation.metadata["quarantineReason"] = "Potentially sensitive detail"
        let stored = try queue.enqueue(operation)
        let session = PFSSCloudflareSession(
            tenant: .init(id: "tenant-1", displayName: "Test Company"),
            member: .init(
                id: "member-1",
                displayName: "Test User",
                email: "test@example.com",
                role: .member,
                employeeID: nil
            ),
            device: .init(id: "device-1", displayName: "Test iPad")
        )

        let diagnostic = PFSSSynchronizationDiagnosticCollector.make(
            store: store,
            session: session,
            description: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = try XCTUnwrap(
            String(data: encoder.encode(diagnostic), encoding: .utf8)
        )

        XCTAssertTrue(text.contains(stored.id.uuidString.lowercased()))
        XCTAssertTrue(text.contains(recordID.uuidString.lowercased()))
        XCTAssertTrue(text.contains("invalid_domain_command"))
        XCTAssertTrue(text.contains("quarantine-123"))
        XCTAssertFalse(text.contains("Must Never Leave Device"))
        XCTAssertFalse(text.contains("Potentially sensitive detail"))
        XCTAssertFalse(text.contains("\"payload\""))
        XCTAssertFalse(text.contains("\"body\""))
    }
}
