import SwiftUI

struct InvoiceTaxCalculationView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var invoice: InvoiceRecord
    let site: CustomerSite?
    let reviewerName: String
    let companyTaxSettings: BusinessTaxSettings

    @State private var ratePercent: Double
    @State private var overrideReason: String
    @State private var exemptionReason: String
    @State private var errorMessage = ""
    @State private var showingError = false
    @FocusState private var isInputFocused: Bool

    init(
        invoice: Binding<InvoiceRecord>,
        site: CustomerSite?,
        reviewerName: String,
        companyTaxSettings: BusinessTaxSettings
    ) {
        _invoice = invoice
        self.site = site
        self.reviewerName = reviewerName
        self.companyTaxSettings = companyTaxSettings
        _ratePercent = State(
            initialValue: NSDecimalNumber(
                decimal: invoice.wrappedValue.taxSnapshot?.appliedRate
                    ?? Decimal(companyTaxSettings.standardRatePercent / 100)
            ).doubleValue * 100
        )
        _overrideReason = State(
            initialValue: invoice.wrappedValue.taxSnapshot?
                .overrideEvidence?.reason
                ?? companyTaxSettings.sourceNotes
        )
        _exemptionReason = State(
            initialValue: invoice.wrappedValue.taxSnapshot?
                .exemptionReason ?? ""
        )
    }

    private var jurisdiction: String {
        let address = site?.serviceAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        return address.isEmpty ? "Job-site jurisdiction unavailable" : address
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Jurisdiction Evidence") {
                    LabeledContent("Job Site", value: jurisdiction)
                    Text(
                        "PFSS does not guess a tax rate. Until a verified rate "
                        + "provider is connected, an authorized reviewer must "
                        + "enter a verified rate and reason."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }


                if companyTaxSettings.isConfigured {
                    Section("Company Standard Rate") {
                        LabeledContent("Jurisdiction", value: companyTaxSettings.jurisdictionName)
                        LabeledContent("Configured Rate") {
                            Text(companyTaxSettings.standardRatePercent / 100, format: .percent.precision(.fractionLength(3)))
                        }
                        LabeledContent("Verified By", value: companyTaxSettings.verifiedBy)
                    }
                }

                Section("Authorized Manual Rate") {
                    LabeledContent("Tax Rate") {
                        HStack(spacing: 4) {
                            SelectAllDecimalField(
                                placeholder: "0.000",
                                value: $ratePercent
                            )
                            .focused($isInputFocused)
                            Text("%")
                        }
                        .frame(maxWidth: 150)
                    }

                    TextField(
                        isUsingCompanyRate
                            ? "Rate source or notes (optional)"
                            : "Required override reason",
                        text: $overrideReason,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .focused($isInputFocused)

                    TextField(
                        "Exemption reason (optional)",
                        text: $exemptionReason,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .focused($isInputFocused)
                }

                Section {
                    Button("Calculate and Apply Tax") { applyTax() }
                        .frame(maxWidth: .infinity)
                        .disabled(
                            ratePercent < 0 || ratePercent > 100 ||
                            (!isUsingCompanyRate && overrideReason
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty)
                        )
                } footer: {
                    Text(
                        "The applied rate and reviewer evidence become part of "
                        + "this invoice snapshot. Catalog changes do not alter it."
                    )
                }
            }
            .navigationTitle("Invoice Tax")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss Keyboard") { isInputFocused = false }
                }
            }
            .alert("Unable to Calculate Tax", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var isUsingCompanyRate: Bool {
        companyTaxSettings.isConfigured
            && abs(ratePercent - companyTaxSettings.standardRatePercent) < 0.000_001
    }

    private func applyTax() {
        isInputFocused = false
        let now = Date()
        let evidence = isUsingCompanyRate ? nil : TaxOverrideEvidence(
            reason: overrideReason.trimmingCharacters(in: .whitespacesAndNewlines),
            authorizedBy: reviewerName,
            authorizedAt: now
        )
        let quote = TaxRateQuote(
            jurisdiction: isUsingCompanyRate
                ? companyTaxSettings.jurisdictionName
                : jurisdiction,
            rate: Decimal(ratePercent / 100),
            source: isUsingCompanyRate
                ? "Company Standard Rate · Verified by \(companyTaxSettings.verifiedBy)"
                : "Authorized Manual Override",
            effectiveDate: isUsingCompanyRate
                ? companyTaxSettings.effectiveDate
                : now
        )

        do {
            let snapshot = try TaxEngine.calculate(
                lines: invoice.lineItems,
                discount: Decimal(invoice.discount),
                quote: quote,
                exemptionReason: exemptionReason,
                overrideEvidence: evidence,
                calculatedAt: now
            )
            invoice = InvoiceEngine.applyingTax(snapshot, to: invoice, at: now)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
