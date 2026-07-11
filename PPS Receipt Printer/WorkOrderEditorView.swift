//
//  WorkOrderEditorView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct WorkOrderEditorView: View {
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

            LineItemListView(
                lineItems: $lineItems,
                isInputFocused: $isInputFocused,
                onEdit: { item in
                    PresentationDebug.log(
                        "Edit requested for line item \(item.id)"
                    )
                    onEditLineItem(item)
                }
            )

            WorkOrderTotalsView(
                lineItems: lineItems,
                discount: 0
            )
        }
    }
}
