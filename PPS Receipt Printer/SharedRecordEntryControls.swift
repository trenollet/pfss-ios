import SwiftUI
import UIKit

struct RecordSelectionOption: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String? = nil
}

struct SearchableRecordSelectionField: View {
    let title: String
    let placeholder: String
    let options: [RecordSelectionOption]
    @Binding var selection: String
    var allowsNone = false

    @State private var isPresented = false
    @State private var searchText = ""

    private var selectedTitle: String {
        options.first(where: { $0.id == selection })?.title ?? placeholder
    }

    private var filteredOptions: [RecordSelectionOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    Text(selectedTitle)
                        .foregroundStyle(
                            selection.isEmpty ? Color.secondary : Color.primary
                        )
                        .lineLimit(1)
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                List {
                    if allowsNone {
                        selectionRow(
                            RecordSelectionOption(id: "", title: "None")
                        )
                    }
                    ForEach(filteredOptions) { option in
                        selectionRow(option)
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                }
            }
        }
    }

    private func selectionRow(_ option: RecordSelectionOption) -> some View {
        Button {
            selection = option.id
            isPresented = false
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .foregroundStyle(.primary)
                    if let subtitle = option.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selection == option.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

/// Decimal entry backed by a numeric model value. Editing selects the current
/// value so replacing quantities, prices, and discounts takes one tap.
struct SelectAllDecimalField: View {
    let placeholder: String
    @Binding var value: Double
    var maximumFractionDigits = 2

    var body: some View {
        SelectAllTextField(
            placeholder: placeholder,
            text: Binding(
                get: { formatted(value) },
                set: { value = parsed($0) ?? value }
            )
        )
        .frame(minWidth: 72)
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func parsed(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? 0 : Double(normalized)
    }
}

struct SelectAllIntegerField: View {
    let placeholder: String
    @Binding var value: Int

    var body: some View {
        SelectAllTextField(
            placeholder: placeholder,
            text: Binding(
                get: { String(value) },
                set: { value = Int($0) ?? value }
            ),
            keyboardType: .numberPad
        )
        .frame(minWidth: 72)
    }
}

/// Numeric entry field that selects its entire value whenever editing begins.
struct SelectAllTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad
    var alignment: NSTextAlignment = .right

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.textAlignment = alignment
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.textAlignment = alignment
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField

        init(parent: SelectAllTextField) { self.parent = parent }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }
    }
}
