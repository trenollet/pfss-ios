import SwiftUI

struct JobRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<JobStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewJob = false
    @State private var searchText: String

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
        guard !query.isEmpty else { return source }

        return source.filter { job in
            job.jobNumber.localizedCaseInsensitiveContains(query) ||
            job.customerNumber.localizedCaseInsensitiveContains(query) ||
            customerDisplayName(for: job.customerNumber).localizedCaseInsensitiveContains(query) ||
            siteDisplayName(for: job.siteID).localizedCaseInsensitiveContains(query) ||
            serviceName(for: job).localizedCaseInsensitiveContains(query) ||
            employeeName(for: job.primaryTechnicianID).localizedCaseInsensitiveContains(query) ||
            job.status.rawValue.localizedCaseInsensitiveContains(query) ||
            job.workNotes.localizedCaseInsensitiveContains(query)
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
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("Job: \(job.jobNumber)").font(.caption)
                            Text("Site: \(siteDisplayName(for: job.siteID))").font(.caption)
                            Text("Service: \(serviceName(for: job))").font(.caption)
                            Text("Primary Tech: \(employeeName(for: job.primaryTechnicianID))").font(.caption)
                            Text("Status: \(job.status.rawValue)").font(.caption)
                            if job.lifecycleStatus == .archived {
                                Text("Archived").foregroundStyle(.red).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search jobs")
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobNewView().environmentObject(store)
            }
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
