//
//  PFSSArchiveFormatTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 16 Step 1 – Portable archive integrity and compatibility coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSArchiveFormatTests: XCTestCase {
    func testStoreArchiveRoundTripPreservesManifestAndPrimaryData() throws {
        let store = AppDataStore(persistenceEnabled: false)
        store.businessProfile.businessName = "Patriot Property Solutions"
        store.addEmployee(EmployeeRecord(
            firstName: "Owner",
            lastName: "Technician",
            role: .owner,
            roles: [.owner, .technician]
        ))
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let service = PFSSArchiveService(
            appVersion: "1.0",
            appBuild: "2"
        )

        let archiveData = try store.createPortableArchive(
            createdAt: createdAt,
            archiveService: service
        )
        let archive = try service.validateAndDecode(archiveData)

        XCTAssertEqual(archive.manifest.createdAt, createdAt)
        XCTAssertEqual(archive.manifest.businessName, "Patriot Property Solutions")
        XCTAssertEqual(archive.manifest.appVersion, "1.0")
        XCTAssertEqual(archive.manifest.appBuild, "2")
        XCTAssertEqual(archive.manifest.recordCounts.employees, 1)
        XCTAssertEqual(archive.payload.appData.employees.first?.roles, [.owner, .technician])
        XCTAssertEqual(archive.payload.pendingOperations.count, 0)
    }

    func testChangedPayloadFailsIntegrityValidation() throws {
        let store = AppDataStore(persistenceEnabled: false)
        let service = PFSSArchiveService()
        let archiveData = try store.createPortableArchive(
            archiveService: service
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: archiveData) as? [String: Any]
        )
        json["payload"] = Data("damaged".utf8).base64EncodedString()
        let damagedData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try service.validateAndDecode(damagedData)) {
            let archiveError = $0 as? PFSSArchiveError
            XCTAssertTrue(
                archiveError == .payloadSizeMismatch ||
                archiveError == .checksumMismatch
            )
        }
    }

    func testNewerSchemaIsRejectedBeforePayloadRestore() throws {
        let store = AppDataStore(persistenceEnabled: false)
        let service = PFSSArchiveService()
        let archiveData = try store.createPortableArchive(
            archiveService: service
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: archiveData) as? [String: Any]
        )
        var manifest = try XCTUnwrap(json["manifest"] as? [String: Any])
        manifest["dataSchemaVersion"] =
            PFSSArchiveConstants.currentDataSchemaVersion + 1
        json["manifest"] = manifest
        let futureArchiveData = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(
            try service.validateAndDecode(futureArchiveData)
        ) {
            XCTAssertEqual(
                $0 as? PFSSArchiveError,
                .newerDataSchema(
                    found: PFSSArchiveConstants.currentDataSchemaVersion + 1,
                    supported: PFSSArchiveConstants.currentDataSchemaVersion
                )
            )
        }
    }

    func testUnreadableFileIsRejectedWithoutAttemptingRestore() {
        let service = PFSSArchiveService()

        XCTAssertThrowsError(
            try service.validateAndDecode(Data("not an archive".utf8))
        ) {
            XCTAssertEqual($0 as? PFSSArchiveError, .unreadableArchive)
        }
    }
}
