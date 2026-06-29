//
//  WorkOrderTotalsView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct WorkOrderTotalsView: View {
    let lineItems: [ServiceLineItem]
    let discount: Double

    private var subtotal: Double {
        PricingCalculator.subtotal(for: lineItems)
    }

    private var total: Double {
        PricingCalculator.total(
            subtotal: subtotal,
            discount: discount
        )
    }

    var body: some View {
        Section("Totals") {
            HStack {
                Text("Subtotal")
                Spacer()
                Text(subtotal, format: .currency(code: "USD"))
                    .bold()
            }

            HStack {
                Text("Discount")
                Spacer()
                Text(discount, format: .currency(code: "USD"))
            }

            HStack {
                Text("Total")
                Spacer()
                Text(total, format: .currency(code: "USD"))
                    .font(.headline)
                    .bold()
            }
        }
    }
}
