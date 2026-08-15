import XCTest
@testable import PPS_Receipt_Printer

final class TaxEngineTests: XCTestCase {
    func testMixedTreatmentsAndIncludedTax() throws {
        let result = try TaxEngine.calculate(
            lines: [
                line(100, .taxable),
                line(108.25, .taxIncluded),
                line(50, .nonTaxable)
            ],
            discount: 0,
            quote: quote(rate: "0.0825"),
            calculatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(result.taxableSubtotal, decimal("100.00"))
        XCTAssertEqual(result.addedTax, decimal("8.25"))
        XCTAssertEqual(result.includedTax, decimal("8.25"))
        XCTAssertEqual(
            TaxEngine.invoiceTotal(
                subtotal: decimal("258.25"),
                discount: 0,
                snapshot: result
            ),
            decimal("266.50")
        )
    }

    func testDiscountIsAllocatedProportionally() throws {
        let result = try TaxEngine.calculate(
            lines: [line(100, .taxable), line(100, .nonTaxable)],
            discount: 20,
            quote: quote(rate: "0.10")
        )

        XCTAssertEqual(result.taxableSubtotal, decimal("90.00"))
        XCTAssertEqual(result.addedTax, decimal("9.00"))
    }

    func testExemptionSuppressesTaxButPreservesEvidence() throws {
        let result = try TaxEngine.calculate(
            lines: [line(100, .taxable)],
            discount: 0,
            quote: quote(rate: "0.10"),
            exemptionReason: "Verified resale certificate"
        )

        XCTAssertEqual(result.addedTax, 0)
        XCTAssertEqual(result.exemptionReason, "Verified resale certificate")
    }

    func testManualOverrideRequiresAuditEvidence() {
        XCTAssertThrowsError(
            try TaxEngine.calculate(
                lines: [line(100, .taxable)],
                discount: 0,
                quote: TaxRateQuote(
                    jurisdiction: "Test",
                    rate: decimal("0.10"),
                    source: "Authorized Manual Override",
                    effectiveDate: Date()
                )
            )
        )
    }

    func testMissingLegacyClassificationFailsClosed() {
        XCTAssertThrowsError(
            try TaxEngine.calculate(
                lines: [line(100, nil)],
                discount: 0,
                quote: quote(rate: "0.10")
            )
        )
    }

    private func line(_ total: Double, _ treatment: TaxTreatment?) -> ServiceLineItem {
        ServiceLineItem(
            taxTreatmentSnapshot: treatment,
            serviceType: .other,
            otherService: "Test",
            description: "",
            quantity: 1,
            unitPrice: total,
            lineTotal: total
        )
    }

    private func quote(rate: String) -> TaxRateQuote {
        TaxRateQuote(
            jurisdiction: "Oklahoma City, OK",
            rate: decimal(rate),
            source: "Test Provider",
            effectiveDate: Date(timeIntervalSince1970: 1)
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
