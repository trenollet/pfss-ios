//
//  LineItemEditorView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/25/26.
//

import SwiftUI

struct LineItemEditorView: View {
    @EnvironmentObject var store: AppDataStore

    @Binding var lineItems: [ServiceLineItem]
    @FocusState.Binding var isInputFocused: Bool

    @State private var catalogSearchText = ""
    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var itemDescription = ""
    @State private var quantity = "1"
    @State private var unitPrice = ""

    private var quantityValue: Double {
        Double(quantity) ?? 1
    }

    private var unitPriceValue: Double {
        Double(unitPrice) ?? 0
    }

    private var lineTotal: Double {
        PricingCalculator.total(
            subtotal: quantityValue * unitPriceValue,
            discount: 0
        )
    }

    private var subtotal: Double {
        PricingCalculator.subtotal(for: lineItems)
    }

    private var filteredCatalogItems: [ServiceCatalogItem] {
        let search = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let source = store.activeServiceCatalogItems

        let results: [ServiceCatalogItem]

        if search.isEmpty {
            results = source
        } else {
            results = source.filter { item in
                item.itemName.localizedCaseInsensitiveContains(search)
                || item.itemDescription.localizedCaseInsensitiveContains(search)
            }
        }

        return results.sorted {
            if $0.usageCount != $1.usageCount {
                return $0.usageCount > $1.usageCount
            }

            return ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast)
        }
    }

    var body: some View {
        Section("Line Items") {
            ForEach(lineItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.description.isEmpty ? serviceName(for: item) : item.description)
                        .font(.headline)

                    Text("\(item.quantity, specifier: "%.2f") × \(item.unitPrice, format: .currency(code: "USD"))")
                        .font(.caption)

                    Text("Total: \(item.lineTotal, format: .currency(code: "USD"))")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteItems)

            TextField("Search Catalog", text: $catalogSearchText)
                .focused($isInputFocused)

            if !filteredCatalogItems.isEmpty {
                ForEach(filteredCatalogItems.prefix(5)) { catalogItem in
                    Button {
                        addCatalogItem(catalogItem)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(catalogItem.itemName)
                                .font(.headline)

                            if !catalogItem.itemDescription.isEmpty {
                                Text(catalogItem.itemDescription)
                                    .font(.caption)
                            }

                            Text("\(catalogItem.defaultQuantity, specifier: "%.2f") × \(catalogItem.defaultPrice, format: .currency(code: "USD"))")
                                .font(.caption)
                        }
                        .padding(.vertical, 3)
                    }
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

            TextField("Custom Description", text: $itemDescription)
                .focused($isInputFocused)

            TextField("Quantity", text: $quantity)
                .keyboardType(.decimalPad)
                .focused($isInputFocused)

            TextField("Unit Price", text: $unitPrice)
                .keyboardType(.decimalPad)
                .focused($isInputFocused)

            HStack {
                Text("Line Total")
                Spacer()
                Text(lineTotal, format: .currency(code: "USD"))
                    .bold()
            }

            Button("Add Custom Line Item") {
                addCustomLineItem()
            }

            HStack {
                Text("Subtotal")
                Spacer()
                Text(subtotal, format: .currency(code: "USD"))
                    .bold()
            }
        }
    }

    private func addCatalogItem(_ catalogItem: ServiceCatalogItem) {
        let lineTotal = catalogItem.defaultQuantity * catalogItem.defaultPrice

        let item = ServiceLineItem(
            catalogItemID: catalogItem.id,
            serviceType: .other,
            otherService: catalogItem.itemName,
            description: catalogItem.itemDescription,
            quantity: catalogItem.defaultQuantity,
            unitPrice: catalogItem.defaultPrice,
            lineTotal: lineTotal
        )

        lineItems.append(item)
        store.recordCatalogItemUsed(catalogItem)

        catalogSearchText = ""
        isInputFocused = false
    }

    private func addCustomLineItem() {
        let item = ServiceLineItem(
            catalogItemID: nil,
            serviceType: serviceType,
            otherService: otherService,
            description: itemDescription,
            quantity: quantityValue,
            unitPrice: unitPriceValue,
            lineTotal: lineTotal
        )

        lineItems.append(item)

        serviceType = .windowCleaning
        otherService = ""
        itemDescription = ""
        quantity = "1"
        unitPrice = ""
        isInputFocused = false
    }

    private func deleteItems(at offsets: IndexSet) {
        lineItems.remove(atOffsets: offsets)
    }

    private func serviceName(for item: ServiceLineItem) -> String {
        if item.serviceType == .other {
            return item.otherService.isEmpty ? "Other" : item.otherService
        }

        return item.serviceType.rawValue
    }
}
