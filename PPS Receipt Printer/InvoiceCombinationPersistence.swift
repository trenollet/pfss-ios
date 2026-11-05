import Foundation

struct InvoiceCombinationSaveRequest: Codable {
    struct Source: Codable {
        var id: UUID
        var revision: String
        var snapshotData: Data
    }
    var requestID: UUID
    var billingCustomerID: UUID
    var invoice: InvoiceRecord
    var sources: [Source]
}

struct InvoiceCombinationSaveReceipt: Codable {
    struct Record: Codable {
        var invoice: InvoiceRecord
        var revision: String
    }
    var invoiceID: UUID
    var records: [Record]
}

enum InvoiceFinancialSaveMessage {
    static func describe(_ error: Error) -> String {
        guard case let PFSSCloudflareBetaError.server(code) = error else { return error.localizedDescription }
        switch code {
        case "invoice_correction_sources_changed", "invoice_combination_sources_changed":
            return "An invoice changed or is no longer available for this save. Synchronize, close this review, and select the invoices again. No partial change was saved."
        case "invoice_combination_snapshot_mismatch", "invoice_correction_snapshot_mismatch":
            return "The invoice details on this device do not match the synchronized record. Synchronize and reopen this review. If it continues, send diagnostics. No partial change was saved."
        case "combined_invoice_number_or_identity_exists":
            return "This invoice number is already in use. Synchronize, close this review, and select the invoices again to use a new number. No partial change was saved."
        case "billing_customer_not_synchronized":
            return "The billing customer has not synchronized yet. Synchronize the customer before saving. No partial change was saved."
        case "invoice_correction_retry_changed", "invoice_combination_retry_changed":
            return "This save was already submitted with different details. Synchronize to check its result before preparing another correction."
        case "invoice_correction_too_large", "invoice_combination_too_large":
            return "This group exceeds the safe save size. Reduce the number of invoices or send diagnostics for assistance."
        case "missing_collection_verification", "stale_collection_verification", "invalid_payment_verification":
            return "Review and confirm the actual collected amounts again. Payment evidence is missing or changed."
        case "allocation_exceeds_collected_funds", "invalid_payment_allocation":
            return "Review your allocations. They must fit each invoice and cannot exceed the verified money in the pool."
        case "changed_payment_history", "changed_original_evidence", "invalid_collection_adjustment", "duplicate_payment_evidence":
            return "The correction could not preserve the original payment evidence safely. Synchronize and reopen the review."
        case "forbidden", "unauthorized":
            return "This device does not currently have access to save invoices. Check company access and synchronization."
        default:
            return "PFSS could not safely save this financial change. Synchronize and reopen the review. If it continues, send diagnostics."
        }
    }
}

extension InvoiceRecord {
    var displayedStatus: String {
        if combinedIntoInvoiceID != nil { return "Combined" }
        if paymentCorrection?.rootInvoiceID == id, paymentCorrection?.retainedInvoiceIDs.isEmpty == true { return "Split" }
        return status.rawValue
    }
    var jobNumbers: [String] { associatedJobNumbers ?? (jobNumber.isEmpty ? [] : [jobNumber]) }
    var addedTaxAmount: Decimal { combination?.addedTax ?? taxSnapshot?.addedTax ?? 0 }
}

@MainActor
extension AppDataStore {
    enum CombinationSaveError: Error, LocalizedError, Equatable {
        case changedSources, syncRequired, invalidReceipt, customerUnavailable
        var errorDescription: String? {
            switch self {
            case .changedSources: "An invoice changed or is already combined. Select the invoices again."
            case .syncRequired: "Synchronize the selected invoices before combining. This save requires an online server check."
            case .invalidReceipt: "The saved invoice could not be applied safely. Synchronize before retrying this same save."
            case .customerUnavailable: "Select an active billing customer."
            }
        }
    }

    func prepareCombinationSave(_ proposal: InvoiceCombinationProposal) throws -> InvoiceCombinationSaveRequest {
        guard let customer = activeCustomers.first(where: { $0.customerNumber == proposal.billingCustomerNumber }) else {
            throw CombinationSaveError.customerUnavailable
        }
        let sourceIDs = Set(proposal.sourceInvoices.map(\.id))
        guard !offlineOperationQueue.actionableOperations.contains(where: { operation in
            (operation.entityType == .invoice && operation.entityID.map(sourceIDs.contains) == true)
                || (operation.entityType == .customer && operation.entityID == customer.id)
        }) else { throw CombinationSaveError.syncRequired }
        var references: [InvoiceCombinationSaveRequest.Source] = []
        for original in proposal.sourceInvoices {
            guard let current = invoices.first(where: { $0.id == original.id }),
                  current.combinedIntoInvoiceID == nil, current.combination == nil, current.paymentCorrection == nil,
                  try Self.recordSynchronizationEncoder.encode(current) == Self.recordSynchronizationEncoder.encode(original) else {
                throw CombinationSaveError.changedSources
            }
            guard let revision = synchronizedRecordRevisions[synchronizationKey(type: .invoice, id: original.id)] else {
                throw CombinationSaveError.syncRequired
            }
            references.append(.init(id: original.id, revision: revision,
                                    snapshotData: try Self.recordSynchronizationEncoder.encode(original)))
        }
        var savedProposal = proposal
        // Use the existing company numbering engine. The suffix identifies
        // this server-reserved document namespace for concurrent saves.
        repeat {
            savedProposal.invoiceNumber = generateInvoiceNumber() + "-C"
        } while invoices.contains { $0.invoiceNumber == savedProposal.invoiceNumber }
        let total = NSDecimalNumber(decimal: proposal.total).doubleValue
        let paid = NSDecimalNumber(decimal: proposal.amountPaid).doubleValue
        var invoice = InvoiceRecord(
            id: proposal.id, invoiceNumber: savedProposal.invoiceNumber,
            customerNumber: proposal.billingCustomerNumber, siteID: nil,
            jobNumber: proposal.jobNumbers.first ?? "",
            lineItems: proposal.lines.map(\.item),
            subtotal: NSDecimalNumber(decimal: proposal.subtotal).doubleValue,
            discount: NSDecimalNumber(decimal: proposal.discount).doubleValue,
            total: total, amountPaid: paid,
            balanceDue: NSDecimalNumber(decimal: proposal.balanceDue).doubleValue,
            status: paid > 0 ? (paid >= total ? .paid : .partiallyPaid) : .draft,
            issueDate: Date(), dueDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
            paidDate: paid > 0 && paid >= total ? Date() : nil,
            notes: "Combined from " + proposal.sourceInvoices.map(\.invoiceNumber).joined(separator: ", ")
        )
        invoice.combination = savedProposal
        invoice.associatedJobNumbers = proposal.jobNumbers
        return .init(requestID: proposal.id, billingCustomerID: customer.id, invoice: invoice, sources: references)
    }

    /// Install all returned bills in one persisted snapshot, never as local
    /// edits to be individually enqueued. The server is the commit authority.
    func applyCombinationSaveReceipt(_ receipt: InvoiceCombinationSaveReceipt) throws -> InvoiceRecord {
        guard let combined = receipt.records.first(where: { $0.invoice.id == receipt.invoiceID })?.invoice,
              let proposal = combined.combination,
              Set(receipt.records.map { $0.invoice.id }).count == receipt.records.count,
              receipt.records.count == proposal.sourceInvoices.count + 1,
              Set(receipt.records.map { $0.invoice.id }) == Set(proposal.sourceInvoices.map(\.id) + [combined.id]),
              receipt.records.allSatisfy({ !$0.revision.isEmpty &&
                  ($0.invoice.id == combined.id || ($0.invoice.combinedIntoInvoiceID == combined.id && $0.invoice.status == .void)) }) else {
            throw CombinationSaveError.invalidReceipt
        }
        // A retry receipt describes the original commit. Never replace newer
        // payment edits already received through normal synchronization.
        if let existing = invoices.first(where: { $0.id == combined.id }) {
            guard existing.combination?.id == proposal.id else { throw CombinationSaveError.invalidReceipt }
            return existing
        }
        for original in proposal.sourceInvoices {
            if let current = invoices.first(where: { $0.id == original.id }), current.combinedIntoInvoiceID != combined.id {
                guard try Self.recordSynchronizationEncoder.encode(current)
                        == Self.recordSynchronizationEncoder.encode(original),
                      !offlineOperationQueue.actionableOperations.contains(where: {
                          $0.entityType == .invoice && $0.entityID == original.id
                      }) else { throw CombinationSaveError.invalidReceipt }
            }
        }
        var updated = invoices
        for record in receipt.records {
            if let index = updated.firstIndex(where: { $0.id == record.invoice.id }) { updated[index] = record.invoice }
            else { updated.append(record.invoice) }
            synchronizedRecordRevisions[synchronizationKey(type: .invoice, id: record.invoice.id)] = record.revision
        }
        let wasApplying = isApplyingRemoteSynchronization
        isApplyingRemoteSynchronization = true
        defer { isApplyingRemoteSynchronization = wasApplying }
        invoices = updated
        saveSynchronizedRecordRevisions()
        persistAppliedSnapshotWithoutEnqueuingChanges()
        return combined
    }

    func invoiceDestination(for invoice: InvoiceRecord) -> InvoiceRecord {
        guard let destination = invoice.combinedIntoInvoiceID,
              let combined = invoices.first(where: { $0.id == destination }) else { return invoice }
        return combined
    }
}
