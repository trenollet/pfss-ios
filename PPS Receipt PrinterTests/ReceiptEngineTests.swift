import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class ReceiptEngineTests: XCTestCase {
    func testPositivePaymentCreatesImmutableSnapshot() {
        let before = makeInvoice(amountPaid: 0, balanceDue: 110)
        var after = before
        after.amountPaid = 40
        after.balanceDue = 70
        after.status = .partiallyPaid

        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let eventID = UUID()
        let result = ReceiptEngine.recordingPayment(
            previous: before,
            proposed: after,
            receiptNumber: "RCT-TEST-001",
            paymentEventID: eventID,
            paymentMethod: .card,
            timestamp: timestamp
        )

        XCTAssertEqual(result.receipts?.count, 1)
        let receipt = try! XCTUnwrap(result.receipts?.first)
        XCTAssertEqual(receipt.paymentAmount, 40)
        XCTAssertEqual(receipt.totalPaid, 40)
        XCTAssertEqual(receipt.balanceDue, 70)
        XCTAssertEqual(receipt.receiptNumber, "RCT-TEST-001")
        XCTAssertEqual(receipt.paymentEventID, eventID)
        XCTAssertEqual(receipt.paymentMethod, .card)
        XCTAssertEqual(receipt.issuedAt, timestamp)
    }

    func testNoReceiptForUnchangedOrReducedPayment() {
        let before = makeInvoice(amountPaid: 40, balanceDue: 70)
        XCTAssertFalse(
            ReceiptEngine.requiresReceipt(previous: before, proposed: before)
        )

        var reduced = before
        reduced.amountPaid = 20
        reduced.balanceDue = 90
        let result = ReceiptEngine.recordingPayment(
            previous: before,
            proposed: reduced,
            receiptNumber: "RCT-TEST-002"
        )
        XCTAssertTrue(result.receipts?.isEmpty ?? true)
    }

    func testPaymentEventIsIdempotent() {
        let before = makeInvoice(amountPaid: 0, balanceDue: 110)
        var after = before
        after.amountPaid = 110
        after.balanceDue = 0
        after.status = .paid
        let eventID = UUID()

        let first = ReceiptEngine.recordingPayment(
            previous: before,
            proposed: after,
            receiptNumber: "RCT-TEST-003",
            paymentEventID: eventID
        )
        let retried = ReceiptEngine.recordingPayment(
            previous: before,
            proposed: first,
            receiptNumber: "RCT-TEST-003",
            paymentEventID: eventID
        )

        XCTAssertEqual(retried.receipts?.count, 1)
    }

    func testReceiptSurvivesCodableRoundTrip() throws {
        let before = makeInvoice(amountPaid: 0, balanceDue: 110)
        var after = before
        after.amountPaid = 110
        after.balanceDue = 0
        after.status = .paid
        let result = ReceiptEngine.recordingPayment(
            previous: before,
            proposed: after,
            receiptNumber: "RCT-TEST-004"
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(InvoiceRecord.self, from: encoded)

        XCTAssertEqual(decoded.receipts?.count, 1)
        XCTAssertEqual(decoded.receipts?.first?.receiptNumber, "RCT-TEST-004")
        XCTAssertEqual(decoded.receipts?.first?.paymentAmount, 110)
    }

    private func makeInvoice(
        amountPaid: Double,
        balanceDue: Double
    ) -> InvoiceRecord {
        InvoiceRecord(
            invoiceNumber: "INV-TEST-001",
            customerNumber: "PPS-TEST-001",
            siteID: UUID(),
            jobNumber: "JOB-TEST-001",
            lineItems: [],
            subtotal: 100,
            discount: 0,
            total: 110,
            taxSnapshot: nil,
            amountPaid: amountPaid,
            balanceDue: balanceDue,
            status: amountPaid > 0 ? .partiallyPaid : .sent,
            issueDate: Date(timeIntervalSince1970: 1_799_000_000),
            dueDate: Date(timeIntervalSince1970: 1_801_000_000),
            paidDate: nil,
            notes: "Snapshot evidence"
        )
    }
}
