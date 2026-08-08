//
//  OfflineRecordNumberTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 18 Step 7 – Collision-resistant offline record identities.
//

import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OfflineRecordNumberTests: XCTestCase {
    func testDifferentOfflineDevicesCannotGenerateSameRecordNumbers() {
        let firstDefaults = makeDefaults(deviceID: "aaaaaaaa-0000-0000-0000-000000000001")
        let secondDefaults = makeDefaults(deviceID: "bbbbbbbb-0000-0000-0000-000000000002")
        let first = AppDataStore(
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false,
            cloudIdentityDefaults: firstDefaults
        )
        let second = AppDataStore(
            offlineSynchronizationMode: .queueRemoteOperations,
            persistenceEnabled: false,
            cloudIdentityDefaults: secondDefaults
        )
        let date = Date(timeIntervalSince1970: 1_786_147_200)

        XCTAssertEqual(first.generateCustomerNumber(), "PPS-AAAAAA-000001")
        XCTAssertEqual(second.generateCustomerNumber(), "PPS-BBBBBB-000001")
        XCTAssertEqual(first.generateJobNumber(for: date), "JOB-2608-AAAAAA-00001")
        XCTAssertEqual(second.generateJobNumber(for: date), "JOB-2608-BBBBBB-00001")
        XCTAssertNotEqual(first.generateLeadNumber(for: date), second.generateLeadNumber(for: date))
        XCTAssertNotEqual(first.generateEstimateNumber(for: date), second.generateEstimateNumber(for: date))
        XCTAssertNotEqual(first.generateInvoiceNumber(for: date), second.generateInvoiceNumber(for: date))
    }

    func testLocalOnlyNumberingRetainsOriginalFormat() {
        let store = AppDataStore(
            offlineSynchronizationMode: .localOnly,
            persistenceEnabled: false
        )
        let date = Date(timeIntervalSince1970: 1_786_147_200)

        XCTAssertEqual(store.generateCustomerNumber(), "PPS-000001")
        XCTAssertEqual(store.generateJobNumber(for: date), "JOB-2608-00001")
    }

    private func makeDefaults(deviceID: String) -> UserDefaults {
        let suiteName = "OfflineRecordNumberTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(deviceID, forKey: "PFSSCloudflareBetaDeviceID")
        return defaults
    }
}
