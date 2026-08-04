//
//  PFSSProductionAccountModelsTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 17 Step 1 – Provider-neutral account contract coverage.
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class PFSSProductionAccountModelsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidRegistrationIsNormalizedWithoutServerOwnedFields() throws {
        var request = validRequest()
        request.owner.displayName = "  Geoff Nordmyer  "
        request.owner.email = "  OWNER@EXAMPLE.COM "
        request.company.displayName = "  PFSS Development  "
        request.requestedPlanCode = "  TEAM-ANNUAL  "

        let result = try PFSSOwnerRegistrationValidator.validate(
            request,
            now: now
        )

        XCTAssertEqual(result.request.owner.displayName, "Geoff Nordmyer")
        XCTAssertEqual(result.normalizedEmail, "owner@example.com")
        XCTAssertEqual(result.request.company.displayName, "PFSS Development")
        XCTAssertEqual(result.request.requestedPlanCode, "team-annual")

        let encoded = try JSONEncoder().encode(result.request)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for serverOwnedKey in [
            "tenantID", "role", "price", "entitlements", "databaseID",
            "bucketName", "storagePath", "infrastructureEndpoint",
        ] {
            XCTAssertNil(json[serverOwnedKey])
        }
    }

    func testRegistrationRejectsInvalidEmailAndUnknownTimeZone() {
        var invalidEmail = validRequest()
        invalidEmail.owner.email = "not-an-email"
        XCTAssertThrowsError(
            try PFSSOwnerRegistrationValidator.validate(invalidEmail, now: now)
        ) {
            XCTAssertEqual(
                $0 as? PFSSRegistrationValidationError,
                .invalidEmail
            )
        }

        var invalidTimeZone = validRequest()
        invalidTimeZone.company.timeZoneID = "PFSS/Unknown"
        XCTAssertThrowsError(
            try PFSSOwnerRegistrationValidator.validate(invalidTimeZone, now: now)
        ) {
            XCTAssertEqual(
                $0 as? PFSSRegistrationValidationError,
                .invalidTimeZone
            )
        }
    }

    func testRegistrationRejectsStaleConsentAndUnverifiedIdentity() {
        var staleConsent = validRequest()
        staleConsent.consent.acceptedAt = now.addingTimeInterval(-86_401)
        XCTAssertThrowsError(
            try PFSSOwnerRegistrationValidator.validate(staleConsent, now: now)
        ) {
            XCTAssertEqual(
                $0 as? PFSSRegistrationValidationError,
                .invalidConsentDate
            )
        }

        var noAssertion = validRequest()
        noAssertion.identityAssertion = "too-short"
        XCTAssertThrowsError(
            try PFSSOwnerRegistrationValidator.validate(noAssertion, now: now)
        ) {
            XCTAssertEqual(
                $0 as? PFSSRegistrationValidationError,
                .invalidIdentityAssertion
            )
        }
    }

    func testCanonicalLifecycleStatesRemainStable() {
        XCTAssertEqual(
            Set(PFSSAccountRegistrationStatus.allCases.map(\.rawValue)),
            [
                "started", "identityVerified", "profileComplete",
                "planAuthorized", "provisioning", "active", "expired",
                "cancelled", "failedRolledBack",
            ]
        )
        XCTAssertEqual(
            Set(PFSSSubscriptionLifecycleStatus.allCases.map(\.rawValue)),
            [
                "pending", "trialing", "active", "pastDue", "suspended",
                "cancelled",
            ]
        )
        XCTAssertEqual(
            Set(PFSSAccountAccessSource.allCases.map(\.rawValue)),
            [
                "appStoreSubscription", "betaGrant", "internalTesting",
                "internalBusinessGrant", "promotionalGrant",
            ]
        )
    }

    func testPlanAllocationRequiresCurrentUnrevokedWindow() {
        let allocation = PFSSPlanAllocation(
            id: UUID(),
            tenantID: UUID(),
            source: .internalBusinessGrant,
            planCode: "internal-full",
            effectiveAt: now.addingTimeInterval(-60),
            expiresAt: nil,
            revokedAt: nil
        )
        XCTAssertTrue(allocation.isEffective(at: now))

        let expired = PFSSPlanAllocation(
            id: UUID(),
            tenantID: UUID(),
            source: .betaGrant,
            planCode: "beta-full",
            effectiveAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(-1),
            revokedAt: nil
        )
        XCTAssertFalse(expired.isEffective(at: now))
    }

    func testEntitlementSnapshotPreservesServerAuthority() throws {
        let json = """
        {
          "appAccountToken": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "planCode": "beta-full",
          "accessSource": "betaGrant",
          "subscriptionStatus": "active",
          "accessMode": "full",
          "entitlements": {
            "userLimit": 5,
            "deviceLimit": 40,
            "recordLimits": {
              "leads": 1000,
              "customers": 1000,
              "jobs": 3000
            },
            "modules": ["sales", "service"]
          },
          "effectiveAt": "2027-01-15T08:00:00Z",
          "expiresAt": null,
          "usage": {
            "users": 4, "employees": 3, "devices": 4, "owners": 1,
            "leads": 20, "customers": 12, "jobs": 40
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            PFSSAccountEntitlementSnapshot.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(snapshot.permitsChanges)
        XCTAssertEqual(snapshot.accessSource, .betaGrant)
        XCTAssertEqual(snapshot.entitlements.userLimit, 5)
        XCTAssertEqual(snapshot.entitlements.recordLimits.jobs, 3_000)
        XCTAssertEqual(snapshot.usage.devices, 4)

        let readOnly = PFSSAccountEntitlementSnapshot(
            appAccountToken: snapshot.appAccountToken,
            planCode: snapshot.planCode,
            accessSource: .appStoreSubscription,
            subscriptionStatus: .pastDue,
            accessMode: .readOnly,
            entitlements: snapshot.entitlements,
            effectiveAt: snapshot.effectiveAt,
            expiresAt: snapshot.expiresAt,
            usage: snapshot.usage
        )
        XCTAssertFalse(readOnly.permitsChanges)
    }

    func testIdentityAuthorizationSessionUsesProviderNeutralContract() throws {
        let session = PFSSIdentityAuthorizationSession(
            authorizationURL: try XCTUnwrap(
                URL(string: "https://identity.staging.pfss.test/authorize")
            ),
            state: String(repeating: "s", count: 43),
            expiresAt: now.addingTimeInterval(300)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(json["providerSecret"])
        XCTAssertNil(json["clientSecret"])
        XCTAssertNotNil(json["authorizationURL"])
    }

    func testPKCEGeneratorProducesURLSafeIndependentSecrets() throws {
        let credentials = try PFSSPKCEGenerator.make()
        let allowed = /^[A-Za-z0-9_-]{43,128}$/
        XCTAssertNotNil(credentials.state.wholeMatch(of: allowed))
        XCTAssertNotNil(credentials.verifier.wholeMatch(of: allowed))
        XCTAssertNotNil(credentials.challenge.wholeMatch(of: allowed))
        XCTAssertNotEqual(credentials.state, credentials.verifier)
        XCTAssertNotEqual(credentials.verifier, credentials.challenge)
    }

    func testOwnerAuthenticationConsumesOnlyMatchingCallbackOnce() async throws {
        let store = PendingAuthorizationMemoryStore()
        let coordinator = PFSSOwnerAuthenticationCoordinator(
            service: PFSSLocalOwnerAuthorizationService(),
            pendingStore: store
        )
        let session = try await coordinator.start(emailHint: "owner@example.com")
        let pending = try XCTUnwrap(store.value)
        XCTAssertEqual(session.state, pending.state)

        let wrongCallback = try XCTUnwrap(URL(
            string: "https://local.pfss.test/auth/callback?state=wrong&code=test"
        ))
        XCTAssertThrowsError(try coordinator.consumeCallback(wrongCallback)) {
            XCTAssertEqual(
                $0 as? PFSSOwnerAuthenticationError,
                .stateMismatch
            )
        }
        XCTAssertNotNil(store.value)

        var components = URLComponents(
            string: "https://local.pfss.test/auth/callback"
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: pending.state),
            URLQueryItem(name: "code", value: "verified-code"),
        ]
        let result = try coordinator.consumeCallback(
            try XCTUnwrap(components.url)
        )
        XCTAssertEqual(result.state, pending.state)
        XCTAssertEqual(result.code, "verified-code")
        XCTAssertEqual(result.codeVerifier, pending.codeVerifier)
        XCTAssertNil(store.value)
        XCTAssertThrowsError(
            try coordinator.consumeCallback(try XCTUnwrap(components.url))
        )
    }

    private func validRequest() -> PFSSOwnerRegistrationRequest {
        PFSSOwnerRegistrationRequest(
            idempotencyKey: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            identityAssertion: "verified-identity-assertion-reference",
            authenticationMethod: .passkey,
            owner: PFSSOwnerRegistrationIdentity(
                displayName: "Geoff Nordmyer",
                email: "owner@example.com"
            ),
            company: PFSSCompanyRegistrationProfile(
                displayName: "PFSS Development",
                timeZoneID: "America/Chicago"
            ),
            requestedPlanCode: "team-annual",
            consent: PFSSRegistrationConsent(
                termsVersion: "terms-2026-07",
                privacyVersion: "privacy-2026-07",
                acceptedAt: now
            ),
            device: PFSSRegistrationDevice(
                id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
                displayName: "Owner iPad"
            )
        )
    }

    private final class PendingAuthorizationMemoryStore:
        PFSSPendingOwnerAuthorizationStoring {
        var value: PFSSPendingOwnerAuthorization?

        func load() -> PFSSPendingOwnerAuthorization? { value }

        func save(_ authorization: PFSSPendingOwnerAuthorization) throws {
            value = authorization
        }

        func delete() { value = nil }
    }
}
