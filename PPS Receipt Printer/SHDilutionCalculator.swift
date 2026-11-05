import Foundation

enum SHDilutionCalculatorError: LocalizedError, Equatable {
    case invalidTotalVolume
    case invalidSourceConcentration
    case invalidDesiredConcentration
    case desiredExceedsSource

    var errorDescription: String? {
        switch self {
        case .invalidTotalVolume:
            return "Enter a total solution amount greater than zero."
        case .invalidSourceConcentration:
            return "Select a valid source SH concentration."
        case .invalidDesiredConcentration:
            return "Enter a desired SH concentration greater than zero."
        case .desiredExceedsSource:
            return "The desired concentration cannot be stronger than the selected SH product."
        }
    }
}

struct SHDilutionResult: Equatable {
    let sourceConcentration: Decimal
    let desiredConcentration: Decimal
    let totalGallons: Decimal
    let shGallons: Decimal
    let waterGallons: Decimal

    var shOunces: Decimal { shGallons * 128 }
    var waterOunces: Decimal { waterGallons * 128 }
    var totalOunces: Decimal { totalGallons * 128 }
}

enum SHDilutionCalculator {
    static func calculate(
        sourceConcentration: Decimal,
        totalGallons: Decimal,
        desiredConcentration: Decimal
    ) throws -> SHDilutionResult {
        guard totalGallons > 0 else {
            throw SHDilutionCalculatorError.invalidTotalVolume
        }
        guard sourceConcentration > 0 else {
            throw SHDilutionCalculatorError.invalidSourceConcentration
        }
        guard desiredConcentration > 0 else {
            throw SHDilutionCalculatorError.invalidDesiredConcentration
        }
        guard desiredConcentration <= sourceConcentration else {
            throw SHDilutionCalculatorError.desiredExceedsSource
        }

        let shGallons = totalGallons * desiredConcentration / sourceConcentration
        return SHDilutionResult(
            sourceConcentration: sourceConcentration,
            desiredConcentration: desiredConcentration,
            totalGallons: totalGallons,
            shGallons: shGallons,
            waterGallons: totalGallons - shGallons
        )
    }
}
