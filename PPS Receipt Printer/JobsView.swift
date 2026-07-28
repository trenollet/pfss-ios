import SwiftUI

struct JobRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<JobStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewJob = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: JobStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateDescending

    init(
        statuses: Set<JobStatus>? = nil,
        title: String = "All Jobs",
        initialSearchText: String = ""
    ) {
        self.statuses = statuses
        self.title = title
        _searchText = State(initialValue: initialSearchText)
    }

    private var filteredJobs: [JobRecord] {
        let lifecycleSource = showArchived ? store.archivedJobs : store.activeJobs
        let source = statuses.map { accepted in
            lifecycleSource.filter { accepted.contains($0.status) }
        } ?? lifecycleSource
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? source : source.filter { job in
            job.jobNumber.localizedCaseInsensitiveContains(query) ||
            job.customerNumber.localizedCaseInsensitiveContains(query) ||
            customerDisplayName(for: job.customerNumber).localizedCaseInsensitiveContains(query) ||
            siteDisplayName(for: job.siteID).localizedCaseInsensitiveContains(query) ||
            serviceName(for: job).localizedCaseInsensitiveContains(query) ||
            employeeName(for: job.primaryTechnicianID).localizedCaseInsensitiveContains(query) ||
            job.status.rawValue.localizedCaseInsensitiveContains(query) ||
            job.workNotes.localizedCaseInsensitiveContains(query)
        }
        let statusFiltered = selectedStatus.map { status in
            searched.filter { $0.status == status }
        } ?? searched
        let dateFiltered = statusFiltered.filter {
            dateFilter.includes($0.scheduledDate)
        }
        return dateFiltered.sorted { first, second in
            switch sortOrder {
            case .dateAscending: return first.scheduledDate < second.scheduledDate
            case .dateDescending: return first.scheduledDate > second.scheduledDate
            case .nameAscending:
                return customerDisplayName(for: first.customerNumber)
                    .localizedCaseInsensitiveCompare(customerDisplayName(for: second.customerNumber)) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button("Add New Job") { showingNewJob = true }
                Toggle("Show Archived", isOn: $showArchived)
            }
            Section("Jobs") {
                ForEach(filteredJobs) { job in
                    NavigationLink { JobDetailView(job: job) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(customerDisplayName(for: job.customerNumber))
                                .font(.title3)
                                .fontWeight(.bold)
                            Label(
                                siteDisplayName(for: job.siteID),
                                systemImage: "mappin.circle.fill"
                            )
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            Text("Job: \(job.jobNumber)").font(.caption)
                            Text("Service: \(serviceName(for: job))").font(.caption)
                            Text("Primary Tech: \(employeeName(for: job.primaryTechnicianID))").font(.caption)
                            HStack {
                                Label(jobListStatusTitle(for: job), systemImage: jobListStatusSymbol(for: job))
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(jobListStatusColor(for: job))
                                Spacer()
                                Label(
                                    job.scheduledDate.formatted(date: .abbreviated, time: .shortened),
                                    systemImage: "calendar"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(listDateColor)
                            }
                            if job.lifecycleStatus == .archived {
                                Text("Archived").foregroundStyle(.red).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if job.lifecycleStatus != .archived {
                            Button(role: .destructive) {
                                store.archiveJob(job)
                            } label: {
                                Label("Archive", systemImage: "archivebox.fill")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search jobs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingFilters = true } label: {
                    Label("Filter", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                Form {
                    Picker("Date", selection: $dateFilter) {
                        ForEach(RecordDateFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Status", selection: $selectedStatus) {
                        Text("All Statuses").tag(JobStatus?.none)
                        ForEach(JobStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Order", selection: $sortOrder) {
                        ForEach(RecordListSortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .navigationTitle("Filter Jobs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { selectedStatus = nil; dateFilter = .all; sortOrder = .dateDescending }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } }
                }
            }
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobNewView().environmentObject(store)
            }
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateDescending
    }

    private var listDateColor: Color {
        Color(red: 0.20, green: 0.95, blue: 0.42)
    }

    private func jobListStatusTitle(for job: JobRecord) -> String {
        job.primaryTechnicianID == nil && job.status != .completed && job.status != .cancelled
            ? "Unassigned" : job.status.rawValue
    }

    private func jobListStatusColor(for job: JobRecord) -> Color {
        if job.primaryTechnicianID == nil && job.status != .completed && job.status != .cancelled { return .red }
        switch job.status {
        case .completed: return .green
        case .scheduled, .assigned: return .blue
        case .inProgress: return .orange
        case .toBeScheduled: return .red
        case .cancelled: return .secondary
        }
    }

    private func jobListStatusSymbol(for job: JobRecord) -> String {
        if job.primaryTechnicianID == nil && job.status != .completed && job.status != .cancelled { return "person.crop.circle.badge.exclamationmark" }
        switch job.status {
        case .completed: return "checkmark.circle.fill"
        case .scheduled, .assigned: return "calendar.circle.fill"
        case .inProgress: return "wrench.and.screwdriver.fill"
        case .toBeScheduled: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private func serviceName(for job: JobRecord) -> String {
        job.serviceType == .other
            ? (job.otherService.isEmpty ? "Other" : job.otherService)
            : job.serviceType.rawValue
    }

    private func customerDisplayName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: { $0.customerNumber == customerNumber }) else {
            return customerNumber
        }
        if !customer.businessName.isEmpty { return customer.businessName }
        if !customer.contactName.isEmpty { return customer.contactName }
        return customerNumber
    }

    private func employeeName(for employeeID: UUID?) -> String {
        guard let employeeID,
              let employee = store.employees.first(where: { $0.id == employeeID }) else {
            return "Unassigned"
        }
        return employee.displayName
    }

    private func siteDisplayName(for siteID: UUID?) -> String {
        guard let siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "No site selected"
        }

        if site.siteName.isEmpty { return site.serviceAddress }
        if site.serviceAddress.isEmpty { return site.siteName }
        return "\(site.siteName) — \(site.serviceAddress)"
    }
}
