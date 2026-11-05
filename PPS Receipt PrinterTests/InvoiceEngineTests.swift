import XCTest
@testable import PPS_Receipt_Printer

final class InvoiceEngineTests: XCTestCase {
    func testDraftCalculationUsesTaxSnapshotAndDiscount() throws {
        let lines = [line(quantity: 2, unitPrice: 50, treatment: .taxable)]
        let tax = try TaxEngine.calculate(
            lines: lines,
            discount: 10,
            quote: TaxRateQuote(
                jurisdiction: "Test",
                rate: Decimal(string: "0.10")!,
                source: "Test",
                effectiveDate: Date(timeIntervalSince1970: 1)
            )
        )

        let invoice = InvoiceEngine.makeDraft(from: .init(
            invoiceNumber: "INV-1",
            customerNumber: "CUS-1",
            siteID: nil,
            jobNumber: "JOB-1",
            lineItems: lines,
            discount: 10,
            taxSnapshot: tax,
            issueDate: Date(timeIntervalSince1970: 2),
            dueDate: Date(timeIntervalSince1970: 3),
            notes: ""
        ))

        XCTAssertEqual(invoice.subtotal, 100)
        XCTAssertEqual(invoice.total, 99)
        XCTAssertEqual(invoice.balanceDue, 99)
        XCTAssertEqual(invoice.status, .draft)
    }

    func testPartialAndFullPaymentsNormalizeConsistently() {
        var invoice = draft(total: 100)
        invoice.status = .sent
        invoice.amountPaid = 25
        invoice = InvoiceEngine.normalizedPaymentState(for: invoice)
        XCTAssertEqual(invoice.status, .partiallyPaid)
        XCTAssertEqual(invoice.balanceDue, 75)

        invoice.amountPaid = 100
        let paidAt = Date(timeIntervalSince1970: 100)
        invoice = InvoiceEngine.normalizedPaymentState(for: invoice, at: paidAt)
        XCTAssertEqual(invoice.status, .paid)
        XCTAssertEqual(invoice.balanceDue, 0)
        XCTAssertEqual(invoice.paidDate, paidAt)
    }

    func testExplicitPaidSelectionFillsRecalculatedInvoiceTotal() {
        var invoice = draft(total: 100)
        invoice.status = .paid
        invoice.amountPaid = 0
        invoice.lineItems = [line(quantity: 1, unitPrice: 125, treatment: .nonTaxable)]
        let paidAt = Date(timeIntervalSince1970: 100)

        let result = InvoiceEngine.recalculatedForEditorSave(
            invoice,
            explicitlyMarkedPaid: true,
            at: paidAt
        )

        XCTAssertEqual(result.total, 125)
        XCTAssertEqual(result.amountPaid, 125)
        XCTAssertEqual(result.balanceDue, 0)
        XCTAssertEqual(result.status, .paid)
        XCTAssertEqual(result.paidDate, paidAt)
    }

    func testEditorSaveDoesNotInventPaymentWithoutNewPaidSelection() {
        var invoice = draft(total: 100)
        invoice.status = .paid
        invoice.amountPaid = 100
        invoice.lineItems = [line(quantity: 1, unitPrice: 125, treatment: .nonTaxable)]

        let result = InvoiceEngine.recalculatedForEditorSave(
            invoice,
            explicitlyMarkedPaid: false
        )

        XCTAssertEqual(result.total, 125)
        XCTAssertEqual(result.amountPaid, 100)
        XCTAssertEqual(result.balanceDue, 25)
        XCTAssertEqual(result.status, .partiallyPaid)
    }

    func testVoidInvoiceHasNoCollectibleBalance() {
        var invoice = draft(total: 100)
        invoice.status = .void
        invoice.amountPaid = 20
        invoice = InvoiceEngine.normalizedPaymentState(for: invoice)
        XCTAssertEqual(invoice.status, .void)
        XCTAssertEqual(invoice.amountPaid, 20)
        XCTAssertEqual(invoice.balanceDue, 0)
        XCTAssertNil(invoice.paidDate)
    }

    func testZeroDollarInvoiceCanBeExplicitlyClosedWithoutCollectingMoney() {
        var invoice = draft(total: 0)
        invoice.status = .paid
        let closedAt = Date(timeIntervalSince1970: 100)
        let result = InvoiceEngine.recalculated(invoice, at: closedAt)
        XCTAssertEqual(result.status, .paid)
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.amountPaid, 0)
        XCTAssertEqual(result.balanceDue, 0)
        XCTAssertEqual(result.paidDate, closedAt)
        XCTAssertNil(result.receipts)
        XCTAssertFalse(ReceiptEngine.requiresReceipt(previous: draft(total: 0), proposed: result))
        XCTAssertEqual(InvoiceEngine.normalizedPaymentState(for: result).status, .paid)
        XCTAssertEqual(InvoiceEngine.normalizedAfterInvoiceEdit(result).paidDate, closedAt)
    }

    func testZeroDollarDraftRemainsOpenUntilExplicitlyClosed() {
        XCTAssertEqual(InvoiceEngine.normalizedAfterInvoiceEdit(draft(total: 0)).status, .draft)
    }

    func testPaymentNormalizationDoesNotSilentlyRepriceLegacyInvoice() {
        var invoice = draft(total: 87.65)
        invoice.subtotal = 100
        invoice.discount = 0
        invoice.status = .sent
        invoice.amountPaid = 10

        let result = InvoiceEngine.normalizedPaymentState(for: invoice)

        XCTAssertEqual(result.total, 87.65)
        XCTAssertEqual(result.balanceDue, 77.65)
        XCTAssertEqual(result.status, .partiallyPaid)
    }

    func testExistingJobInvoiceLookupIsIdempotent() {
        let first = draft(total: 100, jobNumber: "JOB-1")
        let duplicate = draft(total: 200, jobNumber: "JOB-1")
        XCTAssertEqual(
            InvoiceEngine.existingInvoice(
                forJobNumber: "JOB-1",
                in: [first, duplicate]
            )?.id,
            first.id
        )
    }

    func testRepricingPaidInvoicePreservesRecordedPayment() {
        var invoice = draft(total: 100)
        invoice.status = .paid
        invoice.amountPaid = 100
        invoice.paidDate = Date(timeIntervalSince1970: 10)
        invoice.lineItems = [line(quantity: 1, unitPrice: 125, treatment: .nonTaxable)]

        let corrected = InvoiceEngine.recalculated(
            invoice,
            at: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(corrected.total, 125)
        XCTAssertEqual(corrected.amountPaid, 100)
        XCTAssertEqual(corrected.balanceDue, 25)
        XCTAssertEqual(corrected.status, .partiallyPaid)
        XCTAssertNil(corrected.paidDate)
    }

    func testLowerCorrectedTotalDoesNotEraseOverpaymentEvidence() {
        var invoice = draft(total: 100)
        invoice.status = .paid
        invoice.amountPaid = 100
        invoice.lineItems = [line(quantity: 1, unitPrice: 80, treatment: .nonTaxable)]

        let corrected = InvoiceEngine.recalculated(invoice)

        XCTAssertEqual(corrected.total, 80)
        XCTAssertEqual(corrected.amountPaid, 100)
        XCTAssertEqual(corrected.balanceDue, 0)
        XCTAssertEqual(corrected.status, .paid)
    }

    private func line(
        quantity: Double,
        unitPrice: Double,
        treatment: TaxTreatment
    ) -> ServiceLineItem {
        ServiceLineItem(
            taxTreatmentSnapshot: treatment,
            serviceType: .other,
            otherService: "Test",
            description: "",
            quantity: quantity,
            unitPrice: unitPrice,
            lineTotal: quantity * unitPrice
        )
    }

    private func draft(
        total: Double,
        jobNumber: String = "JOB-1"
    ) -> InvoiceRecord {
        InvoiceRecord(
            invoiceNumber: "INV-1",
            customerNumber: "CUS-1",
            siteID: nil,
            jobNumber: jobNumber,
            lineItems: [],
            subtotal: total,
            discount: 0,
            total: total,
            amountPaid: 0,
            balanceDue: total,
            status: .draft,
            issueDate: Date(),
            dueDate: Date(),
            paidDate: nil,
            notes: ""
        )
    }
}
