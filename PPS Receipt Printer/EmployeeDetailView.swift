//
//  EmployeeDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/14/26.
//

import SwiftUI

struct EmployeeDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var employee: EmployeeRecord
    private let originalEmployee: EmployeeRecord

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var showingRoleSelection = false
    @State private var showingUnsavedChangesAlert = false

    @FocusState private var isInputFocused: Bool

    private let colorOptions = [
        "blue",
        "green",
        "orange",
        "purple",
        "red",
        "yellow",
        "gray"
    ]

    private let lunchOptions = [
        0,
        15,
        30,
        45,
        60
    ]

    init(employee: EmployeeRecord) {
        originalEmployee = employee
        _employee = State(initialValue: employee)

        _startTime = State(
            initialValue: Self.dateFromMinutes(
                employee.defaultStartMinutes
            )
        )

        _endTime = State(
            initialValue: Self.dateFromMinutes(
                employee.defaultEndMinutes
            )
        )
    }

    private var dailyCapacityMinutes: Int {
        let startMinutes = minutesFromDate(startTime)
        let endMinutes = minutesFromDate(endTime)

        return max(
            endMinutes
            - startMinutes
            - employee.lunchDurationMinutes,
            0
        )
    }

    var body: some View {
        Form {
            Section("Employee Setup") {
                employeeSectionLink(
                    title: "Employee",
                    subtitle: employee.roleDisplayText,
                    symbol: "person.crop.circle.fill"
                ) {
                    EmployeeIdentityEditorView(employee: $employee)
                }

                employeeSectionLink(
                    title: "Home / Base Address",
                    subtitle: employee.normalizedBaseAddress ?? "Not set",
                    symbol: "house.fill"
                ) {
                    EmployeeBaseAddressEditorView(baseAddress: $employee.baseAddress)
                }

                employeeSectionLink(
                    title: "Working Days",
                    subtitle: "\(employee.workingDays.count) days selected",
                    symbol: "calendar"
                ) {
                    EmployeeWorkingDaysEditorView(workingDays: $employee.workingDays)
                }

                employeeSectionLink(
                    title: "Normal Work Day",
                    subtitle: SchedulingCalculator.formattedDuration(minutes: dailyCapacityMinutes),
                    symbol: "clock.fill"
                ) {
                    EmployeeNormalWorkdayEditorView(
                        startTime: $startTime,
                        endTime: $endTime,
                        lunchMinutes: $employee.lunchDurationMinutes
                    )
                }

                employeeSectionLink(
                    title: "Time Off",
                    subtitle: "\(employee.workforceProfile.availabilityExceptions.filter { $0.kind == .unavailable }.count) scheduled",
                    symbol: "calendar.badge.minus"
                ) {
                    EmployeeTimeOffView(
                        exceptions: $employee.workforceProfile.availabilityExceptions,
                        employeeName: employee.displayName
                    )
                }

                NavigationLink {
                    WorkforceProfileEditorView(
                        profile: $employee.workforceProfile,
                        employeeName: employee.displayName
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            "Workforce Profile",
                            systemImage: "person.text.rectangle"
                        )
                        .fontWeight(.semibold)

                        Text(workforceProfileSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                if employee.lifecycleStatus == .archived {
                    Button {
                        store.restoreEmployee(employee)
                        dismiss()
                    } label: {
                        Label("Restore Employee", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveEmployee(employee)
                        dismiss()
                    } label: {
                        Label("Archive Employee", systemImage: "archivebox.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(employee.displayName)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingRoleSelection) {
            EmployeeRoleSelectionView(selectedRoles: $employee.roles)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(
                    employee.firstName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
        .alert(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert
        ) {
            Button("Save Changes") {
                saveChanges()
            }

            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This employee has changes that have not been saved.")
        }
    }

    private func employeeSectionLink<Destination: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
            }
            .padding(.vertical, 5)
        }
    }

    private var hasUnsavedChanges: Bool {
        encodedEmployee(employeeForComparison) !=
            encodedEmployee(originalEmployee)
    }

    private var employeeForComparison: EmployeeRecord {
        var candidate = employee
        candidate.defaultStartMinutes = minutesFromDate(startTime)
        candidate.defaultEndMinutes = minutesFromDate(endTime)
        candidate.normalizeRoles()
        return candidate
    }

    private var workforceProfileSummary: String {
        let profile = employee.workforceProfile

        guard profile.hasIntelligenceData else {
            return "No operational profile information entered"
        }

        return "\(profile.skills.count) skills · \(profile.certifications.count) certifications · \(profile.resourceAccess.count) resources"
    }

    private func saveChanges() {
        isInputFocused = false

        employee.firstName =
            employee.firstName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.lastName =
            employee.lastName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.phone =
            employee.phone.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.email =
            employee.email.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.baseAddress =
            employee.baseAddress.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.defaultStartMinutes =
            minutesFromDate(startTime)

        employee.defaultEndMinutes =
            minutesFromDate(endTime)

        employee.normalizeRoles()

        store.updateEmployee(employee)
        dismiss()
    }

    private func requestDismissal() {
        isInputFocused = false
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func encodedEmployee(
        _ employee: EmployeeRecord
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(employee)
    }

    private func workingDayBinding(
        for day: Workday
    ) -> Binding<Bool> {
        Binding(
            get: {
                employee.workingDays.contains(day)
            },
            set: { isWorking in
                if isWorking {
                    employee.workingDays.insert(day)
                } else {
                    employee.workingDays.remove(day)
                }
            }
        )
    }

    private func lunchLabel(
        for minutes: Int
    ) -> String {
        guard minutes > 0 else {
            return "No Lunch"
        }

        return SchedulingCalculator.formattedDuration(
            minutes: minutes
        )
    }

    private func minutesFromDate(
        _ date: Date
    ) -> Int {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )

        return
            (components.hour ?? 0) * 60
            + (components.minute ?? 0)
    }

    private static func dateFromMinutes(
        _ minutes: Int
    ) -> Date {
        let safeMinutes = max(minutes, 0)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60

        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func displayColor(
        for colorName: String
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
