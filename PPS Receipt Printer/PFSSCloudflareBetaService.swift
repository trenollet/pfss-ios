//
//  PFSSCloudflareBetaService.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 5 – Tenant-isolated Cloudflare beta client.
//

import Combine
import Foundation
import Security

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
        var displayName: String
    }

    struct Member: Codable, Equatable {
        var id: String
        var displayName: String
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
        case let .server(message):
            return message
        }
    }
}

private struct PFSSCloudflareEnrollmentResponse: Decodable {
    var deviceToken: String
}

private struct PFSSCloudflareBackupList: Decodable {
    var backups: [PFSSCloudflareBackup]
}

private struct PFSSCloudflareOperationResponse: Decodable {
    var revision: String
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
}

private struct PFSSCloudflareSynchronizationConflictList: Decodable {
    var conflicts: [PFSSCloudflareSynchronizationConflict]
}

private struct PFSSCloudflareConflictReportResponse: Decodable {
    var conflictID: String
}

struct PFSSCloudflareConflictResolutionReceipt: Decodable {
    var id: String
    var resolution: String
    var resolvedAt: Date
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

private struct PFSSCloudflareSynchronizationChanges: Decodable {
    var cursor: Int
    var hasMore: Bool
    var changes: [PFSSCloudflareSynchronizationChange]
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
        members = []
        devices = []
        state = savedEndpoint.isEmpty ? .notConfigured : .notEnrolled
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

    func refresh() async throws {
        state = .working
        do {
            try await refreshSession()
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

    func synchronizationBootstrapData() async throws -> Data {
        try await perform(
            try request(path: "/v1/sync/bootstrap", authenticated: true)
        )
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
    ) async throws {
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
        _ = try await perform(request)
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
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw PFSSCloudflareBetaError.server(
                object?["error"] as? String
                    ?? "PFSS beta request failed (\(http.statusCode))."
            )
        }
        return data
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

@MainActor
private final class PFSSCloudSnapshotPublisher {
    private weak var store: AppDataStore?
    private let manager: PFSSCloudflareBetaManager
    private var scheduledTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private let cursorKey = "PFSSCloudSynchronizationCursor"

    init(store: AppDataStore, manager: PFSSCloudflareBetaManager) {
        self.store = store
        self.manager = manager
    }

    func start() {
        store?.startOfflineServices()
        startPolling()
        Task {
            do {
                try await manager.refreshSession()
                if let member = manager.currentSession?.member {
                    store?.updateCloudIdentity(
                        role: member.role,
                        employeeID: member.employeeID
                    )
                }
                if store?.hasLocalCompanyData == false {
                    let data = try await manager.synchronizationBootstrapData()
                    _ = try store?.applySynchronizationBootstrap(data)
                }
                schedule()
            } catch {
                // Polling remains active and will retry session access without
                // requiring the user to visit a particular screen.
            }
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronizeNow()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func synchronizeNow() async {
        guard let store else { return }
        if manager.currentSession == nil {
            try? await manager.refreshSession()
        }
        if let member = manager.currentSession?.member {
            store.updateCloudIdentity(
                role: member.role,
                employeeID: member.employeeID
            )
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

        do {
            store.applyServerConflictResolutionReceipts(
                try await manager.conflictResolutionReceipts()
            )
        } catch {
            // A later poll reconciles any missed Manager decision.
        }

        do {
            var cursor = UserDefaults.standard.integer(forKey: cursorKey)
            var hasMore = true
            while hasMore {
                let page = try await manager.synchronizationChanges(after: cursor)
                store.applyRemoteRecordOperations(page.operations)
                cursor = page.cursor
                hasMore = page.hasMore
                UserDefaults.standard.set(cursor, forKey: cursorKey)
            }
            store.updateCloudSynchronizationAccessStatus(.available)
        } catch {
            if case let PFSSCloudflareBetaError.server(message) = error,
               message == "access_suspended" {
                store.updateCloudSynchronizationAccessStatus(.suspended)
            } else {
                store.updateCloudSynchronizationAccessStatus(
                    .unavailable(error.localizedDescription)
                )
            }
            // The durable local queue and cursor remain unchanged for retry.
        }

        if manager.currentSession?.member.role.canManageAccess == true {
            do {
                try store.reconcileServerConflictInbox(
                    try await manager.synchronizationConflicts()
                )
            } catch {
                // Retain the last durable Manager inbox until the next poll.
            }
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
                   let remoteOperation = conflictResponse.currentOperation {
                    return .conflicted(OfflineConflictInformation(
                        kind: .concurrentModification,
                        localVersion: OfflineRecordVersion(
                            revision: operation.baseRevision,
                            modifiedAt: operation.createdAt,
                            source: .local,
                            payload: operation.payload
                        ),
                        remoteVersion: OfflineRecordVersion(
                            revision: conflictResponse.currentRevision,
                            modifiedAt: remoteOperation.createdAt,
                            source: .remote,
                            payload: remoteOperation.payload
                        )
                    ))
                }
                throw PFSSCloudflareBetaError.server(
                    "Operation synchronization failed (\(http.statusCode))."
                )
            }
            let result = try JSONDecoder().decode(
                PFSSCloudflareOperationResponse.self,
                from: data
            )
            return .synchronized(remoteRevision: result.revision)
        } catch {
            return .failed(OfflineFailureDetails(
                category: .server,
                message: error.localizedDescription,
                isRetryable: true
            ))
        }
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
/// Cloudflare endpoint and protected device credential. A newly enrolled
/// installation begins remote synchronization on its next app launch; an
/// unenrolled installation retains the established local-only behavior.
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
        PFSSCompanyDataRemovalCoordinator.shared.attach(store: store)
        let snapshotPublisher = PFSSCloudSnapshotPublisher(
            store: store,
            manager: manager
        )
        store.onPersistentDataSaved = {
            snapshotPublisher.schedule()
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
