//
//  OperationsTimelineView.swift
//  PPS Receipt Printer
//
//  Phase 14.8 – Synchronized Operations Timeline
//

import SwiftUI

struct OperationsTimelineView: View {
    @EnvironmentObject private var store: AppDataStore

    @State private var selectedDate: Date
    @State private var generatedAt = Date()
    @State private var selectedAssignmentID: UUID?
    @State private var managedAssignmentID: UUID?
    @State private var scheduleJobID: UUID?

    private let calendar = Calendar.current

    init(date: Date = Date()) {
        _selectedDate = State(initialValue: date)
    }

    private var snapshot: OperationsTimelineSnapshot {
        store.operationsTimelineSnapshot(
            on: selectedDate,
            generatedAt: generatedAt,
            calendar: calendar
        )
    }

    private var isShowingDetails: Binding<Bool> {
        Binding(
            get: { selectedAssignmentID != nil },
            set: { if !$0 { selectedAssignmentID = nil } }
        )
    }

    private var isManagingAssignment: Binding<Bool> {
        Binding(
            get: { managedAssignmentID != nil },
            set: { if !$0 { managedAssignmentID = nil } }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                dateControls
                summaryCard
                constraintLegend

                if snapshot.lanes.isEmpty {
                    ContentUnavailableView(
                        "No Technician Timeline",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No active technician lanes are available for this day.")
                    )
                    .padding(.vertical, 40)
                } else {
                    ForEach(snapshot.lanes) { lane in
                        technicianLane(lane)
                    }
                }

                if snapshot.unassignedItems.isEmpty == false {
                    unassignedSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refreshMappedTravel() }
        .task(id: calendar.startOfDay(for: selectedDate)) {
            await refreshMappedTravel()
        }
        .onChange(of: selectedDate) { _, _ in generatedAt = Date() }
        .navigationDestination(isPresented: isShowingDetails) {
            if let assignmentID = selectedAssignmentID {
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
        .navigationDestination(item: $scheduleJobID) { jobID in
            if let job = store.activeJobs.first(where: { $0.id == jobID }) {
                JobDetailView(
                    job: job,
                    scrollToScheduleOnAppear: true,
                    onSave: timelineScheduleDidSave
                )
            } else {
                ContentUnavailableView(
                    "Job Unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Return to the Timeline and refresh to try again.")
                )
            }
        }
        .sheet(isPresented: isManagingAssignment) {
            if let assignmentID = managedAssignmentID {
                DispatchBoardAssignmentActionsView(
                    assignmentID: assignmentID,
                    boardDate: selectedDate,
                    onEditSchedule: {
                        openScheduleEditor(for: assignmentID)
                    }
                )
                .environmentObject(store)
            }
        }
    }

    @MainActor
    private func openScheduleEditor(for assignmentID: UUID) {
        guard let jobID = store.assignmentEngine
            .assignment(id: assignmentID)?.jobID else {
            return
        }

        managedAssignmentID = nil
        Task { @MainActor in
            await Task.yield()
            scheduleJobID = jobID
        }
    }

    @MainActor
    private func timelineScheduleDidSave() {
        generatedAt = Date()
        Task { await refreshMappedTravel() }
    }

    @MainActor
    private func refreshMappedTravel() async {
        let technicians = store.activeEmployees.filter {
            $0.hasRole(.technician)
        }
        for technician in technicians {
            await store.refreshTimelineRoutePlan(
                for: technician,
                on: selectedDate,
                calendar: calendar
            )
        }
        generatedAt = Date()
    }

    private var dateControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { moveDate(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Previous day")

                VStack(spacing: 2) {
                    DatePicker(
                        "Timeline Date",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)

                    Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button { moveDate(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Next day")
            }

            if !calendar.isDateInToday(selectedDate) {
                Button("Return to Today") { selectedDate = Date() }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding()
        .timelineSurface()
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            timelineMetric(
                title: "Scheduled",
                value: snapshot.scheduledAssignmentCount.formatted(),
                symbol: "calendar.badge.clock",
                color: .blue
            )
            timelineMetric(
                title: "Open",
                value: timelineDuration(snapshot.openMinutes),
                symbol: "clock.arrow.circlepath",
                color: .green
            )
            timelineMetric(
                title: "Conflicts",
                value: snapshot.conflictCount.formatted(),
                symbol: "exclamationmark.triangle.fill",
                color: snapshot.conflictCount > 0 ? .orange : .secondary
            )
        }
        .padding()
        .timelineSurface()
    }

    private var constraintLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scheduling Constraints")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 6
            ) {
                timelineLegendBadge(.fixedTime)
                timelineLegendBadge(.flexibleDay)
                timelineLegendBadge(.deadline)
                timelineLegendBadge(.arrivalWindow)
            }
        }
        .padding(12)
        .timelineSurface()
    }

    private func technicianLane(_ lane: OperationsTimelineLane) -> some View {
        let laneColor = timelineEmployeeColor(lane.technicianColorName)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lane.technicianName)
                        .font(.title3.bold())
                    if let start = lane.workdayStart, let end = lane.workdayEnd {
                        Text("\(timelineTime(start))–\(timelineTime(end)) workday")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(timelineDuration(lane.scheduledMinutes)) scheduled")
                    Text("\(timelineDuration(lane.openMinutes)) open")
                        .foregroundStyle(.green)
                }
                .font(.caption.weight(.semibold))
            }

            if lane.entries.isEmpty {
                Text("No planned work or available workday window.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(lane.entries) { entry in
                    timelineEntry(entry, laneColor: laneColor)
                }
            }

            if lane.alerts.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Scheduling Conflicts",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                    ForEach(lane.alerts) { alert in
                        Button {
                            if let assignmentID = alert.assignmentID {
                                managedAssignmentID = assignmentID
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: alert.isBlocking
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.title).font(.caption.bold())
                                    Text(alert.message)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if alert.assignmentID != nil {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 1)
                }
            }
        }
        .padding()
        .timelineSurface(borderColor: laneColor)
    }

    private func timelineEntry(
        _ entry: OperationsTimelineEntry,
        laneColor: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            timelineRail(entry, laneColor: laneColor)
                .frame(width: 82)

            RoundedRectangle(cornerRadius: 2)
                .fill(timelineEntryColor(entry, laneColor: laneColor))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(
                            entry.priority == .emergency ? .red : .primary
                        )
                    if entry.subtitle.isEmpty == false {
                        Text(entry.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Label(
                        timelineDuration(entry.durationMinutes),
                        systemImage: timelineEntrySymbol(entry.kind)
                    )
                    if let status = entry.status {
                        Text(status.rawValue)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(timelineEntryColor(entry, laneColor: laneColor))

                if entry.milestones.isEmpty == false {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Actual Progress")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(entry.milestones) { milestone in
                            Text("\(timelineClockTime(milestone.timestamp))  \(milestone.title)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                if entry.hasConflict || entry.warnings.isEmpty == false {
                    Label(
                        entry.warnings.first ?? "Review scheduling conflict",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if let assignmentID = entry.assignmentID {
                    Divider()
                    HStack(spacing: 10) {
                        Button("Details") { selectedAssignmentID = assignmentID }
                            .buttonStyle(.bordered)
                        Button("Manage") { managedAssignmentID = assignmentID }
                            .buttonStyle(.borderedProminent)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            if entry.priority == .emergency {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red, lineWidth: 2)
            } else if entry.hasConflict {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private func timelineRail(
        _ entry: OperationsTimelineEntry,
        laneColor: Color
    ) -> some View {
        if timelineIsComplete(entry.status) {
            Text("J\no\nb\n\nC\no\nm\np\nl\ne\nt\ne")
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Job Complete")
        } else {
            VStack(spacing: 4) {
                if entry.kind == .assignment {
                    Text(entry.constraint.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(timelineConstraintColor(entry.constraint))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Text(timelineRailTime(entry.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)

                Image(systemName: "arrow.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(laneColor)

                Text(timelineRailTime(entry.end))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unassigned Work", systemImage: "tray.full.fill")
                .font(.title3.bold())
                .foregroundStyle(.yellow)
            Text("These assignments are not placed in a technician timeline.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(snapshot.unassignedItems) { item in
                Button {
                    managedAssignmentID = item.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.customerName).font(.headline)
                            Text("\(item.siteName) · \(item.scheduleTimeText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .timelineSurface(borderColor: .yellow)
    }

    private func timelineMetric(
        title: String,
        value: String,
        symbol: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineConstraintBadge(
        _ constraint: OperationsTimelineConstraint
    ) -> some View {
        Text(constraint.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(timelineConstraintColor(constraint))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(timelineConstraintColor(constraint).opacity(0.12))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }

    private func timelineLegendBadge(
        _ constraint: OperationsTimelineConstraint
    ) -> some View {
        Text(constraint.rawValue)
            .font(.caption2.weight(.medium))
            .foregroundStyle(timelineConstraintColor(constraint))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(timelineConstraintColor(constraint).opacity(0.10))
            .clipShape(Capsule())
    }

    private func moveDate(by days: Int) {
        guard let date = calendar.date(
            byAdding: .day,
            value: days,
            to: selectedDate
        ) else { return }
        selectedDate = date
    }
}

private extension View {
    func timelineSurface(borderColor: Color = .clear) -> some View {
        background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(borderColor, lineWidth: 1.5)
            }
    }
}

private func timelineTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

private let timelineRailTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HHmm"
    return formatter
}()

/// Compact 24-hour time used by the narrow timeline rail.
private func timelineRailTime(_ date: Date) -> String {
    timelineRailTimeFormatter.string(from: date)
}

/// Readable event time used in the wider actual-progress area.
private func timelineClockTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

private func timelineIsComplete(_ status: AssignmentStatus?) -> Bool {
    switch status {
    case .workComplete, .invoiceReady, .closed:
        return true
    default:
        return false
    }
}

private func timelineDuration(_ minutes: Int) -> String {
    let safe = max(minutes, 0)
    let hours = safe / 60
    let remainder = safe % 60
    if hours == 0 { return "\(remainder)m" }
    if remainder == 0 { return "\(hours)h" }
    return "\(hours)h \(remainder)m"
}

private func timelineEmployeeColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "green": return .green
    case "orange": return .orange
    case "purple": return .purple
    case "red": return .red
    case "yellow": return .yellow
    case "gray": return .gray
    default: return .blue
    }
}

private func timelineConstraintColor(
    _ constraint: OperationsTimelineConstraint
) -> Color {
    switch constraint {
    case .fixedTime: return .blue
    case .arrivalWindow: return .purple
    case .flexibleDay: return .teal
    case .deadline: return .orange
    case .operational: return .secondary
    }
}

private func timelineEntryColor(
    _ entry: OperationsTimelineEntry,
    laneColor: Color
) -> Color {
    if entry.priority == .emergency { return .red }
    if entry.hasConflict { return .orange }
    switch entry.kind {
    case .assignment: return laneColor
    case .travel: return .indigo
    case .stopBuffer: return .purple
    case .lunch: return .mint
    case .openCapacity: return .green
    }
}

private func timelineEntrySymbol(_ kind: OperationsTimelineEntryKind) -> String {
    switch kind {
    case .assignment: return "wrench.and.screwdriver.fill"
    case .travel: return "car.fill"
    case .stopBuffer: return "timer"
    case .lunch: return "fork.knife"
    case .openCapacity: return "clock.arrow.circlepath"
    }
}
