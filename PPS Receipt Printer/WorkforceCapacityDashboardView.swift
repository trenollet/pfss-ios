//
//  WorkforceCapacityDashboardView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/15/26.
//

import SwiftUI

struct WorkforceCapacityDashboardView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var selectedDate = Date()

    private var activeEmployees: [EmployeeRecord] {
        store.activeEmployees.sorted {
            $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            ) == .orderedAscending
        }
    }

    private var summaries: [EmployeeCapacitySummary] {
        activeEmployees.map { employee in
            SchedulingCalculator.capacitySummary(
                for: employee,
                on: selectedDate,
                from: store.jobs
            )
        }
    }

    var body: some View {
        List {
            Section("Date") {
                HStack {
                    Button {
                        changeDate(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    VStack(spacing: 2) {
                        Text(
                            selectedDate.formatted(
                                date: .complete,
                                time: .omitted
                            )
                        )
                        .font(.headline)

                        if Calendar.current.isDateInToday(
                            selectedDate
                        ) {
                            Text("Today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        changeDate(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }

                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )

                if !Calendar.current.isDateInToday(
                    selectedDate
                ) {
                    Button("Return to Today") {
                        selectedDate = Date()
                    }
                }
            }

            Section("Workforce Capacity") {
                if summaries.isEmpty {
                    ContentUnavailableView(
                        "No Active Employees",
                        systemImage: "person.3",
                        description: Text(
                            "Add an active employee to begin capacity planning."
                        )
                    )
                } else {
                    ForEach(
                        summaries,
                        id: \.employee.id
                    ) { summary in
                        NavigationLink {
                            EmployeeDailyJobsView(
                                employee: summary.employee,
                                date: selectedDate
                            )
                            .environmentObject(store)
                        } label: {
                            employeeCapacityCard(summary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Capacity Dashboard")
    }

    @ViewBuilder
    private func employeeCapacityCard(
        _ summary: EmployeeCapacitySummary
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        employeeColor(
                            named: summary.employee.colorName
                        )
                    )
                    .frame(width: 14, height: 14)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(summary.employee.displayName)
                        .font(.headline)

                    Text(summary.employee.role.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(
                    "\(summary.utilizationPercentage)%"
                )
                .fontWeight(.semibold)
                .foregroundStyle(
                    utilizationColor(for: summary)
                )
            }

            ProgressView(
                value: min(
                    summary.utilizationFraction,
                    1
                )
            )
            .tint(
                utilizationColor(for: summary)
            )

            HStack {
                metricColumn(
                    title: "Capacity",
                    minutes: summary.capacityMinutes
                )

                Spacer()

                metricColumn(
                    title: "Scheduled",
                    minutes: summary.scheduledMinutes
                )

                Spacer()

                metricColumn(
                    title: summary.isOverCapacity
                        ? "Over By"
                        : "Remaining",
                    minutes: abs(
                        summary.remainingMinutes
                    )
                )
            }

            HStack {
                Label(
                    statusText(for: summary),
                    systemImage: statusIcon(for: summary)
                )
                .font(.caption)
                .foregroundStyle(
                    utilizationColor(for: summary)
                )

                Spacer()

                Text(
                    "\(summary.assignedJobCount) "
                    + (
                        summary.assignedJobCount == 1
                        ? "job"
                        : "jobs"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func metricColumn(
        title: String,
        minutes: Int
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(
                durationText(minutes)
            )
            .font(.caption)
            .fontWeight(.semibold)
        }
    }

    private func statusText(
        for summary: EmployeeCapacitySummary
    ) -> String {
        if !summary.isWorkingDay {
            return summary.scheduledMinutes > 0
                ? "Scheduled on non-working day"
                : "Not scheduled to work"
        }

        if summary.isOverCapacity {
            return "Over capacity"
        }

        if summary.isNearCapacity {
            return "Near capacity"
        }

        return "Available"
    }

    private func statusIcon(
        for summary: EmployeeCapacitySummary
    ) -> String {
        if !summary.isWorkingDay {
            return "calendar.badge.exclamationmark"
        }

        if summary.isOverCapacity {
            return "exclamationmark.triangle.fill"
        }

        if summary.isNearCapacity {
            return "clock.badge.exclamationmark"
        }

        return "checkmark.circle.fill"
    }

    private func utilizationColor(
        for summary: EmployeeCapacitySummary
    ) -> Color {
        if !summary.isWorkingDay {
            return .gray
        }

        if summary.isOverCapacity {
            return .red
        }

        if summary.isNearCapacity {
            return .yellow
        }

        return .green
    }

    private func employeeColor(
        named colorName: String
    ) -> Color {
        switch colorName.lowercased() {
        case "green":
            return .green

        case "orange":
            return .orange

        case "purple":
            return .purple

        case "red":
            return .red

        case "yellow":
            return .yellow

        case "gray":
            return .gray

        default:
            return .blue
        }
    }

    private func durationText(
        _ minutes: Int
    ) -> String {
        guard minutes > 0 else {
            return "0 min"
        }

        return SchedulingCalculator.formattedDuration(
            minutes: minutes
        )
    }

    private func changeDate(
        by dayOffset: Int
    ) {
        selectedDate =
            Calendar.current.date(
                byAdding: .day,
                value: dayOffset,
                to: selectedDate
            ) ?? selectedDate
    }
}
