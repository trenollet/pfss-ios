import SwiftUI

struct SitesView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var showArchived = false
    @State private var showingNewSite = false
    @State private var searchText = ""

    private var filteredSites: [CustomerSite] {
        let source = showArchived ? store.archivedSites : store.activeSites
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }

        return source.filter {
            $0.siteName.localizedCaseInsensitiveContains(query) ||
            $0.serviceAddress.localizedCaseInsensitiveContains(query) ||
            $0.customerNumber.localizedCaseInsensitiveContains(query) ||
            $0.propertyType.localizedCaseInsensitiveContains(query) ||
            $0.accessNotes.localizedCaseInsensitiveContains(query) ||
            $0.workNotes.localizedCaseInsensitiveContains(query)
        }
    }

    private func customerDisplayName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return "Customer Not Found"
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return "Unnamed Customer"
    }

    var body: some View {
        List {
            Section {
                Button("Add New Site") { showingNewSite = true }
                Toggle("Show Archived", isOn: $showArchived)
            }
            Section("Sites") {
                ForEach(filteredSites) { site in
                    NavigationLink { SiteDetailView(site: site) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.siteName.isEmpty ? site.serviceAddress : site.siteName).font(.headline)
                            Text(site.serviceAddress).font(.caption)
                            Text("Customer: \(customerDisplayName(for: site.customerNumber))")
                                .font(.caption)
                            if !site.propertyType.isEmpty {
                                Text("Property: \(site.propertyType)").font(.caption)
                            }
                            if site.lifecycleStatus == .archived {
                                Text("Archived").foregroundStyle(.red).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Sites")
        .searchable(text: $searchText, prompt: "Search sites")
        .sheet(isPresented: $showingNewSite) {
            NavigationStack {
                SiteNewView()
            }
            .environmentObject(store)
        }
    }
}
