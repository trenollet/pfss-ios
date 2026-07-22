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

    @State private var startTime: Date
    @State private var endTime: Date

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
            Section("Employee") {
                TextField(
                    "First Name",
                    text: $employee.firstName
                )
                .textContentType(.givenName)
                .focused($isInputFocused)

                TextField(
                    "Last Name",
                    text: $employee.lastName
                )
                .textContentType(.familyName)
                .focused($isInputFocused)

                TextField(
                    "Phone",
                    text: $employee.phone
                )
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($isInputFocused)

                TextField(
                    "Email",
                    text: $employee.email
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isInputFocused)

                Picker(
                    "Role",
                    selection: $employee.role
                ) {
                    ForEach(EmployeeRole.allCases) { role in
                        Text(role.rawValue)
                            .tag(role)
                    }
                }

                Toggle(
                    "Active Employee",
                    isOn: $employee.isActive
                )
            }

            Section("Normal Workday") {
                DatePicker(
                    "Start Time",
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )

                DatePicker(
                    "End Time",
                    selection: $endTime,
                    displayedComponents: .hourAndMinute
                )

                Picker(
                    "Lunch Duration",
                    selection: $employee.lunchDurationMinutes
                ) {
                    ForEach(
                        lunchOptions,
                        id: \.self
                    ) { minutes in
                        Text(lunchLabel(for: minutes))
                            .tag(minutes)
                    }
                }

                LabeledContent("Daily Capacity") {
                    Text(
                        SchedulingCalculator.formattedDuration(
                            minutes: dailyCapacityMinutes
                        )
                    )
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                }
            }

            Section("Working Days") {
                ForEach(Workday.allCases) { day in
                    Toggle(
                        day.name,
                        isOn: workingDayBinding(for: day)
                    )
                }
            }

            Section("Schedule Color") {
                Picker(
                    "Employee Color",
                    selection: $employee.colorName
                ) {
                    ForEach(
                        colorOptions,
                        id: \.self
                    ) { color in
                        HStack {
                            Circle()
                                .fill(displayColor(for: color))
                                .frame(width: 12, height: 12)

                            Text(color.capitalized)
                        }
                        .tag(color)
                    }
                }

                HStack {
                    Text("Calendar Preview")

                    Spacer()

                    Circle()
                        .fill(
                            displayColor(
                                for: employee.colorName
                            )
                        )
                        .frame(width: 18, height: 18)

                    Text(employee.displayName)
                        .fontWeight(.semibold)
                }
            }

            Section {
                if employee.lifecycleStatus == .archived {
                    Button("Restore Employee") {
                        store.restoreEmployee(employee)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(
                        "Archive Employee",
                        role: .destructive
                    ) {
                        store.archiveEmployee(employee)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(employee.displayName)
        .toolbar {
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

            if isInputFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss Keyboard")
                }
            }
        }
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

        employee.defaultStartMinutes =
            minutesFromDate(startTime)

        employee.defaultEndMinutes =
            minutesFromDate(endTime)

        store.updateEmployee(employee)
        dismiss()
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
