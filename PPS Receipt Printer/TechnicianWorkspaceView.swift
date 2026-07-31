//
//  TechnicianWorkspaceView.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/16/26.
//

import SwiftUI

struct TechnicianWorkspaceView: View {
    @EnvironmentObject var store: AppDataStore

    @AppStorage("selectedTechnicianID")
    private var selectedTechnicianIDString = ""

    private var eligibleEmployees: [EmployeeRecord] {
        store.activeEmployees
            .filter { employee in
                employee.hasRole(.technician)
                    || employee.hasRole(.manager)
                    || employee.hasRole(.owner)
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    private var selectedEmployeeID: UUID? {
        UUID(
            uuidString: selectedTechnicianIDString
        )
    }

    private var selectedEmployee: EmployeeRecord? {
        guard let selectedEmployeeID else {
            return nil
        }

        return eligibleEmployees.first {
            $0.id == selectedEmployeeID
        }
    }

    var body: some View {
        NavigationStack {
            if store.usesAuthenticatedMyDayIdentity {
                authenticatedMyDay
            } else {
                ownerTechnicianWorkspace
            }
        }
    }

    @ViewBuilder
    private var authenticatedMyDay: some View {
        if let employee = store.authenticatedMyDayEmployee {
            TechnicianDailyAgendaView(employee: employee)
                .environmentObject(store)
        } else if store.authenticatedCloudEmployee == nil {
            ContentUnavailableView(
                "No Linked Employee Profile",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text(
                    "Contact your system administrator to have this device added to your employee profile."
                )
            )
            .navigationTitle("My Day")
        } else {
            ContentUnavailableView(
                "My Day Is Not Assigned",
                systemImage: "calendar.badge.exclamationmark",
                description: Text(
                    "My Day is available to employees with Technician access."
                )
            )
            .navigationTitle("My Day")
        }
    }

    private var ownerTechnicianWorkspace: some View {
        List {
                Section("Technician") {
                    Picker(
                        "Viewing Schedule For",
                        selection: technicianSelection
                    ) {
                        Text("Select Technician")
                            .tag("")

                        ForEach(eligibleEmployees) { employee in
                            Text(employee.displayName)
                                .tag(employee.id.uuidString)
                        }
                    }
                }

                if eligibleEmployees.isEmpty {
                    ContentUnavailableView(
                        "No Technicians",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(
                            "Add an active technician before using the technician workspace."
                        )
                    )
                } else if let employee = selectedEmployee {
                    Section("My Day") {
                        NavigationLink {
                            TechnicianDailyAgendaView(
                                employee: employee
                            )
                            .environmentObject(store)
                        } label: {
                            technicianSummary(
                                for: employee
                            )
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Select a Technician",
                            systemImage: "person.crop.circle",
                            description: Text(
                                "Choose the employee whose daily schedule should appear on this device."
                            )
                        )
                    }
                }
        }
        .navigationTitle("Technician")
        .onAppear {
            repairSelectionIfNeeded()
        }
        .onChange(
            of: store.activeEmployees.map(\.id)
        ) { _, _ in
            repairSelectionIfNeeded()
        }
    }

    private var technicianSelection: Binding<String> {
        Binding(
            get: {
                selectedTechnicianIDString
            },
            set: { newValue in
                selectedTechnicianIDString =
                    newValue
            }
        )
    }

    private func technicianSummary(
        for employee: EmployeeRecord
    ) -> some View {
        let summary =
            SchedulingCalculator.capacitySummary(
                for: employee,
                on: Date(),
                from: store.jobs
            )

        return VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        employeeColor(
                            named: employee.colorName
                        )
                    )
                    .frame(
                        width: 16,
                        height: 16
                    )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(employee.displayName)
                        .font(.headline)

                    Text(
                        Date().formatted(
                            date: .complete,
                            time: .omitted
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                summaryMetric(
                    title: "Jobs",
                    value: "\(summary.assignedJobCount)"
                )

                Spacer()

                summaryMetric(
                    title: "Scheduled",
                    value: durationText(
                        summary.scheduledMinutes
                    )
                )

                Spacer()

                summaryMetric(
                    title: summary.isOverCapacity
                        ? "Over By"
                        : "Remaining",
                    value: durationText(
                        abs(summary.remainingMinutes)
                    )
                )
            }

            HStack {
                Label(
                    technicianStatusText(
                        for: summary
                    ),
                    systemImage:
                        technicianStatusIcon(
                            for: summary
                        )
                )
                .font(.caption)
                .foregroundStyle(
                    technicianStatusColor(
                        for: summary
                    )
                )

                Spacer()

                Text(
                    "\(summary.utilizationPercentage)%"
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    technicianStatusColor(
                        for: summary
                    )
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func summaryMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    private func technicianStatusText(
        for summary: EmployeeCapacitySummary
    ) -> String {
        if !summary.isWorkingDay {
            return summary.scheduledMinutes > 0
                ? "Work scheduled today"
                : "Not scheduled today"
        }

        if summary.isOverCapacity {
            return "Schedule exceeds capacity"
        }

        if summary.assignedJobCount == 0 {
            return "No jobs scheduled"
        }

        return "Today's schedule"
    }

    private func technicianStatusIcon(
        for summary: EmployeeCapacitySummary
    ) -> String {
        if !summary.isWorkingDay {
            return "calendar.badge.exclamationmark"
        }

        if summary.isOverCapacity {
            return "exclamationmark.triangle.fill"
        }

        if summary.assignedJobCount == 0 {
            return "calendar.badge.checkmark"
        }

        return "checkmark.circle.fill"
    }

    private func technicianStatusColor(
        for summary: EmployeeCapacitySummary
    ) -> Color {
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

    private func repairSelectionIfNeeded() {
        if let selectedEmployeeID,
           eligibleEmployees.contains(
               where: {
                   $0.id == selectedEmployeeID
               }
           ) {
            return
        }

        selectedTechnicianIDString =
            eligibleEmployees.first?
                .id
                .uuidString
            ?? ""
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
