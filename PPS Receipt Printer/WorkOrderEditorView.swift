//
//  WorkOrderEditorView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct WorkOrderEditorView: View {
    @EnvironmentObject private var store: AppDataStore

    @Binding var lineItems: [ServiceLineItem]
    @FocusState.Binding var isInputFocused: Bool

    var onAddLineItem: () -> Void
    var onEditLineItem: (ServiceLineItem) -> Void

    var body: some View {
        Section("Services & Materials") {
            Button {
                PresentationDebug.log("Add Line Item requested")
                onAddLineItem()
            } label: {
                HStack {
                    Spacer()

                    Image(systemName: "plus.circle.fill")

                    Text("Add Line Item")
                        .fontWeight(.semibold)

                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)

            if lineItems.isEmpty {
                Text("No line items yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lineItems) { item in
                    Button {
                        PresentationDebug.log(
                            "Edit requested for line item \(item.id)"
                        )
                        onEditLineItem(item)
                    } label: {
                        HStack {
                            Text(displayName(for: item))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(
                                PricingCalculator.updatedLineItem(item).lineTotal,
                                format: .currency(code: "USD")
                            )
                            .bold()
                            .foregroundStyle(.primary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            lineItems.removeAll { $0.id == item.id }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            var duplicate = item
                            duplicate.id = UUID()
                            lineItems.append(duplicate)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private func displayName(for item: ServiceLineItem) -> String {
        if let catalogItemID = item.catalogItemID,
           let catalogItem = store.serviceCatalogItems.first(where: {
               $0.id == catalogItemID
           }) {
            return catalogItem.itemName
        }
        if !item.otherService.isEmpty { return item.otherService }
        if !item.description.isEmpty { return item.description }
        return item.serviceType.rawValue
    }
}
