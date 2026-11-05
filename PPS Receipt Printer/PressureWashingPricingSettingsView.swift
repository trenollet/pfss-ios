import SwiftUI

struct PressureWashingPricingSettingsView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings = PressureWashingPricingSettings()
    @State private var didLoad = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section {
                rateField("House Wash", value: $settings.houseWashRate)
                rateField("Driveway & Sidewalk", value: $settings.drivewayAndSidewalkRate)
                rateField("Fence", value: $settings.fenceRate)
                rateField("Dumpster Area", value: $settings.dumpsterAreaRate)
            } header: {
                Text("Default Price per Square Foot")
            } footer: {
                Text("The Other service always uses the custom rate entered in the calculator and does not use size factors.")
            }

            Section {
                ForEach($settings.tiers) { $tier in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Starts at")
                            Spacer()
                            DecimalSettingsField(value: $tier.startsAtSquareFeet, suffix: "sq ft")
                        }
                        HStack {
                            Text("Price factor")
                            Spacer()
                            DecimalSettingsField(value: $tier.multiplier, suffix: "×")
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            settings.tiers.removeAll { $0.id == tier.id }
                        }
                    }
                }

                Button {
                    let nextStart = (settings.tiers.map(\.startsAtSquareFeet).max() ?? 0) + 500
                    settings.tiers.append(
                        PressureWashingPriceTier(startsAtSquareFeet: nextStart, multiplier: 1)
                    )
                } label: {
                    Label("Add Pricing Range", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Size Pricing Ranges")
            } footer: {
                Text("PFSS uses the factor from the largest starting point the job has reached. The highest range continues upward until another range is added.")
            }

            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Wash Pricing Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            settings = store.businessProfile.pressureWashingPricing
            didLoad = true
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func rateField(_ title: String, value: Binding<Decimal>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("$").foregroundStyle(.secondary)
            DecimalSettingsField(value: value, suffix: "")
        }
    }

    private func save() {
        guard !settings.tiers.isEmpty,
              settings.tiers.allSatisfy({ $0.startsAtSquareFeet >= 0 && $0.multiplier > 0 }) else {
            errorMessage = "Every range needs a nonnegative starting area and a factor greater than zero."
            return
        }
        settings.normalize()
        store.businessProfile.pressureWashingPricing = settings
        dismiss()
    }
}

private struct DecimalSettingsField: View {
    @Binding var value: Decimal
    let suffix: String
    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            SelectAllTextField(placeholder: "0.00", text: $text, keyboardType: .decimalPad)
                .frame(width: 92)
                .frame(minHeight: 30)
            if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
        }
        .onAppear { text = number(value) }
        .onChange(of: text) { _, newValue in
            let normalized = newValue.replacingOccurrences(of: ",", with: "")
            if let parsed = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) {
                value = parsed
            }
        }
        .onChange(of: value) { _, newValue in
            let formatted = number(newValue)
            if text != formatted { text = formatted }
        }
    }

    private func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
