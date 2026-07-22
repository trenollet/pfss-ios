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
                Picker("Item Type", selection: $item.itemType) {
                    ForEach(CatalogItemType.allCases) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }

                TextField("Item Name", text: $item.itemName)
                    .focused($isInputFocused)
                
                
                TextField("Item Description", text: $item.itemDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($isInputFocused)

                LabeledContent("Quantity") {
                    TextField(
                        "Quantity",
                        value: $item.defaultQuantity,
                        format: .number
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
                }

                LabeledContent("Price") {
                    TextField(
                        "Price",
                        value: $item.defaultPrice,
                        format: .currency(code: "USD")
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
                }

                LabeledContent("Estimated Minutes Per Unit") {
                    TextField(
                        "Minutes",
                        value: $item.estimatedMinutesPerUnit,
                        format: .number
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .focused($isInputFocused)
                }

                Picker(
                    "Tax Treatment",
                    selection: $item.taxTreatment
                ) {
                    ForEach(TaxTreatment.allCases) { treatment in
                        Text(treatment.rawValue)
                            .tag(treatment)
                    }
                }
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isInputFocused = false
                    store.updateServiceCatalogItem(item)
                    dismiss()
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
    }
}
