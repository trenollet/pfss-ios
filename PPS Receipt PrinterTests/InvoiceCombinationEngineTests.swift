import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class InvoiceCombinationEngineTests: XCTestCase {
    private func invoice(_ number: String, total: Double = 100) -> InvoiceRecord {
        InvoiceEngine.makeDraft(from: .init(
            invoiceNumber: number, customerNumber: "CUS-\(number)", siteID: UUID(),
            jobNumber: "JOB-\(number)", lineItems: [.init(
                serviceType: .other, otherService: "Service \(number)", description: "Original scope",
                quantity: 1, unitPrice: total, lineTotal: total
            )], discount: 0, taxSnapshot: nil, issueDate: Date(), dueDate: Date(), notes: "Source notes"
        ))
    }
    private func verification(_ source: InvoiceRecord, collected: Decimal? = nil) -> InvoiceCollectionVerification {
        .init(id: UUID(), sourceInvoiceID: source.id,
              recordedAmount: (try? InvoiceCombinationEngine.recordedCollectionAmount(for: source)) ?? Decimal(source.amountPaid),
              collectedAmount: collected ?? ((try? InvoiceCombinationEngine.recordedCollectionAmount(for: source)) ?? Decimal(source.amountPaid)),
              receiptIDs: (source.receipts ?? []).map(\.id), paymentEventIDs: (source.receipts ?? []).map(\.paymentEventID),
              verifiedBy: "Technician", verifiedAt: Date(), note: "Checked collection")
    }
    private func propose(_ invoices: [InvoiceRecord], _ checks: [InvoiceCollectionVerification] = []) throws -> InvoiceCombinationProposal {
        try InvoiceCombinationEngine.propose(invoiceNumber: "INV-NEW", billingCustomerNumber: "CUS-UMBRELLA",
                                              sources: invoices, verifications: checks, preparedBy: "Technician")
    }

    func testCombinesDifferentCustomersAndRetainsJobAndLineOrigins() throws {
        let a = invoice("A"), b = invoice("B", total: 200)
        let result = try propose([a, b])
        XCTAssertEqual(result.invoiceNumber, "INV-NEW")
        XCTAssertEqual(result.billingCustomerNumber, "CUS-UMBRELLA")
        XCTAssertEqual(result.jobNumbers, ["JOB-A", "JOB-B"])
        XCTAssertEqual(result.total, 300)
        XCTAssertEqual(result.balanceDue, 300)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].sourceInvoiceID, a.id)
        XCTAssertEqual(result.lines[0].sourceLineItemID, a.lineItems[0].id)
        XCTAssertNotEqual(result.lines[0].item.id, a.lineItems[0].id)
        XCTAssertEqual(result.lines[0].item.description, a.lineItems[0].description)
    }

    func testPaidStatusDoesNotAutomaticallyContributeMoney() throws {
        var a = invoice("A")
        a.status = .paid
        a.amountPaid = 100
        XCTAssertThrowsError(try propose([a, invoice("B")])) {
            XCTAssertEqual($0 as? InvoiceCombinationEngine.ValidationError, .missingCollectionCheck)
        }
        let result = try propose([a, invoice("B")], [verification(a, collected: 0)])
        XCTAssertEqual(result.amountPaid, 0)
        XCTAssertEqual(result.balanceDue, 200)
        XCTAssertEqual(result.sourceInvoices[0].amountPaid, 100)
    }

    func testVerifiedPaidMoneyIsCarriedWithoutIssuingAnotherReceipt() throws {
        let a = invoice("A")
        var paid = a
        paid.amountPaid = 100
        paid.status = .paid
        paid = ReceiptEngine.recordingPayment(previous: a, proposed: paid, receiptNumber: "REC-1")
        let result = try propose([paid, invoice("B", total: 50)], [verification(paid)])
        XCTAssertEqual(result.amountPaid, 100)
        XCTAssertEqual(result.balanceDue, 50)
        XCTAssertEqual(result.sourceInvoices[0].receipts?.first?.id, paid.receipts?.first?.id)
        XCTAssertEqual(result.paymentRedistribution.pool.verifications[0].paymentEventIDs, paid.receipts?.map(\.paymentEventID))
    }

    func testStaleVerificationAndInventedReceiptReferencesAreRejected() throws {
        var a = invoice("A")
        a.amountPaid = 50
        var check = verification(a)
        a.amountPaid = 60
        XCTAssertThrowsError(try propose([a, invoice("B")], [check]))
        check = verification(a)
        check.receiptIDs = [UUID()]
        check.paymentEventIDs = [UUID()]
        XCTAssertThrowsError(try propose([a, invoice("B")], [check]))
    }

    func testSourcesCannotBeSelectedTwiceOrBeVoidOrArchived() {
        let a = invoice("A")
        XCTAssertThrowsError(try propose([a, a]))
        XCTAssertThrowsError(try propose([a]))
        var b = invoice("B")
        b.status = .void
        XCTAssertThrowsError(try propose([a, b]))
        b.status = .draft
        b.lifecycleStatus = .archived
        XCTAssertThrowsError(try propose([a, b]))
    }

    func testHistoricalTaxAndDiscountAreNotRecomputedForBillingCustomer() throws {
        var a = invoice("A")
        a.lineItems[0].taxTreatmentSnapshot = .taxable
        a.discount = 10
        a.taxSnapshot = try TaxEngine.calculate(lines: a.lineItems, discount: 10,
            quote: .init(jurisdiction: "Original", rate: Decimal(string: "0.10")!, source: "Verified", effectiveDate: Date()))
        // Preserve even legacy totals rather than silently repricing them.
        a.total = 97
        let b = invoice("B", total: 200)
        let result = try propose([a, b])
        XCTAssertEqual(result.subtotal, 300)
        XCTAssertEqual(result.discount, 10)
        XCTAssertEqual(result.total, 297)
        XCTAssertEqual(result.sourceInvoices[0].taxSnapshot, a.taxSnapshot)
    }

    func testProposalRoundTripRetainsSourceAndPoolHistory() throws {
        let result = try propose([invoice("A"), invoice("B")])
        let decoded = try JSONDecoder().decode(InvoiceCombinationProposal.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.id, result.id)
        XCTAssertEqual(decoded.total, result.total)
        XCTAssertEqual(decoded.jobNumbers, result.jobNumbers)
        XCTAssertEqual(decoded.paymentRedistribution, result.paymentRedistribution)
    }

    func testMixedJurisdictionTaxesRemainSeparateAndTotalsStayExact() throws {
        var a = invoice("A"), b = invoice("B", total: 200)
        a.lineItems[0].taxTreatmentSnapshot = .taxable
        b.lineItems[0].taxTreatmentSnapshot = .taxable
        a.taxSnapshot = try TaxEngine.calculate(lines: a.lineItems, discount: 0,
            quote: .init(jurisdiction: "Site A", rate: Decimal(string: "0.10")!, source: "Verified A", effectiveDate: Date()))
        b.taxSnapshot = try TaxEngine.calculate(lines: b.lineItems, discount: 0,
            quote: .init(jurisdiction: "Site B", rate: Decimal(string: "0.05")!, source: "Verified B", effectiveDate: Date()))
        a = InvoiceEngine.recalculated(a)
        b = InvoiceEngine.recalculated(b)
        let result = try propose([a, b])
        XCTAssertEqual(result.total, 320)
        XCTAssertEqual(result.addedTax, 20)
        XCTAssertEqual(result.sourceInvoices[0].taxSnapshot?.jurisdiction, "Site A")
        XCTAssertEqual(result.sourceInvoices[1].taxSnapshot?.jurisdiction, "Site B")
    }

    func testOverpaymentEvidenceSurvivesCappedCumulativePayment() throws {
        let a = invoice("A")
        var paid = a
        paid.amountPaid = 110
        paid = ReceiptEngine.recordingPayment(previous: a, proposed: paid, receiptNumber: "REC-OVER")
        paid.amountPaid = 100 // Legacy normalization capped the visible amount.
        paid.total = 50
        let result = try propose([paid, invoice("B", total: 40)], [verification(paid)])
        XCTAssertEqual(result.paymentRedistribution.pool.collectedAmount, 110)
        XCTAssertEqual(result.amountPaid, 90)
        XCTAssertEqual(result.refundRequired, 20)
        XCTAssertEqual(result.sourceInvoices[0].receipts?.first?.paymentAmount, 110)
    }

    func testCombinedInvoiceCannotReuseSourceIdentityOrNumber() {
        let a = invoice("A"), b = invoice("B")
        XCTAssertThrowsError(try InvoiceCombinationEngine.propose(
            id: a.id, invoiceNumber: "NEW", billingCustomerNumber: "CUS", sources: [a, b], verifications: [], preparedBy: "Technician"
        ))
        XCTAssertThrowsError(try InvoiceCombinationEngine.propose(
            invoiceNumber: " a ", billingCustomerNumber: "CUS", sources: [a, b], verifications: [], preparedBy: "Technician"
        ))
    }
}
