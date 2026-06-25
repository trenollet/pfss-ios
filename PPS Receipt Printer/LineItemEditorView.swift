//
//  LineItemEditorView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/25/26.
//

import SwiftUI

struct LineItemEditorView: View {
    @Binding var lineItems: [ServiceLineItem]

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

    var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    var body: some View {
        Section("Line Items") {
            ForEach(lineItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.description.isEmpty ? serviceName(for: item) : item.description)
                        .font(.headline)

                    Text("\(item.quantity, specifier: "%.2f") × \(item.unitPrice, format: .currency(code: "USD"))")
                        .font(.caption)

                    Text("Total: \(item.lineTotal, format: .currency(code: "USD"))")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteItems)

            Picker("Service Type", selection: $serviceType) {
                ForEach(ServiceType.allCases) { service in
                    Text(service.rawValue).tag(service)
                }
            }

            if serviceType == .other {
                TextField("Other Service", text: $otherService)
                    .focused($isInputFocused)
            }

            TextField("Description", text: $itemDescription)
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

            Button("Add Line Item") {
                addLineItem()
            }

            HStack {
                Text("Subtotal")
                Spacer()
                Text(subtotal, format: .currency(code: "USD"))
                    .bold()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
    }

    private func addLineItem() {
        let item = ServiceLineItem(
            serviceType: serviceType,
            otherService: otherService,
            description: itemDescription,
            quantity: quantityValue,
            unitPrice: unitPriceValue,
            lineTotal: lineTotal
        )

        lineItems.append(item)

        serviceType = .windowCleaning
        otherService = ""
        itemDescription = ""
        quantity = "1"
        unitPrice = ""
        isInputFocused = false
    }

    private func deleteItems(at offsets: IndexSet) {
        lineItems.remove(atOffsets: offsets)
    }

    private func serviceName(for item: ServiceLineItem) -> String {
        if item.serviceType == .other {
            return item.otherService.isEmpty ? "Other" : item.otherService
        }

        return item.serviceType.rawValue
    }
}
