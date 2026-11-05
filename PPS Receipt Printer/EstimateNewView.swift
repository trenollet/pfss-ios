//
//  EstimatesView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct EstimateNewView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLeadNumber = ""
    @State private var selectedCustomerNumber = ""
    @State private var selectedSiteID: UUID?

    @State private var lineItems: [ServiceLineItem] = []
    @State private var discountMethod: PricingDiscountMethod = .fixedAmount
    @State private var discountInputValue: Double = 0

    @State private var salesperson = ""
    @State private var status: EstimateRecordStatus = .draft
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 31, to: Date()) ?? Date()
    @State private var estimateTitle = ""
    @State private var scopeOfWork = ""

    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?
    @State private var compactEditorDestination: CompactWorkOrderEditorDestination?

    init(
        preselectedCustomerNumber: String = "",
        preselectedSiteID: UUID? = nil,
        initialLineItems: [ServiceLineItem] = []
    ) {
        _selectedCustomerNumber = State(
            initialValue: preselectedCustomerNumber
        )
        _selectedSiteID = State(initialValue: preselectedSiteID)
        _lineItems = State(initialValue: initialLineItems)
    }

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
        DiscountCalculator.amount(
            subtotal: subtotalValue,
            method: discountMethod,
            inputValue: discountInputValue
        )
    }

    private var totalValue: Double {
        PricingCalculator.total(for: lineItems, discount: discountValue)
    }

    private var availableSites: [CustomerSite] {
        store.activeSites.filter { $0.customerNumber == selectedCustomerNumber }
    }

    private var customerOptions: [RecordSelectionOption] {
        store.activeCustomers
            .sorted { customerName($0).localizedCaseInsensitiveCompare(customerName($1)) == .orderedAscending }
            .map {
                RecordSelectionOption(
                    id: $0.customerNumber,
                    title: customerName($0),
                    subtitle: $0.customerNumber
                )
            }
    }

    private var leadOptions: [RecordSelectionOption] {
        store.activeLeads
            .sorted { leadName($0).localizedCaseInsensitiveCompare(leadName($1)) == .orderedAscending }
            .map {
                RecordSelectionOption(
                    id: $0.leadNumber,
                    title: leadName($0),
                    subtitle: $0.leadNumber
                )
            }
    }

    private var salesEmployees: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.hasRole(.salesperson) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var hasValidEstimateRecipient: Bool {
        !selectedLeadNumber.isEmpty ||
        (!selectedCustomerNumber.isEmpty && selectedSiteID != nil)
    }

    var body: some View {
        Form {
                CompactCustomerInfoSection(
                    leadNumber: $selectedLeadNumber,
                    customerNumber: $selectedCustomerNumber,
                    siteID: $selectedSiteID,
                    salesperson: $salesperson,
                    expirationDate: $expirationDate,
                    onSelect: { compactEditorDestination = .customerInfo }
                )

                CompactTitleSection(
                    title: $estimateTitle,
                    onSelect: { compactEditorDestination = .title }
                )

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(EstimateRecordStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
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

                CompactPricingSection(
                    method: $discountMethod,
                    inputValue: $discountInputValue,
                    subtotal: subtotalValue,
                    onSelect: { compactEditorDestination = .pricing }
                )

                CompactScopeSection(
                    scope: $scopeOfWork,
                    onSelect: { compactEditorDestination = .scope }
                )

            }
            .navigationTitle("New Estimate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                EditorKeyboardDismissAction(isVisible: isInputFocused) {
                    isInputFocused = false
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isInputFocused = false
                        addEstimate()
                    }
                    .disabled(!hasValidEstimateRecipient || lineItems.isEmpty)
                }
            }
            .compactWorkOrderEditorSheet(
                destination: $compactEditorDestination,
                leadNumber: $selectedLeadNumber,
                customerNumber: $selectedCustomerNumber,
                siteID: $selectedSiteID,
                salesperson: $salesperson,
                expirationDate: $expirationDate,
                title: $estimateTitle,
                discountMethod: $discountMethod,
                discountInputValue: $discountInputValue,
                subtotal: subtotalValue,
                scope: $scopeOfWork,
                store: store
            )
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

    private func addEstimate() {
        let firstItem = lineItems.first

        let estimate = EstimateRecord(
            estimateNumber: store.generateEstimateNumber(),
            title: estimateTitle.trimmingCharacters(in: .whitespacesAndNewlines),
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
            expirationDate: expirationDate,
            scopeOfWork: scopeOfWork.trimmingCharacters(in: .whitespacesAndNewlines),
            discountMethod: discountMethod,
            discountInputValue: discountInputValue
        )

        store.addEstimate(estimate)
        dismiss()

        selectedLeadNumber = ""
        selectedCustomerNumber = ""
        selectedSiteID = nil
        lineItems = []
        discountMethod = .fixedAmount
        discountInputValue = 0
        salesperson = ""
        status = .draft
        expirationDate = Calendar.current.date(byAdding: .day, value: 31, to: Date()) ?? Date()
        estimateTitle = ""
        scopeOfWork = ""
    }

    private func customerName(_ customer: Customer) -> String {
        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return "Unnamed Customer"
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
