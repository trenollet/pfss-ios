//
//  DispatchBoardDestinationViews.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Focused Dispatch Board work queues
//

import SwiftUI

// MARK: - Assigned Technician Lanes

struct DispatchBoardAssignedView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var alertAcknowledgements:
        DispatchBoardAlertAcknowledgementStore

    let date: Date

    @State private var generatedAt = Date()
    @State private var selectedAssignmentID: UUID?
    @State private var actionAssignmentID: UUID?
    @State private var selectedEmployee: EmployeeRecord?

    private let calendar = Calendar.current

    private var snapshot: DispatchBoardSnapshot {
        store.dispatchBoardSnapshot(
            on: date,
            generatedAt: generatedAt,
            calendar: calendar
        )
    }

    private var isShowingAssignmentActions: Binding<Bool> {
        Binding(
            get: { actionAssignmentID != nil },
            set: { if $0 == false { actionAssignmentID = nil } }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                queueHeading(
                    title: "Technician Lanes",
                    count: snapshot.assignedCount,
                    symbol: "person.3.sequence.fill"
                )

                if snapshot.technicianLanes.isEmpty {
                    emptyState(
                        title: "No active technicians",
                        message: "Add or activate a technician to create Dispatch Board lanes."
                    )
                } else {
                    ForEach(snapshot.technicianLanes) { lane in
                        technicianLane(lane)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Assigned")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { generatedAt = Date() }
        .navigationDestination(item: $selectedAssignmentID) { assignmentID in
            assignmentDetail(assignmentID)
        }
        .sheet(item: $selectedEmployee) { employee in
            NavigationStack {
                EmployeeDetailView(employee: employee)
            }
            .environmentObject(store)
        }
        .sheet(isPresented: isShowingAssignmentActions) {
            if let assignmentID = actionAssignmentID {
                DispatchBoardAssignmentActionsView(
                    assignmentID: assignmentID,
                    boardDate: date
                )
                .environmentObject(store)
            }
        }
    }

    private func technicianLane(
        _ lane: DispatchBoardTechnicianLane
    ) -> some View {
        let visibleAlerts = alertAcknowledgements.visibleAlerts(
            in: snapshot,
            technicianID: lane.id
        )
        let laneColor = employeeColor(
            named: store.activeEmployees.first { $0.id == lane.id }?.colorName
                ?? "blue"
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    selectedEmployee = store.activeEmployees.first { $0.id == lane.id }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lane.technicianName)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        Label(
                            lane.technicianState.rawValue,
                            systemImage: laneStateSymbol(lane.technicianState)
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(laneStateColor(lane.technicianState))
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(safeProgress(lane.utilization).formatted(
                        .percent.precision(.fractionLength(0))
                    ))
                    .font(.headline.monospacedDigit())
                    Text("\(durationText(lane.plannedServiceMinutes)) planned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: safeProgress(lane.utilization))
                .tint(utilizationColor(lane.utilization))

            if lane.assignments.isEmpty {
                Text("No assignments scheduled for this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(lane.assignments.enumerated()), id: \.element.id) { index, item in
                    DispatchBoardWorkCard(
                        item: item,
                        contextLabel: "Stop \(item.routeSequence ?? index + 1)",
                        onDetails: { selectedAssignmentID = item.id },
                        onManage: { actionAssignmentID = item.id }
                    )
                }

                NavigationLink {
                    RoutePlanPreviewView(
                        dailyPlan: lane.dailyPlan,
                        technicianName: lane.technicianName
                    )
                } label: {
                    Label("Review Route", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if visibleAlerts.isEmpty == false {
                NavigationLink {
                    DispatchBoardAttentionView(
                        date: date,
                        technicianFilterID: lane.id
                    )
                    .environmentObject(store)
                    .environmentObject(alertAcknowledgements)
                } label: {
                    Label(
                        "\(visibleAlerts.count) operational alert\(visibleAlerts.count == 1 ? "" : "s") — Review",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .dispatchBoardSurface(borderColor: laneColor)
    }

    private func assignmentDetail(_ assignmentID: UUID) -> some View {
        AssignmentDetailView(
            engine: store.assignmentEngine,
            dispatchEngine: store.dispatchEngine,
            assignmentID: assignmentID,
            employees: store.activeEmployees,
            customers: store.customers,
            sites: store.sites
        )
    }
}

// MARK: - Unassigned Queue

struct DispatchBoardUnassignedView: View {
    @EnvironmentObject private var store: AppDataStore

    let date: Date

    @State private var generatedAt = Date()
    @State private var selectedAssignmentID: UUID?
    @State private var actionAssignmentID: UUID?

    private var snapshot: DispatchBoardSnapshot {
        store.dispatchBoardSnapshot(on: date, generatedAt: generatedAt)
    }

    private var isShowingAssignmentActions: Binding<Bool> {
        Binding(
            get: { actionAssignmentID != nil },
            set: { if $0 == false { actionAssignmentID = nil } }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                queueHeading(
                    title: "Unassigned Queue",
                    count: snapshot.unassignedCount,
                    symbol: "tray.full.fill"
                )

                if snapshot.unassignedItems.isEmpty {
                    emptyState(
                        title: "Queue is clear",
                        message: "Every active assignment for this day has a Primary Technician."
                    )
                } else {
                    ForEach(snapshot.unassignedItems) { item in
                        DispatchBoardWorkCard(
                            item: item,
                            contextLabel: "Needs Technician",
                            onDetails: { selectedAssignmentID = item.id },
                            onManage: { actionAssignmentID = item.id }
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Unassigned")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { generatedAt = Date() }
        .navigationDestination(item: $selectedAssignmentID) { assignmentID in
            assignmentDetail(assignmentID)
        }
        .sheet(isPresented: isShowingAssignmentActions) {
            if let assignmentID = actionAssignmentID {
                DispatchBoardAssignmentActionsView(
                    assignmentID: assignmentID,
                    boardDate: date
                )
                .environmentObject(store)
            }
        }
    }

    private func assignmentDetail(_ assignmentID: UUID) -> some View {
        AssignmentDetailView(
            engine: store.assignmentEngine,
            dispatchEngine: store.dispatchEngine,
            assignmentID: assignmentID,
            employees: store.activeEmployees,
            customers: store.customers,
            sites: store.sites
        )
    }
}

// MARK: - Emergency Queue

struct DispatchBoardEmergencyView: View {
    @EnvironmentObject private var store: AppDataStore

    let date: Date

    @State private var generatedAt = Date()
    @State private var selectedAssignmentID: UUID?
    @State private var actionAssignmentID: UUID?

    private var snapshot: DispatchBoardSnapshot {
        store.dispatchBoardSnapshot(on: date, generatedAt: generatedAt)
    }

    private var entries: [EmergencyBoardEntry] {
        let assigned = snapshot.technicianLanes.flatMap { lane in
            lane.assignments
                .filter { $0.priority == .emergency }
                .map { EmergencyBoardEntry(item: $0, context: lane.technicianName) }
        }
        let unassigned = snapshot.unassignedItems
            .filter { $0.priority == .emergency }
            .map { EmergencyBoardEntry(item: $0, context: "Needs Technician") }

        return (assigned + unassigned).sorted {
            ($0.item.plannedStart ?? .distantFuture) <
                ($1.item.plannedStart ?? .distantFuture)
        }
    }

    private var isShowingAssignmentActions: Binding<Bool> {
        Binding(
            get: { actionAssignmentID != nil },
            set: { if $0 == false { actionAssignmentID = nil } }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                queueHeading(
                    title: "Emergency Assignments",
                    count: entries.count,
                    symbol: "flag.fill"
                )
                .foregroundStyle(.red)

                if entries.isEmpty {
                    emptyState(
                        title: "No emergencies",
                        message: "No active Assignment has Emergency priority for this day."
                    )
                } else {
                    ForEach(entries) { entry in
                        DispatchBoardWorkCard(
                            item: entry.item,
                            contextLabel: entry.context,
                            onDetails: { selectedAssignmentID = entry.id },
                            onManage: { actionAssignmentID = entry.id }
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Emergency")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { generatedAt = Date() }
        .navigationDestination(item: $selectedAssignmentID) { assignmentID in
            AssignmentDetailView(
                engine: store.assignmentEngine,
                dispatchEngine: store.dispatchEngine,
                assignmentID: assignmentID,
                employees: store.activeEmployees,
                customers: store.customers,
                sites: store.sites
            )
        }
        .sheet(isPresented: isShowingAssignmentActions) {
            if let assignmentID = actionAssignmentID {
                DispatchBoardAssignmentActionsView(
                    assignmentID: assignmentID,
                    boardDate: date
                )
                .environmentObject(store)
            }
        }
    }
}

private struct EmergencyBoardEntry: Identifiable {
    let item: DispatchBoardAssignmentItem
    let context: String
    var id: UUID { item.id }
}

// MARK: - Needs Attention

struct DispatchBoardAttentionView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var alertAcknowledgements:
        DispatchBoardAlertAcknowledgementStore

    let date: Date
    var technicianFilterID: UUID? = nil

    @State private var generatedAt = Date()
    @State private var selectedAssignmentID: UUID?

    private var snapshot: DispatchBoardSnapshot {
        store.dispatchBoardSnapshot(on: date, generatedAt: generatedAt)
    }

    private var alerts: [DispatchBoardAlert] {
        alertAcknowledgements.visibleAlerts(
            in: snapshot,
            technicianID: technicianFilterID
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                queueHeading(
                    title: technicianFilterID == nil
                        ? "Needs Attention"
                        : technicianName,
                    count: alerts.count,
                    symbol: "exclamationmark.triangle.fill"
                )

                if alerts.isEmpty {
                    emptyState(
                        title: "Nothing needs attention",
                        message: "All current conflicts are resolved or have been reviewed for this day."
                    )
                } else {
                    ForEach(alerts) { alert in
                        attentionCard(alert)
                    }
                }

                if alertAcknowledgements.acknowledgedCount(on: date) > 0 {
                    Button {
                        alertAcknowledgements.restoreAcknowledgedAlerts(on: date)
                    } label: {
                        Label(
                            "Restore Accepted Alerts",
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Needs Attention")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { generatedAt = Date() }
        .navigationDestination(item: $selectedAssignmentID) { assignmentID in
            AssignmentDetailView(
                engine: store.assignmentEngine,
                dispatchEngine: store.dispatchEngine,
                assignmentID: assignmentID,
                employees: store.activeEmployees,
                customers: store.customers,
                sites: store.sites
            )
        }
    }

    private var technicianName: String {
        guard let technicianFilterID else { return "Needs Attention" }
        return snapshot.technicianLanes.first { $0.id == technicianFilterID }?
            .technicianName ?? "Technician Alerts"
    }

    private func attentionCard(_ alert: DispatchBoardAlert) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: alertSymbol(alert.severity))
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.headline)
                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let identity = assignmentIdentity(for: alert.assignmentID) {
                        Text("\(identity.customer) · \(identity.site)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                reviewControl(for: alert)

                Button {
                    alertAcknowledgements.acknowledge(alert, on: date)
                } label: {
                    Label("Accept as Is", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .dispatchBoardSurface(borderColor: .orange)
    }

    @ViewBuilder
    private func reviewControl(for alert: DispatchBoardAlert) -> some View {
        if let assignmentID = alert.assignmentID {
            Button {
                selectedAssignmentID = assignmentID
            } label: {
                Label("Review", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else if let technicianID = alert.technicianID,
                  let lane = snapshot.technicianLanes.first(where: {
                      $0.id == technicianID
                  }) {
            NavigationLink {
                RoutePlanPreviewView(
                    dailyPlan: lane.dailyPlan,
                    technicianName: lane.technicianName
                )
            } label: {
                Label("Review Plan", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func assignmentIdentity(
        for assignmentID: UUID?
    ) -> (customer: String, site: String)? {
        guard let assignmentID else { return nil }
        let allItems = snapshot.unassignedItems +
            snapshot.technicianLanes.flatMap(\.assignments)
        guard let item = allItems.first(where: { $0.id == assignmentID }) else {
            return nil
        }
        return (item.customerName, item.siteName)
    }
}

// MARK: - Shared Assignment Card

private struct DispatchBoardWorkCard: View {
    let item: DispatchBoardAssignmentItem
    let contextLabel: String
    let onDetails: () -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(contextLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
                AssignmentStatusBadge(status: item.status)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.priority == .emergency {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.red)
                    }
                    Text(item.customerName)
                        .font(.headline.bold())
                        .foregroundStyle(
                            item.priority == .emergency ? .red : .primary
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.siteName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item.serviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(
                    item.estimatedArrival?.formatted(
                        date: .omitted,
                        time: .shortened
                    ) ?? item.scheduleTimeText,
                    systemImage: "clock.fill"
                )
                Label(
                    durationText(item.serviceMinutes),
                    systemImage: "wrench.and.screwdriver.fill"
                )
                if item.supportingTechnicianIDs.isEmpty == false {
                    Label(
                        "+\(item.supportingTechnicianIDs.count)",
                        systemImage: "person.2.fill"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 10) {
                Button(action: onDetails) {
                    Label("Details", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onManage) {
                    Label(
                        item.primaryTechnicianID == nil ? "Assign" : "Manage",
                        systemImage: item.primaryTechnicianID == nil
                            ? "person.badge.plus"
                            : "slider.horizontal.3"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(item.priority == .emergency ? .red : .blue)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    item.priority == .emergency
                        ? Color.red.opacity(0.65)
                        : Color.secondary.opacity(0.18),
                    lineWidth: item.priority == .emergency ? 2 : 1
                )
        }
    }
}

// MARK: - Shared Helpers

private func queueHeading(
    title: String,
    count: Int,
    symbol: String
) -> some View {
    HStack(spacing: 10) {
        Label(title, systemImage: symbol)
            .font(.title2.bold())
        Spacer()
        Text(count.formatted())
            .font(.headline.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

private func emptyState(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .dispatchBoardSurface()
}

private func safeProgress(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private func durationText(_ minutes: Int) -> String {
    let safeMinutes = max(minutes, 0)
    let hours = safeMinutes / 60
    let remainder = safeMinutes % 60
    if hours == 0 { return "\(remainder) min" }
    if remainder == 0 { return "\(hours) hr" }
    return "\(hours) hr \(remainder) min"
}

private func utilizationColor(_ utilization: Double) -> Color {
    switch safeProgress(utilization) {
    case 0..<0.75: return .green
    case 0.75..<0.95: return .blue
    case 0.95..<1: return .orange
    default: return .red
    }
}

private func laneStateColor(_ state: DispatchBoardTechnicianState) -> Color {
    switch state {
    case .available: return .green
    case .scheduled: return .blue
    case .traveling: return .orange
    case .working: return .purple
    case .attention: return .red
    case .offline: return .secondary
    }
}

private func laneStateSymbol(_ state: DispatchBoardTechnicianState) -> String {
    switch state {
    case .available: return "checkmark.circle.fill"
    case .scheduled: return "calendar.circle.fill"
    case .traveling: return "car.circle.fill"
    case .working: return "wrench.and.screwdriver.fill"
    case .attention: return "exclamationmark.triangle.fill"
    case .offline: return "moon.zzz.fill"
    }
}

private func employeeColor(named colorName: String) -> Color {
    switch colorName.lowercased() {
    case "green": return .green
    case "orange": return .orange
    case "purple": return .purple
    case "red": return .red
    case "yellow": return .yellow
    case "gray": return .gray
    default: return .blue
    }
}

private func alertColor(_ severity: DispatchBoardAlertSeverity) -> Color {
    switch severity {
    case .information: return .blue
    case .warning: return .orange
    case .blocking: return .red
    }
}

private func alertSymbol(_ severity: DispatchBoardAlertSeverity) -> String {
    switch severity {
    case .information: return "info.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .blocking: return "xmark.octagon.fill"
    }
}
