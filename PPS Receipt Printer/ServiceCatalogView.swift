//
//  ServiceCatalogView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct ServiceCatalogView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingNewItemForm = false

    private var filteredItems: [ServiceCatalogItem] {
        let source = showArchived ? store.archivedServiceCatalogItems : store.activeServiceCatalogItems

        return CatalogRankingEngine.rankedItems(
            query: searchText,
            catalogItems: source
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add New Catalog Item") {
                        showingNewItemForm = true
                    }

                    Toggle("Show Archived", isOn: $showArchived)
                }

                Section("Catalog Items") {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            ServiceCatalogDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.itemName)
                                    .font(.headline)

                                if !item.itemDescription.isEmpty {
                                    Text(item.itemDescription)
                                        .font(.caption)
                                }

                                Text("Default: \(item.defaultQuantity, specifier: "%.2f") × \(item.defaultPrice, format: .currency(code: "USD"))")
                                    .font(.caption)

                                Text("Used \(item.usageCount) times")
                                    .font(.caption)

                                if item.lifecycleStatus == .archived {
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
            .navigationTitle("Service Catalog")
            .searchable(text: $searchText, prompt: "Search services")
            .sheet(isPresented: $showingNewItemForm) {
                ServiceCatalogNewItemView()
                    .environmentObject(store)
            }
        }
    }
}
