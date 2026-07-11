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

    @State private var lineItems: [ServiceLineItem] = []
    @State private var discount = ""

    @State private var salesperson = ""
    @State private var status: EstimateRecordStatus = .draft
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var showArchived = false

    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case catalogPicker
        case editLineItem(ServiceLineItem)

        var id: String {
            switch self {
            case .catalogPicker:
                return "catalogPicker"

            case .editLineItem(let item):
                return "editLineItem-\(item.id)"
            }
        }
    }

    private var subtotalValue: Double {
        PricingCalculator.subtotal(for: lineItems)
    }

    private var discountValue: Double {
        Double(discount) ?? 0
    }

    private var totalValue: Double {
        PricingCalculator.total(for: lineItems, discount: discountValue)
    }

    private var availableSites: [CustomerSite] {
        store.activeSites.filter { $0.customerNumber == selectedCustomerNumber }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Estimate") {
                    Picker("Lead", selection: $selectedLeadNumber) {
                        Text("None").tag("")
                        ForEach(store.activeLeads) { lead in
                            Text("\(lead.leadNumber) - \(leadName(lead))")
                                .tag(lead.leadNumber)
                        }
                    }

                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.activeCustomers) { customer in
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

                    TextField("Salesperson", text: $salesperson)
                        .focused($isInputFocused)

                    Picker("Status", selection: $status) {
                        ForEach(EstimateRecordStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                }

                WorkOrderEditorView(
                    lineItems: $lineItems,
                    isInputFocused: $isInputFocused,
                    onAddLineItem: {
                        PresentationDebug.log("New estimate requested catalog picker")
                        activeSheet = .catalogPicker
                    },
                    onEditLineItem: { item in
                        PresentationDebug.log(
                            "New estimate requested editor for \(item.id)"
                        )
                        activeSheet = .editLineItem(item)
                    }
                )

                Section("Pricing") {
                    TextField("Discount", text: $discount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    HStack {
                        Text("Subtotal")
                        Spacer()
                        Text(subtotalValue, format: .currency(code: "USD"))
                            .bold()
                    }

                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalValue, format: .currency(code: "USD"))
                            .bold()
                    }
                }

                Section {
                    Button("Add Estimate") {
                        isInputFocused = false
                        addEstimate()
                    }
                    .disabled(selectedCustomerNumber.isEmpty || lineItems.isEmpty)
                }

                Section("Estimates") {
                    Toggle("Show Archived", isOn: $showArchived)

                    ForEach(showArchived ? store.archivedEstimates : store.activeEstimates) { estimate in
                        NavigationLink {
                            EstimateDetailView(estimate: estimate)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(estimate.estimateNumber)
                                    .font(.headline)

                                Text("Customer: \(customerDisplayName(for: estimate.customerNumber))")
                                    .font(.caption)

                                Text("Total: \(estimate.total, format: .currency(code: "USD"))")
                                    .font(.caption)

                                Text("Status: \(estimate.status.rawValue)")
                                    .font(.caption)

                                if estimate.lifecycleStatus == .archived {
                                    Text("Archived")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .catalogPicker:
                    ServiceCatalogPickerView(
                        lineItems: $lineItems,
                        onFinished: {
                            activeSheet = nil
                        }
                    )
                    .environmentObject(store)

                case .editLineItem(let item):
                    EditableLineItemView(
                        lineItems: $lineItems,
                        catalogItem: nil,
                        existingLineItem: item
                    )
                    .environmentObject(store)
                }
            }
        }
    }

    private func addEstimate() {
        let firstItem = lineItems.first

        let estimate = EstimateRecord(
            estimateNumber: store.generateEstimateNumber(),
            leadNumber: selectedLeadNumber,
            customerNumber: selectedCustomerNumber,
            siteID: selectedSiteID,
            serviceType: firstItem?.serviceType ?? .other,
            otherService: firstItem?.otherService ?? "",
            serviceDetails: lineItems.map { item in
                item.description.isEmpty ? serviceName(for: item) : item.description
            }.joined(separator: "\n"),
            lineItems: lineItems,
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
        selectedCustomerNumber = ""
        selectedSiteID = nil
        lineItems = []
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
    private func customerDisplayName(for customerNumber: String) -> String {
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
    private func serviceName(for item: ServiceLineItem) -> String {
        if item.serviceType == .other {
            return item.otherService.isEmpty ? "Other" : item.otherService
        }

        return item.serviceType.rawValue
    }
}
