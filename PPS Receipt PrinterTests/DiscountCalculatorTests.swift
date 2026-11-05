import Foundation
import PDFKit
import Testing
@testable import PPS_Receipt_Printer

struct DiscountCalculatorTests {
    @Test func fixedAndPercentageDiscountsProduceSameExpectedAmount() {
        #expect(DiscountCalculator.amount(subtotal: 500, method: .fixedAmount, inputValue: 75) == 75)
        #expect(DiscountCalculator.amount(subtotal: 500, method: .percentage, inputValue: 15) == 75)
    }

    @Test func discountsCannotExceedTheAmountBeingDiscounted() {
        #expect(DiscountCalculator.amount(subtotal: 100, method: .fixedAmount, inputValue: 250) == 100)
        #expect(DiscountCalculator.amount(subtotal: 100, method: .percentage, inputValue: 150) == 100)
        #expect(DiscountCalculator.amount(subtotal: 100, method: .percentage, inputValue: -10) == 0)
    }

    @Test func itemDiscountUpdatesSavedLineTotalAndWorkOrderSubtotal() {
        let item = ServiceLineItem(
            serviceType: .painting,
            otherService: "Paint One Coat",
            description: "Living Room",
            quantity: 200,
            unitPrice: 1.35,
            lineTotal: 270,
            discountMethod: .percentage,
            discountInputValue: 10
        )
        let updated = PricingCalculator.updatedLineItem(item)

        #expect(updated.lineTotal == 243)
        #expect(PricingCalculator.grossSubtotal(for: [updated]) == 270)
        #expect(PricingCalculator.itemDiscountTotal(for: [updated]) == 27)
        #expect(PricingCalculator.total(for: [updated], discount: 43) == 200)
    }

    @Test func estimateAndJobPreserveDiscountModesThroughSerialization() throws {
        let item = PricingCalculator.updatedLineItem(
            ServiceLineItem(
                serviceType: .pressureWashing,
                otherService: "House Wash",
                description: "Exterior",
                quantity: 100,
                unitPrice: 2,
                lineTotal: 200,
                discountMethod: .fixedAmount,
                discountInputValue: 25
            )
        )
        let estimate = EstimateRecord(
            estimateNumber: "EST-DISCOUNT",
            leadNumber: "",
            customerNumber: "TEST",
            siteID: nil,
            serviceType: .pressureWashing,
            otherService: "House Wash",
            serviceDetails: "Exterior",
            lineItems: [item],
            subtotal: 175,
            discount: 17.5,
            total: 157.5,
            salesperson: "",
            status: .draft,
            createdDate: Date(),
            expirationDate: Date(),
            discountMethod: .percentage,
            discountInputValue: 10
        )
        let job = JobRecord(
            jobNumber: "JOB-DISCOUNT",
            title: "Exterior Refresh",
            leadNumber: "LEAD-TEST",
            customerNumber: "TEST",
            siteID: nil,
            estimateNumber: estimate.estimateNumber,
            serviceType: estimate.serviceType,
            otherService: estimate.otherService,
            lineItems: estimate.lineItems,
            subtotal: estimate.subtotal,
            discount: estimate.discount,
            discountMethod: estimate.discountMethod,
            discountInputValue: estimate.discountInputValue,
            total: estimate.total,
            salesperson: "Alex Sales",
            expirationDate: estimate.expirationDate,
            primaryTechnicianID: nil,
            secondaryTechnicianID: nil,
            scheduledDate: Date(),
            completedDate: nil,
            status: .toBeScheduled,
            workNotes: "",
            scopeOfWork: "Prepare and coat all named areas.",
            isRecurring: false,
            createdDate: Date()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decodedEstimate = try decoder.decode(EstimateRecord.self, from: encoder.encode(estimate))
        let decodedJob = try decoder.decode(JobRecord.self, from: encoder.encode(job))

        #expect(decodedJob.title == "Exterior Refresh")
        #expect(decodedJob.leadNumber == "LEAD-TEST")
        #expect(decodedJob.salesperson == "Alex Sales")
        #expect(decodedJob.expirationDate == estimate.expirationDate)
        #expect(decodedJob.scopeOfWork == "Prepare and coat all named areas.")

        for record in [
            (decodedEstimate.discountMethod, decodedEstimate.discountInputValue, decodedEstimate.lineItems[0]),
            (decodedJob.discountMethod, decodedJob.discountInputValue, decodedJob.lineItems[0])
        ] {
            #expect(record.0 == .percentage)
            #expect(record.1 == 10)
            #expect(record.2.discountMethod == .fixedAmount)
            #expect(record.2.discountInputValue == 25)
            #expect(record.2.lineTotal == 175)
        }
    }

    @Test func estimatePDFExplainsItemAndPercentagePricingDiscounts() throws {
        let item = PricingCalculator.updatedLineItem(
            ServiceLineItem(
                serviceType: .painting,
                otherService: "Prime and Paint",
                description: "Living Room",
                quantity: 100,
                unitPrice: 2,
                lineTotal: 200,
                discountMethod: .percentage,
                discountInputValue: 10
            )
        )
        let estimate = EstimateRecord(
            estimateNumber: "EST-DISCOUNT-PDF",
            leadNumber: "",
            customerNumber: "TEST",
            siteID: nil,
            serviceType: .painting,
            otherService: "Prime and Paint",
            serviceDetails: item.description,
            lineItems: [item],
            subtotal: 180,
            discount: 18,
            total: 162,
            salesperson: "",
            status: .draft,
            createdDate: Date(),
            expirationDate: Date(),
            discountMethod: .percentage,
            discountInputValue: 10
        )

        let url = try EstimatePDFRenderer.createPDF(
            estimate: estimate,
            businessProfile: BusinessProfile(),
            customer: nil,
            site: nil,
            catalogItems: []
        )
        let text = try #require(PDFDocument(url: url)?.string)
        #expect(text.contains("Item discount: 10%"))
        #expect(text.contains("Discount (10%)"))
        #expect(text.contains("$162.00"))
        #expect(text.components(separatedBy: "EST-DISCOUNT-PDF").count - 1 == 1)
    }
}
