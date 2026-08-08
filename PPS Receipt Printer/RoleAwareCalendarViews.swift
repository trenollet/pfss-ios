//
//  RoleAwareCalendarViews.swift
//  PPS Receipt Printer
//
//  Phase 18 – Shared 1, 3, and 5-day Sales and Technician calendars.
//

import SwiftUI

private enum PFSSCalendarSpan: Int, CaseIterable, Identifiable {
    case one = 1
    case three = 3
    case five = 5

    var id: Int { rawValue }
    var title: String { "\(rawValue) Day" }
}

private struct PFSSCalendarDay: Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

struct SalesFollowUpCalendarView: View {
    @EnvironmentObject private var store: AppDataStore

    @State private var selectedDate = Date()
    @State private var span: PFSSCalendarSpan = .one
    @State private var selectedEmployeeID: UUID?
    @State private var isShowingDatePicker = false

    private var salespeople: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.hasRole(.salesperson) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var selectedEmployee: EmployeeRecord? {
        salespeople.first { $0.id == selectedEmployeeID }
    }

    private var days: [PFSSCalendarDay] {
        calendarDays.map { date in
            PFSSCalendarDay(
                date: date,
                count: followUps(on: date).count
            )
        }
    }

    private var calendarDays: [Date] {
        let start = Calendar.current.startOfDay(for: selectedDate)
        return (0..<span.rawValue).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: start)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if store.canManageCompany {
                    employeeSelector(
                        title: "Viewing Follow-Ups For",
                        employees: salespeople,
                        selection: $selectedEmployeeID
                    )
                } else if let selectedEmployee {
                    lockedEmployeeHeader(selectedEmployee)
                }

                calendarControls

                if selectedEmployee == nil {
                    ContentUnavailableView(
                        "No Salesperson Available",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Assign Sales access to an active employee to view follow-ups.")
                    )
                    .padding(.top, 40)
                } else {
                    dayList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sales Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingDatePicker) {
            calendarDatePicker
        }
        .onAppear(perform: repairSelection)
        .onChange(of: store.activeEmployees.map(\.id)) { _, _ in
            repairSelection()
        }
        .onChange(of: store.cloudEmployeeID) { _, _ in
            repairSelection()
        }
    }

    private var calendarControls: some View {
        VStack(spacing: 14) {
            Picker("Calendar Range", selection: $span) {
                ForEach(PFSSCalendarSpan.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            PFSSCalendarDateNavigator(
                selectedDate: $selectedDate,
                isShowingDatePicker: $isShowingDatePicker
            )
        }
    }

    private var dayList: some View {
        VStack(spacing: 12) {
            ForEach(days) { day in
                NavigationLink {
                    SalesFollowUpDayView(
                        date: day.date,
                        employeeID: selectedEmployeeID
                    )
                    .environmentObject(store)
                } label: {
                    PFSSCalendarDayCard(
                        date: day.date,
                        count: day.count,
                        singularName: "Follow-Up",
                        pluralName: "Follow-Ups",
                        accentColor: .blue
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calendarDatePicker: some View {
        NavigationStack {
            DatePicker(
                "Select Day",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Choose a Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func followUps(on date: Date) -> [Lead] {
        guard let employee = selectedEmployee else { return [] }
        return store.activeLeads.filter {
            Calendar.current.isDate($0.followUpDate, inSameDayAs: date)
                && normalized($0.assignedSalesperson) == normalized(employee.displayName)
        }
    }

    private func repairSelection() {
        if store.canManageCompany,
           let selectedEmployeeID,
           salespeople.contains(where: { $0.id == selectedEmployeeID }) {
            return
        }

        if !store.canManageCompany,
           let authenticated = store.authenticatedCloudEmployee,
           authenticated.hasRole(.salesperson),
           salespeople.contains(where: { $0.id == authenticated.id }) {
            selectedEmployeeID = authenticated.id
        } else {
            selectedEmployeeID = salespeople.first?.id
        }
    }
}

struct TechnicianCalendarView: View {
    @EnvironmentObject private var store: AppDataStore

    @State private var selectedDate = Date()
    @State private var span: PFSSCalendarSpan = .one
    @State private var selectedEmployeeID: UUID?
    @State private var isShowingDatePicker = false

    init(initialEmployeeID: UUID? = nil) {
        _selectedEmployeeID = State(initialValue: initialEmployeeID)
    }

    private var technicians: [EmployeeRecord] {
        store.activeEmployees
            .filter {
                $0.hasRole(.technician)
                    || $0.hasRole(.manager)
                    || $0.hasRole(.owner)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var selectedEmployee: EmployeeRecord? {
        technicians.first { $0.id == selectedEmployeeID }
    }

    private var calendarDays: [Date] {
        let start = Calendar.current.startOfDay(for: selectedDate)
        return (0..<span.rawValue).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: start)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if store.canManageCompany {
                    employeeSelector(
                        title: "Viewing Jobs For",
                        employees: technicians,
                        selection: $selectedEmployeeID
                    )
                } else if let selectedEmployee {
                    lockedEmployeeHeader(selectedEmployee)
                }

                VStack(spacing: 14) {
                    Picker("Calendar Range", selection: $span) {
                        ForEach(PFSSCalendarSpan.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    PFSSCalendarDateNavigator(
                        selectedDate: $selectedDate,
                        isShowingDatePicker: $isShowingDatePicker
                    )
                }

                if let employee = selectedEmployee {
                    VStack(spacing: 12) {
                        ForEach(calendarDays, id: \.self) { date in
                            let jobs = jobs(for: employee, on: date)
                            NavigationLink {
                                TechnicianJobsDayView(
                                    date: date,
                                    employeeID: employee.id
                                )
                                .environmentObject(store)
                            } label: {
                                PFSSCalendarDayCard(
                                    date: date,
                                    count: jobs.count,
                                    singularName: "Job",
                                    pluralName: "Jobs",
                                    accentColor: .orange
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Technician Available",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Assign Technician access to an active employee to view scheduled jobs.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Job Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Day",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose a Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear(perform: repairSelection)
        .onChange(of: store.activeEmployees.map(\.id)) { _, _ in
            repairSelection()
        }
        .onChange(of: store.cloudEmployeeID) { _, _ in
            repairSelection()
        }
    }

    private func jobs(for employee: EmployeeRecord, on date: Date) -> [JobRecord] {
        SchedulingEngine.dailyAgenda(
            for: employee,
            on: date,
            from: store.jobs
        ).jobs
    }

    private func repairSelection() {
        if store.canManageCompany,
           let selectedEmployeeID,
           technicians.contains(where: { $0.id == selectedEmployeeID }) {
            return
        }

        if !store.canManageCompany,
           let authenticated = store.authenticatedCloudEmployee,
           technicians.contains(where: { $0.id == authenticated.id }) {
            selectedEmployeeID = authenticated.id
        } else if selectedEmployeeID == nil
                    || !technicians.contains(where: { $0.id == selectedEmployeeID }) {
            selectedEmployeeID = technicians.first?.id
        }
    }
}

private struct SalesFollowUpDayView: View {
    @EnvironmentObject private var store: AppDataStore
    let date: Date
    let employeeID: UUID?

    private var employee: EmployeeRecord? {
        store.activeEmployees.first { $0.id == employeeID }
    }

    private var leads: [Lead] {
        guard let employee else { return [] }
        return store.activeLeads.filter {
            Calendar.current.isDate($0.followUpDate, inSameDayAs: date)
                && normalized($0.assignedSalesperson) == normalized(employee.displayName)
        }
        .sorted { $0.followUpDate < $1.followUpDate }
    }

    var body: some View {
        List {
            Section(employee?.displayName ?? "Salesperson") {
                if leads.isEmpty {
                    ContentUnavailableView(
                        "No Follow-Ups",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("No sales follow-ups are scheduled for this day.")
                    )
                } else {
                    ForEach(leads) { lead in
                        NavigationLink {
                            LeadDetailView(lead: lead)
                                .environmentObject(store)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(lead.businessName.isEmpty ? lead.contactName : lead.businessName)
                                    .font(.headline)
                                Text(lead.contactName)
                                    .foregroundStyle(.secondary)
                                Label(lead.status.rawValue, systemImage: "flag.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TechnicianJobsDayView: View {
    @EnvironmentObject private var store: AppDataStore
    let date: Date
    let employeeID: UUID

    private var employee: EmployeeRecord? {
        store.activeEmployees.first { $0.id == employeeID }
    }

    private var jobs: [JobRecord] {
        guard let employee else { return [] }
        return SchedulingEngine.dailyAgenda(
            for: employee,
            on: date,
            from: store.jobs
        ).jobs.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        List {
            Section(employee?.displayName ?? "Technician") {
                if jobs.isEmpty {
                    ContentUnavailableView(
                        "No Jobs",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("No jobs are scheduled for this day.")
                    )
                } else {
                    ForEach(jobs) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                                .environmentObject(store)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(jobTitle(job))
                                        .font(.headline)
                                    Spacer()
                                    Text(job.scheduledDate.formatted(date: .omitted, time: .shortened))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                Text(serviceName(job))
                                    .foregroundStyle(.secondary)
                                Label(job.status.rawValue, systemImage: "wrench.and.screwdriver.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func jobTitle(_ job: JobRecord) -> String {
        let customer = store.customers.first { $0.customerNumber == job.customerNumber }
        guard let customer else { return job.jobNumber }
        return customer.businessName.isEmpty ? customer.contactName : customer.businessName
    }

    private func serviceName(_ job: JobRecord) -> String {
        job.serviceType == .other && !job.otherService.isEmpty
            ? job.otherService
            : job.serviceType.rawValue
    }
}

private struct PFSSCalendarDateNavigator: View {
    @Binding var selectedDate: Date
    @Binding var isShowingDatePicker: Bool

    var body: some View {
        VStack(spacing: 10) {
            Button {
                isShowingDatePicker = true
            } label: {
                Label(
                    selectedDate.formatted(date: .complete, time: .omitted),
                    systemImage: "calendar"
                )
                .font(.headline)
            }
            .buttonStyle(.plain)

            HStack {
                Button { changeDate(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.bordered)

                Spacer()

                if Calendar.current.isDateInToday(selectedDate) {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Return to Today") { selectedDate = Date() }
                        .font(.subheadline)
                }

                Spacer()

                Button { changeDate(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func changeDate(by offset: Int) {
        selectedDate = Calendar.current.date(
            byAdding: .day,
            value: offset,
            to: selectedDate
        ) ?? selectedDate
    }
}

private struct PFSSCalendarDayCard: View {
    let date: Date
    let count: Int
    let singularName: String
    let pluralName: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.title.bold())
                    .foregroundStyle(accentColor)
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.headline)
                Text("\(count) \(count == 1 ? singularName : pluralName)")
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accentColor.opacity(0.18))
        }
    }
}

private func employeeSelector(
    title: String,
    employees: [EmployeeRecord],
    selection: Binding<UUID?>
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Picker("Employee", selection: selection) {
            Text("Select Employee").tag(UUID?.none)
            ForEach(employees) { employee in
                Text(employee.displayName).tag(Optional(employee.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
}

private func lockedEmployeeHeader(_ employee: EmployeeRecord) -> some View {
    HStack {
        Label(employee.displayName, systemImage: "person.crop.circle.fill")
            .font(.headline)
        Spacer()
        Text("My Calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
}

private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
    )
}
