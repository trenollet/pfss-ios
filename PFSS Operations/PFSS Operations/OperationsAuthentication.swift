import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct OperationsPKCE {
    let state: String
    let verifier: String
    let challenge: String

    static func make() throws -> OperationsPKCE {
        let state = try random(byteCount: 32)
        let verifier = try random(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return OperationsPKCE(
            state: state,
            verifier: verifier,
            challenge: challenge
        )
    }

    private static func random(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw OperationsAPIError.invalidResponse
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

@MainActor
final class OperationsAuthenticationBrowser: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let scene else { return ASPresentationAnchor() }
        return scene.windows.first(where: \.isKeyWindow)
            ?? UIWindow(windowScene: scene)
    }

    func authenticate(at url: URL, callbackURL: URL) async throws -> URL {
        guard let host = callbackURL.host else {
            throw OperationsAPIError.invalidResponse
        }
        return try await withCheckedThrowingContinuation { continuation in
            let callback = ASWebAuthenticationSession.Callback.https(
                host: host,
                path: callbackURL.path
            )
            let session = ASWebAuthenticationSession(
                url: url,
                callback: callback
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(
                        throwing: error ?? OperationsAPIError.invalidResponse
                    )
                }
            }
            session.presentationContextProvider = self
            // Operations access must never silently reuse a customer or Owner
            // identity cached by Safari. A fresh session makes the platform
            // administrator explicitly authenticate on every new device.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            guard session.start() else {
                continuation.resume(throwing: OperationsAPIError.invalidResponse)
                return
            }
        }
    }
}

enum OperationsCredentialStore {
    private static let service = "com.patriot.pfss.operations"

    static func load(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) throws {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw OperationsAPIError.invalidResponse
        }
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
