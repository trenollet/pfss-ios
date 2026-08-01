//
//  PFSSProductionAccountModels.swift
//  PPS Receipt Printer
//
//  Phase 17 – Provider-neutral production account registration contract.
//

import Foundation

enum PFSSAccountRegistrationStatus: String, Codable, CaseIterable {
    case started
    case identityVerified
    case profileComplete
    case planAuthorized
    case provisioning
    case active
    case expired
    case cancelled
    case failedRolledBack
}

enum PFSSAccountAuthenticationMethod: String, Codable, CaseIterable {
    case password
    case passkey
    case signInWithApple
    case federated
}

enum PFSSSubscriptionLifecycleStatus: String, Codable, CaseIterable {
    case pending
    case trialing
    case active
    case pastDue
    case suspended
    case cancelled
}

/// Server-owned authority describing why a company currently has PFSS access.
/// Registration requests never select this value.
enum PFSSAccountAccessSource: String, Codable, CaseIterable {
    case appStoreSubscription
    case betaGrant
    case internalTesting
    case internalBusinessGrant
    case promotionalGrant
}

enum PFSSAccountAccessMode: String, Codable, CaseIterable {
    case full
    case readOnly
    case blocked
}

struct PFSSAccountEntitlements: Codable, Equatable {
    let userLimit: Int
    let deviceLimit: Int
    let recordLimits: PFSSAccountRecordLimits
    let modules: [String]
}

struct PFSSAccountRecordLimits: Codable, Equatable {
    let leads: Int?
    let customers: Int?
    let jobs: Int?
}

struct PFSSAccountEntitlementUsage: Codable, Equatable {
    let users: Int
    let employees: Int
    let devices: Int
    let owners: Int
    let leads: Int
    let customers: Int
    let jobs: Int
}

/// A server-resolved account decision. The app presents this receipt but never
/// promotes its own plan, changes limits, or infers authority from StoreKit.
struct PFSSAccountEntitlementSnapshot: Codable, Equatable {
    let appAccountToken: UUID
    let planCode: String
    let accessSource: PFSSAccountAccessSource
    let subscriptionStatus: PFSSSubscriptionLifecycleStatus
    let accessMode: PFSSAccountAccessMode
    let entitlements: PFSSAccountEntitlements
    let effectiveAt: Date
    let expiresAt: Date?
    let usage: PFSSAccountEntitlementUsage

    var permitsChanges: Bool { accessMode == .full }
}

enum PFSSOwnerOperationalRole: String, Codable, CaseIterable, Identifiable {
    case salesperson
    case technician

    var id: String { rawValue }
    var title: String {
        switch self {
        case .salesperson: return "Sales"
        case .technician: return "Technician"
        }
    }
}

struct PFSSOwnerWorkProfileReceipt: Codable, Equatable {
    let employeeID: UUID
    let roles: [String]
    let revision: UUID
}

struct PFSSPlanAllocation: Codable, Equatable, Identifiable {
    let id: UUID
    let tenantID: UUID
    let source: PFSSAccountAccessSource
    let planCode: String
    let effectiveAt: Date
    let expiresAt: Date?
    let revokedAt: Date?

    var isRevoked: Bool { revokedAt != nil }

    func isEffective(at date: Date = Date()) -> Bool {
        effectiveAt <= date &&
            (expiresAt == nil || expiresAt! > date) &&
            revokedAt == nil
    }
}

struct PFSSOwnerRegistrationIdentity: Codable, Equatable {
    var displayName: String
    var email: String
}

struct PFSSCompanyRegistrationProfile: Codable, Equatable {
    var displayName: String
    var timeZoneID: String
}

struct PFSSRegistrationConsent: Codable, Equatable {
    var termsVersion: String
    var privacyVersion: String
    var acceptedAt: Date
}

struct PFSSRegistrationDevice: Codable, Equatable {
    var id: UUID
    var displayName: String
}

/// The only client-authored input accepted by the Phase 17 registration
/// boundary. Tenant identity, Owner role, prices, entitlements, and storage
/// configuration are intentionally absent and remain server-owned.
struct PFSSOwnerRegistrationRequest: Codable, Equatable {
    var idempotencyKey: UUID
    var identityAssertion: String
    var authenticationMethod: PFSSAccountAuthenticationMethod
    var owner: PFSSOwnerRegistrationIdentity
    var company: PFSSCompanyRegistrationProfile
    var requestedPlanCode: String
    var consent: PFSSRegistrationConsent
    var device: PFSSRegistrationDevice
}

struct PFSSValidatedOwnerRegistration: Equatable {
    let request: PFSSOwnerRegistrationRequest
    let normalizedEmail: String
}

struct PFSSAccountRegistrationAttempt: Codable, Equatable, Identifiable {
    let id: UUID
    let status: PFSSAccountRegistrationStatus
    let expiresAt: Date
    let createdAt: Date
    let updatedAt: Date
    let cancelledAt: Date?
}

/// The server issues `registrationToken` only when it creates a new attempt.
/// The client must retain it securely to check status or cancel registration.
struct PFSSAccountRegistrationReceipt: Codable, Equatable {
    let registrationAttempt: PFSSAccountRegistrationAttempt
    let registrationToken: String?
    let tokenIssued: Bool
}

struct PFSSIdentityAuthorizationRequest: Codable, Equatable {
    let state: String
    let codeChallenge: String
    let redirectURI: URL
    let emailHint: String?
    let screenHint: String
}

struct PFSSIdentityAuthorizationSession: Codable, Equatable {
    let authorizationURL: URL
    let state: String
    let expiresAt: Date
}

enum PFSSRegistrationValidationError: Error, Equatable, LocalizedError {
    case invalidOwnerName
    case invalidEmail
    case invalidCompanyName
    case invalidTimeZone
    case invalidIdentityAssertion
    case invalidPlanCode
    case invalidTermsVersion
    case invalidPrivacyVersion
    case invalidConsentDate
    case invalidDeviceName

    var errorDescription: String? {
        switch self {
        case .invalidOwnerName:
            return "Enter the Owner's full name."
        case .invalidEmail:
            return "Enter a valid email address."
        case .invalidCompanyName:
            return "Enter a valid company name."
        case .invalidTimeZone:
            return "Select a valid time zone."
        case .invalidIdentityAssertion:
            return "Identity verification must be completed again."
        case .invalidPlanCode:
            return "Select an available PFSS plan."
        case .invalidTermsVersion, .invalidPrivacyVersion:
            return "The current legal agreements must be accepted."
        case .invalidConsentDate:
            return "The legal-consent timestamp is invalid."
        case .invalidDeviceName:
            return "Enter a valid name for this device."
        }
    }
}

enum PFSSOwnerRegistrationValidator {
    private static let planCodePattern =
        /^[a-z0-9](?:[a-z0-9_-]{0,62}[a-z0-9])?$/

    static func validate(
        _ request: PFSSOwnerRegistrationRequest,
        now: Date = Date()
    ) throws -> PFSSValidatedOwnerRegistration {
        var normalized = request
        normalized.owner.displayName = request.owner.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.owner.email = request.owner.email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        normalized.company.displayName = request.company.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.company.timeZoneID = request.company.timeZoneID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.identityAssertion = request.identityAssertion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.requestedPlanCode = request.requestedPlanCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        normalized.consent.termsVersion = request.consent.termsVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.consent.privacyVersion = request.consent.privacyVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.device.displayName = request.device.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard (2...120).contains(normalized.owner.displayName.count) else {
            throw PFSSRegistrationValidationError.invalidOwnerName
        }
        guard isValidEmail(normalized.owner.email) else {
            throw PFSSRegistrationValidationError.invalidEmail
        }
        guard (2...160).contains(normalized.company.displayName.count) else {
            throw PFSSRegistrationValidationError.invalidCompanyName
        }
        guard TimeZone(identifier: normalized.company.timeZoneID) != nil else {
            throw PFSSRegistrationValidationError.invalidTimeZone
        }
        guard (20...4096).contains(normalized.identityAssertion.count) else {
            throw PFSSRegistrationValidationError.invalidIdentityAssertion
        }
        guard normalized.requestedPlanCode.wholeMatch(
            of: planCodePattern
        ) != nil else {
            throw PFSSRegistrationValidationError.invalidPlanCode
        }
        guard (1...80).contains(normalized.consent.termsVersion.count) else {
            throw PFSSRegistrationValidationError.invalidTermsVersion
        }
        guard (1...80).contains(normalized.consent.privacyVersion.count) else {
            throw PFSSRegistrationValidationError.invalidPrivacyVersion
        }
        let earliestConsent = now.addingTimeInterval(-86_400)
        let latestConsent = now.addingTimeInterval(300)
        guard normalized.consent.acceptedAt >= earliestConsent,
              normalized.consent.acceptedAt <= latestConsent else {
            throw PFSSRegistrationValidationError.invalidConsentDate
        }
        guard (1...120).contains(normalized.device.displayName.count) else {
            throw PFSSRegistrationValidationError.invalidDeviceName
        }
        return PFSSValidatedOwnerRegistration(
            request: normalized,
            normalizedEmail: normalized.owner.email
        )
    }

    private static func isValidEmail(_ value: String) -> Bool {
        guard value.count <= 254,
              !value.contains(where: { $0.isWhitespace }) else {
            return false
        }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[0].count <= 64,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".") else {
            return false
        }
        return true
    }
}
