//
//  WorkOrderEditorView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct WorkOrderEditorView: View {

    @EnvironmentObject var store: AppDataStore

    @Binding var lineItems: [ServiceLineItem]

    @FocusState.Binding var isInputFocused: Bool

    @State private var showingCatalogPicker = false

    var body: some View {

        Section("Work Performed") {

            Button {
                showingCatalogPicker = true
            } label: {
                Label("Add Line Item", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            LineItemListView(
                lineItems: $lineItems,
                isInputFocused: $isInputFocused
            )
            WorkOrderTotalsView(
                lineItems: lineItems,
                discount: 0
            )
        }
        .sheet(isPresented: $showingCatalogPicker) {

            ServiceCatalogPickerView(
                lineItems: $lineItems,
                onFinished: {
                    showingCatalogPicker = false
                }
            )
            .environmentObject(store)
        }
    }
}
