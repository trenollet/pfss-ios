import SwiftUI

struct EstimateRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<EstimateRecordStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewEstimate = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: EstimateRecordStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateDescending

    init(
        statuses: Set<EstimateRecordStatus>? = nil,
        title: String = "All Estimates",
        initialSearchText: String = ""
    ) {
        self.statuses = statuses
        self.title = title
        _searchText = State(initialValue: initialSearchText)
    }

    private var filteredEstimates: [EstimateRecord] {
        let lifecycleSource = showArchived ? store.archivedEstimates : store.activeEstimates
        let source = statuses.map { accepted in
            lifecycleSource.filter { accepted.contains($0.status) }
        } ?? lifecycleSource
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? source : source.filter { estimate in
            estimate.estimateNumber.localizedCaseInsensitiveContains(query) ||
            estimate.customerNumber.localizedCaseInsensitiveContains(query) ||
            customerDisplayName(for: estimate.customerNumber).localizedCaseInsensitiveContains(query) ||
            siteDisplayName(for: estimate.siteID).localizedCaseInsensitiveContains(query) ||
            estimate.status.rawValue.localizedCaseInsensitiveContains(query) ||
            estimate.salesperson.localizedCaseInsensitiveContains(query) ||
            estimate.serviceDetails.localizedCaseInsensitiveContains(query)
        }
        let statusFiltered = selectedStatus.map { status in
            searched.filter { $0.status == status }
        } ?? searched
        let dateFiltered = statusFiltered.filter {
            dateFilter.includes($0.createdDate)
        }
        return dateFiltered.sorted { first, second in
            switch sortOrder {
            case .dateAscending: return first.createdDate < second.createdDate
            case .dateDescending: return first.createdDate > second.createdDate
            case .nameAscending:
                return customerDisplayName(for: first.customerNumber)
                    .localizedCaseInsensitiveCompare(
                        customerDisplayName(for: second.customerNumber)
                    ) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button("Add New Estimate") { showingNewEstimate = true }
                Toggle("Show Archived", isOn: $showArchived)
            }
            Section("Estimates") {
                ForEach(filteredEstimates) { estimate in
                    NavigationLink { EstimateDetailView(estimate: estimate) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(customerDisplayName(for: estimate.customerNumber))
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("Estimate: \(estimate.estimateNumber)").font(.caption)
                            Text("Site: \(siteDisplayName(for: estimate.siteID))").font(.caption)
                            Text("Total: \(estimate.total, format: .currency(code: "USD"))").font(.caption)
                            Text("Status: \(estimate.status.rawValue)").font(.caption)
                            Text("Sales Rep: \(estimate.salesperson.isEmpty ? "Unassigned" : estimate.salesperson)")
                                .font(.caption)
                            if estimate.lifecycleStatus == .archived {
                                Text("Archived").foregroundStyle(.red).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if estimate.lifecycleStatus != .archived {
                            Button(role: .destructive) {
                                store.archiveEstimate(estimate)
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
        .searchable(text: $searchText, prompt: "Search estimates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingFilters = true } label: {
                    Label(
                        "Filter",
                        systemImage: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
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
                        Text("All Statuses").tag(EstimateRecordStatus?.none)
                        ForEach(EstimateRecordStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Order", selection: $sortOrder) {
                        ForEach(RecordListSortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .navigationTitle("Filter Estimates")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") {
                            selectedStatus = nil
                            dateFilter = .all
                            sortOrder = .dateDescending
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingFilters = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewEstimate) {
            NavigationStack {
                EstimateNewView().environmentObject(store)
            }
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateDescending
    }

    private func customerDisplayName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: { $0.customerNumber == customerNumber }) else {
            return customerNumber
        }
        if !customer.businessName.isEmpty { return customer.businessName }
        if !customer.contactName.isEmpty { return customer.contactName }
        return customerNumber
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
