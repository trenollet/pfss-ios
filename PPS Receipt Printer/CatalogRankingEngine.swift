//
//  CatalogSearchEngine.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/29/26.
//

import Foundation

struct CatalogRankedItem {
    let item: ServiceCatalogItem
    let totalScore: Int
    let breakdown: CatalogScoreBreakdown
}

struct CatalogScoreBreakdown {
    let exactMatch: Int
    let prefixMatch: Int
    let containsMatch: Int
    let tokenMatch: Int
    let initialismMatch: Int
    let descriptionMatch: Int
    let usage: Int
    let recency: Int

    var total: Int {
        exactMatch +
        prefixMatch +
        containsMatch +
        tokenMatch +
        initialismMatch +
        descriptionMatch +
        usage +
        recency
    }
}

struct CatalogRankingEngine {
    static func rankedItems(
        query: String,
        catalogItems: [ServiceCatalogItem]
    ) -> [ServiceCatalogItem] {
        rankedResults(
            query: query,
            catalogItems: catalogItems
        )
        .map { $0.item }
    }

    static func rankedResults(
        query: String,
        catalogItems: [ServiceCatalogItem]
    ) -> [CatalogRankedItem] {
        let normalizedQuery = normalize(query)

        return catalogItems
            .map { item in
                let scoreBreakdown = breakdown(
                    for: item,
                    query: normalizedQuery
                )

                return CatalogRankedItem(
                    item: item,
                    totalScore: scoreBreakdown.total,
                    breakdown: scoreBreakdown
                )
            }
            .filter { normalizedQuery.isEmpty || $0.totalScore > 0 }
            .sorted {
                if $0.totalScore != $1.totalScore {
                    return $0.totalScore > $1.totalScore
                }

                if $0.item.usageCount != $1.item.usageCount {
                    return $0.item.usageCount > $1.item.usageCount
                }

                return ($0.item.lastUsedDate ?? .distantPast) > ($1.item.lastUsedDate ?? .distantPast)
            }
    }

    private static func breakdown(
        for item: ServiceCatalogItem,
        query: String
    ) -> CatalogScoreBreakdown {
        CatalogScoreBreakdown(
            exactMatch: exactMatchScore(for: item, query: query),
            prefixMatch: prefixMatchScore(for: item, query: query),
            containsMatch: containsMatchScore(for: item, query: query),
            tokenMatch: tokenMatchScore(for: item, query: query),
            initialismMatch: initialismMatchScore(for: item, query: query),
            descriptionMatch: descriptionMatchScore(for: item, query: query),
            usage: usageScore(for: item),
            recency: recencyScore(for: item)
        )
    }

    private static func exactMatchScore(
        for item: ServiceCatalogItem,
        query: String
    ) -> Int {
        guard !query.isEmpty else { return 0 }

        return normalize(item.itemName) == query ? 1000 : 0
    }

    private static func prefixMatchScore(
        for item: ServiceCatalogItem,
        query: String
    ) -> Int {
        guard !query.isEmpty else { return 0 }

        return normalize(item.itemName).hasPrefix(query) ? 500 : 0
    }

    private static func containsMatchScore(
        for item: ServiceCatalogItem,
        query: String
    ) -> Int {
        guard !query.isEmpty else { return 0 }

        return normalize(item.itemName).contains(query) ? 250 : 0
    }

    private static func tokenMatchScore(
        for item: ServiceCatalogItem,
        query: String
    ) -> Int {
        guard !query.isEmpty else { return 0 }

        let queryTokens = tokenize(query)
        let itemTokens = tokenize(item.itemName)

        guard !queryTokens.isEmpty, !itemTokens.isEmpty else { return 0 }

        var score = 0

        for queryToken in queryTokens {
            if itemTokens.contains(queryToken) {
                score += 400
            } else if itemTokens.contains(where: { $0.hasPrefix(queryToken) }) {
                score += 225
            } else if itemTokens.contains(where: { $0.contains(queryToken) }) {
                score += 125
            }
        }

        return score
    }

    private static func initialismMatchScore(
        for item: ServiceCatalogItem,
        query: String
    ) -> Int {
        guard !query.isEmpty else { return 0 }

        let itemInitialism = initialism(for: item.itemName)

        guard !itemInitialism.isEmpty else { return 0 }

        if itemInitialism == query {
            return 450
        }

        if itemInitialism.hasPrefix(query) {
            return 250
        }

        return 0
    }

    private static func descriptionMatchScore(
        for item: ServiceCatalogItem,
        query: String
    ) -> Int {
        guard !query.isEmpty else { return 0 }

        let queryTokens = tokenize(query)
        let description = normalize(item.itemDescription)

        guard !queryTokens.isEmpty else { return 0 }

        var score = 0

        for queryToken in queryTokens {
            if description.contains(queryToken) {
                score += 100
            }
        }

        return score
    }

    private static func usageScore(for item: ServiceCatalogItem) -> Int {
        min(item.usageCount * 5, 250)
    }

    private static func recencyScore(for item: ServiceCatalogItem) -> Int {
        guard let lastUsedDate = item.lastUsedDate else { return 0 }

        let daysSinceUsed = Calendar.current.dateComponents(
            [.day],
            from: lastUsedDate,
            to: Date()
        ).day ?? 999

        if daysSinceUsed <= 7 {
            return 75
        } else if daysSinceUsed <= 30 {
            return 40
        } else if daysSinceUsed <= 90 {
            return 15
        }

        return 0
    }

    private static func tokenize(_ value: String) -> [String] {
        normalize(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func initialism(for value: String) -> String {
        tokenize(value)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
    }
    static func debugRanking(
        query: String,
        catalogItems: [ServiceCatalogItem]
    ) -> String {
        let results = rankedResults(
            query: query,
            catalogItems: catalogItems
        )

        guard !results.isEmpty else {
            return "No ranking results for query: \(query)"
        }

        return results.map { result in
            """
            \(result.item.itemName)
            ---------------------
            Exact Match:       \(result.breakdown.exactMatch)
            Prefix Match:      \(result.breakdown.prefixMatch)
            Contains Match:    \(result.breakdown.containsMatch)
            Token Match:       \(result.breakdown.tokenMatch)
            Initialism Match:  \(result.breakdown.initialismMatch)
            Description Match: \(result.breakdown.descriptionMatch)
            Usage:             \(result.breakdown.usage)
            Recency:           \(result.breakdown.recency)

            TOTAL:             \(result.totalScore)
            """
        }
        .joined(separator: "\n\n")
    }
    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
