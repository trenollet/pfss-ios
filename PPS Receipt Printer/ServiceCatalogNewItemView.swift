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
    @State private var estimatedMinutesPerUnit = ""
    @State private var itemType: CatalogItemType = .service
    @State private var taxTreatment: TaxTreatment = .nonTaxable

    @FocusState private var isInputFocused: Bool

    private var quantityValue: Double {
        Double(defaultQuantity) ?? 1
    }

    private var priceValue: Double {
        Double(defaultPrice) ?? 0
    }
    private var estimatedMinutesValue: Double {
        max(Double(estimatedMinutesPerUnit) ?? 0, 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Catalog Item") {
                    Picker("Item Type", selection: $itemType) {
                        ForEach(CatalogItemType.allCases) { type in
                            Text(type.rawValue)
                                .tag(type)
                        }
                    }
                    TextField("Item Name", text: $itemName)
                        .focused($isInputFocused)

                    TextField("Item Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isInputFocused)
                

                    LabeledContent("Default Quantity") {
                        SelectAllTextField(
                            placeholder: "Quantity",
                            text: $defaultQuantity
                        )
                        .frame(minWidth: 90, minHeight: 30)
                        .focused($isInputFocused)
                    }

                    LabeledContent("Price") {
                        SelectAllTextField(
                            placeholder: "Price",
                            text: $defaultPrice
                        )
                        .frame(minWidth: 90, minHeight: 30)
                        .focused($isInputFocused)
                    }
                    
                    LabeledContent("Estimated Minutes Per Unit") {
                        SelectAllTextField(
                            placeholder: "Minutes",
                            text: $estimatedMinutesPerUnit,
                            keyboardType: .decimalPad
                        )
                        .frame(minWidth: 90, minHeight: 30)
                        .focused($isInputFocused)
                    }
                    
                    Picker("Tax Treatment", selection: $taxTreatment) {
                        ForEach(TaxTreatment.allCases) { treatment in
                            Text(treatment.rawValue)
                                .tag(treatment)
                        }
                    }
                }

                Section {
                    Text("Tax treatment is copied into each estimate, Job, and invoice line when used. Later catalog changes do not rewrite existing transactions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                EditorKeyboardDismissAction(isVisible: isInputFocused) {
                    isInputFocused = false
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCatalogItem()
                    }
                    .disabled(
                        itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !store.canManageCompany
                    )
                }

            }
        }
    }

    private func saveCatalogItem() {
        guard store.canManageCompany else { return }
        let item = ServiceCatalogItem(
            itemName: itemName,
            itemDescription: itemDescription,
            defaultQuantity: quantityValue,
            defaultPrice: priceValue,
            estimatedMinutesPerUnit: estimatedMinutesValue,
            itemType: itemType,
            taxTreatment: taxTreatment
        )

        store.addServiceCatalogItem(item)
        dismiss()
    }
}
