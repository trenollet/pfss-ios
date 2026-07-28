import SwiftUI

struct CustomerRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<EstimateStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewCustomer = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: EstimateStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateDescending

    init(
        statuses: Set<EstimateStatus>? = nil,
        title: String = "All Customers",
        initialSearchText: String = ""
    ) {
        self.statuses = statuses
        self.title = title
        _searchText = State(initialValue: initialSearchText)
    }

    private var filteredCustomers: [Customer] {
        let lifecycleSource = showArchived ? store.archivedCustomers : store.activeCustomers
        let source = statuses.map { accepted in
            lifecycleSource.filter { accepted.contains($0.estimateStatus) }
        } ?? lifecycleSource
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? source : source.filter {
            $0.customerNumber.localizedCaseInsensitiveContains(query) ||
            $0.businessName.localizedCaseInsensitiveContains(query) ||
            $0.contactName.localizedCaseInsensitiveContains(query) ||
            $0.phone.localizedCaseInsensitiveContains(query) ||
            $0.email.localizedCaseInsensitiveContains(query) ||
            $0.estimateStatus.rawValue.localizedCaseInsensitiveContains(query)
        }
        let statusFiltered = selectedStatus.map { status in
            searched.filter { $0.estimateStatus == status }
        } ?? searched
        let dateFiltered = statusFiltered.filter {
            dateFilter.includes($0.followUpDate)
        }
        return dateFiltered.sorted { first, second in
            switch sortOrder {
            case .dateAscending: return first.followUpDate < second.followUpDate
            case .dateDescending: return first.followUpDate > second.followUpDate
            case .nameAscending:
                return customerName(first).localizedCaseInsensitiveCompare(
                    customerName(second)
                ) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button("Add New Customer") { showingNewCustomer = true }
                Toggle("Show Archived", isOn: $showArchived)
            }
            Section("Customers") {
                ForEach(filteredCustomers) { customer in
                    NavigationLink { CustomerDetailView(customer: customer) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(customer.businessName.isEmpty ? customer.contactName : customer.businessName).font(.headline)
                            Text("Contact: \(customer.contactName)").font(.caption)
                            Text("Status: \(customer.estimateStatus.rawValue)").font(.caption)
                            if customer.lifecycleStatus == .archived {
                                Text("Archived").foregroundStyle(.red).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if customer.lifecycleStatus != .archived {
                            Button(role: .destructive) {
                                store.archiveCustomer(customer)
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
        .searchable(text: $searchText, prompt: "Search customers")
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
                        Text("All Statuses").tag(EstimateStatus?.none)
                        ForEach(EstimateStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Order", selection: $sortOrder) {
                        ForEach(RecordListSortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .navigationTitle("Filter Customers")
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
        .sheet(isPresented: $showingNewCustomer) {
            CustomerNewView().environmentObject(store)
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateDescending
    }

    private func customerName(_ customer: Customer) -> String {
        customer.businessName.isEmpty ? customer.contactName : customer.businessName
    }
}
