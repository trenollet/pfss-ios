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
                    SelectAllDecimalField(
                        placeholder: "Quantity",
                        value: $item.defaultQuantity
                    )
                    .focused($isInputFocused)
                }

                LabeledContent("Price") {
                    SelectAllDecimalField(
                        placeholder: "Price",
                        value: $item.defaultPrice
                    )
                    .focused($isInputFocused)
                }

                LabeledContent("Estimated Minutes Per Unit") {
                    SelectAllIntegerField(
                        placeholder: "Minutes",
                        value: $item.estimatedMinutesPerUnit
                    )
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
                    Button {
                        store.restoreServiceCatalogItem(item)
                        dismiss()
                    } label: {
                        Label("Restore Catalog Item", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveServiceCatalogItem(item)
                        dismiss()
                    } label: {
                        CenteredArchiveActionLabel(title: "Archive Catalog Item")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .navigationTitle("Edit Catalog Item")
        .toolbar {
            EditorKeyboardDismissAction(isVisible: isInputFocused) {
                isInputFocused = false
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isInputFocused = false
                    store.updateServiceCatalogItem(item)
                    dismiss()
                }
            }

        }
    }
}
