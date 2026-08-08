import Foundation
import Testing
@testable import PPS_Receipt_Printer

struct FieldPricingEngineTests {
    @Test func calculatesRoutineServiceFrequencyPrices() throws {
        let pricing = try FieldPricingEngine.calculate(basePrice: 100)

        #expect(pricing.basePrice == 100)
        #expect(pricing.weeklyPrice == 20)
        #expect(pricing.biWeeklyPrice == 35)
        #expect(pricing.monthlyPrice == 55)
    }

    @Test func roundsCalculatedPricesToCurrencyPrecision() throws {
        let pricing = try FieldPricingEngine.calculate(basePrice: Decimal(string: "99.99")!)

        #expect(pricing.weeklyPrice == Decimal(string: "20.00")!)
        #expect(pricing.biWeeklyPrice == Decimal(string: "35.00")!)
        #expect(pricing.monthlyPrice == Decimal(string: "54.99")!)
    }

    @Test func rejectsNonPositiveBasePrices() {
        #expect(throws: FieldPricingError.invalidBasePrice) {
            try FieldPricingEngine.calculate(basePrice: 0)
        }
        #expect(throws: FieldPricingError.invalidBasePrice) {
            try FieldPricingEngine.calculate(basePrice: -1)
        }
    }

    @Test func calculatesUsingAdjustedPercentages() throws {
        let pricing = try FieldPricingEngine.calculate(
            basePrice: 200,
            weeklyPercentage: Decimal(string: "22.5")!,
            biWeeklyPercentage: 40,
            monthlyPercentage: 60
        )

        #expect(pricing.weeklyPrice == 45)
        #expect(pricing.biWeeklyPrice == 80)
        #expect(pricing.monthlyPrice == 120)
    }

    @Test func rejectsPercentagesOutsideSupportedRange() {
        #expect(throws: FieldPricingError.invalidPercentage) {
            try FieldPricingEngine.calculate(
                basePrice: 100,
                weeklyPercentage: -1,
                biWeeklyPercentage: 35,
                monthlyPercentage: 55
            )
        }
    }
}
