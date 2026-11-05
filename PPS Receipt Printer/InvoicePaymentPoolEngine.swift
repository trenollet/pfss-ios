import Foundation

/// A verification is an assertion by the user who checked collection, not
/// proof from an invoice status or an automatically generated receipt.
/// Keep this evidence when correcting allocations; never rewrite receipts.
struct InvoiceCollectionVerification: Identifiable, Codable, Equatable {
    var id: UUID
    var sourceInvoiceID: UUID
    var recordedAmount: Decimal
    var collectedAmount: Decimal
    var receiptIDs: [UUID]
    var paymentEventIDs: [UUID]
    var verifiedBy: String
    var verifiedAt: Date
    var note: String
    /// Only for separately verified later receipt events, never a transfer.
    var isAdditionalReceiptCollection: Bool? = nil
}

/// A pool contains verified money, not new payment events. Its identity and
/// verification identities must survive combination and later corrections.
struct InvoicePaymentPool: Identifiable, Codable, Equatable {
    var id: UUID
    var verifications: [InvoiceCollectionVerification]
    var adjustments: [InvoiceCollectionAdjustment]

    var collectedAmount: Decimal {
        verifications.reduce(0) { $0 + $1.collectedAmount }
            + adjustments.reduce(0) { $0 + $1.amountChange }
    }
}

/// An append-only correction of an earlier collection check. This changes
/// the verified accounting amount, not the immutable receipt or actual cash.
/// A real refund must be recorded separately as an actual cash movement.
struct InvoiceCollectionAdjustment: Identifiable, Codable, Equatable {
    var id: UUID
    var verificationID: UUID
    var amountChange: Decimal
    var correctedBy: String
    var correctedAt: Date
    var reason: String
}

struct InvoicePoolAllocation: Codable, Equatable {
    var invoiceID: UUID
    var invoiceTotal: Decimal
    var appliedAmount: Decimal

    var remainingDue: Decimal { invoiceTotal - appliedAmount }
}

/// An immutable correction proposal. Replacing an allocation is not a
/// collection or refund. A positive refundRequired requests human action;
/// it must never be treated as evidence that a refund was actually made.
struct InvoicePaymentRedistribution: Identifiable, Codable, Equatable {
    var id: UUID
    var pool: InvoicePaymentPool
    var replacesRedistributionID: UUID?
    var allocations: [InvoicePoolAllocation]
    var preparedBy: String
    var preparedAt: Date
    var reason: String

    var appliedAmount: Decimal {
        allocations.reduce(0) { $0 + $1.appliedAmount }
    }
    var remainingDue: Decimal {
        allocations.reduce(0) { $0 + $1.remainingDue }
    }
    var refundRequired: Decimal { pool.collectedAmount - appliedAmount }
}

/// UI-independent accounting rules shared by combining and repairing bills.
/// No role restriction belongs here. Existing invoice-access authorization
/// still applies in the persistence/server layers.
enum InvoicePaymentPoolEngine {
    enum ValidationError: Error, Equatable, LocalizedError {
        case invalidAmount
        case missingVerification
        case verificationExceedsRecordedPayment
        case discrepancyNeedsExplanation
        case duplicateVerification
        case duplicateInvoiceVerification
        case duplicateReceipt
        case invalidReceiptReferences
        case duplicateAllocation
        case allocationExceedsInvoice
        case allocationExceedsPool
        case emptyAllocation
        case missingCorrectionReason
        case wrongPool
        case changedCollectionHistory
        case invalidCollectionAdjustment

        var errorDescription: String? {
            switch self {
            case .invalidAmount: "Enter a nonnegative amount with no more than two decimal places."
            case .missingVerification: "Identify who verified the money was actually collected."
            case .verificationExceedsRecordedPayment: "Record additional money as a payment before adding it to the pool."
            case .discrepancyNeedsExplanation: "Explain why the collected amount differs from the recorded payment."
            case .duplicateVerification: "The same verification appears more than once."
            case .duplicateInvoiceVerification: "This invoice's payment is already included in the pool."
            case .duplicateReceipt: "A receipt is already included in another invoice's verification."
            case .invalidReceiptReferences: "Each receipt must retain its original payment-event reference."
            case .duplicateAllocation: "Allocate funds to each invoice only once."
            case .allocationExceedsInvoice: "The allocation exceeds this invoice's total. Leave excess funds in the pool for refund review."
            case .allocationExceedsPool: "The allocations exceed the money actually collected."
            case .emptyAllocation: "Select at least one invoice for redistribution."
            case .missingCorrectionReason: "Identify who prepared the redistribution and explain the correction."
            case .wrongPool: "This correction must use the original payment pool."
            case .changedCollectionHistory: "Preserve the original verifications. Record changes as separate accounting actions."
            case .invalidCollectionAdjustment: "Identify the collection check being corrected, explain the change, and keep its verified amount between zero and the recorded payment."
            }
        }
    }

    static func makePool(
        id: UUID = UUID(),
        verifications: [InvoiceCollectionVerification],
        adjustments: [InvoiceCollectionAdjustment] = []
    ) throws -> InvoicePaymentPool {
        var verificationIDs = Set<UUID>()
        var invoiceIDs = Set<UUID>()
        var legacyInvoiceIDs = Set<UUID>()
        var receiptIDs = Set<UUID>()
        var paymentEventIDs = Set<UUID>()
        var total: Decimal = 0
        var verifiedAmounts: [UUID: Decimal] = [:]
        var recordedAmounts: [UUID: Decimal] = [:]
        for verification in verifications {
            try validateMoney(verification.recordedAmount)
            try validateMoney(verification.collectedAmount)
            guard verificationIDs.insert(verification.id).inserted else {
                throw ValidationError.duplicateVerification
            }
            // Legacy invoices without receipt events can only contribute one
            // verified lump sum. With receipts, later disjoint collections
            // from the same invoice may be added without counting old money.
            if verification.receiptIDs.isEmpty {
                guard !invoiceIDs.contains(verification.sourceInvoiceID) else {
                    throw ValidationError.duplicateInvoiceVerification
                }
                legacyInvoiceIDs.insert(verification.sourceInvoiceID)
            } else if legacyInvoiceIDs.contains(verification.sourceInvoiceID), verification.isAdditionalReceiptCollection != true {
                throw ValidationError.duplicateInvoiceVerification
            }
            invoiceIDs.insert(verification.sourceInvoiceID)
            guard verification.receiptIDs.count == verification.paymentEventIDs.count else {
                throw ValidationError.invalidReceiptReferences
            }
            guard !verification.verifiedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.missingVerification
            }
            guard verification.collectedAmount <= verification.recordedAmount else {
                throw ValidationError.verificationExceedsRecordedPayment
            }
            if verification.collectedAmount != verification.recordedAmount,
               verification.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.discrepancyNeedsExplanation
            }
            for receiptID in verification.receiptIDs {
                guard receiptIDs.insert(receiptID).inserted else {
                    throw ValidationError.duplicateReceipt
                }
            }
            for eventID in verification.paymentEventIDs {
                guard paymentEventIDs.insert(eventID).inserted else {
                    throw ValidationError.duplicateReceipt
                }
            }
            total += verification.collectedAmount
            try validateMoney(total)
            verifiedAmounts[verification.id] = verification.collectedAmount
            recordedAmounts[verification.id] = verification.recordedAmount
        }
        for adjustment in adjustments {
            guard verificationIDs.insert(adjustment.id).inserted,
                  let verified = verifiedAmounts[adjustment.verificationID],
                  let recorded = recordedAmounts[adjustment.verificationID],
                  !adjustment.amountChange.isNaN, adjustment.amountChange != 0,
                  !adjustment.correctedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !adjustment.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidCollectionAdjustment
            }
            try validateMoney(abs(adjustment.amountChange))
            let corrected = verified + adjustment.amountChange
            guard corrected >= 0, corrected <= recorded else {
                throw ValidationError.invalidCollectionAdjustment
            }
            verifiedAmounts[adjustment.verificationID] = corrected
            total += adjustment.amountChange
            try validateMoney(total)
        }
        return InvoicePaymentPool(id: id, verifications: verifications, adjustments: adjustments)
    }

    static func redistribute(
        pool: InvoicePaymentPool,
        allocations: [InvoicePoolAllocation],
        preparedBy: String,
        reason: String,
        replacing previous: InvoicePaymentRedistribution? = nil,
        id: UUID = UUID(),
        at timestamp: Date = Date()
    ) throws -> InvoicePaymentRedistribution {
        // Revalidate decoded or externally supplied pools, not only pools
        // constructed by makePool in this process.
        let validatedPool = try makePool(id: pool.id, verifications: pool.verifications, adjustments: pool.adjustments)
        if let previous {
            guard previous.pool.id == pool.id else { throw ValidationError.wrongPool }
            // New, separately verified collections may join the same pool.
            // Earlier collection evidence must remain byte-for-value intact.
            guard validatedPool.verifications.count >= previous.pool.verifications.count,
                  Array(validatedPool.verifications.prefix(previous.pool.verifications.count))
                    == previous.pool.verifications,
                  validatedPool.adjustments.count >= previous.pool.adjustments.count,
                  Array(validatedPool.adjustments.prefix(previous.pool.adjustments.count))
                    == previous.pool.adjustments else {
                throw ValidationError.changedCollectionHistory
            }
        }
        guard !allocations.isEmpty else { throw ValidationError.emptyAllocation }
        guard !preparedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingCorrectionReason
        }
        var invoiceIDs = Set<UUID>()
        var applied: Decimal = 0
        var invoiceTotal: Decimal = 0
        for allocation in allocations {
            guard invoiceIDs.insert(allocation.invoiceID).inserted else {
                throw ValidationError.duplicateAllocation
            }
            try validateMoney(allocation.invoiceTotal)
            try validateMoney(allocation.appliedAmount)
            guard allocation.appliedAmount <= allocation.invoiceTotal else {
                throw ValidationError.allocationExceedsInvoice
            }
            applied += allocation.appliedAmount
            invoiceTotal += allocation.invoiceTotal
            try validateMoney(applied)
            try validateMoney(invoiceTotal)
        }
        guard applied <= validatedPool.collectedAmount else {
            throw ValidationError.allocationExceedsPool
        }
        return InvoicePaymentRedistribution(
            id: id, pool: validatedPool,
            replacesRedistributionID: previous?.id,
            allocations: allocations, preparedBy: preparedBy,
            preparedAt: timestamp, reason: reason
        )
    }

    private static func validateMoney(_ amount: Decimal) throws {
        // A generous bound keeps sums inside Decimal's precision while also
        // rejecting invalid/overflowed data. Never silently round user funds.
        guard !amount.isNaN, amount >= 0,
              amount <= Decimal(9_000_000_000_000),
              TaxEngine.currency(amount) == amount else {
            throw ValidationError.invalidAmount
        }
    }
}
