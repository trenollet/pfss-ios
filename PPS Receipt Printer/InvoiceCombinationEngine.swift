import Foundation

/// A proposal retains source invoices verbatim, including their tax and
/// receipt evidence. It is deliberately not an InvoiceRecord: persistence
/// must commit source links, the new bill, and payment allocation together.
struct InvoiceCombinationProposal: Identifiable, Codable {
    struct Line: Identifiable, Codable {
        var id: UUID { item.id }
        var sourceInvoiceID: UUID
        var sourceLineItemID: UUID
        var item: ServiceLineItem
    }

    var id: UUID
    var invoiceNumber: String
    var billingCustomerNumber: String
    var sourceInvoices: [InvoiceRecord]
    var lines: [Line]
    var paymentRedistribution: InvoicePaymentRedistribution
    var createdAt: Date

    var jobNumbers: [String] {
        var seen = Set<String>()
        return sourceInvoices.map(\.jobNumber).filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }
    var subtotal: Decimal { sourceInvoices.reduce(0) { $0 + Decimal($1.subtotal) } }
    var discount: Decimal { sourceInvoices.reduce(0) { $0 + Decimal($1.discount) } }
    var total: Decimal { sourceInvoices.reduce(0) { $0 + Decimal($1.total) } }
    var addedTax: Decimal { sourceInvoices.reduce(0) { $0 + ($1.taxSnapshot?.addedTax ?? 0) } }
    var amountPaid: Decimal { paymentRedistribution.allocations.first { $0.invoiceID == id }?.appliedAmount ?? 0 }
    var balanceDue: Decimal { max(total - amountPaid, 0) }
    var refundRequired: Decimal { paymentRedistribution.refundRequired }
}

enum InvoiceCombinationEngine {
    enum ValidationError: Error, Equatable, LocalizedError {
        case insufficientInvoices, duplicateInvoice, unavailableInvoice
        case missingBillDetails, invalidMoney, missingCollectionCheck
        case staleCollectionCheck, unrelatedCollectionCheck, invalidReceiptEvidence
        case reusedInvoiceIdentity

        var errorDescription: String? {
            switch self {
            case .insufficientInvoices: "Select at least two invoices to combine."
            case .duplicateInvoice: "An invoice can only be selected once."
            case .unavailableInvoice: "Archived or void invoices cannot be combined."
            case .missingBillDetails: "Select a billing customer and reserve a new invoice number."
            case .invalidMoney: "Review an invoice containing invalid financial amounts before combining."
            case .missingCollectionCheck: "Verify the amount actually collected for every invoice with a recorded payment or Paid status."
            case .staleCollectionCheck: "The recorded payment changed. Review collection again before combining."
            case .unrelatedCollectionCheck: "A collection check belongs to an invoice that was not selected."
            case .invalidReceiptEvidence: "Retain the original receipt and payment-event references when verifying collection."
            case .reusedInvoiceIdentity: "The combined invoice needs a new identity and invoice number."
            }
        }
    }

    static func propose(
        id: UUID = UUID(),
        invoiceNumber: String,
        billingCustomerNumber: String,
        sources: [InvoiceRecord],
        verifications: [InvoiceCollectionVerification],
        preparedBy: String,
        at timestamp: Date = Date()
    ) throws -> InvoiceCombinationProposal {
        guard sources.count >= 2 else { throw ValidationError.insufficientInvoices }
        guard Set(sources.map(\.id)).count == sources.count else {
            throw ValidationError.duplicateInvoice
        }
        guard !invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !billingCustomerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingBillDetails
        }
        let sourceIDs = Set(sources.map(\.id))
        guard !sourceIDs.contains(id), !sources.contains(where: {
            $0.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }) else { throw ValidationError.reusedInvoiceIdentity }
        guard verifications.allSatisfy({ sourceIDs.contains($0.sourceInvoiceID) }) else {
            throw ValidationError.unrelatedCollectionCheck
        }
        for invoice in sources {
            guard invoice.lifecycleStatus == .active, invoice.status != .void,
                  invoice.combinedIntoInvoiceID == nil, invoice.combination == nil, invoice.paymentCorrection == nil else {
                throw ValidationError.unavailableInvoice
            }
            for value in [invoice.subtotal, invoice.discount, invoice.total, invoice.amountPaid] {
                guard value.isFinite, value >= 0, value <= 9_000_000_000_000,
                      TaxEngine.currency(Decimal(value)) == Decimal(value) else {
                    throw ValidationError.invalidMoney
                }
            }
            let checks = verifications.filter { $0.sourceInvoiceID == invoice.id }
            if invoice.amountPaid > 0 || invoice.status == .paid || !(invoice.receipts ?? []).isEmpty {
                guard checks.count == 1 else { throw ValidationError.missingCollectionCheck }
            } else if checks.count > 1 {
                throw ValidationError.staleCollectionCheck
            }
            if let check = checks.first {
                guard check.recordedAmount == (try recordedCollectionAmount(for: invoice)) else {
                    throw ValidationError.staleCollectionCheck
                }
                let receipts = invoice.receipts ?? []
                guard Set(check.receiptIDs) == Set(receipts.map(\.id)),
                      Set(check.paymentEventIDs) == Set(receipts.map(\.paymentEventID)) else {
                    throw ValidationError.invalidReceiptEvidence
                }
            }
        }
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: verifications)
        let total = sources.reduce(Decimal.zero) { $0 + Decimal($1.total) }
        let redistribution = try InvoicePaymentPoolEngine.redistribute(
            pool: pool,
            allocations: [.init(invoiceID: id, invoiceTotal: total,
                                appliedAmount: min(pool.collectedAmount, total))],
            preparedBy: preparedBy, reason: "Combine selected invoices", at: timestamp
        )
        let lines = sources.flatMap { invoice in
            invoice.lineItems.map { original in
                var copy = original
                copy.id = UUID()
                return InvoiceCombinationProposal.Line(
                    sourceInvoiceID: invoice.id, sourceLineItemID: original.id, item: copy
                )
            }
        }
        return InvoiceCombinationProposal(
            id: id, invoiceNumber: invoiceNumber,
            billingCustomerNumber: billingCustomerNumber,
            sourceInvoices: sources, lines: lines,
            paymentRedistribution: redistribution, createdAt: timestamp
        )
    }

    /// Receipt history can retain an overpayment even when a legacy status
    /// normalization capped the cumulative amountPaid. Review that history,
    /// not the capped number, and explicitly verify actual collection.
    static func recordedCollectionAmount(for invoice: InvoiceRecord) throws -> Decimal {
        guard invoice.amountPaid.isFinite, invoice.amountPaid >= 0,
              invoice.amountPaid <= 9_000_000_000_000,
              TaxEngine.currency(Decimal(invoice.amountPaid)) == Decimal(invoice.amountPaid) else {
            throw ValidationError.invalidMoney
        }
        let receipts = invoice.receipts ?? []
        guard !receipts.isEmpty else { return Decimal(invoice.amountPaid) }
        var events = Set<UUID>()
        var receiptIDs = Set<UUID>()
        var result: Decimal = 0
        for receipt in receipts {
            guard events.insert(receipt.paymentEventID).inserted,
                  receiptIDs.insert(receipt.id).inserted else {
                throw ValidationError.invalidReceiptEvidence
            }
            guard receipt.paymentAmount.isFinite, receipt.paymentAmount >= 0,
                  receipt.paymentAmount <= 9_000_000_000_000,
                  TaxEngine.currency(Decimal(receipt.paymentAmount)) == Decimal(receipt.paymentAmount) else {
                throw ValidationError.invalidMoney
            }
            result += Decimal(receipt.paymentAmount)
            guard !result.isNaN, result <= Decimal(9_000_000_000_000) else {
                throw ValidationError.invalidMoney
            }
        }
        return result
    }
}
