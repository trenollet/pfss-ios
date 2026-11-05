import SwiftUI

/// Review first; only a committed server receipt changes local invoices.
struct InvoiceCombinationReviewView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    let sources: [InvoiceRecord]
    var onSaved: (InvoiceRecord) -> Void
    @State private var billingCustomer = ""
    @State private var collectedAmounts: [UUID: Double] = [:]
    @State private var confirmations = Set<UUID>()
    @State private var notes: [UUID: String] = [:]
    @State private var proposal: InvoiceCombinationProposal?
    @State private var showingPreview = false
    @State private var error: String?

    private var paymentSources: [InvoiceRecord] {
        sources.filter { $0.amountPaid > 0 || $0.status == .paid || !($0.receipts ?? []).isEmpty }
    }
    private var isStale: Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sources.contains { source in
            guard let current = store.invoices.first(where: { $0.id == source.id }),
                  let originalData = try? encoder.encode(source),
                  let currentData = try? encoder.encode(current) else { return true }
            return originalData != currentData
        }
    }

    var body: some View {
        Form {
            Section {
                Label("Review before saving", systemImage: "info.circle")
                Text("Saving requires an online synchronization check. Your originals and payment history will be preserved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bill To") {
                Picker("Customer", selection: $billingCustomer) {
                    Text("Select billing customer").tag("")
                    ForEach(store.activeCustomers) { customer in
                        Text(customerName(customer.customerNumber)).tag(customer.customerNumber)
                    }
                }
            }
            Section("Selected Invoices") {
                ForEach(sources) { invoice in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(customerName(invoice.customerNumber)).font(.headline)
                        HStack {
                            Text(invoice.invoiceNumber)
                            Spacer()
                            Text(invoice.total, format: .currency(code: "USD"))
                        }
                        Text("\(invoice.jobNumber) · \(invoice.status.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !paymentSources.isEmpty {
                Section {
                    Text("Verify what was actually collected. Paid status and receipt history do not confirm collection by themselves. These funds will be transferred, not recorded as another payment.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Payment Carryover") }
                ForEach(paymentSources) { invoice in
                    Section(invoice.invoiceNumber) {
                        LabeledContent("Recorded Payment") {
                            Text(recordedAmount(invoice), format: .currency(code: "USD"))
                        }
                        HStack {
                            Text("Actually Collected")
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            SelectAllDecimalField(placeholder: "0.00", value: Binding(
                                get: { collectedAmounts[invoice.id] ?? recordedAmount(invoice) },
                                set: {
                                    collectedAmounts[invoice.id] = $0
                                    confirmations.remove(invoice.id)
                                }
                            )).frame(maxWidth: 120)
                        }
                        TextField("Collection check / correction notes", text: Binding(
                            get: { notes[invoice.id] ?? "" },
                            set: { notes[invoice.id] = $0 }
                        ), axis: .vertical)
                        Toggle("I checked the amount collected", isOn: Binding(
                            get: { confirmations.contains(invoice.id) },
                            set: {
                                if $0 { confirmations.insert(invoice.id) }
                                else { confirmations.remove(invoice.id) }
                            }
                        ))
                    }
                }
            }
            if isStale {
                Section {
                    Label("An invoice changed. Close this review and select the invoices again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Button("Review Combined Invoice") { review() }
                    .buttonStyle(.borderedProminent)
                    .disabled(billingCustomer.isEmpty || isStale || !paymentSources.allSatisfy { confirmations.contains($0.id) })
            }
        }
        .navigationTitle("Combine Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .navigationDestination(isPresented: $showingPreview) {
            if let proposal { InvoiceCombinationPreviewView(proposal: proposal, onSaved: onSaved) }
        }
        .alert("Review Needed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Review the selected invoices.") }
    }

    private func customerName(_ number: String) -> String {
        guard let customer = store.customers.first(where: { $0.customerNumber == number }) else { return number }
        return !customer.businessName.isEmpty ? customer.businessName
            : (!customer.contactName.isEmpty ? customer.contactName : number)
    }
    private func recordedAmount(_ invoice: InvoiceRecord) -> Double {
        guard let amount = try? InvoiceCombinationEngine.recordedCollectionAmount(for: invoice) else { return 0 }
        return NSDecimalNumber(decimal: amount).doubleValue
    }
    private func review() {
        guard !isStale else { return }
        do {
            let actor = store.authenticatedCloudEmployee?.displayName ?? "Current User"
            let checks = try paymentSources.map { invoice in
                let actual = collectedAmounts[invoice.id] ?? recordedAmount(invoice)
                guard actual.isFinite else { throw InvoicePaymentPoolEngine.ValidationError.invalidAmount }
                return InvoiceCollectionVerification(
                    id: UUID(), sourceInvoiceID: invoice.id,
                    recordedAmount: try InvoiceCombinationEngine.recordedCollectionAmount(for: invoice),
                    collectedAmount: Decimal(actual),
                    receiptIDs: (invoice.receipts ?? []).map(\.id),
                    paymentEventIDs: (invoice.receipts ?? []).map(\.paymentEventID),
                    verifiedBy: actor, verifiedAt: Date(), note: notes[invoice.id] ?? ""
                )
            }
            proposal = try InvoiceCombinationEngine.propose(
                invoiceNumber: "PREVIEW-\(UUID().uuidString)", billingCustomerNumber: billingCustomer,
                sources: sources, verifications: checks, preparedBy: actor
            )
            showingPreview = true
        } catch { self.error = error.localizedDescription }
    }
}

private struct InvoiceCombinationPreviewView: View {
    let proposal: InvoiceCombinationProposal
    let onSaved: (InvoiceRecord) -> Void
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var manager = PFSSCloudflareBetaManager()
    @State private var saveRequest: InvoiceCombinationSaveRequest?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Combined Invoice Preview") {
                Text("Not saved").foregroundStyle(.orange)
                LabeledContent("Invoice Number", value: saveRequest?.invoice.invoiceNumber ?? "Assigned when saved")
                LabeledContent("Bill To", value: billingName)
                LabeledContent("Jobs", value: proposal.jobNumbers.joined(separator: ", "))
            }
            ForEach(proposal.sourceInvoices) { source in
                Section("\(source.invoiceNumber) · \(source.jobNumber)") {
                    ForEach(proposal.lines.filter { $0.sourceInvoiceID == source.id }) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(line.item.catalogItemNameSnapshot ?? (line.item.otherService.isEmpty ? line.item.serviceType.rawValue : line.item.otherService))
                                Spacer()
                                money(line.item.lineTotal)
                            }
                            if !line.item.description.isEmpty {
                                Text(line.item.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(line.item.quantity, specifier: "%.2f") × \(line.item.unitPrice, format: .currency(code: "USD"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Invoice Discount") { money(source.discount) }
                    if let tax = source.taxSnapshot {
                        LabeledContent("Tax · \(tax.jurisdiction)") { decimalMoney(tax.addedTax) }
                    }
                }
            }
            Section("Totals") {
                LabeledContent("Total") { decimalMoney(proposal.total) }
                LabeledContent("Verified Payment Carryover") { decimalMoney(proposal.amountPaid) }
                LabeledContent("Still Due") { decimalMoney(proposal.balanceDue) }
                if proposal.refundRequired > 0 {
                    LabeledContent("Refund Required") { decimalMoney(proposal.refundRequired).foregroundStyle(.orange) }
                    Text("A refund must be handled manually. No refund has been issued.").font(.caption)
                }
            }
            Section {
                Button { save() } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Saving…" : "Save Combined Invoice")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
                Text("Creates a new invoice and marks the originals Combined. Existing collected funds are carried over without issuing new receipts. If a save is interrupted, retry here or synchronize to check its result.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Review Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .navigationBarBackButtonHidden(isSaving)
        .alert("Unable to Save Combined Invoice", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "Synchronize and try again.") }
    }
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if saveRequest == nil { saveRequest = try store.prepareCombinationSave(proposal) }
                guard let request = saveRequest else { return }
                let receipt = try await manager.saveInvoiceCombination(request)
                guard receipt.invoiceID == request.invoice.id else { throw AppDataStore.CombinationSaveError.invalidReceipt }
                let saved = try store.applyCombinationSaveReceipt(receipt)
                onSaved(saved)
            } catch { saveError = InvoiceFinancialSaveMessage.describe(error) }
        }
    }
    private var billingName: String {
        guard let customer = store.customers.first(where: { $0.customerNumber == proposal.billingCustomerNumber }) else { return proposal.billingCustomerNumber }
        return customer.businessName.isEmpty ? customer.contactName : customer.businessName
    }
    private func money(_ amount: Double) -> Text { Text(amount, format: .currency(code: "USD")) }
    private func decimalMoney(_ amount: Decimal) -> Text { money(NSDecimalNumber(decimal: amount).doubleValue) }
}
