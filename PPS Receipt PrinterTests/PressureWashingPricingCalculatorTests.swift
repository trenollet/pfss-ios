import Foundation
import PDFKit
import Testing
@testable import PPS_Receipt_Printer

struct PressureWashingPricingCalculatorTests {
    @Test func standardRatesProduceExpectedPrices() throws {
        #expect(try PressureWashingPricingCalculator.calculate(squareFeet: 2_000, ratePerSquareFoot: 0.45).totalPrice == 900)
        #expect(try PressureWashingPricingCalculator.calculate(squareFeet: 1_000, ratePerSquareFoot: 0.65).totalPrice == 650)
        #expect(try PressureWashingPricingCalculator.calculate(squareFeet: 400, ratePerSquareFoot: 0.75).totalPrice == 300)
        #expect(try PressureWashingPricingCalculator.calculate(squareFeet: 100, ratePerSquareFoot: 2.25).totalPrice == 225)
    }

    @Test func customRateProducesExpectedPrice() throws {
        let result = try PressureWashingPricingCalculator.calculate(squareFeet: 125.5, ratePerSquareFoot: 1.20)
        #expect(result.totalPrice == 150.6)
    }

    @Test func invalidInputsAreRejected() {
        #expect(throws: PressureWashingPricingError.invalidSquareFeet) {
            try PressureWashingPricingCalculator.calculate(squareFeet: 0, ratePerSquareFoot: 0.45)
        }
        #expect(throws: PressureWashingPricingError.invalidRate) {
            try PressureWashingPricingCalculator.calculate(squareFeet: 100, ratePerSquareFoot: 0)
        }
    }

    @Test func geometryCalculatesRectangleAndPolygonAreas() {
        let rectangle = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(2, 0, 0),
            SIMD3<Float>(2, 3, 0)
        ]
        let polygon = rectangle + [SIMD3<Float>(0, 3, 0)]

        #expect(abs((ARAreaGeometry.rectangleAreaSquareFeet(points: rectangle) ?? 0) - 64.58346250026) < 0.001)
        #expect(abs((ARAreaGeometry.polygonAreaSquareFeet(points: polygon) ?? 0) - 64.58346250026) < 0.001)
    }

    @Test func multipleNamedMeasurementsAreCombined() {
        let measurements = [
            PressureWashingAreaMeasurement(title: "Front Walk", squareFeet: 120.5),
            PressureWashingAreaMeasurement(title: "Driveway", squareFeet: 850),
            PressureWashingAreaMeasurement(title: "Rear Patio", squareFeet: 200.25)
        ]

        #expect(PressureWashingMeasurementCalculator.totalSquareFeet(measurements) == 1_170.75)
    }

    @Test func defaultTiersAdjustStandardServicesAndContinueHighestTier() throws {
        let settings = PressureWashingPricingSettings()
        let small = try PressureWashingPricingCalculator.calculate(
            squareFeet: 100,
            serviceType: .houseWash,
            customRate: nil,
            settings: settings
        )
        let large = try PressureWashingPricingCalculator.calculate(
            squareFeet: 8_000,
            serviceType: .houseWash,
            customRate: nil,
            settings: settings
        )
        #expect(small.ratePerSquareFoot == 1.35)
        #expect(small.totalPrice == 135)
        #expect(large.ratePerSquareFoot == 0.225)
        #expect(large.totalPrice == 1_800)
    }

    @Test func defaultTierBoundariesUseTheExpectedStartingRanges() throws {
        let settings = PressureWashingPricingSettings()
        let expectations: [(squareFeet: Decimal, multiplier: Decimal)] = [
            (200, 3),
            (200.01, 2),
            (500, 2),
            (500.01, 1),
            (1_500, 1),
            (1_500.01, 0.75),
            (2_500, 0.75),
            (2_500.01, 0.50),
            (25_000, 0.50)
        ]

        for expectation in expectations {
            let result = try PressureWashingPricingCalculator.calculate(
                squareFeet: expectation.squareFeet,
                serviceType: .houseWash,
                customRate: nil,
                settings: settings
            )
            #expect(result.tierMultiplier == expectation.multiplier)
        }
    }

    @Test func otherServiceAlwaysBypassesTiers() throws {
        let result = try PressureWashingPricingCalculator.calculate(
            squareFeet: 100,
            serviceType: .other,
            customRate: 1.25,
            settings: PressureWashingPricingSettings()
        )
        #expect(result.tierMultiplier == 1)
        #expect(result.ratePerSquareFoot == 1.25)
        #expect(result.totalPrice == 125)
    }

    @Test func calculatedPriceBecomesMatchingLineItemWithMeasurementBreakdown() throws {
        let measurements = [
            PressureWashingAreaMeasurement(title: "Front Drive", squareFeet: 850),
            PressureWashingAreaMeasurement(title: "Rear Walk", squareFeet: 120)
        ]
        let result = try PressureWashingPricingCalculator.calculate(
            squareFeet: 970,
            serviceType: .drivewayAndSidewalk,
            customRate: nil,
            settings: PressureWashingPricingSettings()
        )
        let lineItem = PressureWashingLineItemFactory.makeLineItem(
            serviceType: .drivewayAndSidewalk,
            result: result,
            measurements: measurements
        )

        #expect(lineItem.quantity == 970)
        #expect(lineItem.unitPrice == 0.65)
        #expect(lineItem.lineTotal == 630.5)
        #expect(lineItem.description.contains("Front Drive: 850 sq ft"))
        #expect(lineItem.description.contains("Rear Walk: 120 sq ft"))
        #expect(lineItem.description.contains("Total measured area: 970 sq ft"))
    }

    @Test func estimatePDFPreservesEveryNamedMeasurementLine() throws {
        let measurements = [
            PressureWashingAreaMeasurement(title: "Front Drive", squareFeet: 850),
            PressureWashingAreaMeasurement(title: "Rear Walk", squareFeet: 120),
            PressureWashingAreaMeasurement(title: "Pool Deck", squareFeet: 640),
            PressureWashingAreaMeasurement(title: "Side Patio", squareFeet: 310),
            PressureWashingAreaMeasurement(title: "Entry Walk", squareFeet: 80)
        ]
        let result = try PressureWashingPricingCalculator.calculate(
            squareFeet: 2_000,
            serviceType: .drivewayAndSidewalk,
            customRate: nil,
            settings: PressureWashingPricingSettings()
        )
        let lineItem = PressureWashingLineItemFactory.makeLineItem(
            serviceType: .drivewayAndSidewalk,
            result: result,
            measurements: measurements
        )
        let estimate = EstimateRecord(
            estimateNumber: "EST-PDF-WASH",
            leadNumber: "",
            customerNumber: "",
            siteID: nil,
            serviceType: lineItem.serviceType,
            otherService: lineItem.otherService,
            serviceDetails: lineItem.description,
            lineItems: [lineItem],
            subtotal: lineItem.lineTotal,
            discount: 0,
            total: lineItem.lineTotal,
            salesperson: "",
            status: .draft,
            createdDate: Date(),
            expirationDate: Date()
        )

        let url = try EstimatePDFRenderer.createPDF(
            estimate: estimate,
            businessProfile: BusinessProfile(),
            customer: nil,
            site: nil,
            catalogItems: []
        )
        let pdfText = try #require(PDFDocument(url: url)?.string)

        for measurement in measurements {
            #expect(pdfText.contains(measurement.title))
        }
        #expect(pdfText.contains("Total measured area: 2,000 sq ft"))
        #expect(pdfText.contains("2,000"))
        #expect(pdfText.contains("$0.49"))
        #expect(pdfText.contains("$975.00"))
    }

    @Test func washLineItemRoundTripsInsideEstimateAndJobRecords() throws {
        let measurements = [
            PressureWashingAreaMeasurement(title: "Front Drive", squareFeet: 850.25),
            PressureWashingAreaMeasurement(title: "Rear Walk", squareFeet: 119.75)
        ]
        let result = try PressureWashingPricingCalculator.calculate(
            squareFeet: 970,
            serviceType: .drivewayAndSidewalk,
            customRate: nil,
            settings: PressureWashingPricingSettings()
        )
        let lineItem = PressureWashingLineItemFactory.makeLineItem(
            serviceType: .drivewayAndSidewalk,
            result: result,
            measurements: measurements
        )
        let estimate = EstimateRecord(
            estimateNumber: "EST-WASH-ROUNDTRIP",
            leadNumber: "",
            customerNumber: "PPS-TEST",
            siteID: nil,
            serviceType: lineItem.serviceType,
            otherService: lineItem.otherService,
            serviceDetails: lineItem.description,
            lineItems: [lineItem],
            subtotal: lineItem.lineTotal,
            discount: 0,
            total: lineItem.lineTotal,
            salesperson: "",
            status: .draft,
            createdDate: Date(),
            expirationDate: Date()
        )
        let job = JobRecord(
            jobNumber: "JOB-WASH-ROUNDTRIP",
            customerNumber: "PPS-TEST",
            siteID: nil,
            estimateNumber: "",
            serviceType: lineItem.serviceType,
            otherService: lineItem.otherService,
            lineItems: [lineItem],
            subtotal: lineItem.lineTotal,
            discount: 0,
            total: lineItem.lineTotal,
            primaryTechnicianID: nil,
            secondaryTechnicianID: nil,
            scheduledDate: Date(),
            completedDate: nil,
            status: .toBeScheduled,
            workNotes: "",
            isRecurring: false,
            createdDate: Date()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decodedEstimate = try decoder.decode(
            EstimateRecord.self,
            from: encoder.encode(estimate)
        )
        let decodedJob = try decoder.decode(
            JobRecord.self,
            from: encoder.encode(job)
        )

        let estimateLine = try #require(decodedEstimate.lineItems.first)
        let jobLine = try #require(decodedJob.lineItems.first)
        for decodedLine in [estimateLine, jobLine] {
            #expect(decodedLine.description == lineItem.description)
            #expect(decodedLine.quantity == lineItem.quantity)
            #expect(decodedLine.unitPrice == lineItem.unitPrice)
            #expect(decodedLine.lineTotal == lineItem.lineTotal)
        }
    }

    @Test func arbitraryWashSettingsRoundTripThroughBusinessProfile() throws {
        var profile = BusinessProfile()
        profile.pressureWashingPricing = PressureWashingPricingSettings(
            houseWashRate: 0.58,
            drivewayAndSidewalkRate: 0.72,
            fenceRate: 0.81,
            dumpsterAreaRate: 2.65,
            tiers: [
                PressureWashingPriceTier(startsAtSquareFeet: 0, multiplier: 2.75),
                PressureWashingPriceTier(startsAtSquareFeet: 333.33, multiplier: 1.4),
                PressureWashingPriceTier(startsAtSquareFeet: 1_234.56, multiplier: 0.82)
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(BusinessProfile.self, from: data)

        #expect(decoded.pressureWashingPricing == profile.pressureWashingPricing)
        #expect(decoded.pressureWashingPricing.multiplier(for: 50_000) == 0.82)
    }
}
