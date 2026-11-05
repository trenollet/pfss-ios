import ARKit
import SwiftUI

struct PressureWashingPricingView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    var onAddLineItem: ((ServiceLineItem) -> Void)? = nil
    private enum InputField: Hashable { case squareFeet, customRate }

    @State private var serviceType: PressureWashingServiceType = .houseWash
    @State private var squareFeetText = ""
    @State private var customRateText = ""
    @State private var result: PressureWashingPriceResult?
    @State private var errorMessage = ""
    @State private var measurements: [PressureWashingAreaMeasurement] = []
    @FocusState private var focusedField: InputField?

    var body: some View {
        Form {
            Section("Washing Type") {
                Picker("Service", selection: $serviceType) {
                    ForEach(PressureWashingServiceType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if let rate = store.businessProfile.pressureWashingPricing.baseRate(for: serviceType) {
                    LabeledContent("Price per Square Foot", value: currency(rate))
                } else {
                    currencyField(title: "Custom Price", text: $customRateText, field: .customRate)
                }
            }

            Section {
                LabeledContent("Square Feet") {
                    SelectAllTextField(placeholder: "0.00", text: $squareFeetText, keyboardType: .decimalPad)
                        .frame(width: 120)
                        .frame(minHeight: 30)
                        .focused($focusedField, equals: .squareFeet)
                }

                NavigationLink {
                    PressureWashingMeasurementsView(measurements: $measurements) { total in
                        squareFeetText = number(total)
                    }
                } label: {
                    HStack {
                        Label("Measurements", systemImage: "ruler")
                        Spacer()
                        if !measurements.isEmpty {
                            Text("\(measurements.count) areas")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(measurements.isEmpty
                     ? "Enter one total manually or open Measurements to measure and combine several areas."
                     : "The saved measurements remain available if you need to reopen the list and add another area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Area")
            }

            Section {
                Button(action: calculate) {
                    Label("Calculate Price", systemImage: "dollarsign.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("Reset", role: .destructive, action: reset)
                    .frame(maxWidth: .infinity)
            }

            if let result {
                Section("Price Summary") {
                    LabeledContent("Washing Type", value: serviceType.rawValue)
                    LabeledContent("Measured Area", value: "\(number(result.squareFeet)) sq ft")
                    LabeledContent("Default Rate", value: "\(currency(result.baseRatePerSquareFoot))/sq ft")
                    if serviceType != .other {
                        LabeledContent("Size Factor", value: "\(number(result.tierMultiplier))×")
                    }
                    LabeledContent("Adjusted Rate", value: "\(currency(result.ratePerSquareFoot))/sq ft")
                    HStack {
                        Text("Estimated Price").fontWeight(.semibold)
                        Spacer()
                        Text(currency(result.totalPrice))
                            .font(.title2.bold())
                            .foregroundStyle(.orange)
                    }
                }

                Section("Use This Price") {
                    if let lineItem = calculatedLineItem {
                        if let onAddLineItem {
                            Button {
                                onAddLineItem(lineItem)
                                dismiss()
                            } label: {
                                Label("Add to Current Record", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        NavigationLink {
                            EstimateNewView(initialLineItems: [lineItem])
                                .environmentObject(store)
                        } label: {
                            Label("Create New Estimate", systemImage: "doc.text.fill")
                        }

                        NavigationLink {
                            JobNewView(initialLineItems: [lineItem])
                                .environmentObject(store)
                        } label: {
                            Label("Create New Job", systemImage: "wrench.and.screwdriver.fill")
                        }
                    }
                }
            }

            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Wash Pricing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditorKeyboardDismissAction(isVisible: focusedField != nil) { focusedField = nil }
        }
        .onChange(of: serviceType) { _, _ in clearResult() }
        .onChange(of: squareFeetText) { _, _ in clearResult() }
        .onChange(of: customRateText) { _, _ in clearResult() }
    }

    private func currencyField(title: String, text: Binding<String>, field: InputField) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Text("$").foregroundStyle(.secondary)
                SelectAllTextField(placeholder: "0.00", text: text, keyboardType: .decimalPad)
                    .frame(width: 100)
                    .frame(minHeight: 30)
                    .focused($focusedField, equals: field)
            }
        }
    }

    private func calculate() {
        focusedField = nil
        guard let squareFeet = decimal(from: squareFeetText) else {
            result = nil
            errorMessage = "Enter a valid square-foot measurement."
            return
        }
        let customRate = serviceType == .other ? decimal(from: customRateText) : nil
        if serviceType == .other, customRate == nil {
            result = nil
            errorMessage = "Enter a valid custom price per square foot."
            return
        }

        do {
            result = try PressureWashingPricingCalculator.calculate(
                squareFeet: squareFeet,
                serviceType: serviceType,
                customRate: customRate,
                settings: store.businessProfile.pressureWashingPricing
            )
            errorMessage = ""
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        focusedField = nil
        serviceType = .houseWash
        squareFeetText = ""
        customRateText = ""
        measurements = []
        result = nil
        errorMessage = ""
    }

    private func clearResult() {
        result = nil
        errorMessage = ""
    }

    private func decimal(from text: String) -> Decimal? {
        Decimal(
            string: text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func currency(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private var calculatedLineItem: ServiceLineItem? {
        guard let result else { return nil }
        return PressureWashingLineItemFactory.makeLineItem(
            serviceType: serviceType,
            result: result,
            measurements: measurements
        )
    }
}
