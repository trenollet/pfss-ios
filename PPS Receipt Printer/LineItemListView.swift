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

    @State private var selectedLineItem: ServiceLineItem?


    var body: some View {
        Section("Line Items") {
            if lineItems.isEmpty {
                Text("No line items yet.")
                    .foregroundStyle(.secondary)
            } else {
// - slider style edit button
//                ForEach(lineItems) { item in
//                    Button {
//                      openEditor(for: item)
//                    } label: {
//                        LineItemRowView(
//                            item: item,
//                            displayName: displayName(for: item)
//                        )
//                    }
//                    .swipeActions(edge: .trailing) {
//                        Button(role: .destructive) {
//                            deleteItem(item)
//                        } label: {
//                            Label("Delete", systemImage: "trash")
//                        }
//
//                        Button {
//                            duplicateItem(item)
//                        } label: {
//                            Label("Duplicate", systemImage: "doc.on.doc")
//                        }
//
//                        Button {
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
//                                openEditor(for: item)
//                            }
//                        } label: {
//                            Label("Edit", systemImage: "pencil")
//                        }
//                    }
//                }
//
//  Button style edit button
                ForEach(lineItems) { item in
                    HStack {
                        LineItemRowView(
                            item: item,
                            displayName: displayName(for: item)
                        )

                        Button {
                            openEditor(for: item)
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
        .sheet(item: $selectedLineItem) { item in
            EditableLineItemView(
                lineItems: $lineItems,
                catalogItem: nil,
                existingLineItem: item
            )
            .environmentObject(store)
        }
    }

    private func deleteItem(_ item: ServiceLineItem) {
        lineItems.removeAll { $0.id == item.id }
    }
    private func openEditor(for item: ServiceLineItem) {
        selectedLineItem = lineItems.first(where: { $0.id == item.id }) ?? item
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
