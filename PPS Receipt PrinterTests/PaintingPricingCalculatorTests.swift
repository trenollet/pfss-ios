import Foundation
import Testing
@testable import PPS_Receipt_Printer

struct PaintingPricingCalculatorTests {
    @Test func defaultPaintingRatesUseExpectedPrices() throws {
        let settings = PaintingPricingSettings(
            tiers: [PaintingPriceTier(startsAtSquareFeet: 0, multiplier: 1)]
        )

        let expectations: [(PaintingServiceType, Decimal)] = [
            (.paintOneCoat, 1.35),
            (.primeAndPaint, 1.85),
            (.cleanPrimeAndPaint, 2.35)
        ]
        for (serviceType, expectedRate) in expectations {
            let result = try PaintingPricingCalculator.calculate(
                squareFeet: 100,
                serviceType: serviceType,
                customRate: nil,
                settings: settings
            )
            #expect(result.ratePerSquareFoot == expectedRate)
            #expect(result.totalPrice == expectedRate * 100)
        }
    }

    @Test func paintingTierBoundariesAndHighestTierContinue() throws {
        let settings = PaintingPricingSettings()
        let expectations: [(Decimal, Decimal)] = [
            (200, 3), (200.01, 2), (500, 2), (500.01, 1),
            (1_500, 1), (1_500.01, 0.75), (2_500, 0.75),
            (2_500.01, 0.50), (25_000, 0.50)
        ]
        for (squareFeet, multiplier) in expectations {
            let result = try PaintingPricingCalculator.calculate(
                squareFeet: squareFeet,
                serviceType: .paintOneCoat,
                customRate: nil,
                settings: settings
            )
            #expect(result.tierMultiplier == multiplier)
        }
    }

    @Test func otherPaintingServiceBypassesEveryTier() throws {
        let result = try PaintingPricingCalculator.calculate(
            squareFeet: 100,
            serviceType: .other,
            customRate: 4.25,
            settings: PaintingPricingSettings()
        )
        #expect(result.tierMultiplier == 1)
        #expect(result.ratePerSquareFoot == 4.25)
        #expect(result.totalPrice == 425)
    }

    @Test func paintingLineItemPreservesNamedMeasurementsAndTotals() throws {
        let measurements = [
            PressureWashingAreaMeasurement(title: "Living Room", squareFeet: 420),
            PressureWashingAreaMeasurement(title: "Hallway", squareFeet: 80)
        ]
        let settings = PaintingPricingSettings(
            tiers: [PaintingPriceTier(startsAtSquareFeet: 0, multiplier: 1)]
        )
        let result = try PaintingPricingCalculator.calculate(
            squareFeet: 500,
            serviceType: .primeAndPaint,
            customRate: nil,
            settings: settings
        )
        let lineItem = PaintingLineItemFactory.makeLineItem(
            serviceType: .primeAndPaint,
            result: result,
            measurements: measurements
        )

        #expect(lineItem.serviceType == .painting)
        #expect(lineItem.catalogItemNameSnapshot == "Prime and Paint")
        #expect(lineItem.quantity == 500)
        #expect(lineItem.unitPrice == 1.85)
        #expect(lineItem.lineTotal == 925)
        #expect(lineItem.description.contains("Living Room: 420 sq ft"))
        #expect(lineItem.description.contains("Hallway: 80 sq ft"))
        #expect(lineItem.description.contains("Total measured area: 500 sq ft"))
    }

    @Test func customPaintingSettingsRoundTripThroughBusinessProfile() throws {
        var profile = BusinessProfile()
        profile.paintingPricing = PaintingPricingSettings(
            paintOneCoatRate: 1.55,
            primeAndPaintRate: 2.15,
            cleanPrimeAndPaintRate: 2.85,
            tiers: [
                PaintingPriceTier(startsAtSquareFeet: 0, multiplier: 2.5),
                PaintingPriceTier(startsAtSquareFeet: 777.77, multiplier: 0.8)
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(BusinessProfile.self, from: data)

        #expect(decoded.paintingPricing == profile.paintingPricing)
        #expect(decoded.paintingPricing.multiplier(for: 50_000) == 0.8)
    }
}
