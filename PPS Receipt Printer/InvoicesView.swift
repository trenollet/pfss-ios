//
//  InvoicesView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/11/26.
//

import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var showArchived = false

    private var displayedInvoices: [InvoiceRecord] {
        let source = showArchived
            ? store.archivedInvoices
            : store.activeInvoices

        return source.sorted {
            $0.issueDate > $1.issueDate
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        "Show Archived",
                        isOn: $showArchived
                    )
                }

                Section("Invoices") {
                    if displayedInvoices.isEmpty {
                        Text(
                            showArchived
                                ? "No archived invoices."
                                : "No invoices yet."
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayedInvoices) { invoice in
                            NavigationLink {
                                InvoiceDetailView(invoice: invoice)
                            } label: {
                                VStack(
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    HStack {
                                        Text(invoice.invoiceNumber)
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        Text(invoice.status.rawValue)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    Text(
                                        "Customer: \(customerDisplayName(for: invoice.customerNumber))"
                                    )
                                    .font(.caption)
                                    
                                    if !invoice.jobNumber.isEmpty {
                                        Text("Job: \(invoice.jobNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    HStack {
                                        Text(
                                            invoice.issueDate,
                                            format: .dateTime
                                                .month()
                                                .day()
                                                .year()
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(
                                            invoice.balanceDue,
                                            format: .currency(code: "USD")
                                        )
                                        .fontWeight(.semibold)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Invoices")
        }
    }

    private func customerDisplayName(
        for customerNumber: String
    ) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return customerNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return customerNumber
    }
}
