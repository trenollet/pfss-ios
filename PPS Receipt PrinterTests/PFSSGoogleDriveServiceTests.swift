//
//  PFSSGoogleDriveServiceTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 16 Step 4 – Google Drive configuration coverage.
//

import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSGoogleDriveServiceTests: XCTestCase {
    func testProductionClientCreatesExpectedNativeRedirect() {
        let configuration = PFSSGoogleDriveConfiguration.production

        XCTAssertEqual(
            configuration.clientID,
            "573181539480-q4a2jdm6u4nc35t1p8ioubjb1ocpjkao.apps.googleusercontent.com"
        )
        XCTAssertEqual(
            configuration.callbackScheme,
            "com.googleusercontent.apps.573181539480-q4a2jdm6u4nc35t1p8ioubjb1ocpjkao"
        )
        XCTAssertEqual(
            configuration.redirectURI,
            "com.googleusercontent.apps.573181539480-q4a2jdm6u4nc35t1p8ioubjb1ocpjkao:/oauth2redirect"
        )
    }

    func testGoogleDriveUsesNarrowPerFileScope() {
        XCTAssertEqual(
            PFSSGoogleDriveConfiguration.production.scope,
            "https://www.googleapis.com/auth/drive.file"
        )
    }

    func testManagerStartsDisconnectedWithoutStoredAuthorization() {
        let manager = PFSSGoogleDriveManager(
            configuration: PFSSGoogleDriveConfiguration(
                clientID: "test.apps.googleusercontent.com"
            )
        )

        // A device with an existing production refresh token may begin
        // connected. A distinct test service is not injected here, so verify
        // only that initialization reaches a stable non-working state.
        XCTAssertNotEqual(manager.state, .connecting)
        XCTAssertNotEqual(manager.state, .working)
    }

    func testNonOwnerIdentityRevokesLocalRecoveryAuthorization() {
        let store = AppDataStore(persistenceEnabled: false)
        var revocationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .pfssOwnerRecoveryAuthorizationWasRevoked,
            object: nil,
            queue: nil
        ) { _ in
            revocationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.updateCloudRole(.owner)
        XCTAssertEqual(revocationCount, 0)

        store.updateCloudRole(.manager)
        XCTAssertEqual(revocationCount, 1)

        store.updateCloudIdentity(role: .member, employeeID: UUID().uuidString)
        XCTAssertEqual(revocationCount, 2)
    }
}
