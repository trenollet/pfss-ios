import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class InvoiceCombinationPersistenceTests: XCTestCase {
    private func fixture() throws -> (AppDataStore, InvoiceCombinationProposal) {
        let store = AppDataStore(persistenceEnabled: false)
        let customer = InvoicePreviewFactory.sampleCustomer()
        store.customers = [customer]
        var first = InvoicePreviewFactory.sampleInvoice(catalogItems: InvoicePreviewFactory.sampleCatalogItems())
        first.amountPaid = 0; first.balanceDue = first.total; first.status = .draft
        var second = first
        second.id = UUID(); second.invoiceNumber = "SECOND"; second.jobNumber = "JOB-SECOND"
        store.invoices = [first, second]
        for invoice in store.invoices {
            store.synchronizedRecordRevisions[store.synchronizationKey(type: .invoice, id: invoice.id)] = "revision"
        }
        let proposal = try InvoiceCombinationEngine.propose(invoiceNumber: "PREVIEW",
            billingCustomerNumber: customer.customerNumber, sources: store.invoices,
            verifications: [], preparedBy: "Member")
        return (store, proposal)
    }

    func testPreparationLeavesOriginalsUntouchedAndCreatesNoReceipt() throws {
        let (store, proposal) = try fixture()
        let originalData = try AppDataStore.recordSynchronizationEncoder.encode(store.invoices)
        let request = try store.prepareCombinationSave(proposal)
        XCTAssertTrue(request.invoice.invoiceNumber.hasSuffix("-C"))
        XCTAssertNil(request.invoice.receipts)
        XCTAssertEqual(request.invoice.jobNumbers, proposal.jobNumbers)
        XCTAssertEqual(try AppDataStore.recordSynchronizationEncoder.encode(store.invoices), originalData)
    }

    func testLegacyItemDecodeMaterializesOnlyDocumentedDiscountDefaults() throws {
        let (_, proposal) = try fixture()
        let original = try XCTUnwrap(proposal.sourceInvoices.first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:
            AppDataStore.recordSynchronizationEncoder.encode(original)) as? [String: Any])
        var lines = try XCTUnwrap(object["lineItems"] as? [[String: Any]])
        XCTAssertFalse(lines.isEmpty)
        for index in lines.indices {
            lines[index].removeValue(forKey: "discountMethod")
            lines[index].removeValue(forKey: "discountInputValue")
            lines[index].removeValue(forKey: "estimatedMinutesPerUnit")
        }
        object["lineItems"] = lines
        let decoded = try AppDataStore.recordSynchronizationDecoder.decode(InvoiceRecord.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.total, original.total)
        XCTAssertEqual(decoded.lineItems.map(\.lineTotal), original.lineItems.map(\.lineTotal))
        XCTAssertTrue(decoded.lineItems.allSatisfy {
            $0.discountMethod == .fixedAmount && $0.discountInputValue == 0 && $0.estimatedMinutesPerUnit == 0
        })
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with:
            AppDataStore.recordSynchronizationEncoder.encode(decoded)) as? [String: Any])
        let encodedLines = try XCTUnwrap(encoded["lineItems"] as? [[String: Any]])
        XCTAssertEqual(encodedLines.first?["discountMethod"] as? String, "Dollar Amount")
        XCTAssertEqual(encodedLines.first?["discountInputValue"] as? Double, 0)
    }

    func testSaveMessagesDistinguishMissingCustomerNumberCollisionAndSnapshotMismatch() {
        let missing = InvoiceFinancialSaveMessage.describe(PFSSCloudflareBetaError.server("billing_customer_not_synchronized"))
        let collision = InvoiceFinancialSaveMessage.describe(PFSSCloudflareBetaError.server("combined_invoice_number_or_identity_exists"))
        let mismatch = InvoiceFinancialSaveMessage.describe(PFSSCloudflareBetaError.server("invoice_combination_snapshot_mismatch"))
        XCTAssertTrue(missing.contains("billing customer"))
        XCTAssertTrue(collision.contains("number is already in use"))
        XCTAssertTrue(mismatch.contains("do not match"))
        XCTAssertFalse([missing, collision, mismatch].contains { $0.contains("another device") })
    }

    func testCommittedReceiptInstallsAllRecordsAndRedirectsEveryJob() throws {
        let (store, proposal) = try fixture()
        let request = try store.prepareCombinationSave(proposal)
        let records = proposal.sourceInvoices.map { source -> InvoiceCombinationSaveReceipt.Record in
            var original = source
            original.status = .void; original.balanceDue = 0; original.combinedIntoInvoiceID = request.invoice.id
            return .init(invoice: original, revision: UUID().uuidString)
        } + [.init(invoice: request.invoice, revision: UUID().uuidString)]
        let receipt = InvoiceCombinationSaveReceipt(invoiceID: request.invoice.id, records: records)
        let queueCount = store.offlineOperationQueue.orderedOperations.count
        _ = try store.applyCombinationSaveReceipt(receipt)
        _ = try store.applyCombinationSaveReceipt(receipt)
        XCTAssertEqual(store.invoices.count, 3)
        XCTAssertEqual(store.offlineOperationQueue.orderedOperations.count, queueCount)
        for source in proposal.sourceInvoices {
            XCTAssertEqual(store.invoiceDestination(for: try XCTUnwrap(store.invoices.first { $0.id == source.id })).id, request.invoice.id)
            XCTAssertEqual(InvoiceEngine.existingInvoice(forJobNumber: source.jobNumber, in: store.invoices)?.id, request.invoice.id)
        }
    }

    func testIncompleteReceiptCannotPartiallyApply() throws {
        let (store, proposal) = try fixture()
        let request = try store.prepareCombinationSave(proposal)
        let before = try AppDataStore.recordSynchronizationEncoder.encode(store.invoices)
        XCTAssertThrowsError(try store.applyCombinationSaveReceipt(.init(invoiceID: request.invoice.id,
            records: [.init(invoice: request.invoice, revision: "new")])) )
        XCTAssertEqual(try AppDataStore.recordSynchronizationEncoder.encode(store.invoices), before)
    }

    func testSourceChangesRequireNewReview() throws {
        let (store, proposal) = try fixture()
        store.invoices[0].notes = "Changed after review"
        XCTAssertThrowsError(try store.prepareCombinationSave(proposal))
    }

    func testLegacyInvoiceDecodesWithoutCombinationFields() throws {
        let (store, _) = try fixture()
        let data = try AppDataStore.recordSynchronizationEncoder.encode(store.invoices[0])
        let decoded = try AppDataStore.recordSynchronizationDecoder.decode(InvoiceRecord.self, from: data)
        XCTAssertNil(decoded.combination)
        XCTAssertNil(decoded.combinedIntoInvoiceID)
        XCTAssertNil(decoded.associatedJobNumbers)
    }

    func testPendingSourceEditsMustSynchronizeBeforeSaving() throws {
        let (store, proposal) = try fixture()
        try store.offlineOperationQueue.enqueue(.init(type: .recordMutation, entityType: .invoice,
            entityID: proposal.sourceInvoices[0].id, actionName: "upsertRecord",
            payload: .init(contentType: "application/json", body: Data())))
        XCTAssertThrowsError(try store.prepareCombinationSave(proposal)) {
            XCTAssertEqual($0 as? AppDataStore.CombinationSaveError, .syncRequired)
        }
    }

    func testNumberingSkipsCombinedNumberSynchronizedFromAnotherDevice() throws {
        let (firstStore, firstProposal) = try fixture()
        let firstRequest = try firstStore.prepareCombinationSave(firstProposal)
        let (otherStore, otherProposal) = try fixture()
        otherStore.invoices.append(firstRequest.invoice)
        let next = try otherStore.prepareCombinationSave(otherProposal)
        XCTAssertNotEqual(next.invoice.invoiceNumber, firstRequest.invoice.invoiceNumber)
        XCTAssertTrue(next.invoice.invoiceNumber.hasSuffix("-C"))
    }
}
