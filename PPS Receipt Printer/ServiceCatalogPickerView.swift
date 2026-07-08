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

    var onFinished: () -> Void

    @State private var searchText = ""
    @State private var showingNewCatalogItem = false
    @State private var showingCustomItem = false
    @State private var selectedCatalogItem: ServiceCatalogItem?

    private var filteredItems: [ServiceCatalogItem] {
        let rankedItems = CatalogRankingEngine.rankedItems(
            query: searchText,
            catalogItems: store.activeServiceCatalogItems
        )

        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rankedItems
        }

        let recommendedIDs = Set(recommendedItems.map { $0.id })

        return rankedItems.filter {
            !recommendedIDs.contains($0.id)
        }
    }

    private var recommendedItems: [ServiceCatalogItem] {
        RecommendationEngine.recommendedCatalogItems(
            currentLineItems: lineItems,
            catalogItems: store.activeServiceCatalogItems,
            recommendationRules: store.recommendationRules
        )
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

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !recommendedItems.isEmpty {
                    Section("Recommended for This Work Order") {
                        ForEach(recommendedItems.prefix(5)) { item in
                            Button {
                                selectedCatalogItem = item
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
                                }
                                .padding(.vertical, 4)
                            }
                        }
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
                                selectedCatalogItem = item
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
            .sheet(item: $selectedCatalogItem) { item in
                EditableLineItemView(
                    lineItems: $lineItems,
                    catalogItem: item,
                    existingLineItem: nil,
                    onFinished: {
                        onFinished()
                    }
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showingNewCatalogItem) {
                ServiceCatalogNewItemView(
                    prefilledItemName: suggestedNewItemName
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showingCustomItem) {
                CustomLineItemView(
                    lineItems: $lineItems,
                    onFinished: {
                        onFinished()
                    }
                )
            }
        }
    }
}
