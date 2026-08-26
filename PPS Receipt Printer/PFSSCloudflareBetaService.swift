//
//  PFSSCloudflareBetaService.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 5 – Tenant-isolated Cloudflare beta client.
//

import Combine
import Foundation
import Security
import UIKit

extension Notification.Name {
    static let pfssCompanyAccessWasActivated = Notification.Name(
        "PFSSCompanyAccessWasActivated"
    )
    static let pfssSynchronizationWakeRequested = Notification.Name(
        "PFSSSynchronizationWakeRequested"
    )
    static let pfssSynchronizationPushTokenDidChange = Notification.Name(
        "PFSSSynchronizationPushTokenDidChange"
    )
    static let pfssSynchronizationHealthDidRefresh = Notification.Name(
        "PFSSSynchronizationHealthDidRefresh"
    )
}

struct PFSSCloudflareBetaConfiguration: Equatable {
    var endpoint: URL
}

struct PFSSCloudflareBackup: Identifiable, Codable, Hashable {
    var archiveID: String
    var uploadedAt: Date
    var size: Int64
    var etag: String

    var id: String { archiveID }
}

enum PFSSJobDeclineStatus: String, Codable, Hashable {
    case pending
    case resolved
}

enum PFSSJobDeclineResolutionAction: String, Codable, CaseIterable, Hashable {
    case reassigned
    case rescheduled
    case returned
    case cancelled

    var title: String {
        switch self {
        case .reassigned: return "Reassigned"
        case .rescheduled: return "Rescheduled"
        case .returned: return "Returned to Technician"
        case .cancelled: return "Cancelled"
        }
    }
}

struct PFSSJobDeclineReview: Identifiable, Codable, Hashable {
    var id: String
    var assignmentID: String
    var jobID: String
    var jobNumber: String
    var customerNumber: String
    var technicianMemberID: String
    var technicianEmployeeID: String
    var originatingDeviceID: String
    var reason: String
    var status: PFSSJobDeclineStatus
    var resolutionAction: PFSSJobDeclineResolutionAction?
    var resolutionNote: String?
    var resolvedByMemberID: String?
    var createdAt: Date
    var updatedAt: Date
    var resolvedAt: Date?
}

private struct PFSSJobDeclineReviewEnvelope: Decodable {
    var review: PFSSJobDeclineReview
    var duplicate: Bool
}

private struct PFSSJobDeclineReviewList: Decodable {
    var reviews: [PFSSJobDeclineReview]
}

enum PFSSTenantRole: String, Codable, Equatable {
    case owner
    case manager
    case member

    var title: String { rawValue.capitalized }

    var canManageAccess: Bool {
        self == .owner || self == .manager
    }

    var canManageRecovery: Bool {
        self == .owner
    }
}

enum PFSSEmployeeAccessRolePolicy {
    static func invitationRole(for employee: EmployeeRecord)
        -> PFSSTenantRole? {
        if employee.hasRole(.owner) { return nil }
        return employee.hasRole(.manager) ? .manager : .member
    }
}

enum PFSSTenantMemberStatus: String, Codable, Equatable {
    case invited
    case active
    case suspended
    case revoked

    var title: String { rawValue.capitalized }
}

struct PFSSTenantMember: Identifiable, Codable, Equatable {
    var id: String
    var employeeID: String?
    var displayName: String
    var role: PFSSTenantRole
    var status: PFSSTenantMemberStatus
    var createdAt: Date
    var activatedAt: Date?
}

struct PFSSTenantDevice: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var memberID: String
    var memberName: String
    var role: PFSSTenantRole
    var createdAt: Date
    var lastSeenAt: Date
    var revokedAt: Date?
}

struct PFSSTenantInvitation: Identifiable, Codable, Equatable {
    var memberID: String
    var employeeID: String?
    var enrollmentCode: String
    var expiresAt: Date

    var id: String { memberID }
}

enum PFSSTenantMemberAction: String, Hashable {
    case suspend
    case reactivate
    case revoke

    var title: String {
        switch self {
        case .suspend: return "Suspend"
        case .reactivate: return "Reactivate"
        case .revoke: return "Revoke"
        }
    }
}

enum PFSSEmployeeArchiveAccessAction: Equatable {
    case none
    case cancelInvitation
    case suspendMembership
}

enum PFSSEmployeeRestoreAccessAction: Equatable {
    case leaveAccessUnchanged
}

enum PFSSEmployeeAccessLifecyclePolicy {
    static func archiveAction(
        for status: PFSSTenantMemberStatus?
    ) -> PFSSEmployeeArchiveAccessAction {
        switch status {
        case .invited:
            return .cancelInvitation
        case .active:
            return .suspendMembership
        case .suspended, .revoked, nil:
            return .none
        }
    }

    static func restoreAction(
        for status: PFSSTenantMemberStatus?
    ) -> PFSSEmployeeRestoreAccessAction {
        // Restoring the business record never changes authentication state.
        // Suspended access requires a separate authorized decision, and revoked
        // access requires a new invitation and device credential.
        .leaveAccessUnchanged
    }

    static func allowedActions(
        for status: PFSSTenantMemberStatus
    ) -> Set<PFSSTenantMemberAction> {
        switch status {
        case .invited:
            return []
        case .active:
            return [.suspend, .revoke]
        case .suspended:
            return [.reactivate, .revoke]
        case .revoked:
            return []
        }
    }
}

struct PFSSAccessCleanupResult: Decodable, Equatable {
    var invitationSecretsPurged: Int
    var deviceCredentialsPurged: Int
}

struct PFSSOwnerRecoveryCodeStatus: Decodable, Equatable {
    var availableCodes: Int
    var createdAt: Date?
}

struct PFSSOwnerRecoveryCodeReceipt: Decodable, Equatable {
    var recoveryCodes: [String]
    var createdAt: Date
}

struct PFSSOwnerAccountInvitation: Decodable, Identifiable, Equatable {
    var invitationID: String
    var memberID: String
    var displayName: String
    var email: String
    var invitationCode: String
    var expiresAt: Date

    var id: String { invitationID }
}

struct PFSSEmployeeArchiveAccessResult: Decodable, Equatable {
    enum Action: String, Decodable {
        case none
        case cancelledInvitation
        case suspendedMembership
    }

    var action: Action
    var membershipStatus: PFSSTenantMemberStatus?
}

struct PFSSCloudflareSession: Codable, Equatable {
    struct Tenant: Codable, Equatable {
        var id: String? = nil
        var displayName: String
    }

    struct Member: Codable, Equatable {
        var id: String
        var displayName: String
        var email: String?
        var role: PFSSTenantRole
        var employeeID: String?
    }

    struct Device: Codable, Equatable {
        var id: String
        var displayName: String
    }

    var tenant: Tenant
    var member: Member
    var device: Device
}

enum PFSSCloudflareBetaState: Equatable {
    case notConfigured
    case notEnrolled
    case enrolling
    case connected
    case working
    case failed(String)

    var title: String {
        switch self {
        case .notConfigured: return "Cloudflare Beta Not Configured"
        case .notEnrolled: return "Cloudflare Beta Ready to Enroll"
        case .enrolling: return "Enrolling This Device"
        case .connected: return "Cloudflare Beta Connected"
        case .working: return "Synchronizing with Cloudflare"
        case .failed: return "Cloudflare Beta Error"
        }
    }
}

enum PFSSCloudflareBetaError: LocalizedError {
    case invalidEndpoint
    case notEnrolled
    case noBackup
    case invalidResponse
    case companyDataRemoved
    case accountHold(PFSSAccountHold)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Enter a valid HTTPS Cloudflare Worker address."
        case .notEnrolled:
            return "Enroll this device with its one-time beta code first."
        case .noBackup:
            return "No PFSS backup is available for this beta tenant."
        case .invalidResponse:
            return "The PFSS beta service returned an unreadable response."
        case .companyDataRemoved:
            return "This device no longer has company access. Company-owned data was removed."
        case let .accountHold(hold):
            return hold.message
        case let .server(message):
            return message
        }
    }
}

struct PFSSAccountHold: Codable, Equatable {
    enum HoldType: String, Codable {
        case billingHold
        case securityHold
        case supportHold
    }

    var type: HoldType
    var expiresAt: Date?

    var title: String {
        switch type {
        case .billingHold: return "Account Needs Billing Attention"
        case .securityHold: return "Account Paused for Security Review"
        case .supportHold: return "Account Temporarily Paused"
        }
    }

    var message: String {
        switch type {
        case .billingHold:
            return "Company access is paused while a billing issue is resolved. Contact your system administrator or PFSS Support for assistance."
        case .securityHold:
            return "Company access is paused to protect your account while a security issue is reviewed. Contact your system administrator or PFSS Support for assistance."
        case .supportHold:
            return "Company access is temporarily paused while a support issue is resolved. Contact your system administrator or PFSS Support for assistance."
        }
    }
}

private struct PFSSAccountHoldResponse: Decodable {
    var error: String
    var hold: PFSSAccountHold
}

private struct PFSSCloudflareEnrollmentResponse: Decodable {
    var deviceToken: String
}

private struct PFSSCloudflareBackupList: Decodable {
    var backups: [PFSSCloudflareBackup]
}

private struct PFSSCloudflareOperationResponse: Decodable {
    var revision: String
    var supersededByCloud: Bool?
    var currentOperation: PendingOfflineOperation?
}

private struct PFSSCloudflareSynchronizationChange: Decodable {
    var sequence: Int
    var sourceDeviceID: String
    var revision: String
    var operation: PendingOfflineOperation
}

private struct PFSSCloudflareRecordConflictResponse: Decodable {
    var error: String
    var conflictID: String?
    var currentRevision: String?
    var currentOperation: PendingOfflineOperation?
}

struct PFSSCloudflareSynchronizationConflict: Decodable, Identifiable {
    var id: String
    var entityType: OfflineEntityType
    var entityID: UUID
    var sourceMemberID: String
    var sourceDeviceID: String
    var localOperation: PendingOfflineOperation
    var cloudOperation: PendingOfflineOperation
    var cloudRevision: String
    var detectedAt: Date
    var affectedFields: [String]?
    var operationalImpact: String?
    var policyVersion: Int?
}

private struct PFSSCloudflareSynchronizationConflictList: Decodable {
    var conflicts: [PFSSCloudflareSynchronizationConflict]
}

private struct PFSSCloudflareConflictReportResponse: Decodable {
    var conflictID: String
}

struct PFSSCloudflareConflictResolutionReceipt: Decodable {
    var id: String
    var entityType: OfflineEntityType
    var entityID: UUID
    var resolution: String
    var resolvedAt: Date
    var finalRevision: String
    var policyVersion: Int?
    var affectedFields: [String]?
}

struct PFSSCloudflareRevokedDeviceConflictCleanupReceipt: Decodable {
    var sourceDeviceID: String
    var resolvedCount: Int
    var resolution: String
    var resolvedAt: Date
    var batchID: String
}

private struct PFSSCloudflareRevokedDeviceConflictScope: Decodable {
    var sourceDeviceID: String
    var conflictCount: Int
    var isRevoked: Bool
}

struct PFSSConflictAuditEvent: Decodable, Identifiable {
    var id: String
    var entityType: OfflineEntityType
    var entityID: UUID
    var resolution: String
    var detectedAt: Date
    var resolvedAt: Date
    var resolverRole: PFSSTenantRole?
    var resolverName: String
    var reason: String?
    var affectedFields: [String]
    var policyVersion: Int?
    var localOperation: PendingOfflineOperation
    var cloudOperation: PendingOfflineOperation
    var originalCloudRevision: String
    var finalRevision: String
}

private struct PFSSConflictAuditList: Decodable {
    var events: [PFSSConflictAuditEvent]
}

enum PFSSRecoveryAuditEvent: String {
    case archiveCreated = "recovery.archive_created"
    case externalBackup = "recovery.external_backup"
    case archiveImported = "recovery.archive_imported"
    case archiveRestored = "recovery.archive_restored"
    case localDataCleared = "recovery.local_data_cleared"
}

enum PFSSRecoveryAuditProvider: String {
    case localFile
    case localHistory
    case iCloud
    case googleDrive
    case pfssCloud
}

private struct PFSSCloudflareConflictResolutionList: Decodable {
    var resolutions: [PFSSCloudflareConflictResolutionReceipt]
}

struct PFSSCloudflareSynchronizationQuarantine: Decodable, Identifiable {
    struct Failure: Decodable { var reason: String }
    var id: String
    var operationID: UUID
    var entityType: OfflineEntityType
    var entityID: UUID?
    var sourceMemberID: String
    var sourceDeviceID: String
    var operation: PendingOfflineOperation
    var cloudOperation: PendingOfflineOperation?
    var cloudRevision: String?
    var failure: Failure
    var policyVersion: Int
    var detectedAt: Date
    var affectedFields: [String]
    var operationalImpact: String

    var alreadyMatchesCloudRecord: Bool {
        guard let cloudOperation else { return false }
        return entityType == cloudOperation.entityType &&
            entityID == cloudOperation.entityID &&
            operation.payload == cloudOperation.payload
    }
}

private struct PFSSCloudflareSynchronizationQuarantineList: Decodable {
    var quarantines: [PFSSCloudflareSynchronizationQuarantine]
}

struct PFSSCloudflareQuarantineResolutionReceipt: Decodable {
    var id: String
    var operationID: UUID
    var action: String
    var reason: String?
    var resolvedAt: Date
}

private struct PFSSCloudflareQuarantineResolutionList: Decodable {
    var resolutions: [PFSSCloudflareQuarantineResolutionReceipt]
}

private struct PFSSCloudflareQuarantineReportResponse: Decodable {
    var quarantineID: String
}

private struct PFSSCloudflareSynchronizationChanges: Decodable {
    var cursor: Int
    var serverCursor: Int?
    var hasMore: Bool
    var changes: [PFSSCloudflareSynchronizationChange]
}

private struct PFSSCloudflareSynchronizationCursorReceipt: Decodable {
    var cursor: Int
    var serverCursor: Int
}

enum PFSSSynchronizationHealthLevel: String, Decodable {
    case healthy
    case delayed
    case actionRequired

    var title: String {
        switch self {
        case .healthy: return "Healthy"
        case .delayed: return "Delayed"
        case .actionRequired: return "Action Required"
        }
    }
}

struct PFSSSynchronizationHealth: Decodable {
    struct Summary: Decodable {
        struct PushSummary: Decodable {
            var sent: Int
            var accepted: Int
            var received: Int
            var completed: Int
            var failed: Int
            var deferred: Int
        }

        var activeDevices: Int
        var healthyDevices: Int
        var delayedDevices: Int
        var actionRequiredDevices: Int
        var unresolvedConflicts: Int
        var quarantinedChanges: Int
        var oldestConflictAgeSeconds: Int?
        var oldestQuarantineAgeSeconds: Int?
        var pushLast24Hours: PushSummary
        var activeAlerts: Int
        var criticalAlerts: Int
    }

    struct Device: Decodable, Identifiable {
        struct LatestPush: Decodable {
            var requestedAt: Date
            var acceptedAt: Date?
            var receivedAt: Date?
            var completedAt: Date?
            var failedAt: Date?
            var failureCode: String?
        }

        var deviceID: String
        var displayName: String
        var role: PFSSTenantRole
        var status: PFSSSynchronizationHealthLevel
        var reasons: [String]
        var acknowledgedCursor: Int
        var serverCursor: Int
        var behindBy: Int
        var cursorAgeSeconds: Int?
        var lastSeenAt: Date
        var cursorUpdatedAt: Date?
        var appBuild: String?
        var latestPush: LatestPush?

        var id: String { deviceID }
    }

    struct CountByEntity: Decodable, Identifiable {
        var entityType: String
        var count: Int
        var id: String { entityType }
    }

    struct CountByField: Decodable, Identifiable {
        var field: String
        var count: Int
        var id: String { field }
    }

    struct CountByReason: Decodable, Identifiable {
        var reason: String
        var count: Int
        var id: String { reason }
    }

    struct Trends: Decodable {
        var byEntity: [CountByEntity]
        var byField: [CountByField]
        var quarantineReasons: [CountByReason]
    }

    struct Alert: Decodable, Identifiable {
        var id: String
        var kind: String
        var severity: String
        var title: String
        var detail: String
        var recommendation: String
        var deviceID: String?
        var observedValue: Int
        var thresholdValue: Int
        var openedAt: Date
        var lastObservedAt: Date
    }

    var generatedAt: Date
    var status: PFSSSynchronizationHealthLevel
    var statusLabel: String
    var serverCursor: Int
    var summary: Summary
    var devices: [Device]
    var alerts: [Alert]
    var trendsLast7Days: Trends
}

struct PFSSSynchronizationDeviceHealthReport: Encodable {
    var appBuild: String
    var queueCount: Int
    var oldestQueuedAt: Date?
    var failedCount: Int
    var waitingRetryCount: Int
    var retryAttempts24h: Int
    var blockedDependencyCount: Int
    var conflictedCount: Int
    var quarantinedCount: Int
}

private struct PFSSCloudflareSynchronizationBootstrap {
    var data: Data
    var cursor: Int
}

private struct PFSSTenantMemberList: Decodable {
    var members: [PFSSTenantMember]
}

private struct PFSSTenantDeviceList: Decodable {
    var devices: [PFSSTenantDevice]
}

protocol PFSSCloudflareCredentialStoring: AnyObject {
    func load() -> String?
    func save(_ token: String)
    func delete()
}

final class PFSSCloudflareCredentialStore:
    PFSSCloudflareCredentialStoring {
    private let service = "com.patriot.pfss.cloudflare-beta"
    private let account = "device-token"

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class PFSSCloudflareBetaManager: ObservableObject {
    static let defaultEndpoint =
        "https://pfss-beta-api.timrenollet.workers.dev"

    @Published private(set) var state: PFSSCloudflareBetaState
    @Published private(set) var backups: [PFSSCloudflareBackup] = []
    @Published private(set) var currentSession: PFSSCloudflareSession?
    @Published private(set) var accountEntitlementSnapshot:
        PFSSAccountEntitlementSnapshot?
    @Published private(set) var members: [PFSSTenantMember] = []
    @Published private(set) var devices: [PFSSTenantDevice] = []

    private let credentialStore: any PFSSCloudflareCredentialStoring
    private let defaults: UserDefaults
    private let session: URLSession
    private let deviceIDKey = "PFSSCloudflareBetaDeviceID"

    init(
        defaults: UserDefaults? = nil,
        session: URLSession = .shared,
        credentialStore: (any PFSSCloudflareCredentialStoring)? = nil
    ) {
        let defaults = defaults ?? .standard
        self.defaults = defaults
        self.session = session
        self.credentialStore = credentialStore ?? PFSSCloudflareCredentialStore()
        if self.credentialStore.load() == nil {
            state = .notEnrolled
        } else {
            state = .connected
        }
    }

    var latestBackup: PFSSCloudflareBackup? { backups.first }
    var savedEndpoint: String { Self.defaultEndpoint }
    var isEnrolled: Bool { credentialStore.load() != nil }

    func registrationDeviceID() -> UUID {
        if let saved = defaults.string(forKey: deviceIDKey),
           let id = UUID(uuidString: saved) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString.lowercased(), forKey: deviceIDKey)
        return id
    }

    func acceptProvisionedOwnerDevice(
        token: String,
        deviceID: UUID
    ) async throws {
        guard !token.isEmpty else {
            throw PFSSCloudflareBetaError.invalidResponse
        }
        credentialStore.save(token)
        defaults.set(deviceID.uuidString.lowercased(), forKey: deviceIDKey)
        state = .connected
        try await refreshSession()
        NotificationCenter.default.post(
            name: .pfssCompanyAccessWasActivated,
            object: nil
        )
    }

    func configureOwnerWorkProfile(
        roles: Set<PFSSOwnerOperationalRole>
    ) async throws -> PFSSOwnerWorkProfileReceipt {
        guard currentSession?.member.role == .owner else {
            throw PFSSCloudflareBetaError.server("owner_required")
        }
        guard !roles.isEmpty else {
            throw PFSSCloudflareBetaError.server(
                "Select Sales, Technician, or both."
            )
        }
        var request = try request(
            path: "/v1/account/owner-work-profile",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode([
            "roles": roles.sorted { $0.rawValue < $1.rawValue }
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let receipt = try Self.decoder.decode(
            PFSSOwnerWorkProfileReceipt.self,
            from: try await perform(request)
        )
        try await refreshSession()
        return receipt
    }

    func submitJobDecline(
        assignmentID: UUID,
        jobID: UUID,
        reason: String,
        idempotencyKey: UUID
    ) async throws -> PFSSJobDeclineReview {
        var request = try request(
            path: "/v1/job-declines",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode([
            "assignmentID": assignmentID.uuidString.lowercased(),
            "jobID": jobID.uuidString.lowercased(),
            "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
            "idempotencyKey": idempotencyKey.uuidString.lowercased()
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSJobDeclineReviewEnvelope.self,
            from: try await perform(request)
        ).review
    }

    func jobDeclineReviews(
        status: PFSSJobDeclineStatus = .pending
    ) async throws -> [PFSSJobDeclineReview] {
        let data = try await perform(
            try request(
                path: "/v1/job-declines?status=\(status.rawValue)",
                authenticated: true
            )
        )
        return try Self.decoder.decode(
            PFSSJobDeclineReviewList.self,
            from: data
        ).reviews
    }

    func resolveJobDecline(
        reviewID: String,
        action: PFSSJobDeclineResolutionAction,
        note: String
    ) async throws -> PFSSJobDeclineReview {
        var request = try request(
            path: "/v1/job-declines/\(reviewID)/resolve",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode([
            "action": action.rawValue,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSJobDeclineReviewEnvelope.self,
            from: try await perform(request)
        ).review
    }

    func enroll(code: String, deviceName: String) async throws {
        state = .enrolling
        let enrollmentDeviceID = UUID().uuidString.lowercased()
        let body: [String: String] = [
            "enrollmentCode": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceID": enrollmentDeviceID,
            "deviceName": deviceName
        ]
        var request = try request(path: "/v1/beta/enroll", method: "POST", authenticated: false)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let response = try Self.decoder.decode(
                PFSSCloudflareEnrollmentResponse.self,
                from: try await perform(request)
            )
            credentialStore.save(response.deviceToken)
            defaults.set(enrollmentDeviceID, forKey: deviceIDKey)
            state = .connected
            NotificationCenter.default.post(
                name: .pfssCompanyAccessWasActivated,
                object: nil
            )
            // Enrollment codes are single-use. Once the credential is safely
            // stored, a transient status refresh must not misreport enrollment
            // as failed and tempt the owner to retry a consumed code.
            try? await refreshSession()
            if currentSession?.member.role.canManageRecovery == true {
                try? await refreshBackups()
            } else {
                backups = []
            }
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func disconnect() {
        credentialStore.delete()
        backups = []
        currentSession = nil
        accountEntitlementSnapshot = nil
        members = []
        devices = []
        state = savedEndpoint.isEmpty ? .notConfigured : .notEnrolled
    }

    func logOut() throws {
        try PFSSCompanyDataRemovalCoordinator.shared.logOut {
            self.credentialStore.delete()
        }
        backups = []
        currentSession = nil
        accountEntitlementSnapshot = nil
        members = []
        devices = []
        state = .notEnrolled
    }

    func refreshSession() async throws {
        let data = try await perform(
            try request(path: "/v1/session", authenticated: true)
        )
        currentSession = try Self.decoder.decode(
            PFSSCloudflareSession.self,
            from: data
        )
    }

    func refreshAccountEntitlements() async throws {
        guard currentSession?.member.role == .owner else {
            accountEntitlementSnapshot = nil
            throw PFSSCloudflareBetaError.server("owner_required")
        }
        let data = try await perform(
            try request(path: "/v1/account/entitlements", authenticated: true)
        )
        accountEntitlementSnapshot = try Self.decoder.decode(
            PFSSAccountEntitlementSnapshot.self,
            from: data
        )
    }

    func refresh() async throws {
        state = .working
        do {
            try await refreshSession()
            if currentSession?.member.role == .owner {
                try await refreshAccountEntitlements()
            } else {
                accountEntitlementSnapshot = nil
            }
            if currentSession?.member.role.canManageRecovery == true {
                try await refreshBackups()
            } else {
                backups = []
            }
            if currentSession?.member.role.canManageAccess == true {
                try await refreshAdministration()
            } else {
                members = []
                devices = []
            }
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func refreshAdministration() async throws {
        guard currentSession?.member.role.canManageAccess == true else {
            members = []
            devices = []
            throw PFSSCloudflareBetaError.server("forbidden")
        }
        async let memberData = perform(
            try request(path: "/v1/members", authenticated: true)
        )
        async let deviceData = perform(
            try request(path: "/v1/devices", authenticated: true)
        )
        members = try Self.decoder.decode(
            PFSSTenantMemberList.self,
            from: try await memberData
        ).members
        devices = try Self.decoder.decode(
            PFSSTenantDeviceList.self,
            from: try await deviceData
        ).devices
    }

    func createInvitation(
        displayName: String,
        role: PFSSTenantRole,
        employeeID: UUID? = nil
    ) async throws -> PFSSTenantInvitation {
        guard currentSession?.member.role.canManageAccess == true else {
            throw PFSSCloudflareBetaError.server("forbidden")
        }
        var request = try request(
            path: "/v1/invitations",
            method: "POST",
            authenticated: true
        )
        var invitationPayload: [String: String] = [
            "displayName": displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            "role": role.rawValue
        ]
        if let employeeID {
            invitationPayload["employeeID"] = employeeID.uuidString.lowercased()
        }
        request.httpBody = try JSONEncoder().encode(invitationPayload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let invitation = try Self.decoder.decode(
            PFSSTenantInvitation.self,
            from: try await perform(request)
        )
        try await refreshAdministration()
        return invitation
    }

    func createDeviceInvitation(
        for member: PFSSTenantMember
    ) async throws -> PFSSTenantInvitation {
        guard currentSession?.member.role.canManageAccess == true else {
            throw PFSSCloudflareBetaError.server("forbidden")
        }
        let invitation = try Self.decoder.decode(
            PFSSTenantInvitation.self,
            from: try await perform(
                try request(
                    path: "/v1/members/\(member.id)/device-invitations",
                    method: "POST",
                    authenticated: true
                )
            )
        )
        try await refreshAdministration()
        return invitation
    }

    func secureEmployeeAccessForArchive(
        employeeID: UUID
    ) async throws -> PFSSEmployeeArchiveAccessResult {
        guard currentSession?.member.role.canManageAccess == true else {
            throw PFSSCloudflareBetaError.server("forbidden")
        }
        let data = try await perform(
            try request(
                path: "/v1/employees/\(employeeID.uuidString.lowercased())/secure-for-archive",
                method: "POST",
                authenticated: true
            )
        )
        let result = try Self.decoder.decode(
            PFSSEmployeeArchiveAccessResult.self,
            from: data
        )
        try await refreshAdministration()
        return result
    }

    func revokeDevice(_ device: PFSSTenantDevice) async throws {
        _ = try await perform(
            try request(
                path: "/v1/devices/\(device.id)/revoke",
                method: "POST",
                authenticated: true
            )
        )
        try await refreshAdministration()
        if device.id == currentSession?.device.id {
            credentialStore.delete()
            currentSession = nil
            state = .notEnrolled
        }
    }

    func ownerRecoveryCodeStatus() async throws
        -> PFSSOwnerRecoveryCodeStatus {
        let data = try await perform(
            try request(
                path: "/v1/account-recovery/codes",
                authenticated: true
            )
        )
        return try Self.decoder.decode(
            PFSSOwnerRecoveryCodeStatus.self,
            from: data
        )
    }

    func replaceOwnerRecoveryCodes() async throws
        -> PFSSOwnerRecoveryCodeReceipt {
        let data = try await perform(
            try request(
                path: "/v1/account-recovery/codes",
                method: "POST",
                authenticated: true
            )
        )
        return try Self.decoder.decode(
            PFSSOwnerRecoveryCodeReceipt.self,
            from: data
        )
    }

    func createOwnerInvitation(
        displayName: String,
        email: String
    ) async throws -> PFSSOwnerAccountInvitation {
        var invitationRequest = try request(
            path: "/v1/owner-invitations",
            method: "POST",
            authenticated: true
        )
        invitationRequest.httpBody = try Self.encoder.encode([
            "displayName": displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            "email": email.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        ])
        invitationRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        let invitation = try Self.decoder.decode(
            PFSSOwnerAccountInvitation.self,
            from: try await perform(invitationRequest)
        )
        try await refreshAdministration()
        return invitation
    }

    func revokeOwnerMember(_ member: PFSSTenantMember) async throws {
        _ = try await perform(
            try request(
                path: "/v1/owner-members/\(member.id)/revoke",
                method: "POST",
                authenticated: true
            )
        )
        try await refreshAdministration()
    }

    func cancelInvitation(for member: PFSSTenantMember) async throws {
        _ = try await perform(
            try request(
                path: "/v1/invitations/\(member.id)/cancel",
                method: "POST",
                authenticated: true
            )
        )
        try await refreshAdministration()
    }

    func updateMember(
        _ member: PFSSTenantMember,
        action: PFSSTenantMemberAction
    ) async throws {
        _ = try await perform(
            try request(
                path: "/v1/members/\(member.id)/\(action.rawValue)",
                method: "POST",
                authenticated: true
            )
        )
        try await refreshAdministration()
    }

    func cleanAccessHistory() async throws -> PFSSAccessCleanupResult {
        let data = try await perform(
            try request(
                path: "/v1/access/cleanup",
                method: "POST",
                authenticated: true
            )
        )
        try await refreshAdministration()
        return try JSONDecoder().decode(PFSSAccessCleanupResult.self, from: data)
    }

    func refreshBackups() async throws {
        state = .working
        do {
            let data = try await perform(
                try request(path: "/v1/backups", authenticated: true)
            )
            backups = try Self.decoder.decode(
                PFSSCloudflareBackupList.self,
                from: data
            ).backups.sorted { $0.uploadedAt > $1.uploadedAt }
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func uploadBackup(_ data: Data) async throws {
        state = .working
        var request = try request(
            path: "/v1/backups",
            method: "POST",
            authenticated: true
        )
        request.httpBody = data
        request.setValue(
            PFSSArchiveConstants.mediaType,
            forHTTPHeaderField: "Content-Type"
        )
        do {
            _ = try await perform(request)
            try await refreshBackups()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func submitSynchronizationDiagnostics(
        _ bundle: PFSSSynchronizationDiagnosticBundle
    ) async throws -> PFSSSynchronizationDiagnosticSubmission {
        var request = try request(
            path: "/v1/support/sync-diagnostics",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode(bundle)
        request.setValue(
            "application/vnd.pfss.sync-diagnostics+json",
            forHTTPHeaderField: "Content-Type"
        )
        return try Self.decoder.decode(
            PFSSSynchronizationDiagnosticSubmission.self,
            from: try await perform(request)
        )
    }

    func latestData() async throws -> Data {
        guard credentialStore.load() != nil else {
            throw PFSSCloudflareBetaError.notEnrolled
        }
        return try await perform(
            try request(path: "/v1/backups/latest", authenticated: true)
        )
    }

    func publishSynchronizationSnapshot(_ data: Data) async throws {
        guard currentSession?.member.role.canManageRecovery == true else {
            throw PFSSCloudflareBetaError.server("forbidden")
        }
        var request = try request(
            path: "/v1/sync/snapshot",
            method: "POST",
            authenticated: true
        )
        request.httpBody = data
        request.setValue(
            PFSSArchiveConstants.mediaType,
            forHTTPHeaderField: "Content-Type"
        )
        _ = try await perform(request)
    }

    func synchronizationBootstrap() async throws
        -> (data: Data, cursor: Int) {
        let result = try await performWithResponse(
            try request(path: "/v1/sync/bootstrap", authenticated: true)
        )
        let cursor = Int(
            result.response.value(forHTTPHeaderField: "x-pfss-change-cursor") ?? "0"
        ) ?? 0
        return (result.data, max(cursor, 0))
    }

    func synchronizationBootstrapData() async throws -> Data {
        try await synchronizationBootstrap().data
    }

    /// Returns the current canonical version of every synchronized tenant
    /// record. Recovery overlays these records on the archive so a stale or
    /// incomplete archive can never hide newer server-authoritative data.
    func synchronizationCanonicalBaseline() async throws
        -> (cursor: Int, operations: [PendingOfflineOperation]) {
        let data = try await perform(
            try request(path: "/v1/sync/baseline-records", authenticated: true)
        )
        let response = try Self.decoder.decode(
            PFSSCloudflareCanonicalBaseline.self,
            from: data
        )
        let operations = response.records.map { record in
            var operation = record.operation
            operation.metadata["remoteRevision"] = record.revision
            return operation
        }
        return (response.cursor, operations)
    }

    func synchronizationChanges(after cursor: Int) async throws
        -> (cursor: Int, hasMore: Bool, operations: [PendingOfflineOperation]) {
        let data = try await perform(
            try request(
                path: "/v1/sync/changes?after=\(max(cursor, 0))&limit=200",
                authenticated: true
            )
        )
        let response = try Self.decoder.decode(
            PFSSCloudflareSynchronizationChanges.self,
            from: data
        )
        let operations = response.changes.map { change in
            var operation = change.operation
            operation.metadata["remoteRevision"] = change.revision
            return operation
        }
        return (response.cursor, response.hasMore, operations)
    }

    func acknowledgeSynchronizationCursor(_ cursor: Int) async throws {
        var cursorRequest = try request(
            path: "/v1/sync/cursor",
            method: "POST",
            authenticated: true
        )
        cursorRequest.httpBody = try Self.encoder.encode([
            "cursor": max(cursor, 0)
        ])
        cursorRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try Self.decoder.decode(
            PFSSCloudflareSynchronizationCursorReceipt.self,
            from: try await perform(cursorRequest)
        )
    }

    func registerSynchronizationPushToken(_ token: String) async throws {
        var pushRequest = try request(
            path: "/v1/sync/push",
            method: "POST",
            authenticated: true
        )
        let appBuild = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        pushRequest.httpBody = try Self.encoder.encode([
            "token": token,
            "appBuild": appBuild
        ])
        pushRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(pushRequest)
    }

    func synchronizationHealth() async throws -> PFSSSynchronizationHealth {
        try Self.decoder.decode(
            PFSSSynchronizationHealth.self,
            from: try await perform(
                try request(path: "/v1/sync/health", authenticated: true)
            )
        )
    }

    func reportSynchronizationDeviceHealth(
        _ report: PFSSSynchronizationDeviceHealthReport
    ) async throws {
        var healthRequest = try request(
            path: "/v1/sync/device-health",
            method: "POST",
            authenticated: true
        )
        healthRequest.httpBody = try Self.encoder.encode(report)
        healthRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(healthRequest)
    }

    func reportSynchronizationPushEvent(
        deliveryID: String,
        event: String,
        cursor: Int?
    ) async throws {
        var eventRequest = try request(
            path: "/v1/sync/push-events",
            method: "POST",
            authenticated: true
        )
        var body: [String: Any] = [
            "deliveryID": deliveryID,
            "event": event
        ]
        if let cursor { body["cursor"] = max(cursor, 0) }
        eventRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        eventRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(eventRequest)
    }

    func synchronizeMileageTrips(
        cursor: Int,
        trips: [MileageTrip],
        deletions: [UUID: Date]
    ) async throws -> PFSSMileageSynchronizationResponse {
        struct Upload: Encodable {
            let id: UUID
            let originatingDeviceID: UUID
            let classification: MileageTripClassification
            let startedAt: Date
            let updatedAt: Date
            let payload: MileageTrip
        }
        struct Deletion: Encodable {
            let id: UUID
            let deletedAt: Date
        }
        struct RequestBody: Encodable {
            let cursor: Int
            let trips: [Upload]
            let deletions: [Deletion]
        }
        var request = try request(
            path: "/v1/mileage/sync",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode(RequestBody(
            cursor: max(cursor, 0),
            trips: trips.map {
                Upload(
                    id: $0.id,
                    originatingDeviceID: $0.originatingDeviceID,
                    classification: $0.classification,
                    startedAt: $0.startedAt,
                    updatedAt: $0.updatedAt,
                    payload: $0
                )
            },
            deletions: deletions.map {
                Deletion(id: $0.key, deletedAt: $0.value)
            }
        ))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSMileageSynchronizationResponse.self,
            from: try await perform(request)
        )
    }

    func synchronizationConflicts() async throws
        -> [PFSSCloudflareSynchronizationConflict] {
        let data = try await perform(
            try request(path: "/v1/sync/conflicts", authenticated: true)
        )
        return try Self.decoder.decode(
            PFSSCloudflareSynchronizationConflictList.self,
            from: data
        ).conflicts
    }

    func reportSynchronizationConflict(
        _ operation: PendingOfflineOperation
    ) async throws -> String {
        struct Report: Encodable {
            var operation: PendingOfflineOperation
        }
        var request = try request(
            path: "/v1/sync/conflicts/report",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode(
            Report(
                operation: operation
            )
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSCloudflareConflictReportResponse.self,
            from: try await perform(request)
        ).conflictID
    }

    func conflictResolutionReceipts() async throws
        -> [PFSSCloudflareConflictResolutionReceipt] {
        let data = try await perform(
            try request(
                path: "/v1/sync/conflict-resolutions",
                authenticated: true
            )
        )
        return try Self.decoder.decode(
            PFSSCloudflareConflictResolutionList.self,
            from: data
        ).resolutions
    }

    func resolveSynchronizationConflict(
        id: String,
        resolution: OfflineConflictResolution,
        reason: String,
        affectedFields: [String]
    ) async throws -> PFSSCloudflareConflictResolutionReceipt {
        let value: String
        switch resolution {
        case .keptRemote: value = "keptCloud"
        case .keptLocal: value = "keptDevice"
        default: throw OfflineConflictResolutionError.invalidResolution
        }
        var request = try request(
            path: "/v1/sync/conflicts/\(id)/resolve",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "resolution": value,
            "reason": reason,
            "affectedFields": affectedFields
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSCloudflareConflictResolutionReceipt.self,
            from: try await perform(request)
        )
    }

    func discardRevokedDeviceSynchronizationConflicts(
        sourceDeviceID: String,
        expectedCount: Int,
        reason: String
    ) async throws -> PFSSCloudflareRevokedDeviceConflictCleanupReceipt {
        var components = URLComponents()
        components.path = "/v1/sync/conflicts/revoked-device-scope"
        components.queryItems = [
            URLQueryItem(name: "sourceDeviceID", value: sourceDeviceID)
        ]
        guard let scopePath = components.string else {
            throw OfflineConflictResolutionError.invalidResolution
        }
        let scope = try Self.decoder.decode(
            PFSSCloudflareRevokedDeviceConflictScope.self,
            from: try await perform(
                try request(path: scopePath, authenticated: true)
            )
        )
        guard scope.sourceDeviceID == sourceDeviceID,
              scope.isRevoked,
              scope.conflictCount > 0 else {
            throw OfflineConflictResolutionError.noUnresolvedConflict
        }
        var request = try request(
            path: "/v1/sync/conflicts/discard-revoked-device",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "sourceDeviceID": sourceDeviceID,
            "expectedCount": scope.conflictCount,
            "reason": reason
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSCloudflareRevokedDeviceConflictCleanupReceipt.self,
            from: try await perform(request)
        )
    }

    func synchronizationQuarantines() async throws
        -> [PFSSCloudflareSynchronizationQuarantine] {
        let data = try await perform(
            try request(path: "/v1/sync/quarantines", authenticated: true)
        )
        return try Self.decoder.decode(
            PFSSCloudflareSynchronizationQuarantineList.self,
            from: data
        ).quarantines
    }

    func reportSynchronizationQuarantine(
        _ operation: PendingOfflineOperation,
        reason: String
    ) async throws -> String {
        struct Report: Encodable {
            var operation: PendingOfflineOperation
            var reason: String
        }
        var request = try request(
            path: "/v1/sync/quarantines/report",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try Self.encoder.encode(
            Report(operation: operation, reason: reason)
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSCloudflareQuarantineReportResponse.self,
            from: try await perform(request)
        ).quarantineID
    }

    func quarantineResolutionReceipts() async throws
        -> [PFSSCloudflareQuarantineResolutionReceipt] {
        let data = try await perform(
            try request(
                path: "/v1/sync/quarantine-resolutions",
                authenticated: true
            )
        )
        return try Self.decoder.decode(
            PFSSCloudflareQuarantineResolutionList.self,
            from: data
        ).resolutions
    }

    func resolveSynchronizationQuarantine(
        id: String,
        action: OfflineQuarantineResolution,
        reason: String
    ) async throws -> PFSSCloudflareQuarantineResolutionReceipt {
        let value: String
        switch action {
        case .discard: value = "discard"
        case .retry: value = "retry"
        case .supersede: throw OfflineConflictResolutionError.invalidResolution
        }
        var request = try request(
            path: "/v1/sync/quarantines/\(id)/resolve",
            method: "POST",
            authenticated: true
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": value,
            "reason": reason
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try Self.decoder.decode(
            PFSSCloudflareQuarantineResolutionReceipt.self,
            from: try await perform(request)
        )
    }

    func submitRepairedQuarantineOperation(
        quarantineID: String,
        operation: PendingOfflineOperation,
        reason: String
    ) async throws -> String {
        var operationRequest = try request(
            path: "/v1/operations",
            method: "POST",
            authenticated: true
        )
        operationRequest.httpBody = try Self.encoder.encode(operation)
        operationRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        let accepted = try Self.decoder.decode(
            PFSSCloudflareOperationResponse.self,
            from: try await perform(operationRequest)
        )
        var resolutionRequest = try request(
            path: "/v1/sync/quarantines/\(quarantineID)/resolve",
            method: "POST",
            authenticated: true
        )
        resolutionRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "repair",
            "reason": reason,
            "replacementOperationID": operation.id.uuidString.lowercased()
        ])
        resolutionRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        _ = try await perform(resolutionRequest)
        return accepted.revision
    }

    func conflictAuditEvents() async throws -> [PFSSConflictAuditEvent] {
        let data = try await perform(
            try request(path: "/v1/sync/conflict-audit", authenticated: true)
        )
        return try Self.decoder.decode(
            PFSSConflictAuditList.self,
            from: data
        ).events
    }

    func recordRecoveryAudit(
        _ event: PFSSRecoveryAuditEvent,
        provider: PFSSRecoveryAuditProvider? = nil
    ) async throws {
        var request = try request(
            path: "/v1/recovery/audit",
            method: "POST",
            authenticated: true
        )
        var body = ["eventType": event.rawValue]
        if let provider { body["provider"] = provider.rawValue }
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    func makeSynchronizationAdapter() throws -> PFSSCloudflareSynchronizationAdapter {
        guard let token = credentialStore.load() else {
            throw PFSSCloudflareBetaError.notEnrolled
        }
        return PFSSCloudflareSynchronizationAdapter(
            configuration: try configuration(),
            deviceToken: token,
            session: session,
            removeCredential: { [credentialStore] in
                credentialStore.delete()
            }
        )
    }

    func makeConfigurationForRemoval() throws -> PFSSCloudflareBetaConfiguration {
        try configuration()
    }

    func storedDeviceTokenForRemoval() -> String? {
        credentialStore.load()
    }

    private func configuration() throws -> PFSSCloudflareBetaConfiguration {
        guard let url = URL(string: savedEndpoint), url.scheme == "https" else {
            throw PFSSCloudflareBetaError.invalidEndpoint
        }
        return PFSSCloudflareBetaConfiguration(endpoint: url)
    }

    private func request(
        path: String,
        method: String = "GET",
        authenticated: Bool
    ) throws -> URLRequest {
        let configuration = try configuration()
        let pathParts = path.split(separator: "?", maxSplits: 1)
        let endpoint = configuration.endpoint.appendingPathComponent(
            String(pathParts[0]).trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        )
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        if pathParts.count == 2 {
            components?.percentEncodedQuery = String(pathParts[1])
        }
        guard let url = components?.url else {
            throw PFSSCloudflareBetaError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if authenticated {
            guard let token = credentialStore.load() else {
                throw PFSSCloudflareBetaError.notEnrolled
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        try await performWithResponse(request).data
    }

    private func performWithResponse(_ request: URLRequest) async throws
        -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PFSSCloudflareBetaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let directive = PFSSCompanyDataRemovalCoordinator.directive(
                from: data
            ),
            let token = credentialStore.load() {
                try await PFSSCompanyDataRemovalCoordinator.shared.execute(
                    directive: directive,
                    configuration: try configuration(),
                    deviceToken: token,
                    removeCredential: { [credentialStore] in
                        credentialStore.delete()
                    }
                )
                backups = []
                currentSession = nil
                members = []
                devices = []
                state = .notEnrolled
                throw PFSSCloudflareBetaError.companyDataRemoved
            }
            if let response = try? Self.decoder.decode(
                PFSSAccountHoldResponse.self,
                from: data
            ), response.error == "account_access_on_hold" {
                throw PFSSCloudflareBetaError.accountHold(response.hold)
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw PFSSCloudflareBetaError.server(
                object?["error"] as? String
                    ?? "PFSS beta request failed (\(http.statusCode))."
            )
        }
        return (data, http)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

struct PFSSMileageSynchronizationResponse: Decodable {
    let cursor: Int
    let hasMore: Bool
    let changes: [PFSSMileageSynchronizationChange]
}

private struct PFSSCloudflareCanonicalBaseline: Decodable {
    let cursor: Int
    let records: [PFSSCloudflareCanonicalRecord]
}

private struct PFSSCloudflareCanonicalRecord: Decodable {
    let revision: String
    let operation: PendingOfflineOperation
}

struct PFSSMileageSynchronizationChange: Decodable {
    enum ChangeType: String, Decodable {
        case upsert
        case delete
    }

    let sequence: Int
    let tripID: UUID
    let type: ChangeType
    let payload: MileageTrip?
    let changedAt: Date
}

enum PFSSCloudSynchronizationStateKeys {
    private static let legacyCursor = "PFSSCloudSynchronizationCursor"
    private static let cursorPrefix = "PFSSCloudSynchronizationCursor."
    private static let bootstrapPrefix =
        "PFSSCloudSynchronizationBootstrap."
    private static let legacyBaselineV3Prefix =
        "PFSSCloudSynchronizationBaselineV3."
    private static let legacyBaselineV4Prefix =
        "PFSSCloudSynchronizationBaselineV4."
    private static let legacyBaselineV5Prefix =
        "PFSSCloudSynchronizationBaselineV5."
    private static let legacyBaselineV6Prefix =
        "PFSSCloudSynchronizationBaselineV6."
    private static let legacyBaselineV7Prefix =
        "PFSSCloudSynchronizationBaselineV7."
    private static let baselineV3Prefix =
        // Generation 8 reruns canonical replacement after recovery learned to
        // isolate duplicate historical assignment numbers instead of allowing
        // one invalid pair to empty the entire assignment store.
        "PFSSCloudSynchronizationBaselineV8."

    static func cursor(deviceID: String) -> String {
        "\(cursorPrefix)\(normalized(deviceID))"
    }

    static func bootstrap(deviceID: String) -> String {
        "\(bootstrapPrefix)\(normalized(deviceID))"
    }

    static func baselineV3(deviceID: String) -> String {
        "\(baselineV3Prefix)\(normalized(deviceID))"
    }

    static func migrateLegacyCursorIfNeeded(
        deviceID: String,
        defaults: UserDefaults = .standard
    ) {
        let scopedKey = cursor(deviceID: deviceID)
        guard defaults.object(forKey: scopedKey) == nil,
              defaults.object(forKey: legacyCursor) != nil else { return }
        defaults.set(defaults.integer(forKey: legacyCursor), forKey: scopedKey)
        defaults.removeObject(forKey: legacyCursor)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where
            key == legacyCursor ||
            key.hasPrefix(cursorPrefix) ||
            key.hasPrefix(bootstrapPrefix) ||
            key.hasPrefix(legacyBaselineV3Prefix) ||
            key.hasPrefix(legacyBaselineV4Prefix) ||
            key.hasPrefix(legacyBaselineV5Prefix) ||
            key.hasPrefix(legacyBaselineV6Prefix) ||
            key.hasPrefix(legacyBaselineV7Prefix) ||
            key.hasPrefix(baselineV3Prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func normalized(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
private final class PFSSCloudSnapshotPublisher {
    private weak var store: AppDataStore?
    private let manager: PFSSCloudflareBetaManager
    private var scheduledTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var pushTokenObserver: NSObjectProtocol?
    private let defaults: UserDefaults
    private var cursorKey: String?
    private var isBootstrapReady = false
    private var didScheduleInitialSnapshot = false

    init(
        store: AppDataStore,
        manager: PFSSCloudflareBetaManager,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.manager = manager
        self.defaults = defaults
    }

    func start() {
        store?.startOfflineServices()
        if wakeObserver == nil {
            wakeObserver = NotificationCenter.default.addObserver(
                forName: .pfssSynchronizationWakeRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let wakeRequest = notification.object
                    as? PFSSSynchronizationWakeRequest
                Task { @MainActor [weak self] in
                    self?.requestImmediateSynchronization(
                        wakeRequest: wakeRequest
                    )
                }
            }
        }
        if pushTokenObserver == nil {
            pushTokenObserver = NotificationCenter.default.addObserver(
                forName: .pfssSynchronizationPushTokenDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let token = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    try? await self?.manager.registerSynchronizationPushToken(token)
                }
            }
        }
        if let token = PFSSSynchronizationPushBridge.currentToken {
            Task { [manager] in
                try? await manager.registerSynchronizationPushToken(token)
            }
        }
        startPolling()
        if let wakeRequest = PFSSSynchronizationPushBridge.consumePendingWake() {
            requestImmediateSynchronization(wakeRequest: wakeRequest)
        }
    }

    deinit {
        if let wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
        }
        if let pushTokenObserver {
            NotificationCenter.default.removeObserver(pushTokenObserver)
        }
        scheduledTask?.cancel()
        pollingTask?.cancel()
    }

    /// Invalidates both persisted and in-memory delivery checkpoints before
    /// the Owner's intentionally empty store can pull or publish anything.
    func beginOwnerLocalRecovery() {
        scheduledTask?.cancel()
        store?.requireAuthoritativePullBeforeUpload()
        isBootstrapReady = false
        didScheduleInitialSnapshot = false
        cursorKey = nil
        PFSSCloudSynchronizationStateKeys.clearAll(defaults: defaults)
    }

    private func startPolling(
        wakeRequest: PFSSSynchronizationWakeRequest? = nil
    ) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            var pendingWakeRequest = wakeRequest
            while !Task.isCancelled {
                if let deliveryID = pendingWakeRequest?.deliveryID {
                    try? await self?.manager.reportSynchronizationPushEvent(
                        deliveryID: deliveryID,
                        event: "received",
                        cursor: self?.cursorKey.map {
                            self?.defaults.integer(forKey: $0) ?? 0
                        }
                    )
                    try? await self?.manager.reportSynchronizationPushEvent(
                        deliveryID: deliveryID,
                        event: "syncStarted",
                        cursor: self?.cursorKey.map {
                            self?.defaults.integer(forKey: $0) ?? 0
                        }
                    )
                }
                if await self?.prepareBootstrapIfNeeded() == true {
                    await self?.synchronizeNow()
                    if let wake = pendingWakeRequest {
                        let endingCursor = self?.cursorKey.map {
                            self?.defaults.integer(forKey: $0) ?? 0
                        } ?? 0
                        let completed = wake.expectedCursor.map {
                            endingCursor >= $0
                        } ?? true
                        if let deliveryID = wake.deliveryID {
                            try? await self?.manager
                                .reportSynchronizationPushEvent(
                                    deliveryID: deliveryID,
                                    event: completed
                                        ? "syncCompleted"
                                        : "syncFailed",
                                    cursor: endingCursor
                                )
                        }
                        PFSSSynchronizationPushBridge.completeWake(
                            wake.wakeID,
                            result: completed ? .newData : .failed
                        )
                        pendingWakeRequest = nil
                    }
                } else if let wake = pendingWakeRequest {
                    if let deliveryID = wake.deliveryID {
                        try? await self?.manager.reportSynchronizationPushEvent(
                            deliveryID: deliveryID,
                            event: "syncFailed",
                            cursor: nil
                        )
                    }
                    PFSSSynchronizationPushBridge.completeWake(
                        wake.wakeID,
                        result: .failed
                    )
                    pendingWakeRequest = nil
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// Launch, foreground, and future silent-push signals all converge on the
    /// same pull-before-upload path. Restarting the single polling task
    /// coalesces repeated signals and performs the first pass immediately.
    private func requestImmediateSynchronization(
        wakeRequest: PFSSSynchronizationWakeRequest? = nil
    ) {
        startPolling(wakeRequest: wakeRequest)
    }

    /// Establishes a complete local company snapshot before incremental
    /// changes are allowed to run. Starting polling first can deliver one
    /// record, make the store appear non-empty, and incorrectly skip the full
    /// bootstrap on a newly enrolled device.
    private func prepareBootstrapIfNeeded() async -> Bool {
        guard let store else { return false }
        if isBootstrapReady { return true }

        do {
            try await manager.refreshSession()
            guard let session = manager.currentSession else { return false }
            store.updateCloudIdentity(
                role: session.member.role,
                employeeID: session.member.employeeID,
                displayName: session.member.displayName,
                email: session.member.email
            )

            let deviceID = session.device.id
            let scopedCursorKey = PFSSCloudSynchronizationStateKeys.cursor(
                deviceID: deviceID
            )
            let scopedBootstrapKey = PFSSCloudSynchronizationStateKeys.bootstrap(
                deviceID: deviceID
            )
            let scopedBaselineKey = PFSSCloudSynchronizationStateKeys.baselineV3(
                deviceID: deviceID
            )
            PFSSCloudSynchronizationStateKeys.migrateLegacyCursorIfNeeded(
                deviceID: deviceID,
                defaults: defaults
            )
            cursorKey = scopedCursorKey

            if defaults.bool(forKey: scopedBaselineKey) == false {
                // Local content is not evidence of a complete tenant baseline.
                // Upgrade and newly enrolled devices both hydrate from the
                // cursor-stamped cloud snapshot while retaining durable local
                // intent for reconciliation after the baseline is installed.
                let bootstrap = try await manager.synchronizationBootstrap()
                try store.applySynchronizationBaseline(bootstrap.data)
                let canonical = try await manager.synchronizationCanonicalBaseline()
                store.applyAuthoritativeCanonicalBaseline(canonical.operations)
                let recoveredCursor = max(bootstrap.cursor, canonical.cursor)
                defaults.set(recoveredCursor, forKey: scopedCursorKey)
                // The local cursor is the delivery checkpoint. Server-side
                // acknowledgement is retention/diagnostic bookkeeping and
                // must not invalidate an otherwise complete bootstrap. A
                // later synchronization cycle retries it automatically.
                try? await manager.acknowledgeSynchronizationCursor(
                    recoveredCursor
                )
                defaults.set(true, forKey: scopedBootstrapKey)
                defaults.set(true, forKey: scopedBaselineKey)
            }

            isBootstrapReady = true
            if didScheduleInitialSnapshot == false {
                didScheduleInitialSnapshot = true
                schedule()
            }
            return true
        } catch {
            // Remain gated and retry. An empty installation must never build a
            // partial workspace from incremental changes or publish it as the
            // tenant snapshot.
            return false
        }
    }

    private func synchronizeNow() async {
        guard let store else { return }
        // Membership-to-employee links and access lifecycle can change on the
        // server while this device remains enrolled, so refresh every poll.
        try? await manager.refreshSession()
        if let member = manager.currentSession?.member {
            store.updateCloudIdentity(
                role: member.role,
                employeeID: member.employeeID,
                displayName: member.displayName,
                email: member.email
            )
        }

        // Apply completed Manager/Owner decisions before sending newly queued
        // work. An app resuming from suspension can otherwise submit a change
        // against the revision that existed before its prior conflict was
        // resolved.
        do {
            store.applyServerConflictResolutionReceipts(
                try await manager.conflictResolutionReceipts()
            )
        } catch {
            // A later poll reconciles any missed Manager conflict decision.
        }
        do {
            store.applyServerQuarantineResolutionReceipts(
                try await manager.quarantineResolutionReceipts()
            )
        } catch {
            // A later poll reconciles any missed Manager quarantine decision.
        }

        guard isBootstrapReady, let cursorKey else { return }
        let recoveryStartedAt = Date()
        let startingCursor = defaults.integer(forKey: cursorKey)
        var pulledChanges = 0
        var alreadyReflected = 0
        var superseded = 0

        // Pull is an upload gate. A stale or uncertain device must first see
        // every authoritative tenant change; failure leaves local intent in
        // the durable queue and does not submit it against an unknown base.
        do {
            let result = try await pullAuthoritativeChanges(
                store: store,
                cursorKey: cursorKey
            )
            pulledChanges += result.pulled
            alreadyReflected += result.alreadyReflected
            superseded += result.superseded
            store.completeAuthoritativePullBeforeUpload()
            store.updateCloudSynchronizationAccessStatus(.available)
        } catch {
            updateAccessStatus(for: error, store: store)
            return
        }

        await store.offlineSynchronizationService?
            .processPendingOperations(forceRetry: true)

        for operation in store.offlineOperationQueue.operations where
            operation.status == .conflicted &&
            operation.conflict?.requiresHumanReview == true &&
            operation.metadata["serverConflictID"] == nil {
            do {
                let conflictID = try await manager
                    .reportSynchronizationConflict(operation)
                try store.offlineOperationQueue.mutate(id: operation.id) {
                    $0.metadata["serverConflictID"] = conflictID
                    $0.metadata["conflictDeliveryStatus"] = "sentForReview"
                }
            } catch {
                try? store.offlineOperationQueue.mutate(id: operation.id) {
                    $0.metadata["conflictDeliveryStatus"] = "deliveryFailed"
                    $0.metadata["conflictDeliveryError"] =
                        error.localizedDescription
                }
            }
        }

        for operation in store.offlineOperationQueue.operations where
            operation.metadata["quarantinedAt"] != nil &&
            operation.metadata["serverQuarantineID"] == nil &&
            operation.metadata["serverConflictID"] == nil {
            do {
                let quarantineID = try await manager
                    .reportSynchronizationQuarantine(
                        operation,
                        reason: operation.metadata["quarantineReason"]
                            ?? operation.failure?.message
                            ?? "This operation requires authorized review."
                    )
                try store.offlineOperationQueue.mutate(id: operation.id) {
                    $0.metadata["serverQuarantineID"] = quarantineID
                    $0.metadata["quarantineDeliveryStatus"] = "sentForReview"
                }
            } catch {
                try? store.offlineOperationQueue.mutate(id: operation.id) {
                    $0.metadata["quarantineDeliveryStatus"] = "deliveryFailed"
                    $0.metadata["quarantineDeliveryError"] =
                        error.localizedDescription
                }
            }
        }

        // Pull once more to consume operations accepted during this cycle and
        // leave the local store on the exact server revision represented by
        // its acknowledged cursor.
        do {
            let result = try await pullAuthoritativeChanges(
                store: store,
                cursorKey: cursorKey
            )
            pulledChanges += result.pulled
            alreadyReflected += result.alreadyReflected
            superseded += result.superseded
            store.updateCloudSynchronizationAccessStatus(.available)
        } catch {
            updateAccessStatus(for: error, store: store)
        }

        let requiringReview = store.offlineOperationQueue.operations.filter {
            $0.status == .conflicted && $0.conflict?.requiresHumanReview == true
        }.count
        if pulledChanges > 0 || alreadyReflected > 0 || superseded > 0 {
            PFSSSynchronizationRecoveryStatus.shared.record(
                SynchronizationRecoverySummary(
                    startedAt: recoveryStartedAt,
                    completedAt: Date(),
                    startingCursor: startingCursor,
                    endingCursor: defaults.integer(forKey: cursorKey),
                    pulledChanges: pulledChanges,
                    alreadyReflected: alreadyReflected,
                    supersededDeviceChanges: superseded,
                    requiringReview: requiringReview
                )
            )
        }

        if manager.currentSession?.member.role.canManageAccess == true {
            do {
                try store.reconcileServerConflictInbox(
                    try await manager.synchronizationConflicts()
                )
            } catch {
                // Retain the last durable Manager conflict inbox until the next poll.
            }
            do {
                let quarantines = try await manager.synchronizationQuarantines()
                var requiringReview: [PFSSCloudflareSynchronizationQuarantine] = []
                for item in quarantines {
                    guard item.alreadyMatchesCloudRecord else {
                        requiringReview.append(item)
                        continue
                    }
                    do {
                        _ = try await manager.resolveSynchronizationQuarantine(
                            id: item.id,
                            action: .discard,
                            reason: "Automatically cleared because the requested record already matches the company record."
                        )
                    } catch {
                        requiringReview.append(item)
                    }
                }
                try store.reconcileServerQuarantineInbox(
                    requiringReview
                )
            } catch {
                // Retain the last durable Manager quarantine inbox until the next poll.
            }
        }
        try? await manager.reportSynchronizationDeviceHealth(
            deviceHealthReport(store: store)
        )
    }

    private func deviceHealthReport(
        store: AppDataStore,
        now: Date = Date()
    ) -> PFSSSynchronizationDeviceHealthReport {
        let operations = store.offlineOperationQueue.orderedOperations.filter {
            !$0.status.isTerminal
        }
        let retryCutoff = now.addingTimeInterval(-86_400)
        var blockingKeys: Set<String> = []
        var blockedDependencies = 0
        for operation in operations {
            let keys = operation.synchronizationDependencyKeys
            if !keys.isDisjoint(with: blockingKeys) {
                blockedDependencies += 1
            }
            if operation.status == .failed ||
                operation.status == .conflicted ||
                operation.status == .waitingForRetry {
                blockingKeys.formUnion(keys)
            }
        }
        let appBuild = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        return PFSSSynchronizationDeviceHealthReport(
            appBuild: appBuild,
            queueCount: operations.count,
            oldestQueuedAt: operations.map(\.createdAt).min(),
            failedCount: operations.filter { $0.status == .failed }.count,
            waitingRetryCount: operations.filter {
                $0.status == .waitingForRetry
            }.count,
            retryAttempts24h: operations.reduce(0) { total, operation in
                total + operation.retryAttempts.filter {
                    $0.startedAt >= retryCutoff
                }.count
            },
            blockedDependencyCount: blockedDependencies,
            conflictedCount: operations.filter {
                $0.status == .conflicted
            }.count,
            quarantinedCount: operations.filter {
                $0.metadata["quarantinedAt"] != nil
            }.count
        )
    }

    private func pullAuthoritativeChanges(
        store: AppDataStore,
        cursorKey: String
    ) async throws -> (pulled: Int, alreadyReflected: Int, superseded: Int) {
        var cursor = defaults.integer(forKey: cursorKey)
        var hasMore = true
        var pulled = 0
        var alreadyReflected = 0
        var superseded = 0
        while hasMore {
            let page = try await manager.synchronizationChanges(after: cursor)
            let recovery = store.reconcilePendingOperationsBeforeUpload(
                with: page.operations
            )
            store.applyRemoteRecordOperations(page.operations)
            pulled += page.operations.count
            alreadyReflected += recovery.alreadyReflected
            superseded += recovery.superseded
            cursor = page.cursor
            hasMore = page.hasMore
            defaults.set(cursor, forKey: cursorKey)
        }
        // Changes have already been decoded, applied, and durably checkpointed
        // locally. Do not report cloud synchronization as unavailable merely
        // because the server could not record its advisory acknowledgement.
        // This method runs every polling cycle, so the acknowledgement is
        // naturally retried without blocking uploads or misleading the user.
        try? await manager.acknowledgeSynchronizationCursor(cursor)
        return (pulled, alreadyReflected, superseded)
    }

    private func updateAccessStatus(for error: Error, store: AppDataStore) {
        if case let PFSSCloudflareBetaError.accountHold(hold) = error {
            store.updateCloudSynchronizationAccessStatus(.accountHold(hold))
        } else if case let PFSSCloudflareBetaError.server(message) = error,
                  message == "access_suspended" {
            store.updateCloudSynchronizationAccessStatus(.suspended)
        } else {
            store.updateCloudSynchronizationAccessStatus(
                .unavailable(error.localizedDescription)
            )
        }
    }

    func schedule(delayNanoseconds: UInt64 = 2_000_000_000) {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled,
                      let self,
                      let store = self.store,
                      self.isBootstrapReady,
                      store.hasLocalCompanyData else { return }
                if self.manager.currentSession == nil {
                    try await self.manager.refreshSession()
                }
                guard self.manager.currentSession?.member.role
                        .canManageRecovery == true else { return }
                let data = try store.createPortableArchive()
                try await self.manager.publishSynchronizationSnapshot(data)
            } catch {
                // A later local save or app launch schedules another attempt.
            }
        }
    }
}

@MainActor
final class PFSSCloudflareSynchronizationAdapter: OfflineSynchronizationAdapter {
    private let configuration: PFSSCloudflareBetaConfiguration
    private let deviceToken: String
    private let session: URLSession
    private let removeCredential: @MainActor () -> Void

    init(
        configuration: PFSSCloudflareBetaConfiguration,
        deviceToken: String,
        session: URLSession = .shared,
        removeCredential: @escaping @MainActor () -> Void = {
            PFSSCloudflareCredentialStore().delete()
        }
    ) {
        self.configuration = configuration
        self.deviceToken = deviceToken
        self.session = session
        self.removeCredential = removeCredential
    }

    func synchronize(
        operation: PendingOfflineOperation
    ) async -> OfflineSynchronizationAdapterResult {
        do {
            var request = URLRequest(
                url: configuration.endpoint.appendingPathComponent("v1/operations")
            )
            request.httpMethod = "POST"
            request.httpBody = try Self.encoder.encode(operation)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PFSSCloudflareBetaError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                if let directive = PFSSCompanyDataRemovalCoordinator.directive(
                    from: data
                ) {
                    try await PFSSCompanyDataRemovalCoordinator.shared.execute(
                        directive: directive,
                        configuration: configuration,
                        deviceToken: deviceToken,
                        removeCredential: removeCredential
                    )
                    throw PFSSCloudflareBetaError.companyDataRemoved
                }
                if http.statusCode == 409,
                   let conflictResponse = try? Self.decoder.decode(
                        PFSSCloudflareRecordConflictResponse.self,
                        from: data
                   ),
                   conflictResponse.error == "record_conflict",
                   let conflictID = conflictResponse.conflictID,
                   let currentRevision = conflictResponse.currentRevision,
                   let remoteOperation = conflictResponse.currentOperation {
                    if let revision = await automaticallyRebaseCatalogUsage(
                        operation,
                        onto: remoteOperation,
                        revision: currentRevision,
                        conflictID: conflictID
                    ) {
                        return .synchronized(remoteRevision: revision)
                    }
                    return .conflicted(OfflineConflictInformation(
                        kind: .concurrentModification,
                        localVersion: OfflineRecordVersion(
                            revision: operation.baseRevision,
                            modifiedAt: operation.createdAt,
                            source: .local,
                            payload: operation.payload
                        ),
                        remoteVersion: OfflineRecordVersion(
                            revision: currentRevision,
                            modifiedAt: remoteOperation.createdAt,
                            source: .remote,
                            payload: remoteOperation.payload
                        )
                    ))
                }
                let object = (try? JSONSerialization.jsonObject(with: data))
                    as? [String: Any]
                let serverCode = object?["error"] as? String
                let message = serverCode.map {
                    "PFSS rejected this change: \($0)."
                } ?? "Operation synchronization failed (\(http.statusCode))."
                return .failed(OfflineFailureDetails(
                    category: http.statusCode == 400 ? .validation : .server,
                    code: serverCode ?? String(http.statusCode),
                    message: message,
                    isRetryable: http.statusCode >= 500,
                    metadata: ["httpStatus": String(http.statusCode)]
                ))
            }
            let result = try Self.decoder.decode(
                PFSSCloudflareOperationResponse.self,
                from: data
            )
            if result.supersededByCloud == true,
               let currentOperation = result.currentOperation {
                return .supersededByCloud(
                    remoteRevision: result.revision,
                    operation: currentOperation
                )
            }
            return .synchronized(remoteRevision: result.revision)
        } catch {
            return .failed(OfflineFailureDetails(
                category: .server,
                message: error.localizedDescription,
                isRetryable: true
            ))
        }
    }

    /// Catalog usage count and last-used date are system-maintained telemetry,
    /// not competing human edits. When those are the only differences, safely
    /// place the newer usage snapshot on the current cloud revision instead of
    /// sending routine job creation to the conflict inbox.
    private func automaticallyRebaseCatalogUsage(
        _ localOperation: PendingOfflineOperation,
        onto remoteOperation: PendingOfflineOperation,
        revision: String,
        conflictID: String
    ) async -> String? {
        guard localOperation.entityType == .catalog,
              let localMutation = try? OfflineRecordMutationCodec.decode(
                localOperation.payload,
                decoder: Self.decoder
              ),
              let remoteMutation = try? OfflineRecordMutationCodec.decode(
                remoteOperation.payload,
                decoder: Self.decoder
              ),
              let localItem = try? Self.decoder.decode(
                ServiceCatalogItem.self,
                from: localMutation.recordData
              ),
              let remoteItem = try? Self.decoder.decode(
                ServiceCatalogItem.self,
                from: remoteMutation.recordData
              ),
              Self.catalogBusinessFieldsMatch(localItem, remoteItem),
              localItem.usageCount >= remoteItem.usageCount else {
            return nil
        }

        do {
            var rebased = localOperation
            try OfflineRecordMutationCodec.rebase(
                &rebased,
                to: revision,
                decoder: Self.decoder,
                encoder: Self.encoder
            )
            rebased.metadata["automaticallyResolvedConflictID"] = conflictID
            var request = URLRequest(
                url: configuration.endpoint.appendingPathComponent("v1/operations")
            )
            request.httpMethod = "POST"
            request.httpBody = try Self.encoder.encode(rebased)
            request.setValue(
                "Bearer \(deviceToken)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return try Self.decoder.decode(
                PFSSCloudflareOperationResponse.self,
                from: data
            ).revision
        } catch {
            return nil
        }
    }

    nonisolated private static func catalogBusinessFieldsMatch(
        _ lhs: ServiceCatalogItem,
        _ rhs: ServiceCatalogItem
    ) -> Bool {
        lhs.id == rhs.id &&
        lhs.itemName == rhs.itemName &&
        lhs.itemDescription == rhs.itemDescription &&
        lhs.defaultQuantity == rhs.defaultQuantity &&
        lhs.defaultPrice == rhs.defaultPrice &&
        lhs.estimatedMinutesPerUnit == rhs.estimatedMinutesPerUnit &&
        lhs.itemType == rhs.itemType &&
        lhs.taxTreatment == rhs.taxTreatment &&
        lhs.lifecycleStatus == rhs.lifecycleStatus
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Selects remote queueing only when this installation already has a valid
/// Cloudflare endpoint and protected device credential. The app session host
/// recreates this store immediately after enrollment or sign-in so remote
/// synchronization can begin without relaunching the app.
@MainActor
enum PFSSCloudflareAppDataStoreFactory {
    static func make() -> AppDataStore {
        let manager = PFSSCloudflareBetaManager()
        guard manager.isEnrolled,
              !manager.savedEndpoint.isEmpty,
              let adapter = try? manager.makeSynchronizationAdapter() else {
            let store = AppDataStore()
            PFSSCompanyDataRemovalCoordinator.shared.attach(store: store)
            return store
        }

        let store = AppDataStore(
            offlineSynchronizationMode: .queueRemoteOperations,
            offlineSynchronizationAdapter: adapter
        )
        store.requireAuthoritativePullBeforeUpload()
        PFSSCompanyDataRemovalCoordinator.shared.attach(store: store)
        let snapshotPublisher = PFSSCloudSnapshotPublisher(
            store: store,
            manager: manager
        )
        store.onPersistentDataSaved = {
            snapshotPublisher.schedule()
        }
        store.onOwnerLocalDataCleared = {
            snapshotPublisher.beginOwnerLocalRecovery()
        }
        store.onServerConflictResolutionRequested = {
            conflictID, resolution, reason, affectedFields in
            try await manager.resolveSynchronizationConflict(
                id: conflictID,
                resolution: resolution,
                reason: reason,
                affectedFields: affectedFields
            )
        }
        store.onRevokedDeviceConflictCleanupRequested = {
            sourceDeviceID, expectedCount, reason in
            try await manager.discardRevokedDeviceSynchronizationConflicts(
                sourceDeviceID: sourceDeviceID,
                expectedCount: expectedCount,
                reason: reason
            )
        }
        store.onServerQuarantineResolutionRequested = {
            quarantineID, resolution, reason in
            try await manager.resolveSynchronizationQuarantine(
                id: quarantineID,
                action: resolution,
                reason: reason
            )
        }
        store.onServerQuarantineRepairRequested = {
            quarantineID, operation, reason in
            try await manager.submitRepairedQuarantineOperation(
                quarantineID: quarantineID,
                operation: operation,
                reason: reason
            )
        }
        Task {
            if PFSSCompanyDataRemovalCoordinator.shared.isRemovalPending {
                guard let configuration = try? manager.makeConfigurationForRemoval(),
                      let token = manager.storedDeviceTokenForRemoval() else {
                    // Fail closed. The app-level removal gate remains visible
                    // until the authenticated acknowledgement can complete.
                    return
                }
                do {
                    try await PFSSCompanyDataRemovalCoordinator.shared
                        .resumeIfNeeded(
                            configuration: configuration,
                            deviceToken: token,
                            removeCredential: {
                                PFSSCloudflareCredentialStore().delete()
                            }
                        )
                } catch {
                    // Never start synchronization while removal is incomplete.
                    return
                }
            }

            guard manager.isEnrolled else { return }
            snapshotPublisher.start()
        }
        return store
    }
}
