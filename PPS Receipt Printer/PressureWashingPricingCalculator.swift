import Foundation
import simd

enum PressureWashingServiceType: String, CaseIterable, Identifiable {
    case houseWash = "House Wash"
    case drivewayAndSidewalk = "Driveway & Sidewalk"
    case fence = "Fence"
    case dumpsterArea = "Dumpster Area"
    case other = "Other"

    var id: String { rawValue }

    var standardRate: Decimal? {
        switch self {
        case .houseWash: return 0.45
        case .drivewayAndSidewalk: return 0.65
        case .fence: return 0.75
        case .dumpsterArea: return 2.25
        case .other: return nil
        }
    }
}

struct PressureWashingPriceTier: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startsAtSquareFeet: Decimal
    var multiplier: Decimal
}

struct PressureWashingPricingSettings: Codable, Equatable {
    var houseWashRate: Decimal = 0.45
    var drivewayAndSidewalkRate: Decimal = 0.65
    var fenceRate: Decimal = 0.75
    var dumpsterAreaRate: Decimal = 2.25
    var tiers: [PressureWashingPriceTier] = Self.defaultTiers

    static let defaultTiers = [
        PressureWashingPriceTier(startsAtSquareFeet: 0, multiplier: 3),
        PressureWashingPriceTier(startsAtSquareFeet: 200.01, multiplier: 2),
        PressureWashingPriceTier(startsAtSquareFeet: 500.01, multiplier: 1),
        PressureWashingPriceTier(startsAtSquareFeet: 1_500.01, multiplier: 0.75),
        PressureWashingPriceTier(startsAtSquareFeet: 2_500.01, multiplier: 0.50)
    ]

    func baseRate(for serviceType: PressureWashingServiceType) -> Decimal? {
        switch serviceType {
        case .houseWash: return houseWashRate
        case .drivewayAndSidewalk: return drivewayAndSidewalkRate
        case .fence: return fenceRate
        case .dumpsterArea: return dumpsterAreaRate
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
        houseWashRate = max(houseWashRate, 0.01)
        drivewayAndSidewalkRate = max(drivewayAndSidewalkRate, 0.01)
        fenceRate = max(fenceRate, 0.01)
        dumpsterAreaRate = max(dumpsterAreaRate, 0.01)
        tiers = tiers
            .filter { $0.startsAtSquareFeet >= 0 && $0.multiplier > 0 }
            .sorted { $0.startsAtSquareFeet < $1.startsAtSquareFeet }
        if tiers.isEmpty { tiers = Self.defaultTiers }
        if tiers[0].startsAtSquareFeet != 0 {
            tiers.insert(PressureWashingPriceTier(startsAtSquareFeet: 0, multiplier: 1), at: 0)
        }
    }
}

enum PressureWashingPricingError: LocalizedError, Equatable {
    case invalidSquareFeet
    case invalidRate

    var errorDescription: String? {
        switch self {
        case .invalidSquareFeet:
            return "Enter a measured area greater than zero."
        case .invalidRate:
            return "Enter a price per square foot greater than zero."
        }
    }
}

struct PressureWashingPriceResult: Equatable {
    let squareFeet: Decimal
    let baseRatePerSquareFoot: Decimal
    let tierMultiplier: Decimal
    let ratePerSquareFoot: Decimal
    let totalPrice: Decimal
}

struct PressureWashingAreaMeasurement: Identifiable, Equatable {
    let id: UUID
    var title: String
    var squareFeet: Decimal

    init(id: UUID = UUID(), title: String, squareFeet: Decimal) {
        self.id = id
        self.title = title
        self.squareFeet = squareFeet
    }
}

enum PressureWashingMeasurementCalculator {
    static func totalSquareFeet(_ measurements: [PressureWashingAreaMeasurement]) -> Decimal {
        measurements.reduce(0) { $0 + $1.squareFeet }
    }
}

enum PressureWashingPricingCalculator {
    static func calculate(squareFeet: Decimal, ratePerSquareFoot: Decimal) throws -> PressureWashingPriceResult {
        guard squareFeet > 0 else { throw PressureWashingPricingError.invalidSquareFeet }
        guard ratePerSquareFoot > 0 else { throw PressureWashingPricingError.invalidRate }

        return PressureWashingPriceResult(
            squareFeet: squareFeet,
            baseRatePerSquareFoot: ratePerSquareFoot,
            tierMultiplier: 1,
            ratePerSquareFoot: ratePerSquareFoot,
            totalPrice: squareFeet * ratePerSquareFoot
        )
    }

    static func calculate(
        squareFeet: Decimal,
        serviceType: PressureWashingServiceType,
        customRate: Decimal?,
        settings: PressureWashingPricingSettings
    ) throws -> PressureWashingPriceResult {
        guard squareFeet > 0 else { throw PressureWashingPricingError.invalidSquareFeet }
        let baseRate = serviceType == .other ? customRate : settings.baseRate(for: serviceType)
        guard let baseRate, baseRate > 0 else { throw PressureWashingPricingError.invalidRate }
        let multiplier: Decimal = serviceType == .other ? 1 : settings.multiplier(for: squareFeet)
        let effectiveRate = baseRate * multiplier
        return PressureWashingPriceResult(
            squareFeet: squareFeet,
            baseRatePerSquareFoot: baseRate,
            tierMultiplier: multiplier,
            ratePerSquareFoot: effectiveRate,
            totalPrice: squareFeet * effectiveRate
        )
    }
}

enum PressureWashingLineItemFactory {
    static func makeLineItem(
        serviceType: PressureWashingServiceType,
        result: PressureWashingPriceResult,
        measurements: [PressureWashingAreaMeasurement]
    ) -> ServiceLineItem {
        let itemName: String
        switch serviceType {
        case .houseWash:
            itemName = "House Wash"
        case .drivewayAndSidewalk:
            itemName = "Driveway & Sidewalk Pressure Washing"
        case .fence:
            itemName = "Fence Pressure Washing"
        case .dumpsterArea:
            itemName = "Dumpster Area Pressure Washing"
        case .other:
            itemName = "Other Service"
        }

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
            catalogItemNameSnapshot: itemName,
            catalogItemTypeSnapshot: .service,
            taxTreatmentSnapshot: .nonTaxable,
            serviceType: serviceType == .other ? .other : .pressureWashing,
            otherService: itemName,
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

enum ARAreaGeometry {
    static let squareFeetPerSquareMeter = 10.76391041671

    static func rectangleAreaSquareFeet(points: [SIMD3<Float>]) -> Double? {
        guard points.count >= 3 else { return nil }
        let firstLeg = simd_distance(points[0], points[1])
        let secondLeg = simd_distance(points[1], points[2])
        guard firstLeg > 0, secondLeg > 0 else { return nil }
        return Double(firstLeg * secondLeg) * squareFeetPerSquareMeter
    }

    static func polygonAreaSquareFeet(points: [SIMD3<Float>]) -> Double? {
        guard points.count >= 3 else { return nil }
        var areaVector = SIMD3<Float>.zero
        for index in points.indices {
            areaVector += simd_cross(points[index], points[(index + 1) % points.count])
        }
        let squareMeters = Double(simd_length(areaVector)) / 2
        guard squareMeters > 0 else { return nil }
        return squareMeters * squareFeetPerSquareMeter
    }
}
