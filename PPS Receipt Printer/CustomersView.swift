import SwiftUI

struct CustomersView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var showArchived = false
    @State private var showingNewCustomer = false
    @State private var searchText = ""

    private var filteredCustomers: [Customer] {
        let source = showArchived ? store.archivedCustomers : store.activeCustomers
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
        .navigationTitle("Customers")
        .searchable(text: $searchText, prompt: "Search customers")
        .sheet(isPresented: $showingNewCustomer) {
            CustomerNewView().environmentObject(store)
        }
    }
}
