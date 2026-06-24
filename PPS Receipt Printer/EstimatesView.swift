//
//  EstimatesView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct EstimatesView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var selectedLeadNumber = ""
    @State private var selectedCustomerNumber = ""
    @State private var selectedSiteID: UUID?

    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var serviceDetails = ""
    @State private var subtotal = ""
    @State private var discount = ""
    @State private var salesperson = ""
    @State private var status: EstimateRecordStatus = .draft
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    @FocusState private var isInputFocused: Bool

    private var subtotalValue: Double { Double(subtotal) ?? 0 }
    private var discountValue: Double { Double(discount) ?? 0 }
    private var totalValue: Double { max(subtotalValue - discountValue, 0) }

    private var availableSites: [CustomerSite] {
        store.sites(for: selectedCustomerNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Estimate") {
                    Picker("Lead", selection: $selectedLeadNumber) {
                        Text("None").tag("")
                        ForEach(store.leads) { lead in
                            Text("\(lead.leadNumber) - \(leadName(lead))")
                                .tag(lead.leadNumber)
                        }
                    }

                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.customers) { customer in
                            Text(customerName(customer))
                                .tag(customer.customerNumber)
                        }
                    }

                    Picker("Site", selection: $selectedSiteID) {
                        Text("Select Site").tag(UUID?.none)
                        ForEach(availableSites) { site in
                            Text(site.siteName.isEmpty ? site.serviceAddress : site.siteName)
                                .tag(Optional(site.id))
                        }
                    }

                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }

                    if serviceType == .other {
                        TextField("Other Service", text: $otherService)
                            .focused($isInputFocused)
                    }

                    TextField("Service Details", text: $serviceDetails, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isInputFocused)

                    TextField("Subtotal", text: $subtotal)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    TextField("Discount", text: $discount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalValue, format: .currency(code: "USD"))
                            .bold()
                    }

                    TextField("Salesperson", text: $salesperson)
                        .focused($isInputFocused)

                    Picker("Status", selection: $status) {
                        ForEach(EstimateRecordStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)

                    Button("Add Estimate") {
                        isInputFocused = false
                        addEstimate()
                    }
                    .disabled(selectedCustomerNumber.isEmpty)
                }

                Section("Estimates") {
                    ForEach(store.estimates) { estimate in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(estimate.estimateNumber)
                                .font(.headline)

                            Text("Customer: \(estimate.customerNumber)")
                                .font(.caption)

                            Text("Service: \(serviceName(for: estimate))")
                                .font(.caption)

                            Text("Total: \(estimate.total, format: .currency(code: "USD"))")
                                .font(.caption)

                            Text("Status: \(estimate.status.rawValue)")
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Estimates")
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

    private func addEstimate() {
        let estimate = EstimateRecord(
            estimateNumber: store.generateEstimateNumber(),
            leadNumber: selectedLeadNumber,
            customerNumber: selectedCustomerNumber,
            siteID: selectedSiteID,
            serviceType: serviceType,
            otherService: otherService,
            serviceDetails: serviceDetails,
            subtotal: subtotalValue,
            discount: discountValue,
            total: totalValue,
            salesperson: salesperson,
            status: status,
            createdDate: Date(),
            expirationDate: expirationDate
        )

        store.addEstimate(estimate)

        selectedLeadNumber = ""
        serviceType = .windowCleaning
        otherService = ""
        serviceDetails = ""
        subtotal = ""
        discount = ""
        salesperson = ""
        status = .draft
        expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    private func customerName(_ customer: Customer) -> String {
        let name = customer.businessName.isEmpty ? customer.contactName : customer.businessName
        return "\(name) - \(customer.customerNumber)"
    }

    private func leadName(_ lead: Lead) -> String {
        if !lead.businessName.isEmpty { return lead.businessName }
        if !lead.contactName.isEmpty { return lead.contactName }
        return "Unnamed Lead"
    }

    private func serviceName(for estimate: EstimateRecord) -> String {
        if estimate.serviceType == .other {
            return estimate.otherService.isEmpty ? "Other" : estimate.otherService
        }

        return estimate.serviceType.rawValue
    }
}
