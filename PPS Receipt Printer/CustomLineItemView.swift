//
//  CustomLineItemView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct CustomLineItemView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var lineItems: [ServiceLineItem]
    var onFinished: (() -> Void)? = nil

    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var itemDescription = ""
    @State private var quantity = "1"
    @State private var unitPrice = ""

    @FocusState private var isInputFocused: Bool

    private var quantityValue: Double {
        Double(quantity) ?? 1
    }

    private var unitPriceValue: Double {
        Double(unitPrice) ?? 0
    }

    private var lineTotal: Double {
        quantityValue * unitPriceValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom Line Item") {
                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }

                    if serviceType == .other {
                        TextField("Other Service", text: $otherService)
                            .focused($isInputFocused)
                    }

                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isInputFocused)

                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    TextField("Unit Price", text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    HStack {
                        Text("Line Total")
                        Spacer()
                        Text(lineTotal, format: .currency(code: "USD"))
                            .bold()
                    }
                }

                Section {
                    Button("Add Line Item") {
                        addLineItem()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Custom Item")
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

    private func addLineItem() {
        let item = ServiceLineItem(
            catalogItemID: nil,
            serviceType: serviceType,
            otherService: otherService,
            description: itemDescription,
            quantity: quantityValue,
            unitPrice: unitPriceValue,
            lineTotal: lineTotal
        )

        lineItems.append(item)
        dismiss()
    }
}
