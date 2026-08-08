//
//  FieldPricingEngine.swift
//  PPS Receipt Printer
//
//  Phase 18 – Currency-safe routine-service field pricing.
//

import Foundation

struct FieldPricingBreakdown: Equatable {
    let basePrice: Decimal
    let weeklyPrice: Decimal
    let biWeeklyPrice: Decimal
    let monthlyPrice: Decimal
}

enum FieldPricingError: LocalizedError, Equatable {
    case invalidBasePrice
    case invalidPercentage

    var errorDescription: String? {
        switch self {
        case .invalidBasePrice:
            return "Enter a base price greater than zero."
        case .invalidPercentage:
            return "Enter a percentage from 0 through 1,000."
        }
    }
}

enum FieldPricingEngine {
    static let defaultWeeklyPercentage = Decimal(20)
    static let defaultBiWeeklyPercentage = Decimal(35)
    static let defaultMonthlyPercentage = Decimal(55)

    static func calculate(basePrice: Decimal) throws -> FieldPricingBreakdown {
        try calculate(
            basePrice: basePrice,
            weeklyPercentage: defaultWeeklyPercentage,
            biWeeklyPercentage: defaultBiWeeklyPercentage,
            monthlyPercentage: defaultMonthlyPercentage
        )
    }

    static func calculate(
        basePrice: Decimal,
        weeklyPercentage: Decimal,
        biWeeklyPercentage: Decimal,
        monthlyPercentage: Decimal
    ) throws -> FieldPricingBreakdown {
        guard basePrice > 0 else {
            throw FieldPricingError.invalidBasePrice
        }

        let percentages = [
            weeklyPercentage,
            biWeeklyPercentage,
            monthlyPercentage
        ]
        guard percentages.allSatisfy({ $0 >= 0 && $0 <= 1_000 }) else {
            throw FieldPricingError.invalidPercentage
        }

        let roundedBasePrice = currencyRounded(basePrice)
        return FieldPricingBreakdown(
            basePrice: roundedBasePrice,
            weeklyPrice: currencyRounded(
                roundedBasePrice * weeklyPercentage / 100
            ),
            biWeeklyPrice: currencyRounded(
                roundedBasePrice * biWeeklyPercentage / 100
            ),
            monthlyPrice: currencyRounded(
                roundedBasePrice * monthlyPercentage / 100
            )
        )
    }

    private static func currencyRounded(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }
}
