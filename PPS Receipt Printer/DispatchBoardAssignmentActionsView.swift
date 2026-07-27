//
//  DispatchBoardAssignmentActionsView.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Direct Technician Dispatch Board actions
//

import SwiftUI

struct DispatchBoardAssignmentActionsView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    let assignmentID: UUID
    let boardDate: Date

    @State private var selectedTechnicianID: UUID?
    @State private var reasonPrompt: DispatchBoardReasonPrompt?
    @State private var showingCrewEditor = false
    @State private var showingEmergencyInsertion = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            Form {
                if let assignment {
                    identitySection(assignment)
                    ownershipSection(assignment)
                    routeSection(assignment)
                    crewSection(assignment)
                    emergencySection(assignment)
                } else {
                    ContentUnavailableView(
                        "Assignment Unavailable",
                        systemImage: "rectangle.stack.badge.exclamationmark",
                        description: Text("Refresh the Dispatch Board and try again.")
                    )
                }
            }
            .navigationTitle("Manage Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { selectInitialTechnician() }
            .onChange(of: assignment?.primaryTechnicianID) { _, _ in
                selectInitialTechnician()
            }
            .sheet(item: $reasonPrompt) { prompt in
                reasonPromptView(prompt)
            }
            .sheet(isPresented: $showingCrewEditor) {
                CrewEditor(
                    engine: store.assignmentEngine,
                    dispatchEngine: store.dispatchEngine,
                    assignmentID: assignmentID,
                    employees: store.activeEmployees
                )
            }
            .sheet(isPresented: $showingEmergencyInsertion) {
                DispatchBoardEmergencyInsertionView(
                    assignmentID: assignmentID,
                    requestedStart: assignment?.scheduling.operationalDate ?? boardDate
                )
                .environmentObject(store)
            }
            .alert("Dispatch Board", isPresented: $showingError) {
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

    private var eligibleTechnicians: [EmployeeRecord] {
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

    private var recommendation: OperationalRecommendationResult? {
        guard let job, let assignment else { return nil }
        return store.operationalRecommendation(
            for: job,
            purpose: .technicianAssignment,
            policy: assignment.priority == .emergency ? .emergency : .balanced,
            onOrAfter: assignment.scheduling.operationalDate
        )
    }

    private var selectedTechnician: EmployeeRecord? {
        guard let selectedTechnicianID else { return nil }
        return eligibleTechnicians.first { $0.id == selectedTechnicianID }
    }

    private var selectionRequiresReason: Bool {
        guard let assignment, let selectedTechnicianID else { return false }
        let changesOwner = assignment.primaryTechnicianID != nil &&
            assignment.primaryTechnicianID != selectedTechnicianID
        let tiedLeaderIDs = Set(
            recommendation?.leadingCandidates.map(\.employeeID) ?? []
        )
        let acceptedTie = recommendation?.hasTopScoreTie == true &&
            tiedLeaderIDs.contains(selectedTechnicianID)
        let overridesRecommendation = recommendation != nil &&
            !acceptedTie &&
            recommendation?.bestCandidate?.employeeID != selectedTechnicianID
        return changesOwner || overridesRecommendation
    }

    @ViewBuilder
    private func identitySection(_ assignment: Assignment) -> some View {
        Section("Work") {
            VStack(alignment: .leading, spacing: 12) {
                Text(customerName(for: assignment))
                    .font(.headline)
                Text(siteName(for: assignment))
                    .foregroundStyle(.secondary)
                if let job {
                    Text(job.serviceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                workMetadataRow("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: statusSymbol(assignment.status))
                        Text(assignment.status.rawValue)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(assignment.status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor(assignment.status).opacity(0.12))
                    .clipShape(Capsule())
                    .fixedSize(horizontal: true, vertical: true)
                }

                Divider()

                workMetadataRow("Scheduled") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(assignment.scheduling.displayDateText)
                        Text(assignment.scheduling.displayTimeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                workMetadataRow("Priority") {
                    Text(assignment.priority.rawValue)
                        .foregroundStyle(
                            assignment.priority == .emergency ? .red : .secondary
                        )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func workMetadataRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statusColor(_ status: AssignmentStatus) -> Color {
        switch status {
        case .scheduled: return .blue
        case .dispatched: return .indigo
        case .enRoute: return .orange
        case .onSite: return .purple
        case .workComplete: return .teal
        case .invoiceReady: return .mint
        case .closed: return .green
        case .cancelled: return .red
        }
    }

    private func statusSymbol(_ status: AssignmentStatus) -> String {
        switch status {
        case .scheduled: return "calendar"
        case .dispatched: return "paperplane.fill"
        case .enRoute: return "car.fill"
        case .onSite: return "location.fill"
        case .workComplete: return "checkmark.circle.fill"
        case .invoiceReady: return "doc.text.fill"
        case .closed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    @ViewBuilder
    private func ownershipSection(_ assignment: Assignment) -> some View {
        Section("Primary Technician") {
            if recommendation?.hasTopScoreTie == true {
                Label(
                    "Top candidates tied: \(recommendation?.leadingCandidates.map(\.employeeName).joined(separator: ", ") ?? "")",
                    systemImage: "equal.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.blue)
            } else if let recommended = recommendation?.bestCandidate {
                Label(
                    "PFSS recommends \(recommended.employeeName) (\(recommended.scorePercentage)%)",
                    systemImage: "star.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.green)
            } else {
                Label(
                    "No conflict-free recommendation is available.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
            }

            Picker("Technician", selection: $selectedTechnicianID) {
                Text("Select Technician").tag(UUID?.none)
                ForEach(eligibleTechnicians) { technician in
                    Text(technician.displayName).tag(Optional(technician.id))
                }
            }

            if let selectedTechnician,
               let candidate = recommendation?.candidates.first(where: {
                   $0.employeeID == selectedTechnician.id
               }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rank #\(candidate.rank.map(String.init) ?? "—") · \(candidate.scorePercentage)% confidence")
                        .font(.caption.weight(.semibold))
                    if let warning = candidate.warnings.first {
                        Text("\(warning.title): \(warning.detail)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Button {
                requestAssignmentChange()
            } label: {
                Label(
                    assignment.primaryTechnicianID == nil
                        ? "Assign Technician"
                        : "Apply Reassignment",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedTechnicianID == nil ||
                selectedTechnicianID == assignment.primaryTechnicianID
            )

            if assignment.primaryTechnicianID != nil && crewCanChange(assignment) {
                Button {
                    reasonPrompt = .unassignment
                } label: {
                    Label(
                        "Unassign and Return to Queue",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    @ViewBuilder
    private func routeSection(_ assignment: Assignment) -> some View {
        if assignment.primaryTechnicianID != nil {
            Section("Route Order") {
                LabeledContent(
                    "Current Stop",
                    value: assignment.routeSequence.map(String.init) ?? "Not ordered"
                )

                HStack(spacing: 12) {
                    Button {
                        move(.earlier)
                    } label: {
                        Label("Move Earlier", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(canMove(assignmentID, direction: .earlier) == false)

                    Button {
                        move(.later)
                    } label: {
                        Label("Move Later", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(canMove(assignmentID, direction: .later) == false)
                }
            }
        }
    }

    @ViewBuilder
    private func crewSection(_ assignment: Assignment) -> some View {
        Section("Crew") {
            LabeledContent(
                "Supporting Technicians",
                value: assignment.supportingTechnicianIDs.count.formatted()
            )

            Button {
                showingCrewEditor = true
            } label: {
                Label("Manage Crew", systemImage: "person.2.badge.gearshape.fill")
            }
            .disabled(crewCanChange(assignment) == false)

            if crewCanChange(assignment) == false {
                Text("Crew changes are locked after travel begins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func emergencySection(_ assignment: Assignment) -> some View {
        if assignment.status.isTerminal == false {
            Section("Emergency Dispatch") {
                Button {
                    showingEmergencyInsertion = true
                } label: {
                    Label(
                        assignment.priority == .emergency
                            ? "Review Emergency Insertion"
                            : "Convert and Insert as Emergency",
                        systemImage: "bolt.trianglebadge.exclamationmark.fill"
                    )
                    .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func reasonPromptView(
        _ prompt: DispatchBoardReasonPrompt
    ) -> some View {
        switch prompt {
        case .reassignment:
            DispatchBoardReasonPromptView(
                title: assignment?.primaryTechnicianID == nil
                    ? "Assignment Override"
                    : "Confirm Reassignment",
                message: "Explain why this technician was selected instead of PFSS's recommendation.",
                placeholder: "Reason for reassignment or override",
                actionTitle: assignment?.primaryTechnicianID == nil
                    ? "Apply Assignment"
                    : "Apply Reassignment",
                tint: .blue
            ) { reason in
                assignSelectedTechnician(reason: reason)
            }

        case .unassignment:
            DispatchBoardReasonPromptView(
                title: "Return Work to Queue",
                message: "Explain why this Assignment is being removed from the technician's route.",
                placeholder: "Reason for returning work to queue",
                actionTitle: "Unassign and Return to Queue",
                tint: .red
            ) { reason in
                unassign(reason: reason)
            }
        }
    }

    private func selectInitialTechnician() {
        guard let assignment else { return }
        if selectedTechnicianID == nil ||
            eligibleTechnicians.contains(where: { $0.id == selectedTechnicianID }) == false {
            selectedTechnicianID = assignment.primaryTechnicianID
                ?? recommendation?.bestCandidate?.employeeID
                ?? eligibleTechnicians.first?.id
        }
    }

    private func requestAssignmentChange() {
        if selectionRequiresReason {
            reasonPrompt = .reassignment
        } else {
            assignSelectedTechnician(reason: "")
        }
    }

    private func assignSelectedTechnician(reason: String) {
        guard let selectedTechnicianID else { return }
        perform {
            _ = try store.dispatchBoardAssign(
                assignmentID: assignmentID,
                technicianID: selectedTechnicianID,
                reason: reason
            )
        }
    }

    private func unassign(reason: String) {
        perform {
            _ = try store.dispatchBoardUnassign(
                assignmentID: assignmentID,
                reason: reason
            )
            selectedTechnicianID = recommendation?.bestCandidate?.employeeID
        }
    }

    private func move(_ direction: DispatchBoardRouteMoveDirection) {
        perform {
            try store.dispatchBoardMoveAssignment(
                assignmentID: assignmentID,
                direction: direction,
                on: boardDate,
                calendar: calendar
            )
        }
    }

    private func canMove(
        _ assignmentID: UUID,
        direction: DispatchBoardRouteMoveDirection
    ) -> Bool {
        let snapshot = store.dispatchBoardSnapshot(on: boardDate, calendar: calendar)
        guard let lane = snapshot.technicianLanes.first(where: {
            $0.assignments.contains(where: { $0.id == assignmentID })
        }), let index = lane.assignments.firstIndex(where: {
            $0.id == assignmentID
        }) else { return false }

        switch direction {
        case .earlier: return index > 0
        case .later: return index < lane.assignments.count - 1
        }
    }

    private func crewCanChange(_ assignment: Assignment) -> Bool {
        assignment.status == .scheduled || assignment.status == .dispatched
    }

    private func customerName(for assignment: Assignment) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == assignment.customerNumber
        }) else { return assignment.customerNumber }
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

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private enum DispatchBoardReasonPrompt: String, Identifiable {
    case reassignment
    case unassignment
    var id: String { rawValue }
}

private struct DispatchBoardReasonPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var reasonIsFocused: Bool

    let title: String
    let message: String
    let placeholder: String
    let actionTitle: String
    let tint: Color
    let onApply: (String) -> Void

    @State private var reason = ""

    private var cleanReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $reason, axis: .vertical)
                    .lineLimit(4...7)
                    .textFieldStyle(.roundedBorder)
                    .focused($reasonIsFocused)

                Button {
                    onApply(cleanReason)
                    dismiss()
                } label: {
                    Label(actionTitle, systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(cleanReason.isEmpty)

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { reasonIsFocused = true }
        }
        .presentationDetents([.height(360), .medium])
    }
}
