//
//  PFSSCompanyDataRemoval.swift
//  PPS Receipt Printer
//
//  Phase 16 – Resumable company-data removal for revoked devices.
//

import Foundation

extension Notification.Name {
    static let pfssCompanyDataWasRemoved = Notification.Name(
        "PFSSCompanyDataWasRemoved"
    )
    static let pfssCompanyDataRemovalStateDidChange = Notification.Name(
        "PFSSCompanyDataRemovalStateDidChange"
    )
    static let pfssUserDidLogOut = Notification.Name(
        "PFSSUserDidLogOut"
    )
}

struct PFSSCompanyDataRemovalDirective: Codable, Equatable {
    var type: String
    var tenantID: String
    var deviceID: String
    var issuedAt: Date
}

private struct PFSSCompanyDataRemovalEnvelope: Decodable {
    var error: String
    var directive: PFSSCompanyDataRemovalDirective
}

enum PFSSCompanyDataRemovalError: LocalizedError {
    case storeUnavailable
    case invalidAcknowledgement

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "PFSS could not access the local company data store."
        case .invalidAcknowledgement:
            return "PFSS Cloud did not acknowledge company-data removal."
        }
    }
}

@MainActor
final class PFSSCompanyDataRemovalCoordinator {
    static let shared = PFSSCompanyDataRemovalCoordinator()

    private weak var store: AppDataStore?
    private let defaults: UserDefaults
    private let backupService: PFSSLocalBackupService
    private let session: URLSession
    private let pendingKey = "PFSSCompanyDataRemovalPending"
    private let synchronizationCursorKey = "PFSSCloudSynchronizationCursor"
    private let synchronizedRecordRevisionsKey =
        "PFSSSynchronizedRecordRevisions"

    init(
        defaults: UserDefaults = .standard,
        backupService: PFSSLocalBackupService? = nil,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.backupService = backupService ?? PFSSLocalBackupService()
        self.session = session
    }

    var isRemovalPending: Bool {
        defaults.bool(forKey: pendingKey)
    }

    func attach(store: AppDataStore) {
        self.store = store
    }

    static func directive(from data: Data) -> PFSSCompanyDataRemovalDirective? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(
            PFSSCompanyDataRemovalEnvelope.self,
            from: data
        ),
        envelope.error == "company_data_removal_required",
        envelope.directive.type == "remove_company_data" else {
            return nil
        }
        return envelope.directive
    }

    func execute(
        directive: PFSSCompanyDataRemovalDirective,
        configuration: PFSSCloudflareBetaConfiguration,
        deviceToken: String,
        removeCredential: @MainActor () -> Void
    ) async throws {
        setRemovalPending(true)
        try removeLocalCompanyData()
        try await acknowledge(
            configuration: configuration,
            deviceToken: deviceToken
        )
        removeCredential()
        setRemovalPending(false)
    }

    func resumeIfNeeded(
        configuration: PFSSCloudflareBetaConfiguration,
        deviceToken: String,
        removeCredential: @MainActor () -> Void
    ) async throws {
        guard isRemovalPending else { return }
        try removeLocalCompanyData()
        try await acknowledge(
            configuration: configuration,
            deviceToken: deviceToken
        )
        removeCredential()
        setRemovalPending(false)
    }

    func removeLocalCompanyData() throws {
        try removeLocalCompanyData(postRemovalNotice: true)
    }

    func logOut(removeCredential: @MainActor () -> Void) throws {
        try removeLocalCompanyData(postRemovalNotice: false)
        removeCredential()
        NotificationCenter.default.post(
            name: .pfssUserDidLogOut,
            object: nil
        )
    }

    private func removeLocalCompanyData(
        postRemovalNotice: Bool
    ) throws {
        guard let store else {
            throw PFSSCompanyDataRemovalError.storeUnavailable
        }
        try store.clearAllLocalData()
        store.clearCachedCloudIdentity()
        try backupService.removeAllBackups()
        PFSSOwnerRecoverySecurity.revokeLocalAccess()
        defaults.removeObject(forKey: synchronizationCursorKey)
        defaults.removeObject(forKey: synchronizedRecordRevisionsKey)
        if postRemovalNotice {
            NotificationCenter.default.post(
                name: .pfssCompanyDataWasRemoved,
                object: nil
            )
        }
    }

    private func setRemovalPending(_ isPending: Bool) {
        defaults.set(isPending, forKey: pendingKey)
        NotificationCenter.default.post(
            name: .pfssCompanyDataRemovalStateDidChange,
            object: nil
        )
    }

    private func acknowledge(
        configuration: PFSSCloudflareBetaConfiguration,
        deviceToken: String
    ) async throws {
        var request = URLRequest(
            url: configuration.endpoint.appendingPathComponent(
                "v1/device-removal/acknowledge"
            )
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(deviceToken)",
            forHTTPHeaderField: "Authorization"
        )
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw PFSSCompanyDataRemovalError.invalidAcknowledgement
        }
    }
}
