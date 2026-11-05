//
//  PricingCalculator.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/25/26.
//

import Foundation

enum PricingDiscountMethod: String, CaseIterable, Identifiable, Codable {
    case fixedAmount = "Dollar Amount"
    case percentage = "Percentage"

    var id: String { rawValue }
}

struct DiscountCalculator {
    static func amount(
        subtotal: Double,
        method: PricingDiscountMethod,
        inputValue: Double
    ) -> Double {
        let normalizedSubtotal = max(subtotal, 0)
        let normalizedInput = max(inputValue, 0)
        switch method {
        case .fixedAmount:
            return min(normalizedInput, normalizedSubtotal)
        case .percentage:
            return normalizedSubtotal * min(normalizedInput, 100) / 100
        }
    }
}

struct PricingCalculator {
    static func subtotal(for lineItems: [ServiceLineItem]) -> Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    static func total(subtotal: Double, discount: Double) -> Double {
        max(subtotal - discount, 0)
    }

    static func total(for lineItems: [ServiceLineItem], discount: Double) -> Double {
        let subtotal = subtotal(for: lineItems)
        return total(subtotal: subtotal, discount: discount)
    }

    static func subtotal<T: WorkOrder>(for workOrder: T) -> Double {
        subtotal(for: workOrder.lineItems)
    }

    static func total<T: WorkOrder>(for workOrder: T) -> Double {
        total(
            subtotal: subtotal(for: workOrder),
            discount: workOrder.discount
        )
    }

    static func updatedLineItem(_ item: ServiceLineItem) -> ServiceLineItem {
        var updated = item
        let grossTotal = max(item.quantity * item.unitPrice, 0)
        updated.lineTotal = max(
            grossTotal - DiscountCalculator.amount(
                subtotal: grossTotal,
                method: item.discountMethod,
                inputValue: item.discountInputValue
            ),
            0
        )
        return updated
    }

    static func updatedLineItems(_ items: [ServiceLineItem]) -> [ServiceLineItem] {
        items.map { updatedLineItem($0) }
    }

    static func grossSubtotal(for lineItems: [ServiceLineItem]) -> Double {
        lineItems.reduce(0) { $0 + max($1.quantity * $1.unitPrice, 0) }
    }

    static func itemDiscountTotal(for lineItems: [ServiceLineItem]) -> Double {
        max(grossSubtotal(for: lineItems) - subtotal(for: lineItems), 0)
    }
}
