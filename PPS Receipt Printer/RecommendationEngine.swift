//
//  RecommendationEngine.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/6/26.
//  Refactored for Brick 12 — Recommendation/Decision separation.
//

import Foundation

/// Produces service-catalog recommendations for estimates, invoices, and jobs.
///
/// Operational decisions such as technician assignment and dispatch ranking belong
/// in `DispatchDecisionEngine`. This engine is intentionally limited to service
/// recommendations, cross-sells, and rule-driven catalog suggestions.
struct RecommendationEngine {

    // MARK: - Rule-driven recommendations

    /// Returns catalog items recommended by enabled recommendation rules.
    ///
    /// A rule is triggered when its `triggerCatalogItemID` already appears in the
    /// current line items. Items already present in the transaction are excluded.
    /// Results are deduplicated and ranked by `CatalogRankingEngine`.
    static func recommendedCatalogItems(
        currentLineItems: [ServiceLineItem],
        catalogItems: [ServiceCatalogItem],
        recommendationRules: [RecommendationRule]
    ) -> [ServiceCatalogItem] {
        let context = RecommendationContext(currentLineItems: currentLineItems)

        let recommendedCatalogIDs = enabledRecommendedCatalogIDs(
            triggeredBy: context.usedCatalogIDs,
            rules: recommendationRules
        )

        let recommendations = eligibleCatalogItems(
            from: catalogItems,
            recommendedCatalogIDs: recommendedCatalogIDs,
            excluding: context.usedCatalogIDs
        )

        return rank(recommendations)
    }

    // MARK: - Heuristic recommendations

    /// Returns catalog recommendations inferred from the descriptions of the
    /// current line items.
    ///
    /// This overload remains as a safe fallback when no explicit recommendation
    /// rules are configured. Items already present in the transaction are excluded.
    static func recommendedCatalogItems(
        currentLineItems: [ServiceLineItem],
        catalogItems: [ServiceCatalogItem]
    ) -> [ServiceCatalogItem] {
        let context = RecommendationContext(currentLineItems: currentLineItems)
        let keywords = heuristicKeywords(for: context.normalizedLineItemText)

        guard !keywords.isEmpty else {
            return []
        }

        let recommendations = catalogItems.filter { catalogItem in
            guard !context.usedCatalogIDs.contains(catalogItem.id) else {
                return false
            }

            let searchableText = normalizedCatalogText(for: catalogItem)
            return keywords.contains { searchableText.contains($0) }
        }

        return rank(recommendations)
    }

    // MARK: - Rule processing

    private static func enabledRecommendedCatalogIDs(
        triggeredBy usedCatalogIDs: Set<UUID>,
        rules: [RecommendationRule]
    ) -> Set<UUID> {
        guard !usedCatalogIDs.isEmpty else {
            return []
        }

        return rules.reduce(into: Set<UUID>()) { recommendedIDs, rule in
            guard
                rule.isEnabled,
                usedCatalogIDs.contains(rule.triggerCatalogItemID)
            else {
                return
            }

            recommendedIDs.formUnion(rule.recommendedCatalogItemIDs)
        }
    }

    private static func eligibleCatalogItems(
        from catalogItems: [ServiceCatalogItem],
        recommendedCatalogIDs: Set<UUID>,
        excluding usedCatalogIDs: Set<UUID>
    ) -> [ServiceCatalogItem] {
        guard !recommendedCatalogIDs.isEmpty else {
            return []
        }

        return catalogItems.filter { catalogItem in
            recommendedCatalogIDs.contains(catalogItem.id) &&
            !usedCatalogIDs.contains(catalogItem.id)
        }
    }

    // MARK: - Heuristic processing

    private static func heuristicKeywords(
        for normalizedLineItemText: [String]
    ) -> Set<String> {
        normalizedLineItemText.reduce(into: Set<String>()) { keywords, lineItemText in
            if lineItemText.contains("window") {
                keywords.formUnion([
                    "screen",
                    "track",
                    "hard water",
                    "glass"
                ])
            }

            if lineItemText.contains("pressure") || lineItemText.contains("wash") {
                keywords.formUnion([
                    "gutter",
                    "driveway",
                    "concrete",
                    "house"
                ])
            }

            if lineItemText.contains("gutter") {
                keywords.formUnion([
                    "downspout",
                    "roof",
                    "cleaning"
                ])
            }
        }
    }

    // MARK: - Ranking

    private static func rank(
        _ catalogItems: [ServiceCatalogItem]
    ) -> [ServiceCatalogItem] {
        guard !catalogItems.isEmpty else {
            return []
        }

        return CatalogRankingEngine.rankedItems(
            query: "",
            catalogItems: catalogItems
        )
    }

    // MARK: - Normalization

    private static func normalizedCatalogText(
        for catalogItem: ServiceCatalogItem
    ) -> String {
        normalize(
            catalogItem.itemName + " " + catalogItem.itemDescription
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// MARK: - Internal recommendation context

private extension RecommendationEngine {
    struct RecommendationContext {
        let usedCatalogIDs: Set<UUID>
        let normalizedLineItemText: [String]

        init(currentLineItems: [ServiceLineItem]) {
            usedCatalogIDs = Set(
                currentLineItems.compactMap(\.catalogItemID)
            )

            normalizedLineItemText = currentLineItems.map { lineItem in
                RecommendationEngine.normalize(
                    lineItem.otherService + " " + lineItem.description
                )
            }
        }
    }
}
