//
//  PFSSAppStoreSubscriptionAdapter.swift
//  PPS Receipt Printer
//
//  Phase 17 – StoreKit 2 adapter. Apple supplies signed purchase evidence;
//  the PFSS server remains the only authority that changes account access.
//

import Foundation
import Combine
import StoreKit

enum PFSSAppStorePlan: String, CaseIterable, Identifiable {
    case base = "base-monthly"
    case pro = "pro-monthly"
    case expert = "expert-monthly"

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .base: return "com.patriot.pfss.subscription.base.monthly"
        case .pro: return "com.patriot.pfss.subscription.pro.monthly"
        case .expert: return "com.patriot.pfss.subscription.expert.monthly"
        }
    }
}

struct PFSSAppStoreTransactionEvidence: Encodable, Equatable {
    let signedTransaction: String
    let planCode: String
    let productID: String
}

struct PFSSAppStoreTransactionReceipt: Decodable, Equatable {
    enum Status: String, Decodable {
        case pendingVerification
        case verified
        case rejected
    }

    let evidenceID: UUID
    let status: Status
}

enum PFSSAppStoreSubscriptionError: LocalizedError {
    case productUnavailable
    case purchasePending
    case purchaseCancelled
    case unverifiedTransaction
    case serverVerificationPending

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "This PFSS plan is not available from the App Store yet."
        case .purchasePending:
            return "The App Store purchase is awaiting approval."
        case .purchaseCancelled:
            return "The purchase was cancelled."
        case .unverifiedTransaction:
            return "The App Store could not verify this transaction."
        case .serverVerificationPending:
            return "PFSS received the purchase and is verifying it with Apple."
        }
    }
}

@MainActor
final class PFSSAppStoreSubscriptionAdapter: ObservableObject {
    @Published private(set) var products: [PFSSAppStorePlan: Product] = [:]
    @Published private(set) var isWorking = false

    private let submitEvidence:
        (PFSSAppStoreTransactionEvidence) async throws -> PFSSAppStoreTransactionReceipt

    init(
        submitEvidence: @escaping
            (PFSSAppStoreTransactionEvidence) async throws -> PFSSAppStoreTransactionReceipt
    ) {
        self.submitEvidence = submitEvidence
    }

    func loadProducts() async throws {
        let requested = Set(PFSSAppStorePlan.allCases.map(\.productID))
        let loaded = try await Product.products(for: requested)
        products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
            guard let plan = PFSSAppStorePlan.allCases.first(where: {
                $0.productID == product.id
            }) else { return nil }
            return (plan, product)
        })
    }

    /// A locally verified StoreKit result is submitted as its Apple-signed JWS.
    /// The app does not change its plan from this result; it waits for the
    /// server-resolved entitlement receipt to change after Apple verification.
    func purchase(
        _ plan: PFSSAppStorePlan,
        appAccountToken: UUID
    ) async throws -> PFSSAppStoreTransactionReceipt {
        guard let product = products[plan] else {
            throw PFSSAppStoreSubscriptionError.productUnavailable
        }
        isWorking = true
        defer { isWorking = false }

        let result = try await product.purchase(
            options: [.appAccountToken(appAccountToken)]
        )
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PFSSAppStoreSubscriptionError.unverifiedTransaction
            }
            let receipt = try await submitEvidence(
                PFSSAppStoreTransactionEvidence(
                    signedTransaction: verification.jwsRepresentation,
                    planCode: plan.rawValue,
                    productID: transaction.productID
                )
            )
            guard receipt.status == .verified else {
                throw PFSSAppStoreSubscriptionError.serverVerificationPending
            }
            await transaction.finish()
            return receipt
        case .pending:
            throw PFSSAppStoreSubscriptionError.purchasePending
        case .userCancelled:
            throw PFSSAppStoreSubscriptionError.purchaseCancelled
        @unknown default:
            throw PFSSAppStoreSubscriptionError.productUnavailable
        }
    }
}
