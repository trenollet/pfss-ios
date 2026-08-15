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
        List {
                Section {
                    if store.canManageCompany {
                        Button("Add New Catalog Item") {
                            showingNewItemForm = true
                        }
                    }

                    Toggle("Show Archived", isOn: $showArchived)
                }

                Section("Catalog Items") {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            ServiceCatalogDetailView(item: item)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: symbolName(for: item.itemType))
                                    .font(.title2)
                                    .frame(width: 30)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.itemName)
                                        .font(.headline)

                                    if !item.itemDescription.isEmpty {
                                        Text(item.itemDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Text("\(item.itemType.rawValue) • \(item.taxTreatment.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    HStack {
                                        Text(
                                            "\(item.defaultQuantity, specifier: "%.2f") × \(item.defaultPrice, format: .currency(code: "USD"))"
                                        )
                                        .font(.caption)
                                        .fontWeight(.medium)

                                        Spacer()

                                        Text("Used \(item.usageCount)×")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if item.lifecycleStatus == .archived {
                                        Text("Archived")
                                            .foregroundStyle(.red)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Catalog")
            .searchable(text: $searchText, prompt: "Search catalog")
            .sheet(isPresented: $showingNewItemForm) {
                ServiceCatalogNewItemView()
                    .environmentObject(store)
        }
    }
    private func symbolName(for itemType: CatalogItemType) -> String {
        switch itemType {
        case .service:
            return "wrench.and.screwdriver.fill"

        case .material:
            return "shippingbox.fill"

        case .fee:
            return "receipt.fill"
        }
    }
}
