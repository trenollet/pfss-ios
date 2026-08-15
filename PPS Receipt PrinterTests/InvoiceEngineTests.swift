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
