//
//  RecommendationRule.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/7/26.
//

import Foundation

struct RecommendationRule: Identifiable, Codable, Hashable {
    let id: UUID

    var triggerCatalogItemID: UUID

    var recommendedCatalogItemIDs: [UUID]

    var isEnabled: Bool

    var notes: String

    init(
        id: UUID = UUID(),
        triggerCatalogItemID: UUID,
        recommendedCatalogItemIDs: [UUID] = [],
        isEnabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.triggerCatalogItemID = triggerCatalogItemID
        self.recommendedCatalogItemIDs = recommendedCatalogItemIDs
        self.isEnabled = isEnabled
        self.notes = notes
    }
}
