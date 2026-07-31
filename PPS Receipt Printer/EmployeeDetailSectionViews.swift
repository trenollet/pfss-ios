import SwiftUI

struct EmployeeIdentityEditorView: View {
    @Binding var employee: EmployeeRecord
    var allowsRoleEditing = true
    @State private var showingRoles = false

    private let colors = ["blue", "green", "orange", "purple", "red", "yellow", "gray"]

    var body: some View {
        Form {
            Section("Contact") {
                TextField("First Name", text: $employee.firstName)
                    .textContentType(.givenName)
                TextField("Last Name", text: $employee.lastName)
                    .textContentType(.familyName)
                TextField("Phone", text: $employee.phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $employee.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Access and Display") {
                if allowsRoleEditing {
                    Button { showingRoles = true } label: {
                        LabeledContent("Roles", value: employee.roleDisplayText)
                    }
                    .foregroundStyle(.primary)
                } else {
                    LabeledContent("Roles", value: employee.roleDisplayText)
                    Text("Only a Manager or Owner can change employee roles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Active Employee", isOn: $employee.isActive)
                Picker("Schedule Color", selection: $employee.colorName) {
                    ForEach(colors, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
        }
        .navigationTitle("Employee")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRoles) {
            EmployeeRoleSelectionView(selectedRoles: $employee.roles)
        }
    }
}

struct EmployeeBaseAddressEditorView: View {
    @Binding var baseAddress: String

    var body: some View {
        Form {
            Section {
                TextField("Street, City, State ZIP", text: $baseAddress, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(3...6)
            } footer: {
                Text("Used as the route starting point when a current or previous-stop location is unavailable.")
            }
        }
        .navigationTitle("Home / Base Address")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EmployeeWorkingDaysEditorView: View {
    @Binding var workingDays: Set<Workday>

    var body: some View {
        Form {
            Section("Regular Working Days") {
                ForEach(Workday.allCases) { day in
                    Toggle(day.name, isOn: Binding(
                        get: { workingDays.contains(day) },
                        set: { enabled in
                            if enabled { workingDays.insert(day) }
                            else { workingDays.remove(day) }
                        }
                    ))
                }
            }
        }
        .navigationTitle("Working Days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EmployeeNormalWorkdayEditorView: View {
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var lunchMinutes: Int

    var body: some View {
        Form {
            Section("Normal Work Day") {
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                Picker("Lunch Duration", selection: $lunchMinutes) {
                    ForEach([0, 15, 30, 45, 60], id: \.self) { minutes in
                        Text(minutes == 0 ? "No Lunch" : "\(minutes) minutes").tag(minutes)
                    }
                }
                LabeledContent("Daily Capacity") {
                    Text(SchedulingCalculator.formattedDuration(minutes: capacityMinutes))
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }
            }
        }
        .navigationTitle("Normal Work Day")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var capacityMinutes: Int {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: startTime)
        let end = calendar.dateComponents([.hour, .minute], from: endTime)
        let startMinutes = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        let endMinutes = (end.hour ?? 0) * 60 + (end.minute ?? 0)
        return max(endMinutes - startMinutes - lunchMinutes, 0)
    }
}

struct EmployeeTimeOffView: View {
    @Binding var exceptions: [WorkforceAvailabilityException]
    let employeeName: String
    @State private var draft: WorkforceAvailabilityException?

    private var timeOff: [WorkforceAvailabilityException] {
        exceptions.filter { $0.kind == .unavailable }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        List {
            if timeOff.isEmpty {
                ContentUnavailableView(
                    "No Time Off Scheduled",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Add vacations, appointments, or other unavailable periods for \(employeeName).")
                )
            } else {
                ForEach(timeOff) { item in
                    Button { draft = item } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.reason.isEmpty ? "Time Off" : item.reason)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(timeRange(item))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Time Off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { draft = newTimeOff() } label: {
                    Label("Add Time Off", systemImage: "plus")
                }
            }
        }
        .sheet(item: $draft) { value in
            NavigationStack {
                EmployeeTimeOffEditorView(exception: value) { saved in
                    if let index = exceptions.firstIndex(where: { $0.id == saved.id }) {
                        exceptions[index] = saved
                    } else {
                        exceptions.append(saved)
                    }
                    draft = nil
                }
            }
        }
    }

    private func newTimeOff() -> WorkforceAvailabilityException {
        let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        return WorkforceAvailabilityException(
            kind: .unavailable,
            startDate: start,
            endDate: start.addingTimeInterval(60 * 60),
            reason: ""
        )
    }

    private func delete(at offsets: IndexSet) {
        let ids = Set(offsets.map { timeOff[$0].id })
        exceptions.removeAll { ids.contains($0.id) }
    }

    private func timeRange(_ item: WorkforceAvailabilityException) -> String {
        "\(item.startDate.formatted(date: .abbreviated, time: .shortened)) – \(item.endDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct EmployeeTimeOffEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var exception: WorkforceAvailabilityException
    let onSave: (WorkforceAvailabilityException) -> Void

    var body: some View {
        Form {
            Section("Time Off") {
                TextField("Reason (Vacation, appointment, etc.)", text: $exception.reason)
                DatePicker("Starts", selection: $exception.startDate)
                DatePicker("Ends", selection: $exception.endDate, in: exception.startDate...)
            }
        }
        .navigationTitle("Schedule Time Off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { exception.kind = .unavailable; onSave(exception); dismiss() }
            }
        }
    }
}
