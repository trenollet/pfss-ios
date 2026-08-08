//
//  InvoiceDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/11/26.
//

import SwiftUI
import UIKit

struct InvoiceDetailView: View {
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

    var body: some View {
        Form {
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
                        Text(invoice.jobNumber)
                    }
                }

                Picker("Status", selection: $invoice.status) {
                    ForEach(InvoiceStatus.allCases) { status in
                        Text(status.rawValue)
                            .tag(status)
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(serviceName(for: item))
                                .font(.headline)

                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text(
                                    "\(item.quantity, specifier: "%.2f") × \(item.unitPrice, format: .currency(code: "USD"))"
                                )
                                .font(.caption)

                                Spacer()

                                Text(
                                    item.lineTotal,
                                    format: .currency(code: "USD")
                                )
                                .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

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
                .disabled(!hasUnsavedChanges)
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
    }

    private var hasUnsavedChanges: Bool {
        encodedInvoice(invoice) != encodedInvoice(originalInvoice)
    }

    private func saveInvoice() {
        isInputFocused = false

        invoice.lineItems = PricingCalculator.updatedLineItems(
            invoice.lineItems
        )

        invoice.subtotal = PricingCalculator.subtotal(
            for: invoice.lineItems
        )

        invoice.total = PricingCalculator.total(
            subtotal: invoice.subtotal,
            discount: invoice.discount
        )

        invoice.amountPaid = min(
            max(invoice.amountPaid, 0),
            max(invoice.total, 0)
        )

        store.updateInvoice(invoice)
        originalInvoice = invoice
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

        return ThermalReceiptRenderer.render(
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
