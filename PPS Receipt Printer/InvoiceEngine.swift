import Foundation

/// UI-independent invoice business rules. Views and persistence layers supply
/// inputs; this engine owns calculations and lifecycle normalization.
struct InvoiceEngine {
    struct DraftInput {
        var invoiceNumber: String
        var customerNumber: String
        var siteID: UUID?
        var jobNumber: String
        var lineItems: [ServiceLineItem]
        var discount: Double
        var taxSnapshot: TaxCalculationSnapshot?
        var issueDate: Date
        var dueDate: Date
        var notes: String
    }

    /// Creates a stable draft from already-snapshotted source data.
    static func makeDraft(from input: DraftInput) -> InvoiceRecord {
        let subtotal = PricingCalculator.subtotal(for: input.lineItems)
        let total = invoiceTotal(
            subtotal: subtotal,
            discount: input.discount,
            taxSnapshot: input.taxSnapshot
        )

        return InvoiceRecord(
            invoiceNumber: input.invoiceNumber,
            customerNumber: input.customerNumber,
            siteID: input.siteID,
            jobNumber: input.jobNumber,
            lineItems: input.lineItems,
            subtotal: subtotal,
            discount: input.discount,
            total: total,
            taxSnapshot: input.taxSnapshot,
            amountPaid: 0,
            balanceDue: total,
            status: .draft,
            issueDate: input.issueDate,
            dueDate: input.dueDate,
            paidDate: nil,
            notes: input.notes
        )
    }

    /// Recalculates all derived money fields, then reconciles payment state.
    /// Historical tax evidence is retained exactly as supplied.
    static func recalculated(
        _ invoice: InvoiceRecord,
        at timestamp: Date = Date()
    ) -> InvoiceRecord {
        var result = invoice
        result.lineItems = PricingCalculator.updatedLineItems(result.lineItems)
        result.subtotal = PricingCalculator.subtotal(for: result.lineItems)
        result.discount = nonnegativeCurrency(result.discount)
        result.taxSnapshot = refreshedTaxSnapshot(for: result, at: timestamp)
        result.total = invoiceTotal(
            subtotal: result.subtotal,
            discount: result.discount,
            taxSnapshot: result.taxSnapshot
        )
        return normalizedAfterInvoiceEdit(result, at: timestamp)
    }

    /// Reconciles a corrected invoice without inventing or erasing payment.
    /// Receipts remain the immutable evidence of what the customer actually
    /// paid; repricing can make a paid invoice partially paid, but cannot
    /// silently increase the recorded payment to the new total.
    static func normalizedAfterInvoiceEdit(
        _ invoice: InvoiceRecord,
        at timestamp: Date = Date()
    ) -> InvoiceRecord {
        var result = invoice
        result.total = nonnegativeCurrency(result.total)
        result.amountPaid = nonnegativeCurrency(result.amountPaid)

        if result.status == .void {
            result.balanceDue = 0
            result.paidDate = nil
            return result
        }

        result.balanceDue = nonnegativeCurrency(result.total - result.amountPaid)
        if result.total > 0, result.amountPaid >= result.total {
            result.status = .paid
            result.paidDate = result.paidDate ?? timestamp
        } else if result.amountPaid > 0 {
            result.status = .partiallyPaid
            result.paidDate = nil
        } else {
            if result.status == .paid || result.status == .partiallyPaid {
                result.status = .sent
            }
            result.paidDate = nil
        }
        return result
    }

    /// Applies tax evidence and recalculates the invoice as one atomic value.
    static func applyingTax(
        _ snapshot: TaxCalculationSnapshot?,
        to invoice: InvoiceRecord,
        at timestamp: Date = Date()
    ) -> InvoiceRecord {
        var result = invoice
        result.taxSnapshot = snapshot
        return recalculated(result, at: timestamp)
    }

    /// Reconciles an explicitly selected status with the amount paid. Void
    /// invoices retain their payment evidence but never acquire a paid date.
    static func normalizedPaymentState(
        for invoice: InvoiceRecord,
        at timestamp: Date = Date()
    ) -> InvoiceRecord {
        var result = invoice
        let total = nonnegativeCurrency(result.total)
        result.total = total

        if result.status == .void {
            result.amountPaid = min(nonnegativeCurrency(result.amountPaid), total)
            result.balanceDue = 0
            result.paidDate = nil
            return result
        }

        if result.status == .paid {
            result.amountPaid = total
        } else {
            result.amountPaid = min(nonnegativeCurrency(result.amountPaid), total)

            if total > 0 && result.amountPaid >= total {
                result.status = .paid
            } else if result.amountPaid > 0 {
                result.status = .partiallyPaid
            } else if result.status == .partiallyPaid || result.status == .paid {
                result.status = .sent
            }
        }

        result.balanceDue = nonnegativeCurrency(total - result.amountPaid)
        if result.status == .paid {
            result.paidDate = result.paidDate ?? timestamp
        } else {
            result.paidDate = nil
        }
        return result
    }

    static func invoiceTotal(
        subtotal: Double,
        discount: Double,
        taxSnapshot: TaxCalculationSnapshot?
    ) -> Double {
        NSDecimalNumber(
            decimal: TaxEngine.invoiceTotal(
                subtotal: Decimal(subtotal),
                discount: Decimal(discount),
                snapshot: taxSnapshot
            )
        ).doubleValue
    }

    static func existingInvoice(
        forJobNumber jobNumber: String,
        in invoices: [InvoiceRecord]
    ) -> InvoiceRecord? {
        invoices.first { $0.jobNumber == jobNumber }
    }

    private static func refreshedTaxSnapshot(
        for invoice: InvoiceRecord,
        at timestamp: Date
    ) -> TaxCalculationSnapshot? {
        guard let snapshot = invoice.taxSnapshot else { return nil }
        return try? TaxEngine.calculate(
            lines: invoice.lineItems,
            discount: Decimal(invoice.discount),
            quote: TaxRateQuote(
                jurisdiction: snapshot.jurisdiction,
                rate: snapshot.appliedRate,
                source: snapshot.rateSource,
                effectiveDate: snapshot.rateEffectiveDate
            ),
            exemptionReason: snapshot.exemptionReason,
            overrideEvidence: snapshot.overrideEvidence,
            calculatedAt: timestamp
        )
    }

    private static func nonnegativeCurrency(_ value: Double) -> Double {
        NSDecimalNumber(
            decimal: TaxEngine.currency(max(Decimal(value), 0))
        ).doubleValue
    }
}
