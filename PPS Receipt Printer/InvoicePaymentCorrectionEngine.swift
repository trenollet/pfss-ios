import Foundation

/// Shared immutable group evidence. Only the latest history entry owns funds.
/// Original charges and receipts survive splitting and rebuilding the group.
struct InvoicePaymentCorrection: Codable {
    var id: UUID
    var rootInvoiceID: UUID
    var originalInvoices: [InvoiceRecord]
    var retainedInvoiceIDs: [UUID]
    var history: [InvoicePaymentRedistribution]
    var latest: InvoicePaymentRedistribution { history[history.count - 1] }
}

struct InvoicePaymentCorrectionRequest: Codable {
    var requestID: UUID
    var rootInvoiceID: UUID
    var billingCustomerID: UUID
    var sources: [InvoiceCombinationSaveRequest.Source]
    var originalInvoices: [InvoiceRecord]
    var retainedInvoiceIDs: [UUID]
    var redistribution: InvoicePaymentRedistribution
    var lines: [InvoiceCombinationProposal.Line]
}

enum InvoicePaymentCorrectionEngine {
    enum ValidationError: Error, LocalizedError {
        case unavailableGroup, invalidSelection, stalePaymentEvidence
        var errorDescription: String? {
            switch self {
            case .unavailableGroup: "Synchronize all invoices in this payment group before correcting it."
            case .invalidSelection: "Keep two or more invoices combined, or select Split All."
            case .stalePaymentEvidence: "Payment evidence changed. Review the collection amounts again."
            }
        }
    }

    static func previous(for root: InvoiceRecord) throws -> InvoicePaymentRedistribution {
        if let correction = root.paymentCorrection, !correction.history.isEmpty { return correction.latest }
        guard let combination = root.combination else { throw ValidationError.unavailableGroup }
        return combination.paymentRedistribution
    }

    static func originals(for root: InvoiceRecord) throws -> [InvoiceRecord] {
        if let correction = root.paymentCorrection { return correction.originalInvoices }
        guard let combination = root.combination else { throw ValidationError.unavailableGroup }
        return combination.sourceInvoices
    }

    /// Later actual payments join the pool once, by their immutable event IDs.
    /// An allocation alone is never accepted as another collection.
    static func pendingVerifications(root: InvoiceRecord, members: [InvoiceRecord],
                                     actor: String, at: Date = Date()) throws -> [InvoiceCollectionVerification] {
        let pool = try previous(for: root).pool
        let events = Set(pool.verifications.flatMap(\.paymentEventIDs))
        let priorInvoices = Set(pool.verifications.map(\.sourceInvoiceID))
        return try members.compactMap { invoice in
            let receipts = (invoice.receipts ?? []).filter { !events.contains($0.paymentEventID) }
            if !receipts.isEmpty {
                let basis = try receipts.reduce(Decimal.zero) { total, receipt in
                    guard receipt.paymentAmount.isFinite, receipt.paymentAmount >= 0,
                          TaxEngine.currency(Decimal(receipt.paymentAmount)) == Decimal(receipt.paymentAmount) else {
                        throw ValidationError.stalePaymentEvidence
                    }
                    return total + Decimal(receipt.paymentAmount)
                }
                return .init(id: UUID(), sourceInvoiceID: invoice.id, recordedAmount: basis,
                    collectedAmount: basis, receiptIDs: receipts.map(\.id), paymentEventIDs: receipts.map(\.paymentEventID),
                    verifiedBy: actor, verifiedAt: at, note: "", isAdditionalReceiptCollection: true)
            }
            // New ordinary invoices can contribute verified legacy payments.
            guard invoice.id != root.id, invoice.paymentCorrection == nil, invoice.combinedIntoInvoiceID == nil,
                  !priorInvoices.contains(invoice.id),
                  invoice.amountPaid > 0 || invoice.status == .paid else { return nil }
            let basis = try InvoiceCombinationEngine.recordedCollectionAmount(for: invoice)
            return .init(id: UUID(), sourceInvoiceID: invoice.id, recordedAmount: basis,
                collectedAmount: basis, receiptIDs: [], paymentEventIDs: [],
                verifiedBy: actor, verifiedAt: at, note: "")
        }
    }

    static func lines(for originals: [InvoiceRecord], retained: Set<UUID>, root: InvoiceRecord) -> [InvoiceCombinationProposal.Line] {
        originals.filter { retained.contains($0.id) }.flatMap { source in
            source.lineItems.map { original in
                var item = original
                item.id = root.combination?.lines.first {
                    $0.sourceInvoiceID == source.id && $0.sourceLineItemID == original.id
                }?.item.id ?? UUID()
                return .init(sourceInvoiceID: source.id, sourceLineItemID: original.id, item: item)
            }
        }
    }

    static func invoiceTotals(rootID: UUID, originals: [InvoiceRecord], retained: Set<UUID>) throws -> [(UUID, Decimal)] {
        guard retained.count != 1, retained.isSubset(of: Set(originals.map(\.id))) else { throw ValidationError.invalidSelection }
        var totals: [(UUID, Decimal)] = []
        if !retained.isEmpty {
            totals.append((rootID, originals.filter { retained.contains($0.id) }.reduce(0) { $0 + Decimal($1.total) }))
        }
        totals += originals.filter { !retained.contains($0.id) }.map { ($0.id, Decimal($0.total)) }
        return totals
    }
}

@MainActor
extension AppDataStore {
    func preparePaymentCorrection(root: InvoiceRecord, originals: [InvoiceRecord], retained: Set<UUID>,
                                  billingCustomerNumber: String, redistribution: InvoicePaymentRedistribution,
                                  requestID: UUID = UUID()) throws -> InvoicePaymentCorrectionRequest {
        let priorOriginals = try InvoicePaymentCorrectionEngine.originals(for: root)
        let groupIDs = Set(priorOriginals.map(\.id) + [root.id])
        let ids = Set(originals.map(\.id) + [root.id])
        guard ids.count == originals.count + 1, groupIDs.isSubset(of: ids),
              let customer = activeCustomers.first(where: { $0.customerNumber == billingCustomerNumber }),
              let currentRoot = invoices.first(where: { $0.id == root.id }),
              try Self.recordSynchronizationEncoder.encode(currentRoot) == Self.recordSynchronizationEncoder.encode(root) else {
            throw CombinationSaveError.changedSources
        }
        guard !offlineOperationQueue.actionableOperations.contains(where: {
            ($0.entityType == .invoice && $0.entityID.map(ids.contains) == true)
                || ($0.entityType == .customer && $0.entityID == customer.id)
        }) else { throw CombinationSaveError.syncRequired }
        let totals = try InvoicePaymentCorrectionEngine.invoiceTotals(rootID: root.id, originals: originals, retained: retained)
        guard Set(redistribution.allocations.map(\.invoiceID)) == Set(totals.map(\.0)),
              totals.allSatisfy({ id, total in redistribution.allocations.first { $0.invoiceID == id }?.invoiceTotal == total }) else {
            throw InvoicePaymentCorrectionEngine.ValidationError.invalidSelection
        }
        _ = try InvoicePaymentPoolEngine.redistribute(pool: redistribution.pool, allocations: redistribution.allocations,
            preparedBy: redistribution.preparedBy, reason: redistribution.reason,
            replacing: InvoicePaymentCorrectionEngine.previous(for: root))
        let references = try ids.sorted { $0.uuidString < $1.uuidString }.map { id -> InvoiceCombinationSaveRequest.Source in
            guard let invoice = invoices.first(where: { $0.id == id }),
                  let revision = synchronizedRecordRevisions[synchronizationKey(type: .invoice, id: id)] else {
                throw CombinationSaveError.syncRequired
            }
            return .init(id: id, revision: revision, snapshotData: try Self.recordSynchronizationEncoder.encode(invoice))
        }
        return .init(requestID: requestID, rootInvoiceID: root.id, billingCustomerID: customer.id,
            sources: references, originalInvoices: originals, retainedInvoiceIDs: originals.map(\.id).filter(retained.contains),
            redistribution: redistribution, lines: InvoicePaymentCorrectionEngine.lines(for: originals, retained: retained, root: root))
    }

    func applyPaymentCorrectionReceipt(_ receipt: InvoiceCombinationSaveReceipt,
                                       request: InvoicePaymentCorrectionRequest) throws -> InvoiceRecord {
        guard receipt.invoiceID == request.rootInvoiceID,
              Set(receipt.records.map { $0.invoice.id }) == Set(request.sources.map(\.id)),
              Set(receipt.records.map { $0.invoice.id }).count == receipt.records.count,
              let root = receipt.records.first(where: { $0.invoice.id == receipt.invoiceID })?.invoice,
              let correction = root.paymentCorrection, correction.id == request.requestID,
              !correction.history.isEmpty,
              receipt.records.allSatisfy({ !$0.revision.isEmpty && $0.invoice.paymentCorrection?.id == correction.id }) else {
            throw CombinationSaveError.invalidReceipt
        }
        if let existing = invoices.first(where: { $0.id == root.id }),
           existing.paymentCorrection?.history.contains(where: { $0.id == correction.latest.id }) == true { return existing }
        for reference in request.sources {
            guard let current = invoices.first(where: { $0.id == reference.id }),
                  try Self.recordSynchronizationEncoder.encode(current) == reference.snapshotData,
                  !offlineOperationQueue.actionableOperations.contains(where: { $0.entityType == .invoice && $0.entityID == reference.id }) else {
                throw CombinationSaveError.invalidReceipt
            }
        }
        let wasApplying = isApplyingRemoteSynchronization
        isApplyingRemoteSynchronization = true
        defer { isApplyingRemoteSynchronization = wasApplying }
        var updated = invoices
        for record in receipt.records {
            guard let index = updated.firstIndex(where: { $0.id == record.invoice.id }) else { throw CombinationSaveError.invalidReceipt }
            updated[index] = record.invoice
            synchronizedRecordRevisions[synchronizationKey(type: .invoice, id: record.invoice.id)] = record.revision
        }
        invoices = updated
        saveSynchronizedRecordRevisions()
        persistAppliedSnapshotWithoutEnqueuingChanges()
        return root
    }
}
