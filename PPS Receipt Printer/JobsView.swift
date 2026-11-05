import SwiftUI

enum JobLifecycleListScope {
    case all
    case open
    case closed
}

struct JobRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<JobStatus>?
    let title: String
    let customerNumber: String?
    let lifecycleScope: JobLifecycleListScope
    let jobFilter: ((JobRecord) -> Bool)?
    @State private var showArchived = false
    @State private var showingNewJob = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: JobStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateAscending

    init(
        statuses: Set<JobStatus>? = nil,
        title: String = "All Jobs",
        initialSearchText: String = "",
        customerNumber: String? = nil,
        lifecycleScope: JobLifecycleListScope = .all,
        jobFilter: ((JobRecord) -> Bool)? = nil
    ) {
        self.statuses = statuses
        self.title = title
        self.customerNumber = customerNumber
        self.lifecycleScope = lifecycleScope
        self.jobFilter = jobFilter
        _searchText = State(initialValue: initialSearchText)
    }

    private var filteredJobs: [JobRecord] {
        let lifecycleSource = showArchived ? store.archivedJobs : store.activeJobs
        let source = statuses.map { accepted in
            lifecycleSource.filter { accepted.contains($0.status) }
        } ?? lifecycleSource
        let customFiltered = jobFilter.map { filter in
            source.filter(filter)
        } ?? source
        let lifecycleScoped = customFiltered.filter { job in
            switch lifecycleScope {
            case .all:
                return true
            case .open:
                return !workflowPresentation(for: job).isClosed
                    && job.status != .cancelled
            case .closed:
                return workflowPresentation(for: job).isClosed
            }
        }
        let customerScoped = customerNumber.map { number in
            lifecycleScoped.filter { $0.customerNumber == number }
        } ?? lifecycleScoped
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? customerScoped : customerScoped.filter { job in
            job.jobNumber.localizedCaseInsensitiveContains(query) ||
            job.customerNumber.localizedCaseInsensitiveContains(query) ||
            customerDisplayName(for: job.customerNumber).localizedCaseInsensitiveContains(query) ||
            siteName(for: job.siteID).localizedCaseInsensitiveContains(query) ||
            serviceName(for: job).localizedCaseInsensitiveContains(query) ||
            employeeName(for: job.primaryTechnicianID).localizedCaseInsensitiveContains(query) ||
            job.status.rawValue.localizedCaseInsensitiveContains(query) ||
            workflowPresentation(for: job).statusTitle.localizedCaseInsensitiveContains(query) ||
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
                            HStack(spacing: 8) {
                                Text(customerDisplayName(for: job.customerNumber))
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .lineLimit(1)

                                Spacer(minLength: 6)

                                Image(systemName: jobListStatusSymbol(for: job))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(jobListStatusColor(for: job))
                                .accessibilityLabel(jobListStatusTitle(for: job))
                            }

                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(siteName(for: job.siteID))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                    Text(serviceName(for: job))
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(alignment: .center, spacing: 5) {
                                    Image(systemName: "calendar")

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(
                                            job.scheduledDate.formatted(
                                                date: .abbreviated,
                                                time: .omitted
                                            )
                                        )

                                        Text(
                                            job.scheduledDate.formatted(
                                                date: .omitted,
                                                time: .shortened
                                            )
                                        )
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(jobListStatusColor(for: job))
                            }
                            if job.lifecycleStatus == .archived {
                                Text("Archived").foregroundStyle(.red).font(.caption)
                            }
                        }.padding(.vertical, 2)
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
                        Button("Reset") { selectedStatus = nil; dateFilter = .all; sortOrder = .dateAscending }
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
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateAscending
    }

    private func isScheduledButUnassigned(_ job: JobRecord) -> Bool {
        job.status == .scheduled && job.primaryTechnicianID == nil
    }

    private func jobListStatusTitle(for job: JobRecord) -> String {
        if isScheduledButUnassigned(job) {
            return "Scheduled but unassigned"
        }

        switch job.status {
        case .toBeScheduled, .scheduled, .assigned:
            return job.status.rawValue
        case .inProgress:
            return workflowPresentation(for: job).statusTitle
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func jobListStatusColor(for job: JobRecord) -> Color {
        if isScheduledButUnassigned(job) {
            return .orange
        }

        switch job.status {
        case .toBeScheduled:
            return Color(red: 1, green: 0, blue: 1)
        case .scheduled, .assigned:
            return .blue
        case .inProgress:
            let presentation = workflowPresentation(for: job)
            if presentation.statusTitle == "Invoice Created" {
                return .purple
            }
            if presentation.isClosed {
                return .green
            }
            return .yellow
        case .completed:
            return .green
        case .cancelled:
            return .red
        }
    }

    private func jobListStatusSymbol(for job: JobRecord) -> String {
        if isScheduledButUnassigned(job) {
            return "person.crop.circle.badge.exclamationmark"
        }

        switch job.status {
        case .toBeScheduled:
            return "calendar.badge.clock"
        case .scheduled:
            return "calendar"
        case .assigned:
            return "person.crop.circle.fill"
        case .inProgress:
            return workflowPresentation(for: job).statusSystemImage
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private func workflowPresentation(
        for job: JobRecord
    ) -> JobWorkflowPresentation {
        FieldOperationsEngine().context(
            for: job,
            invoice: store.invoice(for: job),
            assignment: store.assignment(forJobID: job.id)
        ).presentation
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

    private func siteName(for siteID: UUID?) -> String {
        guard let siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "No site selected"
        }

        let name = site.siteName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return name.isEmpty ? "Unnamed Site" : name
    }
}
