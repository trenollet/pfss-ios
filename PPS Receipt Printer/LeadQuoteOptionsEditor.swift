import SwiftUI

struct LeadQuoteOptionsEditor: View {
    @Binding var quoteOptions: [LeadQuoteOption]
    var isInputFocused: FocusState<Bool>.Binding

    var body: some View {
        ForEach($quoteOptions) { $option in
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Quoted Price") {
                    HStack(spacing: 3) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        SelectAllDecimalField(
                            placeholder: "0.00",
                            value: $option.quotedPrice
                        )
                        .focused(isInputFocused)
                        .frame(width: 125)
                    }
                }

                Picker("Frequency", selection: $option.frequency) {
                    ForEach(LeadServiceFrequency.allCases) { frequency in
                        Text(frequency.rawValue).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                if quoteOptions.count > 1 {
                    Button(role: .destructive) {
                        remove(option.id)
                    } label: {
                        Label("Remove Quote", systemImage: "minus.circle")
                    }
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }

        HStack {
            Spacer()
            Button {
                quoteOptions.append(
                    LeadQuoteOption(quotedPrice: 0, frequency: .monthly)
                )
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Another Quoted Price and Frequency")
            Spacer()
        }
    }

    private func remove(_ id: UUID) {
        guard quoteOptions.count > 1 else { return }
        quoteOptions.removeAll { $0.id == id }
    }
}
