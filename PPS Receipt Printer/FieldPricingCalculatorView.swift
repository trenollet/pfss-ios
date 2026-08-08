//
//  FieldPricingCalculatorView.swift
//  PPS Receipt Printer
//
//  Phase 18 – Fast field pricing for routine service estimates.
//

import SwiftUI

struct FieldPricingCalculatorView: View {
    private enum Frequency: String, Identifiable {
        case weekly = "Weekly"
        case biWeekly = "Bi-Weekly"
        case monthly = "Monthly"

        var id: String { rawValue }
    }

    @State private var basePriceText = ""
    @State private var weeklyPercentage = FieldPricingEngine.defaultWeeklyPercentage
    @State private var biWeeklyPercentage = FieldPricingEngine.defaultBiWeeklyPercentage
    @State private var monthlyPercentage = FieldPricingEngine.defaultMonthlyPercentage
    @State private var breakdown: FieldPricingBreakdown?
    @State private var errorMessage = ""
    @State private var editingFrequency: Frequency?
    @State private var percentageText = ""
    @FocusState private var isBasePriceFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $basePriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isBasePriceFocused)
                        .onSubmit(calculate)
                }

                Button(action: calculate) {
                    Label("Calculate Pricing", systemImage: "calculator.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("Base Price")
            } footer: {
                Text("Enter the one time service price to calculate each service frequency.")
            }

            if let breakdown {
                Section {
                    priceRow(
                        .weekly,
                        percentage: weeklyPercentage,
                        value: breakdown.weeklyPrice
                    )
                    priceRow(
                        .biWeekly,
                        percentage: biWeeklyPercentage,
                        value: breakdown.biWeeklyPrice
                    )
                    priceRow(
                        .monthly,
                        percentage: monthlyPercentage,
                        value: breakdown.monthlyPrice
                    )
                } header: {
                    Text("Calculated Pricing")
                } footer: {
                    Text("Tap a frequency to adjust its percentage of the base price.")
                }
            }

            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Pricing Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditorKeyboardDismissAction(isVisible: isBasePriceFocused) {
                isBasePriceFocused = false
            }
        }
        .onChange(of: basePriceText) { _, _ in
            errorMessage = ""
        }
        .sheet(item: $editingFrequency) { frequency in
            percentageEditor(for: frequency)
                .presentationDetents([.height(260)])
        }
    }

    private func priceRow(
        _ frequency: Frequency,
        percentage: Decimal,
        value: Decimal
    ) -> some View {
        Button {
            percentageText = percentage.formatted(.number.precision(.fractionLength(0...2)))
            editingFrequency = frequency
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(frequency.rawValue)
                        .foregroundStyle(.primary)
                    Text("\(percentage.formatted(.number.precision(.fractionLength(0...2))))% of base")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(value, format: .currency(code: "USD"))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func percentageEditor(for frequency: Frequency) -> some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        SelectAllTextField(
                            placeholder: "Percentage",
                            text: $percentageText,
                            keyboardType: .decimalPad
                        )
                        .frame(minWidth: 90)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("The \(frequency.rawValue.lowercased()) price will be this percentage of the base price.")
                }
            }
            .navigationTitle("Adjust \(frequency.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingFrequency = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyPercentage(for: frequency) }
                        .disabled(parsedPercentage == nil)
                }
            }
        }
    }

    private func calculate() {
        isBasePriceFocused = false

        guard let basePrice = parsedBasePrice else {
            breakdown = nil
            errorMessage = FieldPricingError.invalidBasePrice.localizedDescription
            return
        }

        do {
            breakdown = try FieldPricingEngine.calculate(
                basePrice: basePrice,
                weeklyPercentage: weeklyPercentage,
                biWeeklyPercentage: biWeeklyPercentage,
                monthlyPercentage: monthlyPercentage
            )
            errorMessage = ""
        } catch {
            breakdown = nil
            errorMessage = error.localizedDescription
        }
    }

    private var parsedBasePrice: Decimal? {
        let normalized = basePriceText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var parsedPercentage: Decimal? {
        let normalized = percentageText
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        ), value >= 0, value <= 1_000 else {
            return nil
        }
        return value
    }

    private func applyPercentage(for frequency: Frequency) {
        guard let percentage = parsedPercentage else { return }
        switch frequency {
        case .weekly:
            weeklyPercentage = percentage
        case .biWeekly:
            biWeeklyPercentage = percentage
        case .monthly:
            monthlyPercentage = percentage
        }
        editingFrequency = nil
        calculate()
    }
}
