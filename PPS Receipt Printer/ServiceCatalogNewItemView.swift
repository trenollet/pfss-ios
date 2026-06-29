//
//  ServiceCatalogNewItemView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct ServiceCatalogNewItemView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    var prefilledItemName: String = ""

    @State private var itemName = ""
    @State private var itemDescription = ""
    @State private var defaultQuantity = "1"
    @State private var defaultPrice = ""

    @FocusState private var isInputFocused: Bool

    private var quantityValue: Double {
        Double(defaultQuantity) ?? 1
    }

    private var priceValue: Double {
        Double(defaultPrice) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Catalog Item") {
                    TextField("Item Name", text: $itemName)
                        .focused($isInputFocused)

                    TextField("Item Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isInputFocused)

                    TextField("Default Quantity", text: $defaultQuantity)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    TextField("Default Price", text: $defaultPrice)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                }

                Section {
                    Button("Save Catalog Item") {
                        let item = ServiceCatalogItem(
                            itemName: itemName,
                            itemDescription: itemDescription,
                            defaultQuantity: quantityValue,
                            defaultPrice: priceValue
                        )

                        store.addServiceCatalogItem(item)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("New Catalog Item")
            .onAppear {
                if itemName.isEmpty {
                    itemName = prefilledItemName
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
        }
    }
}
