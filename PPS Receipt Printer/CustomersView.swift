import SwiftUI

struct CustomerRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<EstimateStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewCustomer = false
    @State private var searchText: String

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
        guard !query.isEmpty else { return source }

        return source.filter {
            $0.customerNumber.localizedCaseInsensitiveContains(query) ||
            $0.businessName.localizedCaseInsensitiveContains(query) ||
            $0.contactName.localizedCaseInsensitiveContains(query) ||
            $0.phone.localizedCaseInsensitiveContains(query) ||
            $0.email.localizedCaseInsensitiveContains(query) ||
            $0.estimateStatus.rawValue.localizedCaseInsensitiveContains(query)
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
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search customers")
        .sheet(isPresented: $showingNewCustomer) {
            CustomerNewView().environmentObject(store)
        }
    }
}
