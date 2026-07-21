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
    @State private var sharedPDFURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isShowingPDFError = false
    @FocusState private var isInputFocused: Bool

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
                    Text(
                        invoice.amountPaid,
                        format: .currency(code: "USD")
                    )
                }

                LabeledContent("Balance Due") {
                    Text(
                        invoice.balanceDue,
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
                    printThermalReceipt()
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
                .disabled(!printer.isReadyToPrint)
                
                if invoice.lifecycleStatus == .archived {
                    Button("Restore Invoice") {
                        store.restoreInvoice(invoice)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(
                        "Archive Invoice",
                        role: .destructive
                    ) {
                        store.archiveInvoice(invoice)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isInputFocused = false
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveInvoice()
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    isInputFocused = false
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

        invoice.balanceDue = max(
            0,
            invoice.total - invoice.amountPaid
        )

        if invoice.status == .paid {
            invoice.amountPaid = invoice.total
            invoice.balanceDue = 0

            if invoice.paidDate == nil {
                invoice.paidDate = Date()
            }
        } else if invoice.balanceDue > 0 {
            invoice.paidDate = nil
        }

        store.updateInvoice(invoice)
        dismiss()
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

    private func printThermalReceipt() {
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

        let receiptText = ThermalReceiptRenderer.render(
            invoice: invoice,
            businessProfile: store.businessProfile,
            customer: customer,
            site: site,
            catalogItems: store.serviceCatalogItems
        )

        printer.printReceiptText(receiptText)
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
