//
//  RecurringWorkManagementView.swift
//  PPS Receipt Printer
//
//  Phase 18 – Authorized lifecycle controls for a recurring-work series.
//

import SwiftUI

struct RecurringWorkSeriesEditorState: Identifiable, Equatable {
    let id: UUID
    var frequency: JobRecurrenceFrequency
    var endMode: JobRecurrenceEndMode
    var endDate: Date?
    var occurrenceCount: Int?
    var siteID: UUID?

    init(template: RecurringWorkTemplate, id: UUID = UUID()) {
        self.id = id
        frequency = template.rule.jobRecurrenceFrequency
        siteID = template.prototype.siteID
        switch template.endCondition {
        case .noEnd:
            endMode = .noEnd
            endDate = nil
            occurrenceCount = nil
        case let .endDate(date):
            endMode = .endDate
            endDate = date
            occurrenceCount = nil
        case let .occurrenceCount(count):
            endMode = .occurrenceCount
            endDate = nil
            occurrenceCount = count
        }
    }
}

struct RecurringWorkManagementView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    let templateID: UUID
    let currentJobID: UUID?
    let onSeriesUpdated: (() -> Void)?

    @State private var showingTerminationConfirmation = false
    @State private var showingHoldConfirmation = false
    @State private var showingReleaseConfirmation = false
    @State private var seriesEditorState: RecurringWorkSeriesEditorState?
    @State private var jobToSkip: JobRecord?

    init(
        templateID: UUID,
        currentJobID: UUID? = nil,
        onSeriesUpdated: (() -> Void)? = nil
    ) {
        self.templateID = templateID
        self.currentJobID = currentJobID
        self.onSeriesUpdated = onSeriesUpdated
    }

    private var template: RecurringWorkTemplate? {
        store.recurringWorkTemplates.first { $0.id == templateID }
    }

    private var upcomingJobs: [JobRecord] {
        store.jobs
            .filter {
                $0.recurringWorkTemplateID == templateID &&
                $0.lifecycleStatus == .active &&
                $0.workflowState == .notStarted &&
                ($0.status == .toBeScheduled ||
                 $0.status == .scheduled ||
                 $0.status == .assigned)
            }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var availableSites: [CustomerSite] {
        guard let customerNumber = template?.prototype.customerNumber else {
            return []
        }
        return store.sites
            .filter {
                $0.customerNumber == customerNumber &&
                $0.lifecycleStatus == .active
            }
            .sorted {
                let first = $0.siteName.isEmpty ? $0.serviceAddress : $0.siteName
                let second = $1.siteName.isEmpty ? $1.serviceAddress : $1.siteName
                return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
            }
    }

    var body: some View {
        List {
            if let template {
                Section("Series") {
                    LabeledContent("Status", value: template.status.displayName)
                    LabeledContent("Repeats", value: template.rule.displayName)
                    LabeledContent(
                        "Starts",
                        value: template.anchorDate.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent("Ends", value: template.endCondition.displayName)
                    LabeledContent(
                        "Site",
                        value: selectedSiteName(template.prototype.siteID)
                    )
                }

                Section {
                    Button {
                        seriesEditorState = RecurringWorkSeriesEditorState(
                            template: template
                        )
                    } label: {
                        Label("Edit Recurring Series", systemImage: "calendar.badge.clock")
                    }

                    if template.status == .active {
                        Button {
                            showingHoldConfirmation = true
                        } label: {
                            Label("Place Series on Hold", systemImage: "pause.rectangle")
                        }

                        Button {
                            store.pauseRecurringWork(templateID: templateID)
                        } label: {
                            Label("Pause Future Generation", systemImage: "pause.circle")
                        }
                    } else if template.status == .paused {
                        Button {
                            store.resumeRecurringWork(templateID: templateID)
                        } label: {
                            Label("Resume Recurring Work", systemImage: "play.circle")
                        }
                    } else if template.status == .held {
                        Button {
                            showingReleaseConfirmation = true
                        } label: {
                            Label("Release Series Hold", systemImage: "play.rectangle")
                        }
                    }

                    if template.status == .active ||
                        template.status == .paused ||
                        template.status == .held {
                        Button(role: .destructive) {
                            showingTerminationConfirmation = true
                        } label: {
                            Label("Stop Recurring Work", systemImage: "stop.circle")
                        }
                    }
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Holding removes the selected and later unstarted jobs until release, then rebuilds them from the release date. Pausing keeps existing scheduled jobs. Completed and in-progress work remains unchanged.")
                }

                Section("Upcoming Jobs") {
                    if upcomingJobs.isEmpty {
                        ContentUnavailableView(
                            "No Upcoming Jobs",
                            systemImage: "calendar.badge.checkmark",
                            description: Text("This series has no generated future work in its current planning window.")
                        )
                    } else {
                        ForEach(upcomingJobs) { job in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(.primary)
                                    Text(job.jobNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    jobToSkip = job
                                } label: {
                                    Label("Skip", systemImage: "forward.end.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Series Unavailable",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text("Refresh synchronization and try again.")
                )
            }
        }
        .navigationTitle("Recurring Work")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.materializeRecurringWorkHorizon()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $seriesEditorState) { state in
            RecurringWorkSeriesEditorView(
                initialState: state,
                siteOptions: availableSites,
                onSave: { frequency, endMode, endDate, occurrenceCount, siteID in
                    store.updateRecurringWorkSeries(
                        templateID: templateID,
                        frequency: frequency,
                        endMode: endMode,
                        endDate: endDate,
                        occurrenceCount: occurrenceCount,
                        siteID: siteID
                    )
                    onSeriesUpdated?()
                }
            )
            .id(state.id)
        }
        .confirmationDialog(
            "Place this recurring series on hold?",
            isPresented: $showingHoldConfirmation,
            titleVisibility: .visible
        ) {
            Button("Place Series on Hold") {
                store.holdRecurringWork(
                    templateID: templateID,
                    fromJobID: currentJobID
                )
                onSeriesUpdated?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The selected occurrence and every later unstarted job will be removed from the schedule until this hold is released.")
        }
        .confirmationDialog(
            "Release this recurring series hold?",
            isPresented: $showingReleaseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Release and Rebuild Schedule") {
                store.releaseRecurringWork(templateID: templateID)
                onSeriesUpdated?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The held occurrence will be scheduled for today and later jobs will follow the series frequency from that date.")
        }
        .confirmationDialog(
            "Stop this recurring series?",
            isPresented: $showingTerminationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Recurring Work", role: .destructive) {
                store.terminateRecurringWork(templateID: templateID)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Future unstarted occurrences will be removed. Existing work history will remain unchanged.")
        }
        .confirmationDialog(
            "Skip this occurrence?",
            isPresented: Binding(
                get: { jobToSkip != nil },
                set: { if !$0 { jobToSkip = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Skip and Remove", role: .destructive) {
                if let jobToSkip {
                    store.skipRecurringOccurrence(
                        jobID: jobToSkip.id,
                        reason: "Skipped and removed from recurring-work management."
                    )
                }
                jobToSkip = nil
            }
            Button("Skip and Add to End") {
                if let jobToSkip {
                    store.skipRecurringOccurrence(
                        jobID: jobToSkip.id,
                        reason: "Skipped with a replacement added to the end of the recurring series.",
                        addReplacementToSeriesEnd: true
                    )
                }
                jobToSkip = nil
            }
            Button("Cancel", role: .cancel) { jobToSkip = nil }
        } message: {
            Text("Remove this occurrence permanently, or add a replacement occurrence to the end of the series.")
        }
    }

    private func selectedSiteName(_ siteID: UUID?) -> String {
        guard let siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "No site selected"
        }
        return site.siteName.isEmpty ? site.serviceAddress : site.siteName
    }
}

private struct RecurringWorkSeriesEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let siteOptions: [CustomerSite]
    let onSave: (
        JobRecurrenceFrequency,
        JobRecurrenceEndMode,
        Date?,
        Int?,
        UUID?
    ) -> Void

    @State private var frequency: JobRecurrenceFrequency
    @State private var endMode: JobRecurrenceEndMode
    @State private var endDate: Date
    @State private var occurrenceCount: Int
    @State private var siteID: UUID?

    init(
        initialState: RecurringWorkSeriesEditorState,
        siteOptions: [CustomerSite],
        onSave: @escaping (
            JobRecurrenceFrequency,
            JobRecurrenceEndMode,
            Date?,
            Int?,
            UUID?
        ) -> Void
    ) {
        self.siteOptions = siteOptions
        self.onSave = onSave
        _frequency = State(initialValue: initialState.frequency)
        _endMode = State(initialValue: initialState.endMode)
        _endDate = State(
            initialValue: initialState.endDate
                ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())
                ?? Date()
        )
        _occurrenceCount = State(
            initialValue: max(initialState.occurrenceCount ?? 12, 1)
        )
        _siteID = State(initialValue: initialState.siteID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Work Location") {
                    Picker("Site", selection: $siteID) {
                        Text("No site selected").tag(UUID?.none)
                        ForEach(siteOptions) { site in
                            Text(siteDisplayName(site)).tag(Optional(site.id))
                        }
                    }
                }

                Section("Repeat Job") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(JobRecurrenceFrequency.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Series Ends") {
                    Picker("End", selection: $endMode) {
                        ForEach(JobRecurrenceEndMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    switch endMode {
                    case .noEnd:
                        Text("PFSS maintains a rolling 120-day schedule. You can pause or stop the series at any time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .endDate:
                        DatePicker(
                            "Final Date",
                            selection: $endDate,
                            displayedComponents: .date
                        )
                    case .occurrenceCount:
                        Stepper(
                            "Total Jobs: \(occurrenceCount)",
                            value: $occurrenceCount,
                            in: 1...500
                        )
                    }
                }

                Section {
                    Text("PFSS starts this editor with the current synchronized series settings. Saving replaces only future unstarted occurrences; completed work is never changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Recurring Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            frequency,
                            endMode,
                            endMode == .endDate ? endDate : nil,
                            endMode == .occurrenceCount ? occurrenceCount : nil,
                            siteID
                        )
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

private extension RecurringWorkTemplateStatus {
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .held: return "On Hold"
        case .terminated: return "Stopped"
        case .archived: return "Archived"
        }
    }
}

private extension RecurringWorkRule {
    var displayName: String {
        let unitName: String
        switch unit {
        case .day: unitName = interval == 1 ? "day" : "days"
        case .week: unitName = interval == 1 ? "week" : "weeks"
        case .month: unitName = interval == 1 ? "month" : "months"
        case .year: unitName = interval == 1 ? "year" : "years"
        }
        return interval == 1 ? "Every \(unitName)" : "Every \(interval) \(unitName)"
    }
}

private extension RecurringWorkEndCondition {
    var displayName: String {
        switch self {
        case .noEnd:
            return "No end date"
        case .endDate(let date):
            return date.formatted(date: .abbreviated, time: .omitted)
        case .occurrenceCount(let count):
            return "After \(count) jobs"
        }
    }
}
