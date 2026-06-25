//
//  PricingCalculator.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/25/26.
//

import Foundation

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
        updated.lineTotal = item.quantity * item.unitPrice
        return updated
    }

    static func updatedLineItems(_ items: [ServiceLineItem]) -> [ServiceLineItem] {
        items.map { updatedLineItem($0) }
    }
}
