//
//  InvoiceDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/11/26.
//

import SwiftUI
import UIKit

struct InvoiceDetailView: View {
    private enum ActiveSheet: Identifiable {
        case catalogPicker
        case editLineItem(ServiceLineItem)

        var id: String {
            switch self {
            case .catalogPicker: return "catalogPicker"
            case .editLineItem(let item): return "editLineItem-\(item.id)"
            }
        }
    }

    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var printer: BluetoothPrinter

    @State var invoice: InvoiceRecord
    @State private var originalInvoice: InvoiceRecord
    var showsDismissButton = false
    @State private var sharedPDFURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isShowingPDFError = false
    @State private var isShowingReceiptPrinter = false
    @State private var showingUnsavedChangesAlert = false
    @State private var showingTaxCalculation = false
    @State private var activeSheet: ActiveSheet?
    @State private var showingPaymentCorrection = false
    @State private var paymentEditError: String?
    @State private var explicitlyMarkedPaid = false
    @FocusState private var isInputFocused: Bool

    init(invoice: InvoiceRecord, showsDismissButton: Bool = false) {
        _invoice = State(initialValue: invoice)
        _originalInvoice = State(initialValue: invoice)
        self.showsDismissButton = showsDismissButton
    }

    private var customerDisplayName: String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == invoice.customerNumber
        }) else {
            return invoice.customerNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return invoice.customerNumber
    }

    private var displayedBalanceDue: Double {
        max(
            0,
            invoice.total - max(invoice.amountPaid, 0)
        )
    }

    private var invoiceSite: CustomerSite? {
        guard let siteID = invoice.siteID else { return nil }
        return store.sites.first { $0.id == siteID }
    }

    private var reviewerName: String {
        store.authenticatedCloudEmployee?.displayName ?? "Authorized Owner or Manager"
    }

    var body: some View {
        List {
            Section("Invoice") {
                LabeledContent("Invoice Number") {
                    Text(invoice.invoiceNumber)
                        .fontWeight(.semibold)
                }

                LabeledContent("Customer") {
                    Text(customerDisplayName)
                        .multilineTextAlignment(.trailing)
                }

                if !invoice.jobNumber.isEmpty {
                    LabeledContent("Job Number") {
                        Text(invoice.jobNumbers.joined(separator: ", "))
                    }
                }

                Picker("Status", selection: $invoice.status) {
                    ForEach(InvoiceStatus.allCases.filter {
                        (invoice.combination == nil && invoice.paymentCorrection == nil) || $0 != .void || invoice.status == .void
                    }) { status in
                        Text(status.rawValue)
                            .tag(status)
                    }
                }
                .onChange(of: invoice.status) {
                    explicitlyMarkedPaid = invoice.status == .paid
                    if explicitlyMarkedPaid {
                        invoice.amountPaid = max(invoice.total, 0)
                        invoice.balanceDue = 0
                    }
                }
            }

            if let combination = invoice.combination {
                Section("Combined Invoices") {
                    ForEach(combination.sourceInvoices) { source in
                        LabeledContent(source.invoiceNumber, value: source.jobNumber)
                    }
                    if combination.refundRequired > 0 {
                        LabeledContent("Refund Required") {
                            Text(NSDecimalNumber(decimal: combination.refundRequired).doubleValue, format: .currency(code: "USD"))
                        }
                        Text("Resolve this refund manually. PFSS has not issued a refund.").font(.caption).foregroundStyle(.orange)
                    }
                    Text("Source charges and tax evidence are preserved. Changes to a combined bill require manual payment redistribution.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if invoice.combination != nil || invoice.paymentCorrection != nil {
                Section("Payment Corrections") {
                    Button {
                        if hasUnsavedChanges {
                            paymentEditError = "Save or discard current edits before opening payment corrections."
                        } else {
                            showingPaymentCorrection = true
                        }
                    } label: {
                        Label("Split & Redistribute Payments", systemImage: "arrow.triangle.branch")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(correctionRoot == nil)
                    Text("Current edits must be saved or discarded before opening payment corrections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let correction = invoice.paymentCorrection, let latest = correction.history.last {
                        LabeledContent("Correction History", value: "\(correction.history.count - 1) saved corrections")
                        NavigationLink("View Correction History") {
                            InvoicePaymentCorrectionHistoryView(history: correction.history)
                        }
                        if latest.refundRequired > 0 {
                            LabeledContent("Payment Group Refund Required") {
                                Text(NSDecimalNumber(decimal: latest.refundRequired).doubleValue, format: .currency(code: "USD"))
                            }
                            Text("Unassigned funds require manual review. No refund has been issued.").font(.caption).foregroundStyle(.orange)
                        }
                        if invoice.id == correction.rootInvoiceID, correction.retainedInvoiceIDs.isEmpty {
                            Text("This combined invoice was split and is retained for audit only. Open the restored invoices to bill or share.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Dates") {
                DatePicker(
                    "Issue Date",
                    selection: $invoice.issueDate,
                    displayedComponents: .date
                )

                DatePicker(
                    "Due Date",
                    selection: $invoice.dueDate,
                    displayedComponents: .date
                )

                if let paidDate = invoice.paidDate {
                    LabeledContent("Paid Date") {
                        Text(
                            paidDate,
                            format: .dateTime
                                .month()
                                .day()
                                .year()
                        )
                    }
                }
            }

            Section("Services & Materials") {
                if invoice.lineItems.isEmpty {
                    Text("No line items.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(invoice.lineItems) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(serviceName(for: item))
                                    .font(.headline)
                                if !item.description.isEmpty {
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(item.quantity, specifier: "%.2f") × \(item.unitPrice, format: .currency(code: "USD"))")
                                    .font(.caption)
                                Text(item.lineTotal, format: .currency(code: "USD"))
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            Button {
                                activeSheet = .editLineItem(item)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                invoice.lineItems.removeAll { $0.id == item.id }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    activeSheet = .catalogPicker
                } label: {
                    Label("Add Invoice Item", systemImage: "plus.circle.fill")
                }

                if !(invoice.receipts ?? []).isEmpty {
                    Text("Editing charges will not alter the payment already recorded. If the corrected total is higher, the remaining amount will become due.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            .disabled(invoice.combination != nil || invoice.paymentCorrection != nil)

            Section("Financial Summary") {
                LabeledContent("Subtotal") {
                    Text(
                        invoice.subtotal,
                        format: .currency(code: "USD")
                    )
                }

                LabeledContent("Discount") {
                    Text(
                        invoice.discount,
                        format: .currency(code: "USD")
                    )
                }

                if let combination = invoice.combination {
                    ForEach(combination.sourceInvoices) { source in
                        if let tax = source.taxSnapshot {
                            LabeledContent("Tax · \(source.jobNumber)") {
                                Text(NSDecimalNumber(decimal: tax.addedTax).doubleValue, format: .currency(code: "USD"))
                            }
                        }
                    }
                } else if let tax = invoice.taxSnapshot {
                    LabeledContent("Tax") {
                        Text(
                            NSDecimalNumber(decimal: tax.addedTax).doubleValue,
                            format: .currency(code: "USD")
                        )
                    }
                    LabeledContent("Applied Rate") {
                        let percent = NSDecimalNumber(
                            decimal: tax.appliedRate * 100
                        ).doubleValue
                        Text("\(percent, specifier: "%.3f")%")
                    }
                } else {
                    LabeledContent("Tax", value: "Not calculated")
                }

                LabeledContent("Total") {
                    Text(
                        invoice.total,
                        format: .currency(code: "USD")
                    )
                    .fontWeight(.semibold)
                }

                LabeledContent("Amount Paid") {
                    HStack(spacing: 3) {
                        Text("$")
                            .foregroundStyle(.secondary)

                        SelectAllDecimalField(
                            placeholder: "0.00",
                            value: $invoice.amountPaid
                        )
                        .focused($isInputFocused)
                        .disabled(invoice.status != .partiallyPaid)
                    }
                    .frame(maxWidth: 150)
                }

                LabeledContent("Balance Due") {
                    Text(
                        displayedBalanceDue,
                        format: .currency(code: "USD")
                    )
                    .fontWeight(.bold)
                }
            }

            Section("Tax Classification") {
                ForEach(TaxTreatment.allCases) { treatment in
                    let count = invoice.lineItems.filter {
                        $0.taxTreatmentSnapshot == treatment
                    }.count

                    if count > 0 {
                        LabeledContent(treatment.rawValue) {
                            Text("\(count) line\(count == 1 ? "" : "s")")
                        }
                    }
                }

                let legacyCount = invoice.lineItems.filter {
                    $0.taxTreatmentSnapshot == nil
                }.count

                if legacyCount > 0 {
                    LabeledContent("Not Recorded") {
                        Text("\(legacyCount) legacy line\(legacyCount == 1 ? "" : "s")")
                            .foregroundStyle(.orange)
                    }
                }

                Text(
                    invoice.combination != nil
                    ? "Each original invoice retains its own tax jurisdiction and amount. These charges are not recalculated for the billing customer."
                    : invoice.taxSnapshot == nil
                    ? "Tax has not been calculated for this invoice. PFSS will "
                        + "not guess a jurisdiction rate."
                    : "The displayed tax is retained with this invoice. Later "
                        + "catalog or rate changes do not silently recalculate it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if store.canManageCompany && invoice.combination == nil && invoice.paymentCorrection == nil {
                    Button(
                        invoice.taxSnapshot == nil
                        ? "Calculate Invoice Tax"
                        : "Review or Correct Invoice Tax"
                    ) {
                        showingTaxCalculation = true
                    }
                }
            }

            Section("Notes") {
                TextField(
                    "Invoice Notes",
                    text: $invoice.notes,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .focused($isInputFocused)
            }

            Section {
                Button {
                    createAndSharePDF()
                } label: {
                    HStack {
                        Spacer()

                        Label(
                            "Share Invoice",
                            systemImage: "square.and.arrow.up"
                        )

                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                Button {
                    isInputFocused = false
                    isShowingReceiptPrinter = true
                } label: {
                    HStack {
                        Spacer()

                        Label(
                            "Print Receipt",
                            systemImage: "printer.fill"
                        )

                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                if invoice.lifecycleStatus == .archived {
                    Button {
                        store.restoreInvoice(invoice)
                        dismiss()
                    } label: {
                        Label("Restore Invoice", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveInvoice(invoice)
                        dismiss()
                    } label: {
                        CenteredArchiveActionLabel(title: "Archive Invoice")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label(
                        showsDismissButton ? "Close" : "Back",
                        systemImage: showsDismissButton ? "xmark" : "chevron.left"
                    )
                }
            }

            EditorKeyboardDismissAction(isVisible: isInputFocused) {
                isInputFocused = false
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveInvoice()
                }
            }

        }
        .sheet(
            isPresented: Binding(
                get: { sharedPDFURL != nil },
                set: { isPresented in
                    if !isPresented {
                        sharedPDFURL = nil
                    }
                }
            )
        ) {
            if let sharedPDFURL {
                ActivityView(
                    activityItems: [sharedPDFURL]
                )
            }
        }
        .sheet(isPresented: $showingPaymentCorrection) {
            if let root = correctionRoot {
                InvoicePaymentCorrectionView(root: root) { _ in
                    if let current = store.invoices.first(where: { $0.id == invoice.id }) {
                        invoice = store.invoiceDestination(for: current)
                        originalInvoice = invoice
                    }
                }.environmentObject(store)
            }
        }
        .alert("Payment Correction Required", isPresented: Binding(get: { paymentEditError != nil }, set: { if !$0 { paymentEditError = nil } })) {
            Button("OK", role: .cancel) { paymentEditError = nil }
        } message: { Text(paymentEditError ?? "Use the payment correction workspace.") }
        .sheet(isPresented: $isShowingReceiptPrinter) {
            ReceiptPrinterSelectionView(
                receiptText: thermalReceiptText()
            )
            .environmentObject(printer)
        }
        .alert(
            "Unable to Share Invoice",
            isPresented: $isShowingPDFError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                pdfErrorMessage ??
                "The invoice PDF could not be created."
            )
        }
        .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
            Button("Save Changes") { saveInvoice() }
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This invoice has changes that have not been saved.")
        }
        .sheet(isPresented: $showingTaxCalculation) {
            InvoiceTaxCalculationView(
                invoice: $invoice,
                site: invoiceSite,
                reviewerName: reviewerName,
                companyTaxSettings: store.businessProfile.taxSettings
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .catalogPicker:
                ServiceCatalogPickerView(
                    lineItems: $invoice.lineItems,
                    onFinished: { activeSheet = nil }
                )
                .environmentObject(store)
            case .editLineItem(let item):
                EditableLineItemView(
                    lineItems: $invoice.lineItems,
                    catalogItem: nil,
                    existingLineItem: item
                )
                .environmentObject(store)
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        encodedInvoice(invoice) != encodedInvoice(originalInvoice)
    }

    private var correctionRoot: InvoiceRecord? {
        let id = invoice.paymentCorrection?.rootInvoiceID ?? invoice.id
        return store.invoices.first { $0.id == id && $0.combination != nil }
    }

    private func saveInvoice() {
        isInputFocused = false
        if invoice.combination != nil || invoice.paymentCorrection != nil {
            let previous = store.invoices.first { $0.id == invoice.id } ?? originalInvoice
            guard previous.status != .void, invoice.status != .void, invoice.amountPaid >= previous.amountPaid else {
                paymentEditError = "Use Split & Redistribute Payments to reduce or correct collected funds. A split combined invoice is read-only."
                return
            }
        }

        invoice = InvoiceEngine.recalculatedForEditorSave(
            invoice,
            explicitlyMarkedPaid: explicitlyMarkedPaid
        )

        store.updateInvoice(invoice)
        originalInvoice = invoice
        explicitlyMarkedPaid = false
        dismiss()
    }

    private func requestDismissal() {
        isInputFocused = false
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func encodedInvoice(_ invoice: InvoiceRecord) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(invoice)
    }
    private func createAndSharePDF() {
        isInputFocused = false

        let customer = store.customers.first(where: {
            $0.customerNumber == invoice.customerNumber
        })

        let site: CustomerSite?

        if let siteID = invoice.siteID {
            site = store.sites.first(where: {
                $0.id == siteID
            })
        } else {
            site = nil
        }

        do {
            let pdfURL = try InvoicePDFRenderer.createPDF(
                invoice: invoice,
                businessProfile: store.businessProfile,
                customer: customer,
                site: site,
                catalogItems: store.serviceCatalogItems
            )

            sharedPDFURL = pdfURL
        } catch {
            pdfErrorMessage = error.localizedDescription
            isShowingPDFError = true
        }
    }

    private func thermalReceiptText() -> String {
        let customer = store.customers.first(where: {
            $0.customerNumber == invoice.customerNumber
        })

        let site: CustomerSite?

        if let siteID = invoice.siteID {
            site = store.sites.first(where: {
                $0.id == siteID
            })
        } else {
            site = nil
        }

        return ThermalReceiptRenderer.renderPrintableDocument(
            invoice: invoice,
            businessProfile: store.businessProfile,
            customer: customer,
            site: site,
            catalogItems: store.serviceCatalogItems
        )

    }
    
    
    private func serviceName(
        for item: ServiceLineItem
    ) -> String {
        if let snapshotName = item.catalogItemNameSnapshot,
           !snapshotName.isEmpty {
            return snapshotName
        }

        if let catalogItemID = item.catalogItemID,
           let catalogItem = store.serviceCatalogItems.first(where: {
               $0.id == catalogItemID
           }) {
            return catalogItem.itemName
        }

        if !item.otherService.isEmpty {
            return item.otherService
        }

        return item.serviceType.rawValue
    }
}
