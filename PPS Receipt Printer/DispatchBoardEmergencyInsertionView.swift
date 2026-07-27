//
//  DispatchBoardEmergencyInsertionView.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Human-reviewed emergency insertion workflow
//

import SwiftUI

struct DispatchBoardEmergencyInsertionView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    let assignmentID: UUID

    @State private var requestedStart: Date
    @State private var preferredTechnicianID: UUID?
    @State private var reason = ""
    @State private var dispatchImmediately = true
    @State private var plan: EmergencyInsertionPlan?
    @State private var selectedOptionID: UUID?
    @State private var errorMessage = ""
    @State private var showingError = false

    init(assignmentID: UUID, requestedStart: Date) {
        self.assignmentID = assignmentID
        _requestedStart = State(
            initialValue: QuarterHourDatePicker.normalized(requestedStart)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if let assignment, let job {
                    requestSection(assignment, job: job)
                    recommendationSection
                    applySection
                } else {
                    ContentUnavailableView(
                        "Emergency Work Unavailable",
                        systemImage: "bolt.slash.fill",
                        description: Text("The Assignment or its Job could not be found.")
                    )
                }
            }
            .navigationTitle("Emergency Insertion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                preferredTechnicianID = assignment?.primaryTechnicianID
                if assignment?.status == .dispatched {
                    dispatchImmediately = false
                }
            }
            .onChange(of: requestedStart) { _, _ in resetPlan() }
            .onChange(of: preferredTechnicianID) { _, _ in resetPlan() }
            .onChange(of: reason) { _, _ in resetPlan() }
            .onChange(of: dispatchImmediately) { _, _ in resetPlan() }
            .alert("Emergency Insertion", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var assignment: Assignment? {
        store.assignmentEngine.assignment(id: assignmentID)
    }

    private var job: JobRecord? {
        guard let assignment else { return nil }
        return store.activeJobs.first { $0.id == assignment.jobID }
    }

    private var activeTechnicians: [EmployeeRecord] {
        store.activeEmployees
            .filter {
                $0.isActive &&
                $0.lifecycleStatus == .active &&
                ($0.hasRole(.technician) || $0.hasRole(.manager) || $0.hasRole(.owner))
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
    }

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func requestSection(
        _ assignment: Assignment,
        job: JobRecord
    ) -> some View {
        Section("Emergency Request") {
            VStack(alignment: .leading, spacing: 4) {
                Text(customerName(for: assignment))
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(siteName(for: assignment))
                    .foregroundStyle(.secondary)
                    Text(job.serviceType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            QuarterHourDatePicker(
                selection: $requestedStart,
                dateLabel: "Requested Date",
                timeLabel: "Requested Time"
            )

            Picker("Preferred Technician", selection: $preferredTechnicianID) {
                Text("Let PFSS Recommend").tag(UUID?.none)
                ForEach(activeTechnicians) { technician in
                    Text(technician.displayName).tag(Optional(technician.id))
                }
            }

            TextField(
                "Emergency reason",
                text: $reason,
                axis: .vertical
            )
            .lineLimit(2...5)

            Toggle("Dispatch Immediately", isOn: $dispatchImmediately)
                .disabled(assignment.status == .dispatched)

            if assignment.status == .dispatched {
                Text("This Assignment is already dispatched. PFSS will update its emergency placement without dispatching it a second time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                buildPlan(assignment: assignment, job: job)
            } label: {
                Label("Generate Insertion Options", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(normalizedReason.isEmpty)
        }
    }

    @ViewBuilder
    private var recommendationSection: some View {
        if let plan {
            Section("PFSS Recommendation") {
                ForEach(plan.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(plan.options) { option in
                    Button {
                        selectedOptionID = option.id
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedOptionID == option.id
                                ? "checkmark.circle.fill"
                                : "circle")
                                .font(.title3)
                                .foregroundStyle(option.isRecommended ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(option.technicianName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if option.isRecommended {
                                        Text("Recommended")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.green)
                                    }
                                }

                                Text("\(option.proposedStart.formatted(date: .abbreviated, time: .shortened)) · Stop \(option.proposedRouteSequence)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("\(option.confidencePercentage)% confidence")
                                    .font(.caption.weight(.semibold))

                                if option.hasConflictFreeOpening == false {
                                    Label(
                                        "Schedule conflict requires human override",
                                        systemImage: "exclamationmark.triangle.fill"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }

                                ForEach(option.reasons.prefix(2), id: \.self) { explanation in
                                    Text(explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var applySection: some View {
        if let plan {
            Section {
                Button {
                    apply(plan)
                } label: {
                    Label("Apply Emergency Insertion", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedOptionID == nil)

                Text("PFSS recommends; the dispatcher retains final authority. The selected technician, schedule, route order, priority, and override decision are written through the Operations APIs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buildPlan(assignment: Assignment, job: JobRecord) {
        do {
            let request = EmergencyInsertionRequest(
                assignmentID: assignment.id,
                requestedStart: QuarterHourDatePicker.normalized(requestedStart),
                preferredTechnicianID: preferredTechnicianID,
                reason: normalizedReason,
                dispatchImmediately: dispatchImmediately && assignment.status != .dispatched
            )
            let result = try store.dispatchEngine.prepareEmergencyInsertion(
                request: request,
                actor: .system,
                job: job,
                employees: store.activeEmployees,
                jobs: store.activeJobs
            )
            plan = result
            selectedOptionID = result.options.first(where: \.isRecommended)?.id
                ?? result.options.first?.id
        } catch {
            present(error)
        }
    }

    private func apply(_ plan: EmergencyInsertionPlan) {
        guard let selectedOptionID else { return }
        do {
            _ = try store.dispatchEngine.applyEmergencyInsertion(
                plan: plan,
                optionID: selectedOptionID,
                employees: store.activeEmployees,
                actor: .system
            )
            dismiss()
        } catch {
            present(error)
        }
    }

    private func resetPlan() {
        plan = nil
        selectedOptionID = nil
    }

    private func customerName(for assignment: Assignment) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == assignment.customerNumber
        }) else {
            return assignment.customerNumber
        }
        if customer.businessName.isEmpty == false { return customer.businessName }
        if customer.contactName.isEmpty == false { return customer.contactName }
        return assignment.customerNumber
    }

    private func siteName(for assignment: Assignment) -> String {
        guard let siteID = assignment.siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "Site not selected"
        }
        return site.siteName.isEmpty ? site.serviceAddress : site.siteName
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
