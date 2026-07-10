//
//  LineItemListView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct LineItemListView: View {
    @EnvironmentObject var store: AppDataStore

    @Binding var lineItems: [ServiceLineItem]
    @FocusState.Binding var isInputFocused: Bool

    var onEdit: (ServiceLineItem) -> Void


    var body: some View {
        Section("Line Items") {
            if lineItems.isEmpty {
                Text("No line items yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lineItems) { item in
                    HStack {
                        LineItemRowView(
                            item: item,
                            displayName: displayName(for: item)
                        )

                        Button {
                            onEdit(item)
                        } label: {
                            Image(systemName: "pencil.circle")
                                .imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            duplicateItem(item)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private func deleteItem(_ item: ServiceLineItem) {
        lineItems.removeAll { $0.id == item.id }
    }
    
    private func duplicateItem(_ item: ServiceLineItem) {
        var duplicated = item
        duplicated.id = UUID()
        lineItems.append(duplicated)
    }

    private func displayName(for item: ServiceLineItem) -> String {
        if let catalogItemID = item.catalogItemID,
           let catalogItem = store.serviceCatalogItems.first(where: { $0.id == catalogItemID }) {
            return catalogItem.itemName
        }

        if !item.otherService.isEmpty {
            return item.otherService
        }

        if !item.description.isEmpty {
            return item.description
        }

        return item.serviceType.rawValue
    }
}
