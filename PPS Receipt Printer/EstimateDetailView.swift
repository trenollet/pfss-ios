//
//  EstimateDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct EstimateDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var estimate: EstimateRecord
    @FocusState private var isInputFocused: Bool
    
    @State private var activeSheet: ActiveSheet?
    @State private var sharedPDFURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isShowingPDFError = false

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
        PricingCalculator.subtotal(for: estimate)
    }

    private var totalValue: Double {
        PricingCalculator.total(for: estimate)
    }

    private var availableSites: [CustomerSite] {
        store.sites.filter {
            $0.customerNumber == estimate.customerNumber &&
            ($0.lifecycleStatus == .active || $0.id == estimate.siteID)
        }
    }

    var body: some View {
        Form {
            Section("Estimate") {
                Text(estimate.estimateNumber)
                    .font(.headline)

                Text("Customer #: \(estimate.customerNumber)")

                Picker("Site", selection: $estimate.siteID) {
                    Text("No site selected").tag(UUID?.none)
                    ForEach(availableSites) { site in
                        Text(siteDisplayName(site)).tag(Optional(site.id))
                    }
                }

                if !estimate.leadNumber.isEmpty {
                    Text("Lead: \(estimate.leadNumber)")
                }

                Picker("Status", selection: $estimate.status) {
                    ForEach(EstimateRecordStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                DatePicker("Expiration Date", selection: $estimate.expirationDate, displayedComponents: .date)
            }

            WorkOrderEditorView(
                lineItems: $estimate.lineItems,
                isInputFocused: $isInputFocused,
                onAddLineItem: {
                    PresentationDebug.log("Estimate detail requested catalog picker")
                    activeSheet = .catalogPicker
                },
                onEditLineItem: { item in
                    PresentationDebug.log(
                        "Estimate detail requested editor for \(item.id)"
                    )
                    activeSheet = .editLineItem(item)
                }
            )

            Section("Pricing") {
                TextField("Discount", value: $estimate.discount, format: .number)
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
                Section("Scheduling") {
                    HStack {
                        Text("Estimated Labor")

                        Spacer()

                        Text(
                            SchedulingCalculator.formattedDuration(
                                for: estimate.lineItems
                            )
                        )
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    }
                }
            }

            Section {
                Button {
                    createAndSharePDF()
                } label: {
                    HStack {
                        Spacer()

                        Label(
                            "Share Estimate",
                            systemImage: "square.and.arrow.up"
                        )

                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Create Job from Estimate") {
                    estimate.lineItems = PricingCalculator.updatedLineItems(estimate.lineItems)
                    estimate.subtotal = subtotalValue
                    estimate.total = totalValue

                    store.updateEstimate(estimate)
                    store.createJobFromEstimate(estimate)
                    dismiss()
                }
                .disabled(estimate.lifecycleStatus == .archived)

                if estimate.lifecycleStatus == .archived {
                    Button("Restore Estimate") {
                        store.restoreEstimate(estimate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Estimate", role: .destructive) {
                        store.archiveEstimate(estimate)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Estimate")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveEstimate()
                }
            }

            if isInputFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss Keyboard")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .catalogPicker:
                ServiceCatalogPickerView(
                    lineItems: $estimate.lineItems,
                    onFinished: {
                        activeSheet = nil
                    }
                )
                .environmentObject(store)

            case .editLineItem(let item):
                EditableLineItemView(
                    lineItems: $estimate.lineItems,
                    catalogItem: nil,
                    existingLineItem: item
                )
                .environmentObject(store)
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
            "Unable to Share Estimate",
            isPresented: $isShowingPDFError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                pdfErrorMessage ??
                "The estimate PDF could not be created."
            )
        }
    }

    private func siteDisplayName(_ site: CustomerSite) -> String {
        if site.siteName.isEmpty { return site.serviceAddress }
        if site.serviceAddress.isEmpty { return site.siteName }
        return "\(site.siteName) — \(site.serviceAddress)"
    }

    private func saveEstimate() {
        isInputFocused = false

        estimate.lineItems = PricingCalculator.updatedLineItems(estimate.lineItems)
        estimate.subtotal = PricingCalculator.subtotal(for: estimate)
        estimate.total = PricingCalculator.total(for: estimate)

        if let firstItem = estimate.lineItems.first {
            estimate.serviceType = firstItem.serviceType
            estimate.otherService = firstItem.otherService
        }

        estimate.serviceDetails = estimate.lineItems.map { item in
            item.description.isEmpty ? serviceName(for: item) : item.description
        }.joined(separator: "\n")

        store.updateEstimate(estimate)
        dismiss()
    }

    private func createAndSharePDF() {
        isInputFocused = false

        estimate.lineItems = PricingCalculator.updatedLineItems(
            estimate.lineItems
        )

        estimate.subtotal = PricingCalculator.subtotal(
            for: estimate
        )

        estimate.total = PricingCalculator.total(
            for: estimate
        )

        let customer = store.customers.first(where: {
            $0.customerNumber == estimate.customerNumber
        })

        let site: CustomerSite?

        if let siteID = estimate.siteID {
            site = store.sites.first(where: {
                $0.id == siteID
            })
        } else {
            site = nil
        }

        do {
            let pdfURL = try EstimatePDFRenderer.createPDF(
                estimate: estimate,
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
    
    private func serviceName(for item: ServiceLineItem) -> String {
        if item.serviceType == .other {
            return item.otherService.isEmpty ? "Other" : item.otherService
        }

        return item.serviceType.rawValue
    }
}
