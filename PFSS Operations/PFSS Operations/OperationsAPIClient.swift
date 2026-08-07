import Foundation

enum OperationsAPIError: LocalizedError {
    case invalidResponse
    case server(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "PFSS Operations received an unreadable server response."
        case let .server(message):
            return message
        case .unauthorized:
            return "Your PFSS Operations session has expired. Sign in again."
        }
    }
}

struct OperationsAPIClient {
    let endpoint: URL
    var session: URLSession = .shared

    init(
        endpoint: URL = URL(
            string: "https://pfss-beta-api.timrenollet.workers.dev"
        )!
    ) {
        self.endpoint = endpoint
    }

    func authorize(
        state: String,
        challenge: String,
        redirectURI: URL
    ) async throws -> OperationsAuthorizationSession {
        struct Body: Encodable {
            let state: String
            let codeChallenge: String
            let redirectURI: URL
        }
        return try await send(
            path: "/v1/operations-auth/authorize",
            method: "POST",
            body: Body(
                state: state,
                codeChallenge: challenge,
                redirectURI: redirectURI
            )
        )
    }

    func completeAuthorization(
        state: String,
        code: String,
        verifier: String,
        redirectURI: URL,
        deviceID: UUID,
        deviceName: String
    ) async throws -> OperationsSignInReceipt {
        struct Body: Encodable {
            let state: String
            let code: String
            let codeVerifier: String
            let redirectURI: URL
            let deviceID: UUID
            let deviceName: String
        }
        return try await send(
            path: "/v1/operations-auth/callback",
            method: "POST",
            body: Body(
                state: state,
                code: code,
                codeVerifier: verifier,
                redirectURI: redirectURI,
                deviceID: deviceID,
                deviceName: deviceName
            )
        )
    }

    func session(token: String) async throws -> OperationsSessionReceipt {
        try await get(path: "/v1/operations/session", token: token)
    }

    func summary(token: String) async throws -> OperationsSummary {
        try await get(path: "/v1/operations/summary", token: token)
    }

    func monitoring(token: String) async throws -> OperationsMonitoring {
        try await get(path: "/v1/operations/monitoring", token: token)
    }

    func accounts(
        token: String,
        search: String,
        status: String
    ) async throws -> OperationsAccountsPage {
        var components = URLComponents()
        components.path = "/v1/operations/accounts"
        components.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "status", value: status),
        ]
        guard let path = components.string else {
            throw OperationsAPIError.invalidResponse
        }
        return try await get(path: path, token: token)
    }

    func account(token: String, id: String) async throws
        -> OperationsAccountDetail {
        try await get(
            path: "/v1/operations/accounts/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
            token: token
        )
    }

    func createPlanOverride(
        token: String, accountID: String, planCode: String,
        reason: String, permanent: Bool, expiresAt: Date?
    ) async throws -> OperationsPlanOverrideReceipt {
        struct Body: Encodable {
            let planCode: String
            let reason: String
            let permanent: Bool
            let expiresAt: Date?
        }
        let encodedID = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await send(
            path: "/v1/operations/accounts/\(encodedID)/plan-override",
            method: "POST",
            body: Body(planCode: planCode, reason: reason,
                       permanent: permanent, expiresAt: expiresAt),
            token: token
        )
    }

    func placeAccountOnHold(
        token: String, accountID: String, status: String, reason: String,
        permanent: Bool, expiresAt: Date?
    ) async throws -> OperationsLifecycleReceipt {
        struct Body: Encodable {
            let status: String; let reason: String
            let permanent: Bool; let expiresAt: Date?
        }
        let id = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await send(
            path: "/v1/operations/accounts/\(id)/hold", method: "POST",
            body: Body(status: status, reason: reason,
                       permanent: permanent, expiresAt: expiresAt), token: token
        )
    }

    func reactivateAccount(
        token: String, accountID: String, reason: String
    ) async throws -> OperationsLifecycleReceipt {
        struct Body: Encodable { let reason: String }
        let id = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await send(
            path: "/v1/operations/accounts/\(id)/reactivate", method: "POST",
            body: Body(reason: reason), token: token
        )
    }

    func manageAccountArchive(
        token: String, accountID: String, action: String,
        reason: String, confirmation: String?
    ) async throws -> OperationsLifecycleReceipt {
        struct Body: Encodable { let reason: String; let confirmation: String? }
        let id = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await send(
            path: "/v1/operations/accounts/\(id)/\(action)", method: "POST",
            body: Body(reason: reason, confirmation: confirmation), token: token
        )
    }

    func deletionReadiness(
        token: String, accountID: String
    ) async throws -> OperationsDeletionReadiness {
        let id = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await get(
            path: "/v1/operations/accounts/\(id)/deletion-readiness",
            token: token
        )
    }

    func confirmDeviceCleanup(
        token: String, accountID: String, reason: String, confirmation: String
    ) async throws -> OperationsReadinessActionReceipt {
        struct Body: Encodable { let reason: String; let confirmation: String }
        let id = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await send(
            path: "/v1/operations/accounts/\(id)/confirm-device-cleanup",
            method: "POST", body: Body(reason: reason, confirmation: confirmation),
            token: token
        )
    }

    func createRecoveryArchive(
        token: String, accountID: String, reason: String
    ) async throws -> OperationsReadinessActionReceipt {
        struct Body: Encodable { let reason: String }
        let id = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        return try await send(
            path: "/v1/operations/accounts/\(id)/create-recovery-archive",
            method: "POST", body: Body(reason: reason), token: token
        )
    }

    func sendPasswordReset(
        token: String, accountID: String, memberID: String, reason: String
    ) async throws -> OperationsRecoveryReceipt {
        try await recoveryRequest(
            token: token, accountID: accountID, memberID: memberID,
            action: "password-reset", reason: reason
        )
    }

    func revokeSessions(
        token: String, accountID: String, memberID: String, reason: String
    ) async throws -> OperationsRecoveryReceipt {
        try await recoveryRequest(
            token: token, accountID: accountID, memberID: memberID,
            action: "revoke-sessions", reason: reason
        )
    }

    func manageMember(
        token: String, accountID: String, memberID: String,
        action: String, reason: String
    ) async throws -> OperationsAccessLifecycleReceipt {
        try await accessLifecycleRequest(
            token: token, accountID: accountID, resource: "members",
            resourceID: memberID, action: action, reason: reason
        )
    }

    func manageDevice(
        token: String, accountID: String, deviceID: String,
        action: String, reason: String
    ) async throws -> OperationsAccessLifecycleReceipt {
        try await accessLifecycleRequest(
            token: token, accountID: accountID, resource: "devices",
            resourceID: deviceID, action: action, reason: reason
        )
    }

    private func accessLifecycleRequest(
        token: String, accountID: String, resource: String,
        resourceID: String, action: String, reason: String
    ) async throws -> OperationsAccessLifecycleReceipt {
        struct Body: Encodable { let reason: String }
        let account = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        let identifier = resourceID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? resourceID
        return try await send(
            path: "/v1/operations/accounts/\(account)/\(resource)/\(identifier)/\(action)",
            method: "POST", body: Body(reason: reason), token: token
        )
    }

    private func recoveryRequest(
        token: String, accountID: String, memberID: String,
        action: String, reason: String
    ) async throws -> OperationsRecoveryReceipt {
        struct Body: Encodable { let reason: String }
        let account = accountID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? accountID
        let member = memberID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? memberID
        return try await send(
            path: "/v1/operations/accounts/\(account)/members/\(member)/\(action)",
            method: "POST", body: Body(reason: reason), token: token
        )
    }

    private func get<Response: Decodable>(
        path: String,
        token: String
    ) async throws -> Response {
        try await send(
            path: path,
            method: "GET",
            body: Optional<String>.none,
            token: token
        )
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        token: String? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: endpoint) else {
            throw OperationsAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try Self.encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OperationsAPIError.invalidResponse
        }
        if http.statusCode == 401 { throw OperationsAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? Self.decoder.decode(
                [String: String].self,
                from: data
            )
            throw OperationsAPIError.server(
                Self.message(for: payload?["error"])
            )
        }
        guard let decoded = try? Self.decoder.decode(Response.self, from: data) else {
            throw OperationsAPIError.invalidResponse
        }
        return decoded
    }

    private static func message(for code: String?) -> String {
        switch code {
        case "operations_access_not_authorized":
            return "This verified identity has not been authorized for PFSS Operations."
        case "operations_identity_mismatch":
            return "The verified identity does not match the invited administrator."
        case "identity_provider_unavailable":
            return "Secure administrator sign-in is temporarily unavailable."
        case "operations_plan_override_forbidden":
            return "Your Operations role cannot grant beta access or override plans."
        case "invalid_plan_override":
            return "Select a valid plan, enter a detailed reason, and verify the expiration."
        case "operations_account_hold_forbidden":
            return "Your Operations role cannot manage this type of account hold."
        case "invalid_account_hold", "invalid_account_reactivation":
            return "Choose a valid hold and enter a detailed reason."
        case "account_not_on_hold":
            return "This account is no longer on hold. Refresh and try again."
        case "operations_recovery_forbidden":
            return "Your Operations role cannot provide recovery assistance."
        case "invalid_recovery_assistance", "invalid_session_revocation":
            return "Enter a detailed reason of at least 10 characters."
        case "managed_identity_not_found":
            return "This user does not have a managed Owner identity available for recovery."
        case "operations_member_access_forbidden":
            return "Your Operations role cannot change user or device access."
        case "invalid_member_access_action", "invalid_device_access_action":
            return "Enter a detailed reason of at least 10 characters."
        case "cannot_remove_final_active_owner":
            return "PFSS will not disable or remove the final active Owner."
        case "device_data_removal_pending":
            return "Company-data removal is still pending on a device. Refresh after that device acknowledges removal."
        case "invalid_member_access_transition", "invalid_device_access_transition":
            return "That action is not available from the user or device's current status."
        case "member_already_removed", "device_already_removed":
            return "This record has already been permanently removed."
        case "operations_account_archive_forbidden":
            return "Only the Platform Owner may archive or schedule deletion of an account."
        case "invalid_account_archive_action":
            return "Enter a detailed reason of at least 10 characters."
        case "account_name_confirmation_mismatch":
            return "The company-name confirmation does not match."
        case "invalid_account_archive_transition":
            return "That account action is not available from its current status."
        case "account_device_cleanup_pending":
            return "One or more devices have not acknowledged company-data removal."
        case "account_archive_backup_required":
            return "Create and upload a current recovery archive before scheduling deletion."
        case "invalid_deletion_readiness_action":
            return "The account must be archived and the reason must contain at least 10 characters."
        case "synchronization_snapshot_unavailable":
            return "No current synchronized company snapshot is available for a recovery archive."
        default:
            return "PFSS Operations could not complete the request."
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
