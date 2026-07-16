//
//  EmployeeDailyJobsView.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/15/26.
//

import SwiftUI

struct EmployeeDailyJobsView: View {
    @EnvironmentObject var store: AppDataStore

    let employee: EmployeeRecord

    @State private var selectedDate: Date

    private var summary: EmployeeCapacitySummary {
        SchedulingCalculator.capacitySummary(
            for: employee,
            on: selectedDate,
            from: store.jobs
        )
    }
    init(
        employee: EmployeeRecord,
        date: Date
    ) {
        self.employee = employee
        _selectedDate = State(initialValue: date)
    }

    private var sortedJobs: [JobRecord] {
        summary.assignedJobs.sorted {
            $0.scheduledDate < $1.scheduledDate
        }
    }

    var body: some View {
        List {
            Section {
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

                if !Calendar.current.isDateInToday(
                    selectedDate
                ) {
                    Button("Return to Today") {
                        selectedDate = Date()
                    }
                }
            }
            Section {
                employeeHeader
            }

            Section("Daily Capacity") {
                capacityRow(
                    label: "Capacity",
                    minutes: summary.capacityMinutes
                )

                capacityRow(
                    label: "Scheduled",
                    minutes: summary.scheduledMinutes
                )

                capacityRow(
                    label: summary.isOverCapacity
                        ? "Over Capacity By"
                        : "Remaining",
                    minutes: abs(summary.remainingMinutes),
                    valueColor: utilizationColor
                )

                HStack {
                    Text("Utilization")

                    Spacer()

                    Text("\(summary.utilizationPercentage)%")
                        .fontWeight(.semibold)
                        .foregroundStyle(utilizationColor)
                }

                ProgressView(
                    value: min(
                        summary.utilizationFraction,
                        1
                    )
                )
                .tint(utilizationColor)

                Label(
                    statusText,
                    systemImage: statusIcon
                )
                .font(.caption)
                .foregroundStyle(utilizationColor)
            }

            Section("Assigned Jobs") {
                if sortedJobs.isEmpty {
                    ContentUnavailableView(
                        "No Assigned Jobs",
                        systemImage: "calendar.badge.checkmark",
                        description: Text(
                            "This employee has no jobs assigned for the selected date."
                        )
                    )
                } else {
                    ForEach(sortedJobs) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                                .environmentObject(store)
                        } label: {
                            jobRow(job)
                        }
                    }
                }
            }
        }
        .navigationTitle(employee.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var employeeHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        employeeColor(
                            named: employee.colorName
                        )
                    )
                    .frame(width: 18, height: 18)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(employee.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(employee.role.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }


            if !summary.isWorkingDay {
                Label(
                    summary.scheduledMinutes > 0
                        ? "Jobs are assigned on a non-working day."
                        : "Not normally scheduled to work this day.",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func jobRow(
        _ job: JobRecord
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    job.scheduledDate.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
                .fontWeight(.semibold)

                Spacer()

                Text(
                    SchedulingCalculator
                        .formattedScheduledDuration(
                            for: job
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(serviceName(for: job))
                .font(.headline)

            Text(
                customerDisplayName(
                    for: job.customerNumber
                )
            )
            .font(.subheadline)

            if let siteText = siteDisplayText(for: job),
               !siteText.isEmpty {
                Label(
                    siteText,
                    systemImage: "mappin.and.ellipse"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Text(job.jobNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(job.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(
                        statusColor(for: job.status)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private func capacityRow(
        label: String,
        minutes: Int,
        valueColor: Color = .primary
    ) -> some View {
        HStack {
            Text(label)

            Spacer()

            Text(durationText(minutes))
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
    }

    private var utilizationColor: Color {
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

    private var statusText: String {
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

    private var statusIcon: String {
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

    private func serviceName(
        for job: JobRecord
    ) -> String {
        if job.serviceType == .other {
            return job.otherService.isEmpty
                ? "Other Service"
                : job.otherService
        }

        return job.serviceType.rawValue
    }

    private func customerDisplayName(
        for customerNumber: String
    ) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return customerNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return customerNumber
    }

    private func siteDisplayText(
        for job: JobRecord
    ) -> String? {
        guard
            let siteID = job.siteID,
            let site = store.sites.first(where: {
                $0.id == siteID
            })
        else {
            return nil
        }

        if !site.siteName.isEmpty {
            return site.siteName
        }

        return site.serviceAddress
    }

    private func statusColor(
        for status: JobStatus
    ) -> Color {
        switch status {
        case .completed:
            return .green

        case .cancelled:
            return .red

        case .inProgress:
            return .orange

        case .assigned, .scheduled:
            return .blue

        case .toBeScheduled:
            return .secondary
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
}
