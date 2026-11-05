import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class InvoicePaymentPoolEngineTests: XCTestCase {
    private func verification(_ amount: Decimal, recorded: Decimal? = nil) -> InvoiceCollectionVerification {
        InvoiceCollectionVerification(
            id: UUID(), sourceInvoiceID: UUID(), recordedAmount: recorded ?? amount,
            collectedAmount: amount, receiptIDs: [UUID()], paymentEventIDs: [UUID()], verifiedBy: "Technician",
            verifiedAt: Date(timeIntervalSince1970: 10), note: "Checked actual collection"
        )
    }

    private func allocation(total: Decimal, paid: Decimal) -> InvoicePoolAllocation {
        InvoicePoolAllocation(invoiceID: UUID(), invoiceTotal: total, appliedAmount: paid)
    }

    private func plan(_ pool: InvoicePaymentPool, _ allocations: [InvoicePoolAllocation],
                      replacing previous: InvoicePaymentRedistribution? = nil) throws -> InvoicePaymentRedistribution {
        try InvoicePaymentPoolEngine.redistribute(
            pool: pool, allocations: allocations, preparedBy: "Technician",
            reason: "Correct wrong source invoice", replacing: previous
        )
    }

    func testVerifiedMoneyIsPooledAndUnderpaymentIsCalledOut() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(100), verification(25)])
        let result = try plan(pool, [allocation(total: 200, paid: 125)])
        XCTAssertEqual(result.appliedAmount, 125)
        XCTAssertEqual(result.remainingDue, 75)
        XCTAssertEqual(result.refundRequired, 0)
    }

    func testFalsePaidAmountCanBeVerifiedAsZeroWithoutInventingMoney() throws {
        let check = verification(0, recorded: 100)
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [check])
        let result = try plan(pool, [allocation(total: 100, paid: 0)])
        XCTAssertEqual(result.remainingDue, 100)
        XCTAssertEqual(result.pool.verifications.first?.recordedAmount, 100)
        XCTAssertEqual(result.appliedAmount, 0)
    }

    func testDisputedCollectionRequiresExplanation() {
        var check = verification(0, recorded: 100)
        check.note = "  "
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [check])) {
            XCTAssertEqual($0 as? InvoicePaymentPoolEngine.ValidationError, .discrepancyNeedsExplanation)
        }
    }

    func testCorrectionRetainsPoolAndLinksPreviousAllocation() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(100), verification(200)])
        let initial = try plan(pool, [allocation(total: 300, paid: 300)])
        let corrected = try plan(pool, [allocation(total: 100, paid: 100), allocation(total: 150, paid: 150)], replacing: initial)
        XCTAssertEqual(corrected.pool, initial.pool)
        XCTAssertEqual(corrected.replacesRedistributionID, initial.id)
        XCTAssertEqual(corrected.refundRequired, 50)
        XCTAssertEqual(corrected.remainingDue, 0)
        XCTAssertEqual(initial.appliedAmount, 300)
    }

    func testRefundIsNotAutomaticallyAppliedOrRecordedAsReturned() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(110)])
        let result = try plan(pool, [allocation(total: 100, paid: 100)])
        XCTAssertEqual(result.refundRequired, 10)
        XCTAssertEqual(result.pool.collectedAmount, 110)
    }

    func testDuplicateMoneyCannotEnterPoolTwice() {
        let check = verification(100)
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [check, check]))
        var other = verification(100)
        other.sourceInvoiceID = check.sourceInvoiceID
        var legacy = check
        legacy.receiptIDs = []
        legacy.paymentEventIDs = []
        other.receiptIDs = []
        other.paymentEventIDs = []
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [legacy, other]))
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [legacy, check]))
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [check, legacy]))
        other.sourceInvoiceID = UUID()
        other.receiptIDs = check.receiptIDs
        other.paymentEventIDs = check.paymentEventIDs
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [check, other]))
        other.receiptIDs = [UUID()]
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [check, other]))
    }

    func testAllocationCannotSpendMoreThanCollected() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(100)])
        XCTAssertThrowsError(try plan(pool, [allocation(total: 200, paid: 101)])) {
            XCTAssertEqual($0 as? InvoicePaymentPoolEngine.ValidationError, .allocationExceedsPool)
        }
        var item = allocation(total: 100, paid: 100)
        XCTAssertThrowsError(try plan(pool, [item, item]))
        item.appliedAmount = 101
        XCTAssertThrowsError(try plan(pool, [item]))
    }

    func testMoneyUsesExactCentsWithoutFloatingPointDrift() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(Decimal(string: "0.10")!), verification(Decimal(string: "0.20")!)])
        let result = try plan(pool, [allocation(total: Decimal(string: "0.30")!, paid: Decimal(string: "0.30")!)])
        XCTAssertEqual(result.remainingDue, 0)
        XCTAssertEqual(result.refundRequired, 0)
    }

    func testInvalidAndFractionalCentAmountsAreRejected() {
        for amount in [Decimal.nan, Decimal(-1), Decimal(string: "0.001")!, Decimal(string: "9000000000001")!] {
            XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [verification(amount)]))
        }
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [verification(101, recorded: 100)]))
    }

    func testCorrectionCannotRewriteVerificationHistory() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(100)])
        let initial = try plan(pool, [allocation(total: 100, paid: 100)])
        var changed = pool
        changed.verifications[0].collectedAmount = 90
        XCTAssertThrowsError(try plan(changed, [allocation(total: 100, paid: 90)], replacing: initial)) {
            XCTAssertEqual($0 as? InvoicePaymentPoolEngine.ValidationError, .changedCollectionHistory)
        }
        changed = pool
        changed.id = UUID()
        XCTAssertThrowsError(try plan(changed, [allocation(total: 100, paid: 100)], replacing: initial))
    }

    func testAuditRoundTripPreservesAmountsAndOriginReferences() throws {
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(100)])
        let initial = try plan(pool, [allocation(total: 150, paid: 100)])
        let data = try JSONEncoder().encode(initial)
        XCTAssertEqual(try JSONDecoder().decode(InvoicePaymentRedistribution.self, from: data), initial)
    }

    func testLaterCombinedInvoiceCollectionsJoinPoolWithoutRecountingOriginalMoney() throws {
        let original = verification(100)
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [original])
        let initial = try plan(pool, [allocation(total: 200, paid: 100)])
        let laterPayment = verification(100)
        let expanded = try InvoicePaymentPoolEngine.makePool(id: pool.id, verifications: [original, laterPayment])
        let correction = try plan(expanded, [allocation(total: 150, paid: 150)], replacing: initial)
        XCTAssertEqual(correction.pool.collectedAmount, 200)
        XCTAssertEqual(correction.refundRequired, 50)
        XCTAssertEqual(initial.pool.collectedAmount, 100)
        let sameInvoiceNewPayment = InvoiceCollectionVerification(
            id: UUID(), sourceInvoiceID: laterPayment.sourceInvoiceID,
            recordedAmount: 20, collectedAmount: 20, receiptIDs: [UUID()], paymentEventIDs: [UUID()],
            verifiedBy: "Technician", verifiedAt: Date(), note: "New payment"
        )
        XCTAssertNoThrow(try InvoicePaymentPoolEngine.makePool(
            id: pool.id, verifications: [original, laterPayment, sameInvoiceNewPayment]
        ))
    }

    func testMistakenCollectionCheckIsReversibleWithoutErasingHistory() throws {
        let original = verification(100)
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [original])
        let initial = try plan(pool, [allocation(total: 100, paid: 100)])
        let adjustment = InvoiceCollectionAdjustment(
            id: UUID(), verificationID: original.id, amountChange: -100,
            correctedBy: "Technician", correctedAt: Date(), reason: "Money was not collected"
        )
        let correctedPool = try InvoicePaymentPoolEngine.makePool(
            id: pool.id, verifications: pool.verifications, adjustments: [adjustment]
        )
        let result = try plan(correctedPool, [allocation(total: 100, paid: 0)], replacing: initial)
        XCTAssertEqual(result.remainingDue, 100)
        XCTAssertEqual(result.pool.verifications, pool.verifications)
        XCTAssertEqual(result.pool.adjustments, [adjustment])
        XCTAssertEqual(initial.appliedAmount, 100)
        let restored = InvoiceCollectionAdjustment(
            id: UUID(), verificationID: original.id, amountChange: 100,
            correctedBy: "Technician", correctedAt: Date(), reason: "Located collection evidence"
        )
        let restoredPool = try InvoicePaymentPoolEngine.makePool(
            id: pool.id, verifications: pool.verifications, adjustments: [adjustment, restored]
        )
        XCTAssertEqual(try plan(restoredPool, [allocation(total: 100, paid: 100)], replacing: result).remainingDue, 0)
        XCTAssertThrowsError(try plan(pool, [allocation(total: 100, paid: 100)], replacing: result))
    }

    func testAdjustmentsCannotInventMoneyOrBeAppliedTwice() throws {
        let original = verification(100)
        let adjustment = InvoiceCollectionAdjustment(
            id: UUID(), verificationID: original.id, amountChange: -50,
            correctedBy: "Technician", correctedAt: Date(), reason: "Collection correction"
        )
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [original], adjustments: [adjustment, adjustment]))
        var invalid = adjustment
        invalid.amountChange = -101
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [original], adjustments: [invalid]))
        invalid.amountChange = 1
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [original], adjustments: [invalid]))
        invalid = adjustment
        invalid.verificationID = UUID()
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [original], adjustments: [invalid]))
    }

    func testVerificationAndCorrectionRequireIdentifiedUserButNoManagerRole() throws {
        var check = verification(100)
        check.verifiedBy = " "
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.makePool(verifications: [check]))
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: [verification(100)])
        XCTAssertNoThrow(try plan(pool, [allocation(total: 100, paid: 100)]))
        XCTAssertThrowsError(try InvoicePaymentPoolEngine.redistribute(
            pool: pool, allocations: [allocation(total: 100, paid: 100)],
            preparedBy: "Technician", reason: " "
        ))
    }
}
