//
//  RecommendationEngine.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/6/26.
//

import Foundation

struct RecommendationEngine {
    static func recommendedCatalogItems(
        currentLineItems: [ServiceLineItem],
        catalogItems: [ServiceCatalogItem],
        recommendationRules: [RecommendationRule]
    ) -> [ServiceCatalogItem] {
        let alreadyUsedCatalogIDs = Set(
            currentLineItems.compactMap { $0.catalogItemID }
        )

        let triggeredCatalogIDs = alreadyUsedCatalogIDs

        let recommendedIDsFromRules = recommendationRules
            .filter { rule in
                rule.isEnabled &&
                triggeredCatalogIDs.contains(rule.triggerCatalogItemID)
            }
            .flatMap { $0.recommendedCatalogItemIDs }

        let recommendedIDSet = Set(recommendedIDsFromRules)

        let recommendations = catalogItems.filter { item in
            recommendedIDSet.contains(item.id) &&
            !alreadyUsedCatalogIDs.contains(item.id)
        }

        return CatalogRankingEngine.rankedItems(
            query: "",
            catalogItems: recommendations
        )
    }

    static func recommendedCatalogItems(
        currentLineItems: [ServiceLineItem],
        catalogItems: [ServiceCatalogItem]
    ) -> [ServiceCatalogItem] {
        let currentNames = currentLineItems.map {
            normalize($0.otherService + " " + $0.description)
        }

        let alreadyUsedCatalogIDs = Set(
            currentLineItems.compactMap { $0.catalogItemID }
        )

        let recommendationKeywords = recommendedKeywords(
            from: currentNames
        )

        let recommendations = catalogItems.filter { catalogItem in
            guard !alreadyUsedCatalogIDs.contains(catalogItem.id) else {
                return false
            }

            let searchableText = normalize(
                catalogItem.itemName + " " + catalogItem.itemDescription
            )

            return recommendationKeywords.contains { keyword in
                searchableText.contains(keyword)
            }
        }

        return CatalogRankingEngine.rankedItems(
            query: "",
            catalogItems: recommendations
        )
    }

    private static func recommendedKeywords(
        from currentNames: [String]
    ) -> [String] {
        var keywords: Set<String> = []

        for name in currentNames {
            if name.contains("window") {
                keywords.insert("screen")
                keywords.insert("track")
                keywords.insert("hard water")
                keywords.insert("glass")
            }

            if name.contains("pressure") || name.contains("wash") {
                keywords.insert("gutter")
                keywords.insert("driveway")
                keywords.insert("concrete")
                keywords.insert("house")
            }

            if name.contains("gutter") {
                keywords.insert("downspout")
                keywords.insert("roof")
                keywords.insert("cleaning")
            }
        }

        return Array(keywords)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
