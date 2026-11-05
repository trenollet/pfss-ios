import SwiftUI

struct DiscountEditorRows: View {
    let title: String
    @Binding var method: PricingDiscountMethod
    @Binding var inputValue: Double
    let subtotal: Double

    @State private var isEditorPresented = false

    private var discountAmount: Double {
        DiscountCalculator.amount(
            subtotal: subtotal,
            method: method,
            inputValue: inputValue
        )
    }

    private var summary: String {
        guard discountAmount > 0 else { return "No Discount" }
        if method == .percentage {
            let percentage = inputValue.formatted(
                .number.precision(.fractionLength(0...2))
            )
            return "\(percentage)% (\(discountAmount.formatted(.currency(code: "USD"))))"
        }
        return discountAmount.formatted(.currency(code: "USD"))
    }

    var body: some View {
        Button {
            isEditorPresented = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .sheet(isPresented: $isEditorPresented) {
            DiscountEditorSheet(
                title: title,
                method: $method,
                inputValue: $inputValue,
                subtotal: subtotal
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

struct DiscountEditorSheet: View {
    let title: String
    @Binding var method: PricingDiscountMethod
    @Binding var inputValue: Double
    let subtotal: Double

    @Environment(\.dismiss) private var dismiss
    @State private var draftMethod: PricingDiscountMethod
    @State private var draftInputValue: Double
    @FocusState private var isInputFocused: Bool

    init(
        title: String,
        method: Binding<PricingDiscountMethod>,
        inputValue: Binding<Double>,
        subtotal: Double
    ) {
        self.title = title
        _method = method
        _inputValue = inputValue
        self.subtotal = subtotal
        _draftMethod = State(initialValue: method.wrappedValue)
        _draftInputValue = State(initialValue: inputValue.wrappedValue)
    }

    private var discountAmount: Double {
        DiscountCalculator.amount(
            subtotal: subtotal,
            method: draftMethod,
            inputValue: draftInputValue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Discount Type", selection: $draftMethod) {
                        ForEach(PricingDiscountMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent(
                        draftMethod == .fixedAmount ? "Dollar Amount" : "Percentage"
                    ) {
                        HStack(spacing: 4) {
                            if draftMethod == .fixedAmount {
                                Text("$").foregroundStyle(.secondary)
                            }
                            SelectAllDecimalField(
                                placeholder: "0.00",
                                value: $draftInputValue
                            )
                            .focused($isInputFocused)
                            .frame(width: 110)
                            if draftMethod == .percentage {
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Discount") {
                        Text(discountAmount, format: .currency(code: "USD"))
                            .bold()
                    }
                    LabeledContent("After Discount") {
                        Text(
                            max(subtotal - discountAmount, 0),
                            format: .currency(code: "USD")
                        )
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        method = draftMethod
                        inputValue = normalizedInputValue
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                isInputFocused = true
            }
            .onChange(of: draftInputValue) { _, newValue in
                let normalized = normalize(newValue)
                if draftInputValue != normalized {
                    draftInputValue = normalized
                }
            }
            .onChange(of: draftMethod) { _, _ in
                draftInputValue = normalize(draftInputValue)
            }
        }
    }

    private var normalizedInputValue: Double {
        normalize(draftInputValue)
    }

    private func normalize(_ value: Double) -> Double {
        let upperLimit = draftMethod == .percentage ? 100 : max(subtotal, 0)
        return min(max(value, 0), upperLimit)
    }
}
