//
//  PFSSGoogleDriveService.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 4 – Google Drive authorization, backup, and recovery.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

extension Notification.Name {
    static let pfssOwnerRecoveryAuthorizationWasRevoked = Notification.Name(
        "PFSSOwnerRecoveryAuthorizationWasRevoked"
    )
}

struct PFSSGoogleDriveConfiguration {
    static let production = PFSSGoogleDriveConfiguration(
        clientID: "573181539480-q4a2jdm6u4nc35t1p8ioubjb1ocpjkao.apps.googleusercontent.com"
    )

    let clientID: String
    let scope = "https://www.googleapis.com/auth/drive.file"

    var callbackScheme: String {
        let suffix = ".apps.googleusercontent.com"
        let identifier = clientID.hasSuffix(suffix)
            ? String(clientID.dropLast(suffix.count))
            : clientID
        return "com.googleusercontent.apps.\(identifier)"
    }

    var redirectURI: String { "\(callbackScheme):/oauth2redirect" }
}

struct PFSSGoogleDriveArchive: Identifiable, Hashable {
    var id: String
    var name: String
    var modifiedTime: Date
    var size: Int64
}

enum PFSSGoogleDriveState: Equatable {
    case disconnected
    case connecting
    case connected
    case working
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: return "Google Drive Not Connected"
        case .connecting: return "Connecting to Google Drive"
        case .connected: return "Google Drive Connected"
        case .working: return "Working with Google Drive"
        case .failed: return "Google Drive Error"
        }
    }
}

enum PFSSGoogleDriveError: LocalizedError {
    case authorizationCancelled
    case invalidAuthorizationResponse
    case notConnected
    case noBackup
    case invalidServerResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .authorizationCancelled:
            return "Google Drive connection was cancelled."
        case .invalidAuthorizationResponse:
            return "Google did not return a valid authorization response."
        case .notConnected:
            return "Connect PFSS to Google Drive first."
        case .noBackup:
            return "No PFSS backup is available in Google Drive."
        case .invalidServerResponse:
            return "Google Drive returned an unreadable response."
        case let .server(message):
            return message
        }
    }
}

private struct PFSSGoogleTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: TimeInterval
    var refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct PFSSGoogleDriveFileList: Decodable {
    var files: [PFSSGoogleDriveFile]
}

private struct PFSSGoogleDriveFile: Decodable {
    var id: String
    var name: String
    var modifiedTime: Date
    var size: String?

    var archive: PFSSGoogleDriveArchive {
        PFSSGoogleDriveArchive(
            id: id,
            name: name,
            modifiedTime: modifiedTime,
            size: Int64(size ?? "0") ?? 0
        )
    }
}

private final class PFSSGoogleRefreshTokenStore {
    private let service = "com.patriot.pfss.google-drive"
    private let account = "refresh-token"

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

enum PFSSGoogleDriveSecurity {
    static func removeStoredCompanyCredential() {
        PFSSGoogleRefreshTokenStore().delete()
    }
}

enum PFSSOwnerRecoverySecurity {
    static func revokeLocalAccess() {
        PFSSGoogleDriveSecurity.removeStoredCompanyCredential()
        NotificationCenter.default.post(
            name: .pfssOwnerRecoveryAuthorizationWasRevoked,
            object: nil
        )
    }
}

@MainActor
final class PFSSGoogleDriveManager: NSObject, ObservableObject,
    ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var state: PFSSGoogleDriveState = .disconnected
    @Published private(set) var archives: [PFSSGoogleDriveArchive] = []

    private let configuration: PFSSGoogleDriveConfiguration
    private let tokenStore = PFSSGoogleRefreshTokenStore()
    private let session: URLSession
    private var accessToken: String?
    private var accessTokenExpiration: Date = .distantPast
    private var authenticationSession: ASWebAuthenticationSession?

    init(
        configuration: PFSSGoogleDriveConfiguration? = nil,
        session: URLSession = .shared
    ) {
        self.configuration = configuration ?? .production
        self.session = session
        super.init()
        if tokenStore.load() != nil { state = .connected }
    }

    var latestArchive: PFSSGoogleDriveArchive? { archives.first }

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let windowScene else {
            preconditionFailure("Google authorization requires an active window scene.")
        }
        return windowScene.windows.first { $0.isKeyWindow }
            ?? UIWindow(windowScene: windowScene)
    }

    func connect() async throws {
        state = .connecting
        do {
            let verifier = Self.codeVerifier()
            let challenge = Self.base64URL(
                Data(SHA256.hash(data: Data(verifier.utf8)))
            )
            let stateValue = UUID().uuidString
            var components = URLComponents(
                string: "https://accounts.google.com/o/oauth2/v2/auth"
            )!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: configuration.clientID),
                URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: configuration.scope),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: stateValue)
            ]
            let callback = try await authorize(at: components.url!)
            let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            let values = Dictionary(uniqueKeysWithValues:
                (callbackComponents?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )
            guard values["state"] == stateValue,
                  let code = values["code"], !code.isEmpty else {
                throw PFSSGoogleDriveError.invalidAuthorizationResponse
            }
            let tokens = try await exchangeCode(code, verifier: verifier)
            accept(tokens)
            state = .connected
            try await refresh()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func disconnect() {
        authenticationSession?.cancel()
        authenticationSession = nil
        tokenStore.delete()
        accessToken = nil
        accessTokenExpiration = .distantPast
        archives = []
        state = .disconnected
    }

    func refresh() async throws {
        let token = try await validAccessToken()
        state = .working
        defer { if state == .working { state = .connected } }
        var components = URLComponents(
            string: "https://www.googleapis.com/drive/v3/files"
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: "appProperties has { key='pfssArchive' and value='true' } and trashed=false"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime,size)")
        ]
        let data = try await request(components.url!, token: token)
        let list = try Self.decoder.decode(PFSSGoogleDriveFileList.self, from: data)
        archives = list.files.map(\.archive)
    }

    func upload(_ data: Data, createdAt: Date = Date()) async throws {
        let token = try await validAccessToken()
        state = .working
        let boundary = "pfss-\(UUID().uuidString)"
        let name = "PFSS-Google-\(Self.fileDateFormatter.string(from: createdAt)).pfssarchive"
        let metadata: [String: Any] = [
            "name": name,
            "mimeType": PFSSArchiveConstants.mediaType,
            "appProperties": ["pfssArchive": "true"]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metadataData)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(PFSSArchiveConstants.mediaType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
        state = .connected
        try await refresh()
    }

    func latestData() async throws -> (PFSSGoogleDriveArchive, Data) {
        try await refresh()
        guard let latestArchive else { throw PFSSGoogleDriveError.noBackup }
        let token = try await validAccessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(latestArchive.id)?alt=media")!
        return (latestArchive, try await request(url, token: token))
    }

    private func authorize(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: PFSSGoogleDriveError.authorizationCancelled)
                } else {
                    continuation.resume(throwing: error ?? PFSSGoogleDriveError.invalidAuthorizationResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            session.start()
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> PFSSGoogleTokenResponse {
        try await tokenRequest([
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI
        ])
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> PFSSGoogleTokenResponse {
        try await tokenRequest([
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
    }

    private func tokenRequest(_ values: [String: String]) async throws -> PFSSGoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values
            .map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)
        return try Self.decoder.decode(PFSSGoogleTokenResponse.self, from: try await perform(request))
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiration > Date().addingTimeInterval(60) {
            return accessToken
        }
        guard let refreshToken = tokenStore.load() else {
            state = .disconnected
            throw PFSSGoogleDriveError.notConnected
        }
        let tokens = try await refreshAccessToken(refreshToken)
        accept(tokens)
        return tokens.accessToken
    }

    private func accept(_ tokens: PFSSGoogleTokenResponse) {
        accessToken = tokens.accessToken
        accessTokenExpiration = Date().addingTimeInterval(tokens.expiresIn)
        if let refreshToken = tokens.refreshToken { tokenStore.save(refreshToken) }
    }

    private func request(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PFSSGoogleDriveError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any]
            let errorObject = object?["error"] as? [String: Any]
            let message = errorObject?["message"] as? String
                ?? "Google Drive request failed (\(http.statusCode))."
            throw PFSSGoogleDriveError.server(message)
        }
        return data
    }

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "-._~")
            )
        ) ?? self
    }
}
