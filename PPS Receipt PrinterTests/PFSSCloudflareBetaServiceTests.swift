//
//  PFSSCloudflareBetaServiceTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 16 Step 5 – Cloudflare beta client boundary coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSCloudflareBetaServiceTests: XCTestCase {
    func testEmployeeApplicationRolesDetermineInvitationAccess() {
        let technician = EmployeeRecord(
            firstName: "Field",
            lastName: "Technician",
            roles: [.technician, .salesperson]
        )
        let manager = EmployeeRecord(
            firstName: "Operations",
            lastName: "Manager",
            roles: [.manager, .technician]
        )
        let owner = EmployeeRecord(
            firstName: "Company",
            lastName: "Owner",
            roles: [.owner]
        )

        XCTAssertEqual(
            PFSSEmployeeAccessRolePolicy.invitationRole(for: technician),
            .member
        )
        XCTAssertEqual(
            PFSSEmployeeAccessRolePolicy.invitationRole(for: manager),
            .manager
        )
        XCTAssertNil(
            PFSSEmployeeAccessRolePolicy.invitationRole(for: owner)
        )
    }

    func testBuiltInEndpointIsTheProductionHTTPSWorker() throws {
        let manager = PFSSCloudflareBetaManager(
            defaults: isolatedDefaults(),
            credentialStore: TestCloudflareCredentialStore()
        )

        XCTAssertEqual(
            manager.savedEndpoint,
            "https://pfss-beta-api.timrenollet.workers.dev"
        )
        XCTAssertEqual(URL(string: manager.savedEndpoint)?.scheme, "https")
    }

    func testFreshManagerUsesBuiltInEndpointWithoutTenantCredential() {
        let manager = PFSSCloudflareBetaManager(
            defaults: isolatedDefaults(),
            credentialStore: TestCloudflareCredentialStore()
        )

        XCTAssertEqual(manager.state, .notEnrolled)
        XCTAssertFalse(manager.isEnrolled)
        XCTAssertEqual(
            manager.savedEndpoint,
            "https://pfss-beta-api.timrenollet.workers.dev"
        )
    }

    func testCloudflareAdapterNeverAcceptsTenantIdentifier() {
        let configuration = PFSSCloudflareBetaConfiguration(
            endpoint: URL(string: "https://pfss-beta.example.workers.dev")!
        )
        let adapter = PFSSCloudflareSynchronizationAdapter(
            configuration: configuration,
            deviceToken: "device-token"
        )

        // Construction requires only a server address and a device credential.
        // There is intentionally no tenant parameter for a caller to spoof.
        XCTAssertNotNil(adapter)
    }

    func testSessionDecodesServerResolvedMembershipWithoutTenantIdentifier() throws {
        let data = Data(
            """
            {
              "tenant": { "displayName": "PFSS Development" },
              "member": {
                "id": "member-1",
                "displayName": "Development Owner",
                "role": "owner"
              },
              "device": { "id": "device-1", "displayName": "Test iPhone" }
            }
            """.utf8
        )

        let session = try JSONDecoder().decode(
            PFSSCloudflareSession.self,
            from: data
        )

        XCTAssertEqual(session.tenant.displayName, "PFSS Development")
        XCTAssertEqual(session.member.role, .owner)
        XCTAssertEqual(session.member.role.title, "Owner")
        XCTAssertEqual(session.device.displayName, "Test iPhone")
    }

    func testRoleAuthorityKeepsMemberAdministrationRestricted() {
        XCTAssertTrue(PFSSTenantRole.owner.canManageAccess)
        XCTAssertTrue(PFSSTenantRole.manager.canManageAccess)
        XCTAssertFalse(PFSSTenantRole.member.canManageAccess)
        XCTAssertTrue(PFSSTenantRole.owner.canManageRecovery)
        XCTAssertFalse(PFSSTenantRole.manager.canManageRecovery)
        XCTAssertFalse(PFSSTenantRole.member.canManageRecovery)
    }

    func testAuthenticatedEmployeeIdentityDrivesNonOwnerUserInfo() {
        let employee = EmployeeRecord(
            firstName: "Geoff",
            lastName: "Nordmeyer",
            roles: [.salesperson, .technician]
        )
        let store = AppDataStore(persistenceEnabled: false)
        store.addEmployee(employee)

        store.updateCloudIdentity(
            role: .member,
            employeeID: employee.id.uuidString
        )
        XCTAssertTrue(store.shouldPresentAuthenticatedUserInfo)
        XCTAssertFalse(store.shouldPresentAdminDashboardTile)
        XCTAssertEqual(store.authenticatedCloudEmployee?.id, employee.id)
        XCTAssertEqual(
            store.authenticatedCloudEmployee?.roleDisplayText,
            "Sales, Technician"
        )
        XCTAssertTrue(store.usesAuthenticatedMyDayIdentity)
        XCTAssertEqual(store.authenticatedMyDayEmployee?.id, employee.id)

        let salesperson = EmployeeRecord(
            firstName: "Sales",
            lastName: "Only",
            roles: [.salesperson]
        )
        store.addEmployee(salesperson)
        store.updateCloudIdentity(
            role: .member,
            employeeID: salesperson.id.uuidString
        )
        XCTAssertNil(store.authenticatedMyDayEmployee)

        store.updateCloudIdentity(role: .owner, employeeID: nil)
        XCTAssertFalse(store.shouldPresentAuthenticatedUserInfo)
        XCTAssertTrue(store.shouldPresentAdminDashboardTile)
        XCTAssertNil(store.authenticatedCloudEmployee)
        XCTAssertFalse(store.usesAuthenticatedMyDayIdentity)
        XCTAssertNil(store.authenticatedMyDayEmployee)
    }

    func testAuthenticatedEmployeeIdentitySurvivesRelaunchUntilCompanyRemoval() {
        let defaults = isolatedDefaults()
        let employee = EmployeeRecord(
            firstName: "Persistent",
            lastName: "Technician",
            roles: [.technician]
        )
        let firstStore = AppDataStore(
            persistenceEnabled: false,
            cloudIdentityDefaults: defaults
        )
        firstStore.updateCloudIdentity(
            role: .member,
            employeeID: employee.id.uuidString
        )

        let relaunchedStore = AppDataStore(
            persistenceEnabled: false,
            cloudIdentityDefaults: defaults
        )
        relaunchedStore.addEmployee(employee)
        XCTAssertEqual(relaunchedStore.cloudRole, .member)
        XCTAssertEqual(relaunchedStore.authenticatedCloudEmployee?.id, employee.id)
        XCTAssertEqual(
            relaunchedStore.authenticatedCloudEmployee?.roleDisplayText,
            "Technician"
        )

        relaunchedStore.clearCachedCloudIdentity()
        let removedStore = AppDataStore(
            persistenceEnabled: false,
            cloudIdentityDefaults: defaults
        )
        XCTAssertNil(removedStore.cloudEmployeeID)
        XCTAssertNil(removedStore.authenticatedCloudEmployee)
    }

    func testOwnerIdentityFallsBackToUniqueVerifiedEmployeeEmail() {
        let employee = EmployeeRecord(
            firstName: "Timothy",
            lastName: "Renollet",
            email: "tim@example.com",
            roles: [.owner, .technician]
        )
        let store = AppDataStore(persistenceEnabled: false)
        store.addEmployee(employee)

        store.updateCloudIdentity(
            role: .owner,
            employeeID: nil,
            displayName: "Timothy Renollet",
            email: " TIM@EXAMPLE.COM "
        )

        XCTAssertEqual(store.authenticatedCloudEmployee?.id, employee.id)
        XCTAssertTrue(store.updateAuthenticatedJobTimerReminderPreferences(
            JobTimerReminderPreferences(
                arrivalToSetupMinutes: 3,
                setupToWorkMinutes: 10
            )
        ))
        XCTAssertEqual(
            store.authenticatedCloudEmployee?.jobTimerReminderPreferences,
            JobTimerReminderPreferences(
                arrivalToSetupMinutes: 3,
                setupToWorkMinutes: 10
            )
        )
    }

    func testMemberDeviceAndInvitationContractsDecode() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let member = try decoder.decode(
            PFSSTenantMember.self,
            from: Data(
                """
                {
                  "id": "member-1",
                  "employeeID": "employee-1",
                  "displayName": "Field Manager",
                  "role": "manager",
                  "status": "active",
                  "createdAt": "2030-01-02T12:00:00Z",
                  "activatedAt": "2030-01-02T12:01:00Z"
                }
                """.utf8
            )
        )
        let device = try decoder.decode(
            PFSSTenantDevice.self,
            from: Data(
                """
                {
                  "id": "device-1",
                  "displayName": "Manager iPhone",
                  "memberID": "member-1",
                  "memberName": "Field Manager",
                  "role": "manager",
                  "createdAt": "2030-01-02T12:00:00Z",
                  "lastSeenAt": "2030-01-02T12:05:00Z",
                  "revokedAt": null
                }
                """.utf8
            )
        )
        let invitation = try decoder.decode(
            PFSSTenantInvitation.self,
            from: Data(
                """
                {
                  "memberID": "member-2",
                  "employeeID": "employee-2",
                  "enrollmentCode": "PFSS-single-use",
                  "expiresAt": "2030-01-09T12:00:00Z"
                }
                """.utf8
            )
        )

        XCTAssertEqual(member.role, .manager)
        XCTAssertEqual(member.employeeID, "employee-1")
        XCTAssertEqual(member.status, .active)
        XCTAssertEqual(device.memberID, member.id)
        XCTAssertNil(device.revokedAt)
        XCTAssertEqual(invitation.id, "member-2")
        XCTAssertEqual(invitation.employeeID, "employee-2")
    }

    func testAccessLifecycleContractsRemainExplicit() throws {
        XCTAssertEqual(PFSSTenantMemberAction.suspend.title, "Suspend")
        XCTAssertEqual(PFSSTenantMemberAction.reactivate.title, "Reactivate")
        XCTAssertEqual(PFSSTenantMemberAction.revoke.title, "Revoke")

        let cleanup = try JSONDecoder().decode(
            PFSSAccessCleanupResult.self,
            from: Data(
                """
                {
                  "invitationSecretsPurged": 3,
                  "deviceCredentialsPurged": 2
                }
                """.utf8
            )
        )
        XCTAssertEqual(cleanup.invitationSecretsPurged, 3)
        XCTAssertEqual(cleanup.deviceCredentialsPurged, 2)
    }

    func testEmployeeArchiveAccessLifecycleIsFailSafe() {
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.archiveAction(for: .invited),
            .cancelInvitation
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.archiveAction(for: .active),
            .suspendMembership
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.archiveAction(for: .suspended),
            .none
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.archiveAction(for: .revoked),
            .none
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.archiveAction(for: nil),
            .none
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.restoreAction(for: .suspended),
            .leaveAccessUnchanged
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.restoreAction(for: .revoked),
            .leaveAccessUnchanged
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.allowedActions(for: .active),
            [.suspend, .revoke]
        )
        XCTAssertEqual(
            PFSSEmployeeAccessLifecyclePolicy.allowedActions(for: .suspended),
            [.reactivate, .revoke]
        )
        XCTAssertTrue(
            PFSSEmployeeAccessLifecyclePolicy.allowedActions(for: .revoked)
                .isEmpty
        )
    }

    func testRemovalDirectiveDecodesOnlyExplicitCompanyRemoval() throws {
        let data = Data(
            """
            {
              "error": "company_data_removal_required",
              "directive": {
                "type": "remove_company_data",
                "tenantID": "tenant-1",
                "deviceID": "device-1",
                "issuedAt": "2030-01-02T12:00:00Z"
              }
            }
            """.utf8
        )

        let directive = PFSSCompanyDataRemovalCoordinator.directive(from: data)

        XCTAssertEqual(directive?.tenantID, "tenant-1")
        XCTAssertEqual(directive?.deviceID, "device-1")
        XCTAssertEqual(directive?.type, "remove_company_data")
    }

    func testLocalRemovalClearsCompanyDataAndApplicationBackups() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PFSS-Removal-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupService = PFSSLocalBackupService(directoryURL: directory)
        _ = try backupService.save(Data("company".utf8), kind: .manual)
        let defaults = isolatedDefaults()
        defaults.set(41, forKey: "PFSSCloudSynchronizationCursor")
        defaults.set(
            ["customer:one": "revision-9"],
            forKey: "PFSSSynchronizedRecordRevisions"
        )
        let coordinator = PFSSCompanyDataRemovalCoordinator(
            defaults: defaults,
            backupService: backupService
        )
        let store = AppDataStore(persistenceEnabled: false)
        store.businessProfile.businessName = "Company Data"
        coordinator.attach(store: store)

        try coordinator.removeLocalCompanyData()

        XCTAssertTrue(store.businessProfile.businessName.isEmpty)
        XCTAssertTrue(backupService.availableBackups().isEmpty)
        XCTAssertNil(
            defaults.object(forKey: "PFSSCloudSynchronizationCursor")
        )
        XCTAssertNil(
            defaults.object(forKey: "PFSSSynchronizedRecordRevisions")
        )
    }

    func testSynchronizationBootstrapHydratesOnlyAnEmptyStore() throws {
        let source = AppDataStore(persistenceEnabled: false)
        source.businessProfile.businessName = "Bootstrap Company"
        let archive = try source.createPortableArchive()

        let emptyTarget = AppDataStore(persistenceEnabled: false)
        XCTAssertTrue(
            try emptyTarget.applySynchronizationBootstrap(archive)
        )
        XCTAssertEqual(
            emptyTarget.businessProfile.businessName,
            "Bootstrap Company"
        )
        XCTAssertTrue(emptyTarget.offlineOperationQueue.operations.isEmpty)

        let existingTarget = AppDataStore(persistenceEnabled: false)
        existingTarget.businessProfile.businessName = "Existing Company"
        XCTAssertFalse(
            try existingTarget.applySynchronizationBootstrap(archive)
        )
        XCTAssertEqual(
            existingTarget.businessProfile.businessName,
            "Existing Company"
        )
    }

    func testSynchronizationStateKeysAreScopedToTheEnrolledDevice() {
        XCTAssertEqual(
            PFSSCloudSynchronizationStateKeys.cursor(deviceID: " Device-A "),
            "PFSSCloudSynchronizationCursor.device-a"
        )
        XCTAssertEqual(
            PFSSCloudSynchronizationStateKeys.bootstrap(deviceID: "Device-B"),
            "PFSSCloudSynchronizationBootstrap.device-b"
        )
        XCTAssertNotEqual(
            PFSSCloudSynchronizationStateKeys.cursor(deviceID: "Device-A"),
            PFSSCloudSynchronizationStateKeys.cursor(deviceID: "Device-B")
        )
    }

    func testSynchronizationStateMigratesLegacyCursorOnce() {
        let defaults = isolatedDefaults()
        defaults.set(41, forKey: "PFSSCloudSynchronizationCursor")

        PFSSCloudSynchronizationStateKeys.migrateLegacyCursorIfNeeded(
            deviceID: "Device-A",
            defaults: defaults
        )

        XCTAssertEqual(
            defaults.integer(
                forKey: PFSSCloudSynchronizationStateKeys.cursor(
                    deviceID: "Device-A"
                )
            ),
            41
        )
        XCTAssertNil(defaults.object(forKey: "PFSSCloudSynchronizationCursor"))
    }

    func testSynchronizationStateIsClearedForFreshEnrollment() {
        let defaults = isolatedDefaults()
        defaults.set(7, forKey: "PFSSCloudSynchronizationCursor")
        defaults.set(
            11,
            forKey: PFSSCloudSynchronizationStateKeys.cursor(
                deviceID: "Device-A"
            )
        )
        defaults.set(
            true,
            forKey: PFSSCloudSynchronizationStateKeys.bootstrap(
                deviceID: "Device-A"
            )
        )

        PFSSCloudSynchronizationStateKeys.clearAll(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "PFSSCloudSynchronizationCursor"))
        XCTAssertNil(
            defaults.object(
                forKey: PFSSCloudSynchronizationStateKeys.cursor(
                    deviceID: "Device-A"
                )
            )
        )
        XCTAssertNil(
            defaults.object(
                forKey: PFSSCloudSynchronizationStateKeys.bootstrap(
                    deviceID: "Device-A"
                )
            )
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "PFSSCloudflareBetaServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class TestCloudflareCredentialStore:
    PFSSCloudflareCredentialStoring {
    private var token: String?

    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}
