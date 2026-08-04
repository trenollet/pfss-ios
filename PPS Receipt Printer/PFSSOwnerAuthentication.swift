//
//  PFSSOwnerAuthentication.swift
//  PPS Receipt Printer
//
//  Phase 17 – Provider-neutral Owner authentication and PKCE coordination.
//

import CryptoKit
import Combine
import Foundation
import Security

struct PFSSPKCECredentials: Equatable {
    let state: String
    let verifier: String
    let challenge: String
}

enum PFSSPKCEGenerator {
    static func make() throws -> PFSSPKCECredentials {
        let state = try randomBase64URL(byteCount: 32)
        let verifier = try randomBase64URL(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PFSSPKCECredentials(
            state: state,
            verifier: verifier,
            challenge: challenge
        )
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw PFSSOwnerAuthenticationError.secureRandomUnavailable
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct PFSSPendingOwnerAuthorization: Codable, Equatable {
    let state: String
    let codeVerifier: String
    let redirectURI: URL
    let expiresAt: Date
}

struct PFSSOwnerAuthorizationCode: Equatable {
    let state: String
    let code: String
    let codeVerifier: String
    let redirectURI: URL
}

protocol PFSSPendingOwnerAuthorizationStoring {
    func load() -> PFSSPendingOwnerAuthorization?
    func save(_ authorization: PFSSPendingOwnerAuthorization) throws
    func delete()
}

struct PFSSPendingOwnerAuthorizationKeychainStore:
    PFSSPendingOwnerAuthorizationStoring {
    private let service = "com.patriot.pfss.owner-authorization"
    private let account = "pending-pkce"

    func load() -> PFSSPendingOwnerAuthorization? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder.pfssAccount.decode(
            PFSSPendingOwnerAuthorization.self,
            from: data
        )
    }

    func save(_ authorization: PFSSPendingOwnerAuthorization) throws {
        let data = try JSONEncoder.pfssAccount.encode(authorization)
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw PFSSOwnerAuthenticationError.secureStorageUnavailable
        }
    }

    func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

private extension JSONEncoder {
    static var pfssAccount: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pfssAccount: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

protocol PFSSOwnerAuthorizationServing {
    func startAuthorization(
        _ request: PFSSIdentityAuthorizationRequest
    ) async throws -> PFSSIdentityAuthorizationSession
}

struct PFSSLocalOwnerAuthorizationService: PFSSOwnerAuthorizationServing {
    func startAuthorization(
        _ request: PFSSIdentityAuthorizationRequest
    ) async throws -> PFSSIdentityAuthorizationSession {
        guard request.redirectURI.absoluteString ==
                "https://local.pfss.test/auth/callback" else {
            throw PFSSOwnerAuthenticationError.untrustedRedirect
        }
        var components = URLComponents(
            string: "https://local.pfss.test/authorize"
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: request.state),
            URLQueryItem(name: "code_challenge", value: request.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authorizationURL = components.url else {
            throw PFSSOwnerAuthenticationError.invalidProviderResponse
        }
        return PFSSIdentityAuthorizationSession(
            authorizationURL: authorizationURL,
            state: request.state,
            expiresAt: Date().addingTimeInterval(300)
        )
    }
}

enum PFSSOwnerAuthenticationError: LocalizedError, Equatable {
    case secureRandomUnavailable
    case secureStorageUnavailable
    case invalidProviderResponse
    case untrustedRedirect
    case missingPendingAuthorization
    case authorizationExpired
    case stateMismatch
    case missingAuthorizationCode

    var errorDescription: String? {
        switch self {
        case .secureRandomUnavailable, .secureStorageUnavailable:
            return "PFSS could not securely prepare sign-in. Try again."
        case .invalidProviderResponse:
            return "The identity provider returned an invalid response."
        case .untrustedRedirect:
            return "PFSS blocked an untrusted sign-in return address."
        case .missingPendingAuthorization:
            return "Start Owner sign-in again."
        case .authorizationExpired:
            return "Owner sign-in expired. Start again."
        case .stateMismatch:
            return "PFSS blocked an invalid sign-in response."
        case .missingAuthorizationCode:
            return "Owner identity verification was not completed."
        }
    }
}

@MainActor
final class PFSSOwnerAuthenticationCoordinator: ObservableObject {
    @Published private(set) var authorizationSession:
        PFSSIdentityAuthorizationSession?

    private let service: any PFSSOwnerAuthorizationServing
    private let pendingStore: any PFSSPendingOwnerAuthorizationStoring
    private let redirectURI: URL

    init(
        service: (any PFSSOwnerAuthorizationServing)? = nil,
        pendingStore: (any PFSSPendingOwnerAuthorizationStoring)? = nil,
        redirectURI: URL = URL(
            string: "https://local.pfss.test/auth/callback"
        )!
    ) {
        self.service = service ?? PFSSLocalOwnerAuthorizationService()
        self.pendingStore = pendingStore ??
            PFSSPendingOwnerAuthorizationKeychainStore()
        self.redirectURI = redirectURI
    }

    func start(emailHint: String? = nil) async throws
        -> PFSSIdentityAuthorizationSession {
        let pkce = try PFSSPKCEGenerator.make()
        let request = PFSSIdentityAuthorizationRequest(
            state: pkce.state,
            codeChallenge: pkce.challenge,
            redirectURI: redirectURI,
            emailHint: emailHint
        )
        let session = try await service.startAuthorization(request)
        guard session.state == pkce.state,
              session.authorizationURL.scheme == "https",
              session.expiresAt > Date() else {
            throw PFSSOwnerAuthenticationError.invalidProviderResponse
        }
        try pendingStore.save(PFSSPendingOwnerAuthorization(
            state: pkce.state,
            codeVerifier: pkce.verifier,
            redirectURI: redirectURI,
            expiresAt: session.expiresAt
        ))
        authorizationSession = session
        return session
    }

    func consumeCallback(
        _ callbackURL: URL,
        now: Date = Date()
    ) throws -> PFSSOwnerAuthorizationCode {
        guard let pending = pendingStore.load() else {
            throw PFSSOwnerAuthenticationError.missingPendingAuthorization
        }
        guard pending.expiresAt > now else {
            pendingStore.delete()
            throw PFSSOwnerAuthenticationError.authorizationExpired
        }
        guard callbackURL.scheme == pending.redirectURI.scheme,
              callbackURL.host == pending.redirectURI.host,
              callbackURL.path == pending.redirectURI.path else {
            throw PFSSOwnerAuthenticationError.untrustedRedirect
        }
        let query = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        )?.queryItems
        let returnedState = query?.first(where: { $0.name == "state" })?.value
        guard returnedState == pending.state else {
            throw PFSSOwnerAuthenticationError.stateMismatch
        }
        guard let code = query?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw PFSSOwnerAuthenticationError.missingAuthorizationCode
        }
        pendingStore.delete()
        authorizationSession = nil
        return PFSSOwnerAuthorizationCode(
            state: pending.state,
            code: code,
            codeVerifier: pending.codeVerifier,
            redirectURI: pending.redirectURI
        )
    }
}
