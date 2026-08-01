//
//  PFSSOwnerRegistrationService.swift
//  PPS Receipt Printer
//
//  Phase 17 – Live Owner authentication and company registration client.
//

import AuthenticationServices
import Combine
import Foundation
import UIKit

struct PFSSVerifiedOwnerIdentity: Equatable {
    let identityAssertion: String
    let authenticationMethod: PFSSAccountAuthenticationMethod
    let displayName: String
    let email: String
}

struct PFSSOwnerProvisioningReceipt: Equatable {
    let tenantID: UUID
    let tenantName: String
    let memberID: UUID
    let deviceID: UUID
    let deviceToken: String
}

enum PFSSOwnerRegistrationServiceError: LocalizedError {
    case invalidResponse
    case registrationInterrupted
    case server(String)
    case authorizationCancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "PFSS received an unreadable registration response."
        case .registrationInterrupted:
            return "Company registration was interrupted. Start again."
        case let .server(message):
            return message
        case .authorizationCancelled:
            return "Owner verification was cancelled."
        }
    }
}

struct PFSSCloudflareOwnerAccountService: PFSSOwnerAuthorizationServing {
    static let stagingRedirectURI = URL(
        string: "https://auth-staging.patriot-ok.com/callback/"
    )!

    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(
            string: "https://pfss-beta-api.timrenollet.workers.dev"
        )!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func startAuthorization(
        _ request: PFSSIdentityAuthorizationRequest
    ) async throws -> PFSSIdentityAuthorizationSession {
        try await send(
            path: "/v1/owner-auth/authorize",
            body: request,
            response: PFSSIdentityAuthorizationSession.self
        )
    }

    func exchange(
        _ authorization: PFSSOwnerAuthorizationCode
    ) async throws -> PFSSVerifiedOwnerIdentity {
        struct Body: Encodable {
            let state: String
            let code: String
            let codeVerifier: String
            let redirectURI: URL
        }
        struct Response: Decodable {
            struct Owner: Decodable {
                let displayName: String
                let email: String
            }
            let identityAssertion: String
            let authenticationMethod: PFSSAccountAuthenticationMethod
            let owner: Owner
        }
        let response = try await send(
            path: "/v1/owner-auth/callback",
            body: Body(
                state: authorization.state,
                code: authorization.code,
                codeVerifier: authorization.codeVerifier,
                redirectURI: authorization.redirectURI
            ),
            response: Response.self
        )
        return PFSSVerifiedOwnerIdentity(
            identityAssertion: response.identityAssertion,
            authenticationMethod: response.authenticationMethod,
            displayName: response.owner.displayName,
            email: response.owner.email
        )
    }

    func register(
        _ request: PFSSOwnerRegistrationRequest
    ) async throws -> PFSSOwnerProvisioningReceipt {
        let validated = try PFSSOwnerRegistrationValidator.validate(request)
        let started = try await send(
            path: "/v1/account-registration/attempts",
            body: validated.request,
            response: PFSSAccountRegistrationReceipt.self
        )
        guard let registrationToken = started.registrationToken else {
            throw PFSSOwnerRegistrationServiceError.registrationInterrupted
        }
        struct Completion: Decodable {
            struct Attempt: Decodable { let status: PFSSAccountRegistrationStatus }
            struct Tenant: Decodable { let id: UUID; let displayName: String }
            struct Owner: Decodable { let memberID: UUID }
            struct Device: Decodable { let id: UUID; let deviceToken: String }
            let registrationAttempt: Attempt
            let tenant: Tenant
            let owner: Owner
            let device: Device
            let tokenIssued: Bool
        }
        let completion: Completion = try await send(
            path: "/v1/account-registration/attempts/\(started.registrationAttempt.id.uuidString.lowercased())/complete",
            body: EmptyBody(),
            response: Completion.self,
            additionalHeaders: [
                "x-pfss-registration-token": registrationToken,
            ]
        )
        guard completion.registrationAttempt.status == .active,
              completion.tokenIssued,
              !completion.device.deviceToken.isEmpty else {
            throw PFSSOwnerRegistrationServiceError.invalidResponse
        }
        return PFSSOwnerProvisioningReceipt(
            tenantID: completion.tenant.id,
            tenantName: completion.tenant.displayName,
            memberID: completion.owner.memberID,
            deviceID: completion.device.id,
            deviceToken: completion.device.deviceToken
        )
    }

    func signIn(
        identity: PFSSVerifiedOwnerIdentity,
        deviceID: UUID,
        deviceName: String
    ) async throws -> PFSSOwnerProvisioningReceipt {
        struct Body: Encodable {
            let identityAssertion: String
            let deviceID: UUID
            let deviceName: String
        }
        struct Response: Decodable {
            struct Tenant: Decodable { let id: UUID; let displayName: String }
            struct Owner: Decodable { let memberID: UUID }
            struct Device: Decodable { let id: UUID; let deviceToken: String }
            let tenant: Tenant
            let owner: Owner
            let device: Device
            let tokenIssued: Bool
        }
        let response: Response = try await send(
            path: "/v1/owner-auth/sign-in",
            body: Body(
                identityAssertion: identity.identityAssertion,
                deviceID: deviceID,
                deviceName: deviceName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ),
            response: Response.self
        )
        guard response.tokenIssued, !response.device.deviceToken.isEmpty else {
            throw PFSSOwnerRegistrationServiceError.invalidResponse
        }
        return PFSSOwnerProvisioningReceipt(
            tenantID: response.tenant.id,
            tenantName: response.tenant.displayName,
            memberID: response.owner.memberID,
            deviceID: response.device.id,
            deviceToken: response.device.deviceToken
        )
    }

    func recover(
        recoveryCode: String,
        deviceID: UUID,
        deviceName: String
    ) async throws -> PFSSOwnerProvisioningReceipt {
        struct Body: Encodable {
            let recoveryCode: String
            let deviceID: UUID
            let deviceName: String
        }
        struct Response: Decodable {
            struct Tenant: Decodable { let id: UUID; let displayName: String }
            struct Owner: Decodable { let memberID: UUID }
            struct Device: Decodable { let id: UUID; let deviceToken: String }
            let tenant: Tenant
            let owner: Owner
            let device: Device
            let tokenIssued: Bool
        }
        let response: Response = try await send(
            path: "/v1/account-recovery/redeem",
            body: Body(
                recoveryCode: recoveryCode.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                deviceID: deviceID,
                deviceName: deviceName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ),
            response: Response.self
        )
        guard response.tokenIssued, !response.device.deviceToken.isEmpty else {
            throw PFSSOwnerRegistrationServiceError.invalidResponse
        }
        return PFSSOwnerProvisioningReceipt(
            tenantID: response.tenant.id,
            tenantName: response.tenant.displayName,
            memberID: response.owner.memberID,
            deviceID: response.device.id,
            deviceToken: response.device.deviceToken
        )
    }

    func acceptOwnerInvitation(
        invitationCode: String,
        identity: PFSSVerifiedOwnerIdentity,
        deviceID: UUID,
        deviceName: String
    ) async throws -> PFSSOwnerProvisioningReceipt {
        struct Body: Encodable {
            let invitationCode: String
            let identityAssertion: String
            let deviceID: UUID
            let deviceName: String
        }
        struct Response: Decodable {
            struct Tenant: Decodable { let id: UUID; let displayName: String }
            struct Owner: Decodable { let memberID: UUID }
            struct Device: Decodable { let id: UUID; let deviceToken: String }
            let tenant: Tenant
            let owner: Owner
            let device: Device
            let tokenIssued: Bool
        }
        let response: Response = try await send(
            path: "/v1/owner-invitations/accept",
            body: Body(
                invitationCode: invitationCode.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                identityAssertion: identity.identityAssertion,
                deviceID: deviceID,
                deviceName: deviceName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ),
            response: Response.self
        )
        guard response.tokenIssued, !response.device.deviceToken.isEmpty else {
            throw PFSSOwnerRegistrationServiceError.invalidResponse
        }
        return PFSSOwnerProvisioningReceipt(
            tenantID: response.tenant.id,
            tenantName: response.tenant.displayName,
            memberID: response.owner.memberID,
            deviceID: response.device.id,
            deviceToken: response.device.deviceToken
        )
    }

    private struct EmptyBody: Encodable {}

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        response: Response.Type,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: endpoint.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try Self.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw PFSSOwnerRegistrationServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? Self.decoder.decode(ServerError.self, from: data)
            throw PFSSOwnerRegistrationServiceError.server(
                Self.message(for: error?.error)
            )
        }
        do {
            return try Self.decoder.decode(response, from: data)
        } catch {
            throw PFSSOwnerRegistrationServiceError.invalidResponse
        }
    }

    private struct ServerError: Decodable { let error: String }

    private static func message(for code: String?) -> String {
        switch code {
        case "account_or_company_requires_sign_in":
            return "An account or company already exists. Sign in instead."
        case "identity_verification_required":
            return "Owner verification expired. Start again."
        case "registration_provisioning_failed":
            return "PFSS could not finish creating the company. No partial company was retained. Try again."
        case "plan_authorization_required":
            return "This plan requires subscription authorization."
        case "owner_company_not_found":
            return "No active PFSS company is linked to this Owner account."
        case "owner_company_selection_required":
            return "This Owner belongs to more than one company. Company selection must be completed before sign-in."
        case "device_limit_reached":
            return "This company has reached its enrolled-device limit."
        case "invalid_or_used_recovery_code":
            return "That recovery code is invalid or has already been used."
        case "invalid_or_expired_owner_invitation":
            return "That Owner invitation is invalid, expired, or already used."
        case "owner_invitation_identity_mismatch":
            return "The verified email does not match the Owner invitation."
        case "owner_already_exists":
            return "That Owner already has company access."
        case "final_active_owner_protected":
            return "PFSS must always retain at least one active Owner."
        default:
            return "PFSS could not complete registration. Try again."
        }
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }

    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }
}

@MainActor
final class PFSSOwnerAuthenticationBrowser: NSObject, ObservableObject,
    ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let scene else {
            preconditionFailure("Owner authentication requires an active scene.")
        }
        return scene.windows.first(where: \.isKeyWindow)
            ?? UIWindow(windowScene: scene)
    }

    func authenticate(
        at url: URL,
        callbackURL: URL,
        prefersEphemeralSession: Bool = false
    ) async throws -> URL {
        guard let host = callbackURL.host else {
            throw PFSSOwnerAuthenticationError.untrustedRedirect
        }
        return try await withCheckedThrowingContinuation { continuation in
            let callback = ASWebAuthenticationSession.Callback.https(
                host: host,
                path: callbackURL.path
            )
            let authenticationSession = ASWebAuthenticationSession(
                url: url,
                callback: callback
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if (error as? ASWebAuthenticationSessionError)?.code ==
                            .canceledLogin {
                    continuation.resume(
                        throwing: PFSSOwnerRegistrationServiceError
                            .authorizationCancelled
                    )
                } else {
                    continuation.resume(
                        throwing: error ??
                            PFSSOwnerRegistrationServiceError.invalidResponse
                    )
                }
            }
            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession =
                prefersEphemeralSession
            self.session = authenticationSession
            guard authenticationSession.start() else {
                continuation.resume(
                    throwing: PFSSOwnerRegistrationServiceError.invalidResponse
                )
                return
            }
        }
    }
}
