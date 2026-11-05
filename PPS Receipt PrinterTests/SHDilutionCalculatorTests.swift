import Foundation
import Testing
@testable import PPS_Receipt_Printer

struct SHDilutionCalculatorTests {
    @Test func tenPercentSourceMakesOnePercentFiveGallonMix() throws {
        let result = try SHDilutionCalculator.calculate(
            sourceConcentration: 10,
            totalGallons: 5,
            desiredConcentration: 1
        )

        #expect(result.shGallons == 0.5)
        #expect(result.waterGallons == 4.5)
        #expect(result.shOunces == 64)
        #expect(result.waterOunces == 576)
    }

    @Test func twelvePointFivePercentSourceMakesThreePercentMix() throws {
        let result = try SHDilutionCalculator.calculate(
            sourceConcentration: 12.5,
            totalGallons: 2.5,
            desiredConcentration: 3
        )

        #expect(result.shGallons == 0.6)
        #expect(result.waterGallons == 1.9)
        #expect(result.shOunces == 76.8)
        #expect(result.waterOunces == 243.2)
    }

    @Test func rejectsDesiredStrengthAboveSourceStrength() {
        #expect(throws: SHDilutionCalculatorError.desiredExceedsSource) {
            try SHDilutionCalculator.calculate(
                sourceConcentration: 10,
                totalGallons: 5,
                desiredConcentration: 12.5
            )
        }
    }

    @Test func rejectsZeroVolumeAndConcentration() {
        #expect(throws: SHDilutionCalculatorError.invalidTotalVolume) {
            try SHDilutionCalculator.calculate(
                sourceConcentration: 10,
                totalGallons: 0,
                desiredConcentration: 1
            )
        }
        #expect(throws: SHDilutionCalculatorError.invalidDesiredConcentration) {
            try SHDilutionCalculator.calculate(
                sourceConcentration: 10,
                totalGallons: 5,
                desiredConcentration: 0
            )
        }
    }
}
