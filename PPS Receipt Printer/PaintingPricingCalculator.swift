import Foundation

enum PaintingServiceType: String, CaseIterable, Identifiable {
    case paintOneCoat = "Paint One Coat"
    case primeAndPaint = "Prime and Paint"
    case cleanPrimeAndPaint = "Clean, Prime and Paint"
    case other = "Other"

    var id: String { rawValue }
}

struct PaintingPriceTier: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startsAtSquareFeet: Decimal
    var multiplier: Decimal
}

struct PaintingPricingSettings: Codable, Equatable {
    var paintOneCoatRate: Decimal = 1.35
    var primeAndPaintRate: Decimal = 1.85
    var cleanPrimeAndPaintRate: Decimal = 2.35
    var tiers: [PaintingPriceTier] = Self.defaultTiers

    static let defaultTiers = [
        PaintingPriceTier(startsAtSquareFeet: 0, multiplier: 3),
        PaintingPriceTier(startsAtSquareFeet: 200.01, multiplier: 2),
        PaintingPriceTier(startsAtSquareFeet: 500.01, multiplier: 1),
        PaintingPriceTier(startsAtSquareFeet: 1_500.01, multiplier: 0.75),
        PaintingPriceTier(startsAtSquareFeet: 2_500.01, multiplier: 0.50)
    ]

    func baseRate(for serviceType: PaintingServiceType) -> Decimal? {
        switch serviceType {
        case .paintOneCoat: return paintOneCoatRate
        case .primeAndPaint: return primeAndPaintRate
        case .cleanPrimeAndPaint: return cleanPrimeAndPaintRate
        case .other: return nil
        }
    }

    func multiplier(for squareFeet: Decimal) -> Decimal {
        let validTiers = tiers
            .filter { $0.startsAtSquareFeet >= 0 && $0.multiplier > 0 }
            .sorted { $0.startsAtSquareFeet < $1.startsAtSquareFeet }
        return validTiers.last(where: { squareFeet >= $0.startsAtSquareFeet })?.multiplier ?? 1
    }

    mutating func normalize() {
        paintOneCoatRate = max(paintOneCoatRate, 0.01)
        primeAndPaintRate = max(primeAndPaintRate, 0.01)
        cleanPrimeAndPaintRate = max(cleanPrimeAndPaintRate, 0.01)
        tiers = tiers
            .filter { $0.startsAtSquareFeet >= 0 && $0.multiplier > 0 }
            .sorted { $0.startsAtSquareFeet < $1.startsAtSquareFeet }
        if tiers.isEmpty { tiers = Self.defaultTiers }
        if tiers[0].startsAtSquareFeet != 0 {
            tiers.insert(PaintingPriceTier(startsAtSquareFeet: 0, multiplier: 1), at: 0)
        }
    }
}

enum PaintingPricingError: LocalizedError, Equatable {
    case invalidSquareFeet
    case invalidRate

    var errorDescription: String? {
        switch self {
        case .invalidSquareFeet: return "Enter a measured area greater than zero."
        case .invalidRate: return "Enter a price per square foot greater than zero."
        }
    }
}

struct PaintingPriceResult: Equatable {
    let squareFeet: Decimal
    let baseRatePerSquareFoot: Decimal
    let tierMultiplier: Decimal
    let ratePerSquareFoot: Decimal
    let totalPrice: Decimal
}

enum PaintingPricingCalculator {
    static func calculate(
        squareFeet: Decimal,
        serviceType: PaintingServiceType,
        customRate: Decimal?,
        settings: PaintingPricingSettings
    ) throws -> PaintingPriceResult {
        guard squareFeet > 0 else { throw PaintingPricingError.invalidSquareFeet }
        let baseRate = serviceType == .other ? customRate : settings.baseRate(for: serviceType)
        guard let baseRate, baseRate > 0 else { throw PaintingPricingError.invalidRate }
        let multiplier: Decimal = serviceType == .other ? 1 : settings.multiplier(for: squareFeet)
        let effectiveRate = baseRate * multiplier
        return PaintingPriceResult(
            squareFeet: squareFeet,
            baseRatePerSquareFoot: baseRate,
            tierMultiplier: multiplier,
            ratePerSquareFoot: effectiveRate,
            totalPrice: squareFeet * effectiveRate
        )
    }
}

enum PaintingLineItemFactory {
    static func makeLineItem(
        serviceType: PaintingServiceType,
        result: PaintingPriceResult,
        measurements: [PressureWashingAreaMeasurement]
    ) -> ServiceLineItem {
        var descriptionLines = measurements.map {
            "\($0.title): \(number($0.squareFeet)) sq ft"
        }
        if descriptionLines.isEmpty {
            descriptionLines.append("Measured area: \(number(result.squareFeet)) sq ft")
        } else {
            descriptionLines.append("Total measured area: \(number(result.squareFeet)) sq ft")
        }

        return ServiceLineItem(
            catalogItemID: nil,
            catalogItemNameSnapshot: serviceType.rawValue,
            catalogItemTypeSnapshot: .service,
            taxTreatmentSnapshot: .nonTaxable,
            serviceType: .painting,
            otherService: serviceType.rawValue,
            description: descriptionLines.joined(separator: "\n"),
            quantity: NSDecimalNumber(decimal: result.squareFeet).doubleValue,
            unitPrice: NSDecimalNumber(decimal: result.ratePerSquareFoot).doubleValue,
            lineTotal: NSDecimalNumber(decimal: result.totalPrice).doubleValue
        )
    }

    private static func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
