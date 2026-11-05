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

    private var grossSubtotal: Double {
        PricingCalculator.grossSubtotal(for: lineItems)
    }

    private var itemDiscountTotal: Double {
        PricingCalculator.itemDiscountTotal(for: lineItems)
    }

    private var total: Double {
        PricingCalculator.total(
            subtotal: subtotal,
            discount: discount
        )
    }

    var body: some View {
        Section("Totals") {
            if itemDiscountTotal > 0 {
                HStack {
                    Text("Items Before Discount")
                    Spacer()
                    Text(grossSubtotal, format: .currency(code: "USD"))
                }

                HStack {
                    Text("Item Discounts")
                    Spacer()
                    Text(-itemDiscountTotal, format: .currency(code: "USD"))
                }
            }

            HStack {
                Text("Items Subtotal")
                Spacer()
                Text(subtotal, format: .currency(code: "USD"))
                    .bold()
            }

            if discount > 0 {
                HStack {
                    Text("Pricing Discount")
                    Spacer()
                    Text(-discount, format: .currency(code: "USD"))
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
}
