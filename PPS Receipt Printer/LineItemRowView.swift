//
//  LineItemRowView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import SwiftUI

struct LineItemRowView: View {
    let item: ServiceLineItem
    let displayName: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(item.quantity, specifier: "%.2f") × \(item.unitPrice, format: .currency(code: "USD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let itemDiscount = DiscountCalculator.amount(
                    subtotal: max(item.quantity * item.unitPrice, 0),
                    method: item.discountMethod,
                    inputValue: item.discountInputValue
                )
                if itemDiscount > 0 {
                    Text(
                        item.discountMethod == .percentage
                            ? "Item discount: \(item.discountInputValue.formatted(.number.precision(.fractionLength(0...2))))% (\(itemDiscount.formatted(.currency(code: "USD"))))"
                            : "Item discount: \(itemDiscount.formatted(.currency(code: "USD")))"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }

            Spacer()

            Text(item.lineTotal, format: .currency(code: "USD"))
                .bold()
        }
        .padding(.vertical, 4)
    }
}
