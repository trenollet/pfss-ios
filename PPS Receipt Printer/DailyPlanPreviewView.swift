//
//  DailyPlanPreviewView.swift
//  PPS Receipt Printer
//
//  Phase 14.3 – Daily Planner visual acceptance surface
//

import SwiftUI

/// Displays a safe, non-mutating Daily Planner proposal.
///
/// Generating or refreshing this preview never changes an Assignment. The
/// proposed timeline can be passed to RoutePlanPreviewView, where the user must
/// explicitly review and apply a route before routeSequence values change.
struct DailyPlanPreviewView: View {

    @EnvironmentObject private var store: AppDataStore

    @State private var selectedTechnicianID: UUID?
    @State private var selectedDate = Date()
    @State private var generatedPlan: DailyPlan?
    @State private var generatedAt: Date?

    private let calendar = Calendar.current

    private var technicians: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.role == .technician }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    private var selectedTechnician: EmployeeRecord? {
        guard let selectedTechnicianID else { return nil }
        return technicians.first { $0.id == selectedTechnicianID }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                plannerControls

                if let generatedPlan {
                    planHeader(generatedPlan)
                    routePlanningSection(generatedPlan)
                    timelineSection(generatedPlan)
                    openCapacitySection(generatedPlan)
                    conflictSection(generatedPlan)
                    recommendationSection(generatedPlan)
                    proposalNotice
                } else {
                    instructionsCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Daily Plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedTechnicianID == nil {
                selectedTechnicianID = technicians.first?.id
            }
        }
        .onChange(of: selectedTechnicianID) { _, _ in
            clearGeneratedPlan()
        }
        .onChange(of: selectedDate) { _, _ in
            clearGeneratedPlan()
        }
    }

    // MARK: - Controls

    private var plannerControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Plan Inputs", systemImage: "slider.horizontal.3")
                .font(.headline)

            Divider()

            HStack {
                Text("Technician")

                Spacer()

                Menu {
                    ForEach(technicians) { technician in
                        Button {
                            selectedTechnicianID = technician.id
                        } label: {
                            if technician.id == selectedTechnicianID {
                                Label(
                                    technician.displayName,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(technician.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(
                            selectedTechnician?.displayName
                                ?? "Select Technician"
                        )
                        .lineLimit(1)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                }
                .disabled(technicians.isEmpty)
            }

            DatePicker(
                "Plan Date",
                selection: $selectedDate,
                displayedComponents: .date
            )

            Button(action: generatePlan) {
                Label(
                    generatedPlan == nil ? "Generate Plan" : "Refresh Plan",
                    systemImage: "calendar.badge.clock"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTechnician == nil)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Preview Before Committing", systemImage: "eye.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Choose a technician and date, then generate a proposed workday. The preview honors scheduling modes, lunch, buffers, working hours, and available capacity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("No Assignment will be changed.")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Summary

    private func planHeader(_ plan: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTechnician?.displayName ?? "Technician")
                        .font(.title2.bold())

                    Text(plan.date.formatted(date: .complete, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                planStatusBadge(plan)
            }

            if let workdayStart = plan.workdayStart,
               let workdayEnd = plan.workdayEnd {
                Label(
                    "Workday \(time(workdayStart))–\(time(workdayEnd))",
                    systemImage: "clock"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                summaryMetric(
                    title: "Placed",
                    value: "\(plan.plannedAssignmentCount)",
                    icon: "checkmark.circle.fill"
                )

                summaryMetric(
                    title: "Unplaced",
                    value: "\(plan.unplacedAssignmentIDs.count)",
                    icon: "exclamationmark.circle.fill"
                )

                summaryMetric(
                    title: "Service",
                    value: duration(plan.plannedServiceMinutes),
                    icon: "wrench.and.screwdriver.fill"
                )

                summaryMetric(
                    title: "Occupied",
                    value: duration(plan.plannedOccupiedMinutes),
                    icon: "calendar.badge.clock"
                )
            }

            HStack {
                Label(
                    "Daily reserve: \(duration(plan.dailyReserveMinutes))",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if let generatedAt {
                    Text("Generated \(time(generatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func planStatusBadge(_ plan: DailyPlan) -> some View {
        Label(
            plan.isComplete ? "Complete" : "Review",
            systemImage: plan.isComplete
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(plan.isComplete ? Color.green : Color.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (plan.isComplete ? Color.green : Color.orange)
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }

    private func summaryMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Route Planning

    private func routePlanningSection(_ plan: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Route This Plan")
                        .font(.headline)

                    Text("Calculate road mileage, drive time, stop ETAs, and scheduling-constraint conflicts before applying a route.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                RoutePlanPreviewView(
                    dailyPlan: plan,
                    technicianName: selectedTechnician?.displayName
                        ?? "Technician"
                )
            } label: {
                Label(
                    "Review Road Route",
                    systemImage: "map.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.assignmentItems.isEmpty)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Timeline

    private func timelineSection(_ plan: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Proposed Timeline", icon: "list.bullet.rectangle")

            if plan.items.isEmpty {
                emptyCard(
                    title: "No work was placed",
                    detail: "Review the conflicts below or choose another date."
                )
            } else {
                ForEach(plan.items) { item in
                    timelineCard(item)
                }
            }
        }
    }

    private func timelineCard(_ item: DailyPlanItem) -> some View {
        let assignment = assignment(for: item.assignmentID)

        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                Text(time(item.serviceStart))
                    .font(.subheadline.bold())

                Rectangle()
                    .fill(accentColor(for: item).opacity(0.35))
                    .frame(width: 2, height: 44)

                Text(time(item.serviceEnd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 62)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayTitle(for: item, assignment: assignment))
                            .font(.headline)

                        if let assignment {
                            Text(siteDisplayName(for: assignment))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    modeBadge(item)
                }

                if item.kind == .assignment {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(
                    "Service \(duration(item.serviceMinutes)) · Occupied \(duration(item.occupiedMinutes))",
                    systemImage: "clock.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if item.occupiedStart != item.serviceStart ||
                    item.occupiedEnd != item.serviceEnd {
                    Text("Buffer window: \(time(item.occupiedStart))–\(time(item.occupiedEnd))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(accentColor(for: item))
                .frame(width: 5)
        }
    }

    private func modeBadge(_ item: DailyPlanItem) -> some View {
        Text(item.kind == .lunch
            ? "Lunch"
            : (item.schedulingMode?.rawValue ?? "Assignment"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(accentColor(for: item))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(accentColor(for: item).opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Capacity and Diagnostics

    private func openCapacitySection(_ plan: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Open Capacity", icon: "clock.arrow.circlepath")

            if plan.openWindows.isEmpty {
                emptyCard(
                    title: "No open windows",
                    detail: "The proposed workday has no remaining usable openings."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plan.openWindows.enumerated()), id: \.element.id) { index, window in
                        HStack {
                            Label(
                                "\(time(window.start))–\(time(window.end))",
                                systemImage: "clock"
                            )

                            Spacer()

                            Text(duration(window.durationMinutes))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)

                        if index < plan.openWindows.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    @ViewBuilder
    private func conflictSection(_ plan: DailyPlan) -> some View {
        if !plan.conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Conflicts & Unplaced Work", icon: "exclamationmark.triangle.fill")

                ForEach(plan.conflicts) { conflict in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: conflict.severity == .error
                            ? "xmark.octagon.fill"
                            : "exclamationmark.triangle.fill")
                            .foregroundStyle(conflict.severity == .error
                                ? Color.red
                                : Color.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.kind.rawValue)
                                .font(.headline)

                            Text(conflict.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    @ViewBuilder
    private func recommendationSection(_ plan: DailyPlan) -> some View {
        if !plan.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Planner Decisions", icon: "sparkles")

                VStack(spacing: 0) {
                    ForEach(Array(plan.recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(recommendation.kind.rawValue)
                                    .font(.subheadline.weight(.semibold))

                                Text(recommendation.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 12)

                        if index < plan.recommendations.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var proposalNotice: some View {
        Label(
            "Preview only — this plan has not changed the committed schedule.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Actions

    private func generatePlan() {
        guard let selectedTechnician else { return }

        generatedPlan = store.dailyPlan(
            for: selectedTechnician,
            on: selectedDate,
            calendar: calendar
        )
        generatedAt = Date()
    }

    private func clearGeneratedPlan() {
        generatedPlan = nil
        generatedAt = nil
    }

    // MARK: - Display Helpers

    private func assignment(for id: UUID?) -> Assignment? {
        guard let id else { return nil }
        return store.assignmentEngine.assignments.first { $0.id == id }
    }

    private func displayTitle(
        for item: DailyPlanItem,
        assignment: Assignment?
    ) -> String {
        guard item.kind == .assignment, let assignment else {
            return item.title
        }

        guard let customer = store.customers.first(where: {
            $0.customerNumber == assignment.customerNumber
        }) else {
            return assignment.customerNumber.isEmpty
                ? item.title
                : assignment.customerNumber
        }

        let businessName = customer.businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contactName = customer.contactName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !businessName.isEmpty { return businessName }
        if !contactName.isEmpty { return contactName }
        return customer.customerNumber
    }

    private func siteDisplayName(for assignment: Assignment) -> String {
        guard let siteID = assignment.siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "No site assigned"
        }

        let name = site.siteName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Site" : name
    }

    private func accentColor(for item: DailyPlanItem) -> Color {
        guard item.kind == .assignment else { return .green }

        switch item.schedulingMode {
        case .fixedTime: return .blue
        case .arrivalWindow: return .purple
        case .flexibleDay: return .teal
        case .deadline: return .orange
        case nil: return .gray
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title2.bold())
    }

    private func emptyCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func duration(_ minutes: Int) -> String {
        let safeMinutes = max(minutes, 0)
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60

        if hours > 0 && remainder > 0 {
            return "\(hours) hr \(remainder) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(remainder) min"
    }
}

