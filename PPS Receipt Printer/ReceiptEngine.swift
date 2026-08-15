import Foundation

/// UI-independent receipt rules. The engine converts an increase in an
/// invoice's cumulative amount paid into immutable payment evidence.
struct ReceiptEngine {
    static func requiresReceipt(
        previous: InvoiceRecord,
        proposed: InvoiceRecord
    ) -> Bool {
        currency(proposed.amountPaid - previous.amountPaid) > 0
    }

    static func recordingPayment(
        previous: InvoiceRecord,
        proposed: InvoiceRecord,
        receiptNumber: String,
        paymentEventID: UUID = UUID(),
        paymentMethod: ReceiptPaymentMethod = .unspecified,
        timestamp: Date = Date()
    ) -> InvoiceRecord {
        var result = proposed

        guard !(result.receipts ?? []).contains(where: {
            $0.paymentEventID == paymentEventID
        }) else {
            return result
        }

        let paymentAmount = currency(
            result.amountPaid - previous.amountPaid
        )
        guard paymentAmount > 0 else { return result }

        let snapshot = ReceiptSnapshot(
            id: UUID(),
            paymentEventID: paymentEventID,
            receiptNumber: receiptNumber,
            invoiceID: result.id,
            invoiceNumber: result.invoiceNumber,
            customerNumber: result.customerNumber,
            siteID: result.siteID,
            jobNumber: result.jobNumber,
            lineItems: result.lineItems,
            subtotal: result.subtotal,
            discount: result.discount,
            total: result.total,
            taxSnapshot: result.taxSnapshot,
            paymentAmount: paymentAmount,
            totalPaid: currency(result.amountPaid),
            balanceDue: currency(result.balanceDue),
            paymentMethod: paymentMethod,
            issuedAt: timestamp,
            notes: result.notes
        )
        var receipts = result.receipts ?? []
        receipts.append(snapshot)
        result.receipts = receipts
        return result
    }

    static func latestReceipt(in invoice: InvoiceRecord) -> ReceiptSnapshot? {
        invoice.receipts?.max { $0.issuedAt < $1.issuedAt }
    }

    private static func currency(_ value: Double) -> Double {
        NSDecimalNumber(
            decimal: TaxEngine.currency(Decimal(value))
        ).doubleValue
    }
}
