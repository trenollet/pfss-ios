import Foundation

struct TaxRateQuote: Codable, Equatable {
    var jurisdiction: String
    var rate: Decimal
    var source: String
    var effectiveDate: Date
}

struct TaxOverrideEvidence: Codable, Equatable {
    var reason: String
    var authorizedBy: String
    var authorizedAt: Date
}

struct TaxCalculationSnapshot: Codable, Equatable {
    var jurisdiction: String
    var rateSource: String
    var rateEffectiveDate: Date
    var appliedRate: Decimal
    var taxableSubtotal: Decimal
    var taxIncludedSubtotal: Decimal
    var includedTax: Decimal
    var addedTax: Decimal
    var roundingAdjustment: Decimal
    var exemptionReason: String?
    var overrideEvidence: TaxOverrideEvidence?
    var calculatedAt: Date

    var totalTax: Decimal { includedTax + addedTax }
}

protocol TaxRateProviding {
    func quote(for jurisdiction: String, on date: Date) throws -> TaxRateQuote
}

enum TaxRateProviderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "No verified tax rate is available for this jurisdiction."
    }
}

/// A provider used when an authorized reviewer supplies a verified rate. A
/// remote jurisdiction provider can replace this without changing TaxEngine.
struct AuthorizedTaxRateProvider: TaxRateProviding {
    var rate: Decimal
    var source: String
    var effectiveDate: Date

    func quote(for jurisdiction: String, on date: Date) throws -> TaxRateQuote {
        TaxRateQuote(
            jurisdiction: jurisdiction,
            rate: rate,
            source: source,
            effectiveDate: effectiveDate
        )
    }
}

enum TaxEngineError: LocalizedError {
    case missingClassification
    case invalidRate
    case invalidOverride

    var errorDescription: String? {
        switch self {
        case .missingClassification:
            return "Every invoice line must have a recorded tax classification."
        case .invalidRate:
            return "The tax rate must be between 0% and 100%."
        case .invalidOverride:
            return "A manual rate requires a reason and authorized reviewer."
        }
    }
}

struct TaxEngine {
    static func calculate(
        lines: [ServiceLineItem],
        discount: Decimal,
        quote: TaxRateQuote,
        exemptionReason: String? = nil,
        overrideEvidence: TaxOverrideEvidence? = nil,
        calculatedAt: Date = Date()
    ) throws -> TaxCalculationSnapshot {
        guard quote.rate >= 0, quote.rate <= 1 else {
            throw TaxEngineError.invalidRate
        }
        guard lines.allSatisfy({ $0.taxTreatmentSnapshot != nil }) else {
            throw TaxEngineError.missingClassification
        }
        if quote.source == "Authorized Manual Override" {
            guard let evidence = overrideEvidence,
                  !evidence.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !evidence.authorizedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TaxEngineError.invalidOverride
            }
        }

        let subtotal = lines.reduce(Decimal.zero) {
            $0 + Decimal($1.lineTotal)
        }
        let normalizedDiscount = min(max(discount, 0), subtotal)
        let discountFactor = subtotal > 0
            ? (subtotal - normalizedDiscount) / subtotal
            : 0

        var taxable = Decimal.zero
        var included = Decimal.zero
        for line in lines {
            let discountedAmount = Decimal(line.lineTotal) * discountFactor
            switch line.taxTreatmentSnapshot {
            case .taxable:
                taxable += discountedAmount
            case .taxIncluded:
                included += discountedAmount
            case .nonTaxable, .exempt, .none:
                break
            }
        }

        let isExempt = !(exemptionReason ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rawAddedTax = isExempt ? 0 : taxable * quote.rate
        let rawIncludedTax = isExempt || quote.rate == 0
            ? 0
            : included - (included / (1 + quote.rate))
        let addedTax = currency(rawAddedTax)
        let includedTax = currency(rawIncludedTax)
        let rounding = (addedTax - rawAddedTax) + (includedTax - rawIncludedTax)

        return TaxCalculationSnapshot(
            jurisdiction: quote.jurisdiction,
            rateSource: quote.source,
            rateEffectiveDate: quote.effectiveDate,
            appliedRate: quote.rate,
            taxableSubtotal: currency(taxable),
            taxIncludedSubtotal: currency(included),
            includedTax: includedTax,
            addedTax: addedTax,
            roundingAdjustment: rounding,
            exemptionReason: isExempt ? exemptionReason : nil,
            overrideEvidence: overrideEvidence,
            calculatedAt: calculatedAt
        )
    }

    static func invoiceTotal(
        subtotal: Decimal,
        discount: Decimal,
        snapshot: TaxCalculationSnapshot?
    ) -> Decimal {
        currency(max(subtotal - discount, 0) + (snapshot?.addedTax ?? 0))
    }

    static func currency(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal.zero
        NSDecimalRound(&result, &source, 2, .bankers)
        return result
    }
}
