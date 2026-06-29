//
//  ServiceCatalogDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct ServiceCatalogDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var item: ServiceCatalogItem
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("Catalog Item") {
                TextField("Item Name", text: $item.itemName)
                    .focused($isInputFocused)

                TextField("Item Description", text: $item.itemDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($isInputFocused)

                TextField("Default Quantity", value: $item.defaultQuantity, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)

                TextField("Default Price", value: $item.defaultPrice, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
            }

            Section("Usage") {
                Text("Used \(item.usageCount) times")

                if let lastUsedDate = item.lastUsedDate {
                    Text("Last Used: \(lastUsedDate.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Last Used: Never")
                }
            }

            Section {
                Button("Save Changes") {
                    isInputFocused = false
                    store.updateServiceCatalogItem(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                if item.lifecycleStatus == .archived {
                    Button("Restore Catalog Item") {
                        store.restoreServiceCatalogItem(item)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Catalog Item", role: .destructive) {
                        store.archiveServiceCatalogItem(item)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Catalog Item")
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
