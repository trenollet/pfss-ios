//
//  PFSSLocalBackupRestoreTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 16 Step 2 – Local backup and guarded restore coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSLocalBackupRestoreTests: XCTestCase {
    func testOwnerRecoveryBoundaryRejectsManagerAndMemberServiceCalls() throws {
        let owner = AppDataStore(persistenceEnabled: false)
        owner.updateCloudRole(.owner)
        owner.businessProfile.businessName = "Protected Company"
        let archive = try owner.createOwnerRecoveryArchive()
        XCTAssertNoThrow(try owner.inspectOwnerRecoveryArchive(archive))
        let ownerBackupDirectory = temporaryBackupDirectory()
        defer { try? FileManager.default.removeItem(at: ownerBackupDirectory) }
        owner.businessProfile.businessName = "Changed Company"
        XCTAssertNoThrow(
            try owner.restoreOwnerRecoveryArchive(
                archive,
                backupService: PFSSLocalBackupService(
                    directoryURL: ownerBackupDirectory
                )
            )
        )
        XCTAssertEqual(owner.businessProfile.businessName, "Protected Company")
        XCTAssertNoThrow(try owner.clearOwnerLocalData())
        XCTAssertTrue(owner.businessProfile.businessName.isEmpty)

        for role in [PFSSTenantRole.manager, .member] {
            let store = AppDataStore(persistenceEnabled: false)
            store.updateCloudRole(role)
            store.businessProfile.businessName = "Must Remain"
            XCTAssertThrowsError(try store.createOwnerRecoveryArchive())
            XCTAssertThrowsError(try store.inspectOwnerRecoveryArchive(archive))
            XCTAssertThrowsError(try store.restoreOwnerRecoveryArchive(archive))
            XCTAssertThrowsError(try store.clearOwnerLocalData())
            XCTAssertEqual(store.businessProfile.businessName, "Must Remain")
        }
    }

    func testManualBackupIsSavedListedAndReadable() throws {
        let directory = temporaryBackupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupService = PFSSLocalBackupService(directoryURL: directory)
        let data = Data("portable archive".utf8)
        let createdAt = Date(timeIntervalSince1970: 1_900_000_000)

        let saved = try backupService.save(
            data,
            kind: .manual,
            createdAt: createdAt
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.fileURL.path))
        XCTAssertEqual(try backupService.data(for: saved), data)
        XCTAssertEqual(backupService.availableBackups().map(\.fileURL), [saved.fileURL])
        XCTAssertEqual(backupService.availableBackups().first?.kind, .manual)
    }

    func testValidatedRestoreReplacesDataAndKeepsPreRestoreSafetyBackup() throws {
        let directory = temporaryBackupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupService = PFSSLocalBackupService(directoryURL: directory)
        let archiveService = PFSSArchiveService(
            appVersion: "16.2",
            appBuild: "1"
        )

        let sourceQueue = OfflineOperationQueue(
            persistence: Step2MemoryQueuePersistence()
        )
        let source = AppDataStore(
            offlineOperationQueue: sourceQueue,
            persistenceEnabled: false
        )
        source.businessProfile.businessName = "Restored Business"
        source.addEmployee(EmployeeRecord(
            firstName: "Cloud",
            lastName: "Owner",
            role: .owner,
            roles: [.owner]
        ))
        let queuedOperation = PendingOfflineOperation(
            idempotencyKey: "phase16-step2-queued-operation",
            type: .recordMutation,
            entityType: .customer,
            actionName: "restoreQueueCoverage",
            payload: try OfflineOperationPayload(["record": "customer"])
        )
        _ = try sourceQueue.enqueue(queuedOperation)
        let archiveData = try source.createPortableArchive(
            archiveService: archiveService
        )

        let targetQueue = OfflineOperationQueue(
            persistence: Step2MemoryQueuePersistence()
        )
        let target = AppDataStore(
            offlineOperationQueue: targetQueue,
            persistenceEnabled: false
        )
        target.businessProfile.businessName = "Current Business"
        target.addEmployee(EmployeeRecord(
            firstName: "Current",
            lastName: "Owner",
            role: .owner,
            roles: [.owner]
        ))

        let result = try target.restorePortableArchive(
            archiveData,
            archiveService: archiveService,
            backupService: backupService,
            restoredAt: Date(timeIntervalSince1970: 1_900_000_100)
        )

        XCTAssertEqual(target.businessProfile.businessName, "Restored Business")
        XCTAssertEqual(target.employees.first?.firstName, "Cloud")
        XCTAssertEqual(targetQueue.orderedOperations.map(\.actionName), [
            "restoreQueueCoverage"
        ])
        XCTAssertEqual(result.safetyBackup.kind, .preRestoreSafety)

        let safetyData = try backupService.data(for: result.safetyBackup)
        let safetyArchive = try archiveService.validateAndDecode(safetyData)
        XCTAssertEqual(
            safetyArchive.payload.appData.businessProfile.businessName,
            "Current Business"
        )
        XCTAssertEqual(
            safetyArchive.payload.appData.employees.first?.firstName,
            "Current"
        )
    }

    func testDamagedArchiveIsRejectedBeforeMutationOrSafetyBackup() throws {
        let directory = temporaryBackupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupService = PFSSLocalBackupService(directoryURL: directory)
        let store = AppDataStore(persistenceEnabled: false)
        store.businessProfile.businessName = "Protected Business"

        XCTAssertThrowsError(try store.restorePortableArchive(
            Data("damaged archive".utf8),
            backupService: backupService
        ))
        XCTAssertEqual(store.businessProfile.businessName, "Protected Business")
        XCTAssertTrue(backupService.availableBackups().isEmpty)
    }

    func testClearAllLocalDataResetsStoreAndPreservesBackupFiles() throws {
        let directory = temporaryBackupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupService = PFSSLocalBackupService(directoryURL: directory)
        let queue = OfflineOperationQueue(
            persistence: Step2MemoryQueuePersistence()
        )
        let store = AppDataStore(
            offlineOperationQueue: queue,
            persistenceEnabled: false
        )
        store.businessProfile.businessName = "Business To Clear"
        store.addEmployee(EmployeeRecord(
            firstName: "Owner",
            lastName: "To Clear",
            role: .owner,
            roles: [.owner]
        ))
        _ = try queue.enqueue(PendingOfflineOperation(
            type: .recordMutation,
            entityType: .employee,
            actionName: "clearCoverage",
            payload: try OfflineOperationPayload(["value": "pending"])
        ))
        let backupData = try store.createPortableArchive()
        let backup = try backupService.save(backupData, kind: .manual)

        try store.clearAllLocalData()

        XCTAssertTrue(store.businessProfile.businessName.isEmpty)
        XCTAssertTrue(store.customers.isEmpty)
        XCTAssertTrue(store.sites.isEmpty)
        XCTAssertTrue(store.leads.isEmpty)
        XCTAssertTrue(store.estimates.isEmpty)
        XCTAssertTrue(store.jobs.isEmpty)
        XCTAssertTrue(store.invoices.isEmpty)
        XCTAssertTrue(store.employees.isEmpty)
        XCTAssertTrue(store.serviceCatalogItems.isEmpty)
        XCTAssertTrue(store.recommendationRules.isEmpty)
        XCTAssertTrue(store.assignmentStore.assignments.isEmpty)
        XCTAssertTrue(queue.operations.isEmpty)
        XCTAssertEqual(try backupService.data(for: backup), backupData)
    }

    private func temporaryBackupDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PFSS-Step2-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}

private final class Step2MemoryQueuePersistence:
    OfflineOperationQueuePersistence {
    private var data: Data?

    func load() throws -> Data? { data }

    func save(_ data: Data) throws {
        self.data = data
    }
}
