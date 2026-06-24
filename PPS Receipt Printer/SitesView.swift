//
//  SitesView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct SitesView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var selectedCustomerNumber = ""
    @State private var siteName = ""
    @State private var serviceAddress = ""
    @State private var propertyType = ""
    @State private var accessNotes = ""
    @State private var workNotes = ""

    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("New Site / Work Location") {
                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.customers) { customer in
                            Text(customerDisplayName(customer))
                                .tag(customer.customerNumber)
                        }
                    }

                    TextField("Site Name", text: $siteName)
                        .focused($isInputFocused)

                    TextField("Service Address", text: $serviceAddress)
                        .focused($isInputFocused)

                    TextField("Property Type", text: $propertyType)
                        .focused($isInputFocused)

                    TextField("Access Notes", text: $accessNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)

                    TextField("Work Notes", text: $workNotes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isInputFocused)

                    Button("Add Site") {
                        isInputFocused = false
                        addSite()
                    }
                    .disabled(selectedCustomerNumber.isEmpty)
                }

                Section("Sites") {
                    ForEach(store.sites) { site in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.siteName.isEmpty ? site.serviceAddress : site.siteName)
                                .font(.headline)

                            Text(site.serviceAddress)
                            Text("Customer #: \(site.customerNumber)")
                                .font(.caption)

                            if !site.propertyType.isEmpty {
                                Text("Property: \(site.propertyType)")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sites")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
        }
    }

    private func customerDisplayName(_ customer: Customer) -> String {
        if !customer.businessName.isEmpty {
            return "\(customer.businessName) - \(customer.customerNumber)"
        }

        return "\(customer.contactName) - \(customer.customerNumber)"
    }

    private func addSite() {
        let site = CustomerSite(
            customerNumber: selectedCustomerNumber,
            siteName: siteName,
            serviceAddress: serviceAddress,
            propertyType: propertyType,
            accessNotes: accessNotes,
            workNotes: workNotes
        )

        store.addSite(site)

        siteName = ""
        serviceAddress = ""
        propertyType = ""
        accessNotes = ""
        workNotes = ""
    }
}
