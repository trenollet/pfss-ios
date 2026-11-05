import SwiftUI

struct SHCalculatorView: View {
    private enum SourceStrength: String, CaseIterable, Identifiable {
        case pool = "Pool Chlorine — 10%"
        case industrial = "Industrial Chlorine — 12.5%"

        var id: String { rawValue }
        var concentration: Decimal {
            switch self {
            case .pool: return 10
            case .industrial: return 12.5
            }
        }
    }

    private enum InputField: Hashable {
        case totalGallons
        case desiredConcentration
    }

    @State private var sourceStrength: SourceStrength = .pool
    @State private var totalGallonsText = ""
    @State private var desiredConcentrationText = ""
    @State private var result: SHDilutionResult?
    @State private var errorMessage = ""
    @FocusState private var focusedField: InputField?

    var body: some View {
        Form {
            Section("SH Product") {
                Picker("Starting Concentration", selection: $sourceStrength) {
                    ForEach(SourceStrength.allCases) { strength in
                        Text(strength.rawValue).tag(strength)
                    }
                }
            }

            Section {
                measurementField(
                    title: "Total Solution",
                    suffix: "gal",
                    text: $totalGallonsText,
                    field: .totalGallons
                )
                measurementField(
                    title: "Desired SH",
                    suffix: "%",
                    text: $desiredConcentrationText,
                    field: .desiredConcentration
                )

                Button(action: calculate) {
                    Label("Calculate Mix", systemImage: "drop.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button("Reset", role: .destructive, action: reset)
                    .frame(maxWidth: .infinity)
            } header: {
                Text("Solution")
            } footer: {
                Text("Enter gallons and concentration using no more than two decimal places.")
            }

            if let result {
                Section {
                    resultRow(
                        title: "SH to Add",
                        gallons: result.shGallons,
                        ounces: result.shOunces,
                        color: .cyan
                    )
                    resultRow(
                        title: "Water to Add",
                        gallons: result.waterGallons,
                        ounces: result.waterOunces,
                        color: .blue
                    )
                    resultRow(
                        title: "Total Solution",
                        gallons: result.totalGallons,
                        ounces: result.totalOunces,
                        color: .secondary
                    )
                } header: {
                    Text("Mixing Amounts")
                } footer: {
                    Text("Calculated from the labeled product strength using C₁V₁ = C₂V₂.")
                }
            }

            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Safety") {
                Label("Use the product label and Safety Data Sheet. Wear appropriate eye and skin protection and work in a ventilated area.", systemImage: "shield.lefthalf.filled")
                Label("Never mix sodium hypochlorite with acids, ammonia, or other cleaning chemicals.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Results assume the product is at its labeled concentration and that the mixture contains only SH solution and water. Sodium hypochlorite loses strength with age, heat, and sunlight.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .navigationTitle("SH Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditorKeyboardDismissAction(isVisible: focusedField != nil) {
                focusedField = nil
            }
        }
        .onChange(of: sourceStrength) { _, _ in clearCalculatedState() }
        .onChange(of: totalGallonsText) { _, _ in clearCalculatedState() }
        .onChange(of: desiredConcentrationText) { _, _ in clearCalculatedState() }
    }

    private func measurementField(
        title: String,
        suffix: String,
        text: Binding<String>,
        field: InputField
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                SelectAllTextField(
                    placeholder: "0.00",
                    text: text,
                    keyboardType: .decimalPad
                )
                .frame(width: 100)
                .frame(minHeight: 30)
                .focused($focusedField, equals: field)
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultRow(
        title: String,
        gallons: Decimal,
        ounces: Decimal,
        color: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text("\(formatted(ounces)) fl oz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(formatted(gallons)) gal")
                .font(.title3.bold())
                .foregroundStyle(color)
        }
    }

    private func calculate() {
        focusedField = nil
        guard hasAtMostTwoDecimalPlaces(totalGallonsText),
              hasAtMostTwoDecimalPlaces(desiredConcentrationText) else {
            result = nil
            errorMessage = "Use no more than two decimal places."
            return
        }
        guard let totalGallons = decimal(from: totalGallonsText) else {
            result = nil
            errorMessage = "Enter a valid total solution amount."
            return
        }
        guard let desiredConcentration = decimal(from: desiredConcentrationText) else {
            result = nil
            errorMessage = "Enter a valid desired SH concentration."
            return
        }

        do {
            result = try SHDilutionCalculator.calculate(
                sourceConcentration: sourceStrength.concentration,
                totalGallons: totalGallons,
                desiredConcentration: desiredConcentration
            )
            errorMessage = ""
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        focusedField = nil
        sourceStrength = .pool
        totalGallonsText = ""
        desiredConcentrationText = ""
        result = nil
        errorMessage = ""
    }

    private func clearCalculatedState() {
        result = nil
        errorMessage = ""
    }

    private func decimal(from text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func hasAtMostTwoDecimalPlaces(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: ",", with: "")
        guard let separator = normalized.firstIndex(of: ".") else { return true }
        return normalized.distance(from: normalized.index(after: separator), to: normalized.endIndex) <= 2
    }

    private func formatted(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
