import SwiftUI

struct JobRecurrencePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: JobRecurrenceFrequency?
    @Binding var endMode: JobRecurrenceEndMode
    @Binding var endDate: Date?
    @Binding var occurrenceCount: Int?
    private let siteSelection: Binding<UUID?>?
    private let siteOptions: [CustomerSite]
    @State private var draftSelection: JobRecurrenceFrequency
    @State private var draftEndMode: JobRecurrenceEndMode
    @State private var draftEndDate: Date
    @State private var draftOccurrenceCount: Int
    @State private var draftSiteID: UUID?
    private let onSave: ((
        JobRecurrenceFrequency,
        JobRecurrenceEndMode,
        Date?,
        Int?,
        UUID?
    ) -> Void)?

    init(
        selection: Binding<JobRecurrenceFrequency?>,
        endMode: Binding<JobRecurrenceEndMode>,
        endDate: Binding<Date?>,
        occurrenceCount: Binding<Int?>,
        siteSelection: Binding<UUID?>? = nil,
        siteOptions: [CustomerSite] = [],
        onSave: ((
            JobRecurrenceFrequency,
            JobRecurrenceEndMode,
            Date?,
            Int?,
            UUID?
        ) -> Void)? = nil
    ) {
        _selection = selection
        _endMode = endMode
        _endDate = endDate
        _occurrenceCount = occurrenceCount
        self.siteSelection = siteSelection
        self.siteOptions = siteOptions
        _draftSelection = State(initialValue: selection.wrappedValue ?? .weekly)
        _draftEndMode = State(initialValue: endMode.wrappedValue)
        _draftEndDate = State(
            initialValue: endDate.wrappedValue
                ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())
                ?? Date()
        )
        _draftOccurrenceCount = State(
            initialValue: max(occurrenceCount.wrappedValue ?? 12, 1)
        )
        _draftSiteID = State(initialValue: siteSelection?.wrappedValue)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if siteSelection != nil {
                    Section("Work Location") {
                        Picker("Site", selection: $draftSiteID) {
                            Text("No site selected").tag(UUID?.none)
                            ForEach(siteOptions) { site in
                                Text(siteDisplayName(site)).tag(Optional(site.id))
                            }
                        }
                    }
                }

                Section("Repeat Job") {
                    Picker("Frequency", selection: $draftSelection) {
                        ForEach(JobRecurrenceFrequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Series Ends") {
                    Picker("End", selection: $draftEndMode) {
                        ForEach(JobRecurrenceEndMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    switch draftEndMode {
                    case .noEnd:
                        Text("PFSS maintains a rolling 120-day schedule. You can pause or stop the series at any time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .endDate:
                        DatePicker(
                            "Final Date",
                            selection: $draftEndDate,
                            displayedComponents: .date
                        )
                    case .occurrenceCount:
                        Stepper(
                            "Total Jobs: \(draftOccurrenceCount)",
                            value: $draftOccurrenceCount,
                            in: 1...500
                        )
                    }
                }

                Section {
                    Text("PFSS creates a bounded schedule of future jobs from this template. Existing completed work is never changed when the series is edited.")
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
                        endMode = draftEndMode
                        switch draftEndMode {
                        case .noEnd:
                            endDate = nil
                            occurrenceCount = nil
                        case .endDate:
                            endDate = draftEndDate
                            occurrenceCount = nil
                        case .occurrenceCount:
                            endDate = nil
                            occurrenceCount = draftOccurrenceCount
                        }
                        onSave?(
                            draftSelection,
                            draftEndMode,
                            draftEndMode == .endDate ? draftEndDate : nil,
                            draftEndMode == .occurrenceCount
                                ? draftOccurrenceCount
                                : nil,
                            draftSiteID
                        )
                        siteSelection?.wrappedValue = draftSiteID
                        dismiss()
                    }
                }
            }
        }
    }

    private func siteDisplayName(_ site: CustomerSite) -> String {
        if site.siteName.isEmpty { return site.serviceAddress }
        if site.serviceAddress.isEmpty { return site.siteName }
        return "\(site.siteName) — \(site.serviceAddress)"
    }
}
