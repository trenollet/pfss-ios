//
//  TechnicianDailyAgendaView.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/16/26.
//

import SwiftUI

struct TechnicianDailyAgendaView: View {
    @EnvironmentObject var store: AppDataStore

    let employee: EmployeeRecord

    @State private var selectedDate = Date()

    private var summary: EmployeeCapacitySummary {
        SchedulingCalculator.capacitySummary(
            for: employee,
            on: selectedDate,
            from: store.jobs
        )
    }

    private var sortedJobs: [JobRecord] {
        summary.assignedJobs.sorted {
            $0.scheduledDate < $1.scheduledDate
        }
    }

    private var completedJobCount: Int {
        sortedJobs.filter {
            $0.status == .completed
        }
        .count
    }

    private var firstJob: JobRecord? {
        sortedJobs.first
    }

    private var estimatedFinishDate: Date? {
        sortedJobs.compactMap { job in
            Calendar.current.date(
                byAdding: .minute,
                value: SchedulingCalculator.scheduledMinutes(
                    for: job
                ),
                to: job.scheduledDate
            )
        }
        .max()
    }

    var body: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 18
            ) {
                greetingHeader

                dateNavigator

                dailySummaryCard

                scheduleHeader

                if sortedJobs.isEmpty {
                    emptyScheduleCard
                } else {
                    ForEach(
                        Array(sortedJobs.enumerated()),
                        id: \.element.id
                    ) { index, job in
                        NavigationLink {
                            JobDetailView(job: job)
                                .environmentObject(store)
                        } label: {
                            technicianJobCard(
                                job,
                                sequenceNumber: index + 1
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(
            Color(uiColor: .systemGroupedBackground)
        )
        .navigationTitle("My Day")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var greetingHeader: some View {
        HStack(
            alignment: .center,
            spacing: 12
        ) {
            Circle()
                .fill(
                    employeeColor(
                        named: employee.colorName
                    )
                )
                .frame(
                    width: 46,
                    height: 46
                )
                .overlay {
                    Text(employeeInitials)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    "\(greetingText), \(employee.firstName)"
                )
                .font(.title2)
                .fontWeight(.bold)

                Text(
                    selectedDate.formatted(
                        date: .complete,
                        time: .omitted
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var dateNavigator: some View {
        HStack {
            Button {
                changeDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(
                        width: 40,
                        height: 40
                    )
            }
            .buttonStyle(.bordered)

            Spacer()

            if !Calendar.current.isDateInToday(
                selectedDate
            ) {
                Button("Return to Today") {
                    selectedDate = Date()
                }
                .font(.subheadline)
            } else {
                Text("Today")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                changeDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(
                        width: 40,
                        height: 40
                    )
            }
            .buttonStyle(.bordered)
        }
    }

    private var dailySummaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("TODAY'S PLAN")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(dailyHeadline)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                Text(
                    "\(summary.utilizationPercentage)%"
                )
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(utilizationColor)
            }

            ProgressView(
                value: min(
                    summary.utilizationFraction,
                    1
                )
            )
            .tint(utilizationColor)
            .scaleEffect(
                x: 1,
                y: 1.8,
                anchor: .center
            )

            HStack(
                alignment: .top,
                spacing: 12
            ) {
                summaryMetric(
                    title: "Jobs",
                    value: "\(summary.assignedJobCount)",
                    systemImage: "briefcase.fill"
                )

                Spacer()

                summaryMetric(
                    title: "Scheduled",
                    value: durationText(
                        summary.scheduledMinutes
                    ),
                    systemImage: "clock.fill"
                )

                Spacer()

                summaryMetric(
                    title: "Finish",
                    value: estimatedFinishText,
                    systemImage: "flag.checkered"
                )
            }

            Divider()

            HStack {
                Label(
                    progressText,
                    systemImage: progressIcon
                )
                .font(.subheadline)
                .foregroundStyle(utilizationColor)

                Spacer()

                Text(
                    "\(completedJobCount) of "
                    + "\(summary.assignedJobCount) complete"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !summary.isWorkingDay {
                Label(
                    summary.scheduledMinutes > 0
                        ? "Work is assigned on a non-working day."
                        : "You are not normally scheduled today.",
                    systemImage:
                        "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if summary.isOverCapacity {
                Label(
                    "Schedule exceeds daily capacity by "
                    + durationText(
                        abs(summary.remainingMinutes)
                    ),
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }

    private var scheduleHeader: some View {
        HStack {
            Text("Today's Schedule")
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            if let firstJob {
                Text(
                    "Starts "
                    + firstJob.scheduledDate.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyScheduleCard: some View {
        VStack(spacing: 14) {
            Image(
                systemName:
                    "calendar.badge.checkmark"
            )
            .font(.system(size: 40))
            .foregroundStyle(.secondary)

            Text("No Jobs Scheduled")
                .font(.headline)

            Text(
                "There are no assigned jobs for this day."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(.vertical, 40)
        .padding(.horizontal)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }

    private func technicianJobCard(
        _ job: JobRecord,
        sequenceNumber: Int
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 14
        ) {
            timelineColumn(
                for: job,
                sequenceNumber: sequenceNumber
            )

            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(
                    alignment: .firstTextBaseline
                ) {
                    Text(serviceName(for: job))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(
                        SchedulingCalculator
                            .formattedScheduledDuration(
                                for: job
                            )
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                }

                Text(
                    customerDisplayName(
                        for: job.customerNumber
                    )
                )
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

                if let site = site(for: job) {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            if !site.siteName.isEmpty {
                                Text(site.siteName)
                                    .fontWeight(.medium)
                            }

                            Text(site.serviceAddress)
                        }
                    } icon: {
                        Image(
                            systemName:
                                "mappin.and.ellipse"
                        )
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Label(
                        job.status.rawValue,
                        systemImage:
                            statusIcon(
                                for: job.status
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        statusColor(
                            for: job.status
                        )
                    )

                    Spacer()

                    Text(job.jobNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(
                Color(
                    uiColor:
                        .secondarySystemGroupedBackground
                )
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 16)
            )
        }
    }

    private func timelineColumn(
        for job: JobRecord,
        sequenceNumber: Int
    ) -> some View {
        VStack(spacing: 8) {
            Text(
                job.scheduledDate.formatted(
                    date: .omitted,
                    time: .shortened
                )
            )
            .font(.caption)
            .fontWeight(.bold)
            .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .fill(
                        employeeColor(
                            named: employee.colorName
                        )
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )

                Text("\(sequenceNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(
                    employeeColor(
                        named: employee.colorName
                    )
                    .opacity(0.35)
                )
                .frame(
                    width: 3,
                    height: 72
                )
        }
        .frame(width: 62)
    }

    private func summaryMetric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Label(
                title,
                systemImage: systemImage
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
        }
    }

    private var dailyHeadline: String {
        switch summary.assignedJobCount {
        case 0:
            return "Your day is clear"

        case 1:
            return "1 job scheduled"

        default:
            return "\(summary.assignedJobCount) jobs scheduled"
        }
    }

    private var estimatedFinishText: String {
        guard let estimatedFinishDate else {
            return "—"
        }

        return estimatedFinishDate.formatted(
            date: .omitted,
            time: .shortened
        )
    }

    private var progressText: String {
        if summary.assignedJobCount == 0 {
            return "No work scheduled"
        }

        if completedJobCount ==
            summary.assignedJobCount {

            return "Day complete"
        }

        if completedJobCount > 0 {
            return "Day in progress"
        }

        return "Ready to begin"
    }

    private var progressIcon: String {
        if summary.assignedJobCount == 0 {
            return "calendar.badge.checkmark"
        }

        if completedJobCount ==
            summary.assignedJobCount {

            return "checkmark.seal.fill"
        }

        if completedJobCount > 0 {
            return "figure.walk.motion"
        }

        return "play.circle.fill"
    }

    private var utilizationColor: Color {
        if !summary.isWorkingDay {
            return .gray
        }

        if summary.isOverCapacity {
            return .red
        }

        if summary.utilizationPercentage >= 80 {
            return .yellow
        }

        return .green
    }

    private var greetingText: String {
        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )

        switch hour {
        case 0..<12:
            return "Good Morning"

        case 12..<17:
            return "Good Afternoon"

        default:
            return "Good Evening"
        }
    }

    private var employeeInitials: String {
        let firstInitial =
            employee.firstName.first.map(String.init)
            ?? ""

        let lastInitial =
            employee.lastName.first.map(String.init)
            ?? ""

        let initials =
            firstInitial + lastInitial

        return initials.isEmpty
            ? "?"
            : initials.uppercased()
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
        guard let customer =
                store.customers.first(where: {
                    $0.customerNumber ==
                        customerNumber
                })
        else {
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

    private func site(
        for job: JobRecord
    ) -> CustomerSite? {
        guard let siteID = job.siteID else {
            return nil
        }

        return store.sites.first {
            $0.id == siteID
        }
    }

    private func statusIcon(
        for status: JobStatus
    ) -> String {
        switch status {
        case .toBeScheduled:
            return "calendar.badge.questionmark"

        case .scheduled:
            return "calendar"

        case .assigned:
            return "person.badge.clock"

        case .inProgress:
            return "play.circle.fill"

        case .completed:
            return "checkmark.circle.fill"

        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private func statusColor(
        for status: JobStatus
    ) -> Color {
        switch status {
        case .toBeScheduled:
            return .secondary

        case .scheduled, .assigned:
            return .blue

        case .inProgress:
            return .orange

        case .completed:
            return .green

        case .cancelled:
            return .red
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
            )
            ?? selectedDate
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
