//
//  ServiceCatalogItemRowView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/8/26.
//

import SwiftUI

struct ServiceCatalogItemRowView: View {
    let item: ServiceCatalogItem
    var showUsageCount: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.itemName)
                .font(.headline)

            if !item.itemDescription.isEmpty {
                Text(item.itemDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(item.defaultQuantity, specifier: "%.2f") × \(item.defaultPrice, format: .currency(code: "USD"))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showUsageCount, item.usageCount > 0 {
                Text("Used \(item.usageCount) times")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
