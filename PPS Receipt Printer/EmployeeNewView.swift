//
//  EmployeeNewView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/14/26.
//

import SwiftUI

struct EmployeeNewView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""

    @State private var role: EmployeeRole = .technician

    @State private var startTime =
        EmployeeNewView.dateFromMinutes(480)

    @State private var endTime =
        EmployeeNewView.dateFromMinutes(1020)

    @State private var lunchDurationMinutes = 30

    @State private var workingDays =
        Workday.standardWorkweek

    @State private var colorName = "blue"
    @State private var isActive = true

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

    private var dailyCapacityMinutes: Int {
        let startMinutes = minutesFromDate(startTime)
        let endMinutes = minutesFromDate(endTime)

        return max(
            endMinutes -
            startMinutes -
            lunchDurationMinutes,
            0
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    TextField(
                        "First Name",
                        text: $firstName
                    )
                    .textContentType(.givenName)
                    .focused($isInputFocused)

                    TextField(
                        "Last Name",
                        text: $lastName
                    )
                    .textContentType(.familyName)
                    .focused($isInputFocused)

                    TextField(
                        "Phone",
                        text: $phone
                    )
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($isInputFocused)

                    TextField(
                        "Email",
                        text: $email
                    )
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isInputFocused)

                    Picker(
                        "Role",
                        selection: $role
                    ) {
                        ForEach(EmployeeRole.allCases) { role in
                            Text(role.rawValue)
                                .tag(role)
                        }
                    }

                    Toggle(
                        "Active Employee",
                        isOn: $isActive
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
                        selection: $lunchDurationMinutes
                    ) {
                        ForEach(
                            lunchOptions,
                            id: \.self
                        ) { minutes in
                            Text(
                                SchedulingCalculator
                                    .formattedDuration(
                                        minutes: minutes
                                    )
                            )
                            .tag(minutes)
                        }
                    }

                    LabeledContent("Daily Capacity") {
                        Text(
                            SchedulingCalculator
                                .formattedDuration(
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
                        selection: $colorName
                    ) {
                        ForEach(
                            colorOptions,
                            id: \.self
                        ) { color in
                            Text(color.capitalized)
                                .tag(color)
                        }
                    }
                }

            }
            .navigationTitle("New Employee")
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEmployee()
                    }
                    .disabled(
                        firstName
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
    }

    private func workingDayBinding(
        for day: Workday
    ) -> Binding<Bool> {
        Binding(
            get: {
                workingDays.contains(day)
            },
            set: { isWorking in
                if isWorking {
                    workingDays.insert(day)
                } else {
                    workingDays.remove(day)
                }
            }
        )
    }

    private func saveEmployee() {
        let employee = EmployeeRecord(
            firstName: firstName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            lastName: lastName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            phone: phone.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            email: email.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            role: role,
            defaultStartMinutes:
                minutesFromDate(startTime),
            defaultEndMinutes:
                minutesFromDate(endTime),
            lunchDurationMinutes:
                lunchDurationMinutes,
            workingDays: workingDays,
            colorName: colorName,
            isActive: isActive,
            lifecycleStatus: .active
        )

        store.addEmployee(employee)
        dismiss()
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
}
