//
//  EditableLineItemView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct EditableLineItemView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @Binding var lineItems: [ServiceLineItem]

    let catalogItem: ServiceCatalogItem?
    let existingLineItem: ServiceLineItem?
    var onFinished: (() -> Void)? = nil

    @State private var itemName = ""
    @State private var itemDescription = ""
    @State private var quantity = "1"
    @State private var unitPrice = ""
    @State private var estimatedMinutesPerUnit = ""

    @FocusState private var isInputFocused: Bool

    private var isEditingExisting: Bool {
        existingLineItem != nil
    }

    private var quantityValue: Double {
        Double(quantity) ?? 1
    }

    private var unitPriceValue: Double {
        Double(unitPrice) ?? 0
    }
    private var estimatedMinutesValue: Int {
        max(Int(estimatedMinutesPerUnit) ?? 0, 0)
    }

    private var lineTotal: Double {
        quantityValue * unitPriceValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Line Item") {
                    TextField("Item Name", text: $itemName)
                        .focused($isInputFocused)

                    TextField("Item Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isInputFocused)

                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    TextField("Unit Price", text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                    
                    LabeledContent("Estimated Minutes Per Unit") {
                        TextField(
                            "Minutes",
                            text: $estimatedMinutesPerUnit
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                    }

                    HStack {
                        Text("Line Total")
                        Spacer()
                        Text(lineTotal, format: .currency(code: "USD"))
                            .bold()
                    }
                }

            }
            .navigationTitle(isEditingExisting ? "Edit Line Item" : "New Line Item")
            .onAppear {
                loadDefaults()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLineItem()
                    }
                    .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func loadDefaults() {
        guard itemName.isEmpty else { return }

        if let existingLineItem {
            if !existingLineItem.otherService.isEmpty {
                itemName = existingLineItem.otherService
            } else if let catalogItemID = existingLineItem.catalogItemID,
                      let catalogItem = store.serviceCatalogItems.first(where: { $0.id == catalogItemID }) {
                itemName = catalogItem.itemName
            }

            itemDescription = existingLineItem.description
            quantity = String(format: "%.2f", existingLineItem.quantity)
            unitPrice = String(format: "%.2f", existingLineItem.unitPrice)
            estimatedMinutesPerUnit = String(
                existingLineItem.estimatedMinutesPerUnit
            )
            return
        }

        if let catalogItem {
            itemName = catalogItem.itemName
            itemDescription = catalogItem.itemDescription
            quantity = String(format: "%.2f", catalogItem.defaultQuantity)
            unitPrice = String(format: "%.2f", catalogItem.defaultPrice)
            estimatedMinutesPerUnit = String(
                catalogItem.estimatedMinutesPerUnit
            )
        }
    }

    private func saveLineItem() {
        let updatedItem = ServiceLineItem(
            id: existingLineItem?.id ?? UUID(),
            catalogItemID: catalogItem?.id ?? existingLineItem?.catalogItemID,
            serviceType: .other,
            otherService: itemName,
            description: itemDescription,
            quantity: quantityValue,
            unitPrice: unitPriceValue,
            lineTotal: lineTotal,
            estimatedMinutesPerUnit: estimatedMinutesValue
        )

        if let existingLineItem,
           let index = lineItems.firstIndex(where: { $0.id == existingLineItem.id }) {
            lineItems[index] = updatedItem
        } else {
            lineItems.append(updatedItem)

            if let catalogItem {
                store.recordCatalogItemUsed(catalogItem)
            }
        }

        dismiss()
    }
}
