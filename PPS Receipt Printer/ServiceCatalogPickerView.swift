//
//  ServiceCatalogPickerView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct ServiceCatalogPickerView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @Binding var lineItems: [ServiceLineItem]

    @State private var searchText = ""
    @State private var showingNewCatalogItem = false
    @State private var showingCustomItem = false

    private var filteredItems: [ServiceCatalogItem] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var suggestedNewItemName: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingCustomItem = true
                    } label: {
                        Label("Custom Line Item", systemImage: "square.and.pencil")
                    }

                    Button {
                        showingNewCatalogItem = true
                    } label: {
                        Label(
                            suggestedNewItemName.isEmpty
                            ? "New Catalog Item"
                            : "Create \"\(suggestedNewItemName)\"",
                            systemImage: "plus.circle"
                        )
                    }
                }

                if filteredItems.isEmpty {
                    Section {
                        Text("No matching catalog items.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(searchText.isEmpty ? "Most Used Services" : "Search Results") {
                        ForEach(filteredItems) { item in
                            Button {
                                addCatalogItem(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.itemName)
                                        .font(.headline)

                                    if !item.itemDescription.isEmpty {
                                        Text(item.itemDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text("\(item.defaultQuantity, specifier: "%.2f") × \(item.defaultPrice, format: .currency(code: "USD"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if item.usageCount > 0 {
                                        Text("Used \(item.usageCount) times")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Service")
            .searchable(text: $searchText, prompt: "Search services")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingNewCatalogItem) {
                ServiceCatalogNewItemView(
                    prefilledItemName: suggestedNewItemName
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showingCustomItem) {
                CustomLineItemView(lineItems: $lineItems)
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
        dismiss()
    }
}
