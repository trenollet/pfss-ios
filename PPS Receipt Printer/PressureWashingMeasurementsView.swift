import SwiftUI

private struct PressureWashingMeasurementDraft: Identifiable {
    let id = UUID()
    var existingMeasurementID: UUID?
    var title: String
    var squareFeetText: String
}

struct PressureWashingMeasurementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var measurements: [PressureWashingAreaMeasurement]
    let onUseTotal: (Decimal) -> Void

    @State private var showsCameraMeasurement = false
    @State private var measurementDraft: PressureWashingMeasurementDraft?

    private var totalSquareFeet: Decimal {
        PressureWashingMeasurementCalculator.totalSquareFeet(measurements)
    }

    var body: some View {
        List {
            if measurements.isEmpty {
                ContentUnavailableView(
                    "No Measurements Yet",
                    systemImage: "ruler",
                    description: Text("Measure each section separately, give it a useful name, then combine the areas.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Saved Areas") {
                    ForEach(measurements) { measurement in
                        Button {
                            measurementDraft = PressureWashingMeasurementDraft(
                                existingMeasurementID: measurement.id,
                                title: measurement.title,
                                squareFeetText: number(measurement.squareFeet)
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(measurement.title)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text("Tap to revise")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(number(measurement.squareFeet)) sq ft")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                measurements.removeAll { $0.id == measurement.id }
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Combined Area") {
                        Text("\(number(totalSquareFeet)) sq ft")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    showsCameraMeasurement = true
                } label: {
                    Label("Add Camera Measurement", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    measurementDraft = PressureWashingMeasurementDraft(
                        existingMeasurementID: nil,
                        title: defaultTitle,
                        squareFeetText: ""
                    )
                } label: {
                    Label("Add Manual Measurement", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !measurements.isEmpty {
                Section {
                    Button {
                        onUseTotal(totalSquareFeet)
                        dismiss()
                    } label: {
                        Label("Use Total Area", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } footer: {
                    Text("Returns the combined square footage to the pricing calculator. You can reopen this page and add more areas at any time.")
                }
            }
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsCameraMeasurement) {
            NavigationStack {
                ARAreaMeasurementView { measuredArea in
                    measurementDraft = PressureWashingMeasurementDraft(
                        existingMeasurementID: nil,
                        title: defaultTitle,
                        squareFeetText: measuredArea.formatted(.number.precision(.fractionLength(0...2)))
                    )
                }
            }
        }
        .sheet(item: $measurementDraft) { draft in
            measurementEditor(draft)
        }
    }

    private var defaultTitle: String {
        "Area \(measurements.count + 1)"
    }

    private func measurementEditor(_ initialDraft: PressureWashingMeasurementDraft) -> some View {
        PressureWashingMeasurementEditor(
            initialTitle: initialDraft.title,
            initialSquareFeet: initialDraft.squareFeetText,
            onSave: { title, squareFeet in
                if let existingID = initialDraft.existingMeasurementID,
                   let existingIndex = measurements.firstIndex(where: { $0.id == existingID }) {
                    measurements[existingIndex].title = title
                    measurements[existingIndex].squareFeet = squareFeet
                } else {
                    measurements.append(
                        PressureWashingAreaMeasurement(title: title, squareFeet: squareFeet)
                    )
                }
                measurementDraft = nil
            },
            onCancel: { measurementDraft = nil }
        )
    }

    private func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct PressureWashingMeasurementEditor: View {
    @State private var title: String
    @State private var squareFeetText: String
    @State private var errorMessage = ""
    let onSave: (String, Decimal) -> Void
    let onCancel: () -> Void

    init(
        initialTitle: String,
        initialSquareFeet: String,
        onSave: @escaping (String, Decimal) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _title = State(initialValue: initialTitle)
        _squareFeetText = State(initialValue: initialSquareFeet)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Measurement") {
                    SelectAllTextField(
                        placeholder: "Title, such as Front Walk",
                        text: $title,
                        keyboardType: .default
                    )
                    .frame(minHeight: 34)
                    LabeledContent("Area") {
                        HStack(spacing: 5) {
                            TextField("0.00", text: $squareFeetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("sq ft").foregroundStyle(.secondary)
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
            .navigationTitle("Save Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            errorMessage = "Enter a title so this area is easy to identify."
            return
        }
        let normalized = squareFeetText.replacingOccurrences(of: ",", with: "")
        guard let squareFeet = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), squareFeet > 0 else {
            errorMessage = "Enter an area greater than zero."
            return
        }
        onSave(cleanedTitle, squareFeet)
    }
}
