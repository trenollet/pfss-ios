//
//  PFSSICloudArchiveServiceTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 16 Step 3 – iCloud archive transport coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSICloudArchiveServiceTests: XCTestCase {
    func testAvailableTransportUploadsListsAndReadsNewestArchive() throws {
        let container = temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let transport = PFSSICloudDriveArchiveTransport(
            retainedBackupCount: 10,
            containerURLProvider: { container },
            identityAvailable: { true }
        )
        let olderData = Data("older".utf8)
        let newerData = Data("newer".utf8)

        _ = try transport.upload(
            olderData,
            createdAt: Date(timeIntervalSince1970: 1_900_001_000)
        )
        _ = try transport.upload(
            newerData,
            createdAt: Date(timeIntervalSince1970: 1_900_001_100)
        )
        let archives = try transport.availableArchives()

        XCTAssertEqual(transport.availability(), .available)
        XCTAssertEqual(archives.count, 2)
        XCTAssertEqual(try transport.data(for: archives[0]), newerData)
        XCTAssertEqual(try transport.data(for: archives[1]), olderData)
    }

    func testRetentionRemovesOldestCloudBackup() throws {
        let container = temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let transport = PFSSICloudDriveArchiveTransport(
            retainedBackupCount: 2,
            containerURLProvider: { container },
            identityAvailable: { true }
        )

        for offset in 0..<3 {
            _ = try transport.upload(
                Data("backup-\(offset)".utf8),
                createdAt: Date(timeIntervalSince1970: 1_900_002_000 + Double(offset))
            )
        }

        let archives = try transport.availableArchives()
        XCTAssertEqual(archives.count, 2)
        XCTAssertEqual(try transport.data(for: archives[0]), Data("backup-2".utf8))
        XCTAssertEqual(try transport.data(for: archives[1]), Data("backup-1".utf8))
    }

    func testSignedOutTransportCannotReadOrWriteContainer() {
        let transport = PFSSICloudDriveArchiveTransport(
            containerURLProvider: { nil },
            identityAvailable: { false }
        )

        XCTAssertEqual(transport.availability(), .signedOut)
        XCTAssertThrowsError(try transport.availableArchives()) {
            XCTAssertEqual($0 as? PFSSICloudArchiveError, .signedOut)
        }
        XCTAssertThrowsError(try transport.upload(Data())) {
            XCTAssertEqual($0 as? PFSSICloudArchiveError, .signedOut)
        }
    }

    func testICloudArchiveStillUsesValidatedPortableContract() throws {
        let container = temporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let transport = PFSSICloudDriveArchiveTransport(
            containerURLProvider: { container },
            identityAvailable: { true }
        )
        let store = AppDataStore(persistenceEnabled: false)
        store.businessProfile.businessName = "iCloud Test Business"
        let archiveService = PFSSArchiveService()
        let data = try store.createPortableArchive(archiveService: archiveService)

        let uploaded = try transport.upload(data)
        let downloaded = try transport.data(for: uploaded)
        let validated = try archiveService.validateAndDecode(downloaded)

        XCTAssertEqual(
            validated.payload.appData.businessProfile.businessName,
            "iCloud Test Business"
        )
    }

    private func temporaryContainer() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PFSS-iCloud-Step3-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
