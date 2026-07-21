import SwiftUI

struct JobRecurrencePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: JobRecurrenceFrequency?
    @State private var draftSelection: JobRecurrenceFrequency

    init(selection: Binding<JobRecurrenceFrequency?>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue ?? .weekly)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repeat Job") {
                    Picker("Frequency", selection: $draftSelection) {
                        ForEach(JobRecurrenceFrequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Text("PFSS will create the next occurrence automatically and place it into future dispatch scheduling without assigning a technician.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        selection = draftSelection
                        dismiss()
                    }
                }
            }
        }
    }
}
