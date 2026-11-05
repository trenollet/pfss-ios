import SwiftUI

/// One online, atomic correction; no transfer creates a receipt or refund.
struct InvoicePaymentCorrectionView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    let root: InvoiceRecord
    let onSaved: (InvoiceRecord) -> Void
    @StateObject private var manager = PFSSCloudflareBetaManager()
    @State private var originals: [InvoiceRecord] = []
    @State private var retained = Set<UUID>()
    @State private var checks: [InvoiceCollectionVerification] = []
    @State private var amounts: [UUID: Double] = [:]
    @State private var allocations: [UUID: Double] = [:]
    @State private var billingCustomer = ""
    @State private var reason = ""
    @State private var confirmed = false
    @State private var initialized = false
    @State private var isSaving = false
    @State private var showingSaveConfirmation = false
    @State private var request: InvoicePaymentCorrectionRequest?
    @State private var error: String?

    private var totals: [(UUID, Decimal)] {
        (try? InvoicePaymentCorrectionEngine.invoiceTotals(rootID: root.id, originals: originals, retained: retained)) ?? []
    }
    private var poolAmount: Decimal {
        checks.reduce(0) { $0 + Decimal(amounts[$1.id] ?? NSDecimalNumber(decimal: effectiveAmount($1)).doubleValue) }
    }
    private var allocated: Decimal { totals.reduce(0) { $0 + Decimal(allocations[$1.0] ?? 0) } }
    private var remainingDue: Decimal { totals.reduce(0) { $0 + max($1.1 - Decimal(allocations[$1.0] ?? 0), 0) } }
    private var eligibleAdditions: [InvoiceRecord] {
        let ids = Set(originals.map(\.id))
        return store.activeInvoices.filter {
            $0.id != root.id && !ids.contains($0.id) && $0.status != .void &&
            $0.combination == nil && $0.combinedIntoInvoiceID == nil && $0.paymentCorrection == nil
        }
    }
    private var changesLocked: Bool { isSaving || request != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Keep two or more invoices in the combined bill, or split all. Then assign the verified funds to the resulting invoices. No new payment or refund is recorded.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Split All", role: .destructive) { retained.removeAll(); resetAllocations() }
                }
                .disabled(changesLocked)
                Section("Invoices to Keep Combined") {
                    ForEach(originals) { source in
                        Button {
                            if !retained.insert(source.id).inserted { retained.remove(source.id) }
                            resetAllocations()
                        } label: {
                            HStack {
                                Image(systemName: retained.contains(source.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(source.invoiceNumber).font(.headline)
                                    Text("\(customerName(source.customerNumber)) · \(source.jobNumber)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                money(Decimal(source.total))
                            }
                        }.foregroundStyle(.primary)
                    }
                    if retained.count == 1 {
                        Text("Keep at least two combined, or deselect this invoice to split all.").font(.caption).foregroundStyle(.orange)
                    }
                    if !eligibleAdditions.isEmpty {
                        Menu("Add Another Invoice") {
                            ForEach(eligibleAdditions) { invoice in
                                Button("\(invoice.invoiceNumber) · \(customerName(invoice.customerNumber))") { add(invoice) }
                            }
                        }
                    }
                }.disabled(changesLocked)
                if !retained.isEmpty {
                    Section("Combined Bill To") {
                        Picker("Customer", selection: $billingCustomer) {
                            ForEach(store.activeCustomers) { customer in
                                Text(customerName(customer.customerNumber)).tag(customer.customerNumber)
                            }
                        }
                    }.disabled(changesLocked)
                }
                Section("Verify Collected Funds") {
                    ForEach(checks) { check in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(invoiceName(check.sourceInvoiceID)).font(.headline)
                            HStack {
                                Text("Actually Collected")
                                Spacer()
                                Text("$")
                                SelectAllDecimalField(placeholder: "0.00", value: Binding(
                                    get: { amounts[check.id] ?? NSDecimalNumber(decimal: effectiveAmount(check)).doubleValue },
                                    set: { amounts[check.id] = $0; confirmed = false }
                                )).frame(maxWidth: 130)
                            }
                            Text("Recorded: \(NSDecimalNumber(decimal: check.recordedAmount).doubleValue, format: .currency(code: "USD"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Verified Pool") { money(poolAmount) }
                    Toggle("I checked the actual collected amounts", isOn: $confirmed)
                }.disabled(changesLocked)
                Section("Assign Funds Manually") {
                    ForEach(totals, id: \.0) { id, total in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(id == root.id ? "Combined · \(root.invoiceNumber)" : invoiceName(id)).font(.headline)
                            LabeledContent("Invoice Total") { money(total) }
                            HStack {
                                Text("Apply From Pool")
                                Spacer()
                                Text("$")
                                SelectAllDecimalField(placeholder: "0.00", value: Binding(
                                    get: { allocations[id] ?? 0 }, set: { allocations[id] = $0 }
                                )).frame(maxWidth: 130)
                            }
                            LabeledContent("Still Due") { money(max(total - Decimal(allocations[id] ?? 0), 0)) }
                        }
                    }
                    LabeledContent("Total Still Due") { money(remainingDue) }
                    if poolAmount - allocated > 0 {
                        LabeledContent("Refund Required") { money(poolAmount - allocated).foregroundStyle(.orange) }
                        Text("Review unassigned funds. Any refund must be handled manually; PFSS has not returned money.")
                            .font(.caption).foregroundStyle(.orange)
                    } else if allocated > poolAmount {
                        Text("Assigned funds exceed the verified pool.").foregroundStyle(.red)
                    }
                }.disabled(changesLocked)
                Section("Correction Reason") {
                    TextField("Explain the split, invoice correction or payment change", text: $reason, axis: .vertical)
                }.disabled(changesLocked)
                Section {
                    Button {
                        if request == nil { showingSaveConfirmation = true } else { save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving…" : (request == nil ? "Save Correction" : "Retry Same Correction"))
                            Spacer()
                        }
                    }.buttonStyle(.borderedProminent)
                        .disabled(isSaving || retained.count == 1 || !confirmed || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Existing receipts and every earlier allocation stay in the audit history. Saving needs an online check. If interrupted, retry the same correction or synchronize to check its result.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Split & Redistribute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(isSaving)
            } }
            .interactiveDismissDisabled(isSaving)
            .task { initialize() }
            .confirmationDialog("Save this correction?", isPresented: $showingSaveConfirmation, titleVisibility: .visible) {
                Button("Save Correction") { save() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Still due: \(NSDecimalNumber(decimal: remainingDue).doubleValue, format: .currency(code: "USD")). Refund required: \(NSDecimalNumber(decimal: max(poolAmount - allocated, 0)).doubleValue, format: .currency(code: "USD")). No payment or refund will be issued.")
            }
            .alert("Correction Not Saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "Synchronize and try again.") }
        }
    }

    private func effectiveAmount(_ check: InvoiceCollectionVerification) -> Decimal {
        let adjustments = (try? InvoicePaymentCorrectionEngine.previous(for: root))?.pool.adjustments ?? []
        return check.collectedAmount + adjustments.filter { $0.verificationID == check.id }.reduce(0) { $0 + $1.amountChange }
    }
    private func initialize() {
        guard !initialized else { return }
        initialized = true
        do {
            originals = try InvoicePaymentCorrectionEngine.originals(for: root)
            retained = Set(root.paymentCorrection?.retainedInvoiceIDs ?? root.combination?.sourceInvoices.map(\.id) ?? [])
            billingCustomer = root.customerNumber
            checks = try InvoicePaymentCorrectionEngine.previous(for: root).pool.verifications
            let ids = Set(originals.map(\.id) + [root.id])
            guard store.invoices.filter({ ids.contains($0.id) }).count == ids.count else {
                throw InvoicePaymentCorrectionEngine.ValidationError.unavailableGroup
            }
            checks += try InvoicePaymentCorrectionEngine.pendingVerifications(root: root,
                members: store.invoices.filter { ids.contains($0.id) }, actor: actor)
            resetAllocations()
        } catch { self.error = error.localizedDescription }
    }
    private var actor: String { store.authenticatedCloudEmployee?.displayName ?? "Current User" }
    private func resetAllocations() { allocations.removeAll() }
    private func add(_ invoice: InvoiceRecord) {
        do {
            let newChecks = try InvoicePaymentCorrectionEngine.pendingVerifications(root: root, members: [invoice], actor: actor)
            originals.append(invoice); retained.insert(invoice.id); checks += newChecks
            confirmed = false; resetAllocations()
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if request == nil {
                    let previous = try InvoicePaymentCorrectionEngine.previous(for: root)
                    var newChecks = checks
                    var adjustments = previous.pool.adjustments
                    for index in newChecks.indices {
                        let check = newChecks[index]
                        let input = amounts[check.id] ?? NSDecimalNumber(decimal: effectiveAmount(check)).doubleValue
                        guard input.isFinite else { throw InvoicePaymentPoolEngine.ValidationError.invalidAmount }
                        let amount = Decimal(input)
                        if index < previous.pool.verifications.count {
                            let change = amount - effectiveAmount(check)
                            if change != 0 {
                                adjustments.append(.init(id: UUID(), verificationID: check.id, amountChange: change,
                                    correctedBy: actor, correctedAt: Date(), reason: reason))
                            }
                        } else {
                            newChecks[index].collectedAmount = amount; newChecks[index].note = reason
                        }
                    }
                    let pool = try InvoicePaymentPoolEngine.makePool(id: previous.pool.id, verifications: newChecks, adjustments: adjustments)
                    let redistribution = try InvoicePaymentPoolEngine.redistribute(pool: pool,
                        allocations: totals.map { .init(invoiceID: $0.0, invoiceTotal: $0.1, appliedAmount: Decimal(allocations[$0.0] ?? 0)) },
                        preparedBy: actor, reason: reason, replacing: previous)
                    request = try store.preparePaymentCorrection(root: root, originals: originals, retained: retained,
                        billingCustomerNumber: billingCustomer, redistribution: redistribution)
                }
                guard let request else { return }
                let receipt = try await manager.correctInvoicePayments(request)
                let result = try store.applyPaymentCorrectionReceipt(receipt, request: request)
                onSaved(result)
                dismiss()
            } catch { self.error = InvoiceFinancialSaveMessage.describe(error) }
        }
    }
    private func customerName(_ number: String) -> String {
        guard let customer = store.customers.first(where: { $0.customerNumber == number }) else { return number }
        return customer.businessName.isEmpty ? customer.contactName : customer.businessName
    }
    private func invoiceName(_ id: UUID) -> String {
        store.invoices.first { $0.id == id }?.invoiceNumber ?? originals.first { $0.id == id }?.invoiceNumber ?? "Invoice"
    }
    private func money(_ value: Decimal) -> some View {
        Text(NSDecimalNumber(decimal: value).doubleValue, format: .currency(code: "USD"))
    }
}

struct InvoicePaymentCorrectionHistoryView: View {
    @EnvironmentObject private var store: AppDataStore
    let history: [InvoicePaymentRedistribution]
    var body: some View {
        List {
            ForEach(Array(history.reversed())) { entry in
                Section(entry.preparedAt.formatted(date: .abbreviated, time: .shortened)) {
                    Text(entry.reason).font(.headline)
                    Text("Recorded by: \(entry.preparedBy)").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Verified Collected Funds") { money(entry.pool.collectedAmount) }
                    ForEach(entry.allocations, id: \.invoiceID) { allocation in
                        LabeledContent(store.invoices.first { $0.id == allocation.invoiceID }?.invoiceNumber ?? "Invoice") {
                            money(allocation.appliedAmount)
                        }
                    }
                    LabeledContent("Still Due") { money(entry.remainingDue) }
                    LabeledContent("Refund Required") { money(entry.refundRequired) }
                    ForEach(entry.pool.adjustments) { adjustment in
                        VStack(alignment: .leading) {
                            Text(adjustment.reason)
                            money(adjustment.amountChange).font(.caption)
                            Text(adjustment.correctedAt, format: .dateTime.month().day().year().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Historical allocation only. Do not count this entry as another payment or issued refund.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Correction History").navigationBarTitleDisplayMode(.inline)
    }
    private func money(_ value: Decimal) -> some View {
        Text(NSDecimalNumber(decimal: value).doubleValue, format: .currency(code: "USD"))
    }
}
