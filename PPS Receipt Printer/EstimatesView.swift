import SwiftUI

struct EstimateRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<EstimateRecordStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewEstimate = false
    @State private var searchText: String

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
        guard !query.isEmpty else { return source }

        return source.filter { estimate in
            estimate.estimateNumber.localizedCaseInsensitiveContains(query) ||
            estimate.customerNumber.localizedCaseInsensitiveContains(query) ||
            customerDisplayName(for: estimate.customerNumber).localizedCaseInsensitiveContains(query) ||
            siteDisplayName(for: estimate.siteID).localizedCaseInsensitiveContains(query) ||
            estimate.status.rawValue.localizedCaseInsensitiveContains(query) ||
            estimate.salesperson.localizedCaseInsensitiveContains(query) ||
            estimate.serviceDetails.localizedCaseInsensitiveContains(query)
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
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search estimates")
        .sheet(isPresented: $showingNewEstimate) {
            NavigationStack {
                EstimateNewView().environmentObject(store)
            }
        }
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
