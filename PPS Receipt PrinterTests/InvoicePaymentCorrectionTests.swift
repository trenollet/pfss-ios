import PDFKit
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class InvoicePaymentCorrectionTests: XCTestCase {
    private func fixture() throws -> (AppDataStore, InvoiceRecord, [InvoiceRecord]) {
        let store = AppDataStore(persistenceEnabled: false)
        let customer = InvoicePreviewFactory.sampleCustomer()
        store.customers = [customer]
        var a = InvoiceRecord(invoiceNumber: "A", customerNumber: customer.customerNumber, siteID: nil,
            jobNumber: "JOB-A", lineItems: [], subtotal: 100, discount: 0, total: 100,
            amountPaid: 50, balanceDue: 50, status: .partiallyPaid, issueDate: Date(), dueDate: Date(),
            paidDate: Date(timeIntervalSince1970: 1_780_000_000), notes: "Original A")
        var b = a
        b.id = UUID(); b.invoiceNumber = "B"; b.jobNumber = "JOB-B"
        b.subtotal = 200; b.total = 200; b.amountPaid = 0; b.balanceDue = 200; b.status = .draft; b.paidDate = nil
        let originals = [a, b]
        let check = InvoiceCollectionVerification(id: UUID(), sourceInvoiceID: a.id,
            recordedAmount: 50, collectedAmount: 50, receiptIDs: [], paymentEventIDs: [],
            verifiedBy: "Member", verifiedAt: Date(), note: "Actually collected")
        let proposal = try InvoiceCombinationEngine.propose(invoiceNumber: "COMBINED-C",
            billingCustomerNumber: customer.customerNumber, sources: originals, verifications: [check], preparedBy: "Member")
        var root = a
        root.id = proposal.id; root.invoiceNumber = proposal.invoiceNumber; root.subtotal = 300; root.total = 300
        root.balanceDue = 250; root.paidDate = nil; root.combination = proposal; root.associatedJobNumbers = proposal.jobNumbers
        a.status = .void; a.balanceDue = 0; a.combinedIntoInvoiceID = root.id
        b.status = .void; b.balanceDue = 0; b.combinedIntoInvoiceID = root.id
        store.invoices = [a, b, root]
        for invoice in store.invoices {
            store.synchronizedRecordRevisions[store.synchronizationKey(type: .invoice, id: invoice.id)] = "revision"
        }
        return (store, root, originals)
    }

    private func splitRequest(_ store: AppDataStore, _ root: InvoiceRecord, _ originals: [InvoiceRecord]) throws -> InvoicePaymentCorrectionRequest {
        let previous = try InvoicePaymentCorrectionEngine.previous(for: root)
        let redistribution = try InvoicePaymentPoolEngine.redistribute(pool: previous.pool,
            allocations: [.init(invoiceID: originals[0].id, invoiceTotal: 100, appliedAmount: 50),
                          .init(invoiceID: originals[1].id, invoiceTotal: 200, appliedAmount: 0)],
            preparedBy: "Member", reason: "Split wrong umbrella bill", replacing: previous)
        return try store.preparePaymentCorrection(root: root, originals: originals, retained: [],
            billingCustomerNumber: root.customerNumber, redistribution: redistribution)
    }

    private func splitReceipt(_ request: InvoicePaymentCorrectionRequest, root: InvoiceRecord) -> InvoiceCombinationSaveReceipt {
        let correction = InvoicePaymentCorrection(id: request.requestID, rootInvoiceID: root.id,
            originalInvoices: request.originalInvoices, retainedInvoiceIDs: [],
            history: [root.combination!.paymentRedistribution, request.redistribution])
        var retired = root
        retired.status = .void; retired.amountPaid = 0; retired.balanceDue = 0
        retired.jobNumber = ""; retired.associatedJobNumbers = []; retired.paymentCorrection = correction
        let records = request.originalInvoices.map { source -> InvoiceCombinationSaveReceipt.Record in
            var result = source
            result.paymentCorrection = correction
            let applied = request.redistribution.allocations.first { $0.invoiceID == source.id }!.appliedAmount
            result.amountPaid = NSDecimalNumber(decimal: applied).doubleValue
            result.balanceDue = source.total - result.amountPaid
            result.status = result.amountPaid > 0 ? .partiallyPaid : .draft
            return .init(invoice: result, revision: UUID().uuidString)
        } + [.init(invoice: retired, revision: UUID().uuidString)]
        return .init(invoiceID: root.id, records: records)
    }

    func testSplitPreparationConservesFundsAndDoesNotChangeAnyRecord() throws {
        let (store, root, originals) = try fixture()
        let before = try AppDataStore.recordSynchronizationEncoder.encode(store.invoices)
        let request = try splitRequest(store, root, originals)
        XCTAssertEqual(request.redistribution.appliedAmount, 50)
        XCTAssertEqual(request.redistribution.remainingDue, 250)
        XCTAssertEqual(request.redistribution.refundRequired, 0)
        XCTAssertEqual(request.sources.count, 3)
        XCTAssertEqual(try AppDataStore.recordSynchronizationEncoder.encode(store.invoices), before)
    }

    func testSplitReceiptIsAtomicIdempotentAndJobsReturnToOriginalInvoices() throws {
        let (store, root, originals) = try fixture()
        let request = try splitRequest(store, root, originals)
        let receipt = splitReceipt(request, root: root)
        let queueCount = store.offlineOperationQueue.orderedOperations.count
        _ = try store.applyPaymentCorrectionReceipt(receipt, request: request)
        _ = try store.applyPaymentCorrectionReceipt(receipt, request: request)
        XCTAssertEqual(store.invoices.count, 3)
        XCTAssertEqual(store.offlineOperationQueue.orderedOperations.count, queueCount)
        XCTAssertEqual(store.invoices.first { $0.id == root.id }?.displayedStatus, "Split")
        for original in originals {
            XCTAssertEqual(InvoiceEngine.existingInvoice(forJobNumber: original.jobNumber, in: store.invoices)?.id, original.id)
        }
        let decoded = try AppDataStore.recordSynchronizationDecoder.decode([InvoiceRecord].self,
            from: AppDataStore.recordSynchronizationEncoder.encode(store.invoices))
        XCTAssertEqual(decoded.first?.paymentCorrection?.history.count, 2)
        XCTAssertNil(decoded.first?.receipts)
    }

    func testIncompleteOrChangedSourceReceiptCannotPartiallyApply() throws {
        let (store, root, originals) = try fixture()
        let request = try splitRequest(store, root, originals)
        var receipt = splitReceipt(request, root: root)
        receipt.records.removeLast()
        XCTAssertThrowsError(try store.applyPaymentCorrectionReceipt(receipt, request: request))
        XCTAssertNil(store.invoices[0].paymentCorrection)
        store.invoices[0].notes = "Edited while save was in flight"
        XCTAssertThrowsError(try store.applyPaymentCorrectionReceipt(splitReceipt(request, root: root), request: request))
        XCTAssertEqual(store.invoices[0].notes, "Edited while save was in flight")
    }

    func testLaterPaymentsJoinOnceAndNeverInferTransferAsNewCash() throws {
        let (_, root, _) = try fixture()
        XCTAssertTrue(try InvoicePaymentCorrectionEngine.pendingVerifications(root: root, members: [root], actor: "Member").isEmpty)
        var paid = root
        paid.amountPaid = 300; paid.status = .paid
        paid = ReceiptEngine.recordingPayment(previous: root, proposed: paid, receiptNumber: "LATER")
        let newChecks = try InvoicePaymentCorrectionEngine.pendingVerifications(root: root, members: [paid], actor: "Member")
        XCTAssertEqual(newChecks.count, 1)
        XCTAssertEqual(newChecks[0].recordedAmount, 250)
        let previous = try InvoicePaymentCorrectionEngine.previous(for: root)
        let pool = try InvoicePaymentPoolEngine.makePool(id: previous.pool.id,
            verifications: previous.pool.verifications + newChecks)
        XCTAssertEqual(pool.collectedAmount, 300)
        paid.combination?.paymentRedistribution.pool = pool
        XCTAssertTrue(try InvoicePaymentCorrectionEngine.pendingVerifications(root: paid, members: [paid], actor: "Member").isEmpty)
    }

    func testLaterReceiptMayJoinLegacyCheckOnlyWithExplicitAdditionalEvidence() throws {
        let (_, root, originals) = try fixture()
        var paid = originals[0]
        paid.amountPaid = 100; paid.status = .paid
        paid = ReceiptEngine.recordingPayment(previous: originals[0], proposed: paid, receiptNumber: "LATER-A")
        // The real split member carries group metadata; allocation isn't a new payment.
        paid.paymentCorrection = .init(id: UUID(), rootInvoiceID: root.id, originalInvoices: originals,
            retainedInvoiceIDs: [], history: [root.combination!.paymentRedistribution])
        let checks = try InvoicePaymentCorrectionEngine.pendingVerifications(root: root, members: [paid], actor: "Member")
        XCTAssertEqual(checks.count, 1)
        let pool = try InvoicePaymentPoolEngine.makePool(verifications: root.combination!.paymentRedistribution.pool.verifications + checks)
        XCTAssertEqual(pool.collectedAmount, 100)
    }

    func testHistoricalCashIsCountedOnceAfterSplitAndReallocation() throws {
        let (store, root, originals) = try fixture()
        let request = try splitRequest(store, root, originals)
        _ = try store.applyPaymentCorrectionReceipt(splitReceipt(request, root: root), request: request)
        let summary = RevenueSummaryEngine.summary(for: .daily, jobs: [], invoices: store.invoices,
            now: originals[0].paidDate!, calendar: .current)
        XCTAssertEqual(summary.collected, 50)
        let today = RevenueSummaryEngine.summary(for: .daily, jobs: [], invoices: store.invoices, now: Date(), calendar: .current)
        XCTAssertEqual(today.collected, 0)
    }

    func testSplitAllOrAtLeastTwoAndCombinedAllocationIsNotGroupTotal() throws {
        let (_, root, originals) = try fixture()
        XCTAssertThrowsError(try InvoicePaymentCorrectionEngine.invoiceTotals(rootID: root.id,
            originals: originals, retained: [originals[0].id]))
        var proposal = root.combination!
        proposal.paymentRedistribution.allocations = [.init(invoiceID: root.id, invoiceTotal: 100, appliedAmount: 10),
            .init(invoiceID: UUID(), invoiceTotal: 200, appliedAmount: 40)]
        XCTAssertEqual(proposal.amountPaid, 10)
        XCTAssertEqual(proposal.balanceDue, 290)
    }

    func testRetiredBillCannotBeSharedAndRestoredBillStillPrints() throws {
        let (store, root, originals) = try fixture()
        let request = try splitRequest(store, root, originals)
        let receipt = splitReceipt(request, root: root)
        let retired = receipt.records.first { $0.invoice.id == root.id }!.invoice
        XCTAssertThrowsError(try InvoicePDFRenderer.createPDF(invoice: retired, businessProfile: BusinessProfile(),
            customer: store.customers.first, site: nil, catalogItems: []))
        let restored = receipt.records.first { $0.invoice.id == originals[0].id }!.invoice
        let url = try InvoicePDFRenderer.createPDF(invoice: restored, businessProfile: BusinessProfile(),
            customer: store.customers.first, site: nil, catalogItems: [])
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(document.string?.contains("50.00") == true)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "PFSS Restored Invoice QA"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPaymentEditAfterSplitKeepsChargesAndCreatesOnlyTheNewPaymentReceipt() throws {
        let (store, root, originals) = try fixture()
        let request = try splitRequest(store, root, originals)
        _ = try store.applyPaymentCorrectionReceipt(splitReceipt(request, root: root), request: request)
        var source = try XCTUnwrap(store.invoices.first { $0.id == originals[0].id })
        source.amountPaid = 75
        let recalculated = InvoiceEngine.recalculated(source)
        XCTAssertEqual(recalculated.total, 100)
        XCTAssertEqual(recalculated.subtotal, 100)
        store.updateInvoice(recalculated)
        let saved = try XCTUnwrap(store.invoices.first { $0.id == source.id })
        XCTAssertEqual(saved.amountPaid, 75)
        XCTAssertEqual(saved.balanceDue, 25)
        XCTAssertEqual(saved.receipts?.count, 1)
        XCTAssertEqual(saved.receipts?.first?.paymentAmount, 25)
        source = saved
        source.amountPaid = 0
        store.updateInvoice(source)
        XCTAssertEqual(store.invoices.first { $0.id == source.id }?.amountPaid, 75)
        let currentRoot = try XCTUnwrap(store.invoices.first { $0.id == root.id })
        let checks = try InvoicePaymentCorrectionEngine.pendingVerifications(root: currentRoot,
            members: store.invoices, actor: "Member")
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(checks[0].collectedAmount, 25)
        let previous = try InvoicePaymentCorrectionEngine.previous(for: currentRoot)
        let pool = try InvoicePaymentPoolEngine.makePool(id: previous.pool.id,
            verifications: previous.pool.verifications + checks, adjustments: previous.pool.adjustments)
        XCTAssertEqual(pool.collectedAmount, 75)
    }

    func testArchivedPaymentEvidenceIsNotLostOrCountedAsActiveCharges() throws {
        let (store, root, originals) = try fixture()
        let request = try splitRequest(store, root, originals)
        _ = try store.applyPaymentCorrectionReceipt(splitReceipt(request, root: root), request: request)
        for index in store.invoices.indices { store.invoices[index].lifecycleStatus = .archived }
        let summary = RevenueSummaryEngine.summary(for: .daily, jobs: [], invoices: store.invoices,
            now: originals[0].paidDate!, calendar: .current)
        XCTAssertEqual(summary.collected, 50)
        XCTAssertEqual(summary.invoiced, 0)
        XCTAssertEqual(summary.outstanding, 0)
    }
}
