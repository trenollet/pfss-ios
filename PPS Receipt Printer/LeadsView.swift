import SwiftUI

struct LeadsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var showArchived = false
    @State private var showingNewLead = false
    @State private var searchText = ""

    private var filteredLeads: [Lead] {
        let source = showArchived ? store.archivedLeads : store.activeLeads
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }

        return source.filter {
            $0.leadNumber.localizedCaseInsensitiveContains(query) ||
            $0.businessName.localizedCaseInsensitiveContains(query) ||
            $0.contactName.localizedCaseInsensitiveContains(query) ||
            $0.phone.localizedCaseInsensitiveContains(query) ||
            $0.email.localizedCaseInsensitiveContains(query) ||
            $0.status.rawValue.localizedCaseInsensitiveContains(query) ||
            serviceName(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add New Lead") { showingNewLead = true }
                    Toggle("Show Archived", isOn: $showArchived)
                }
                Section("Leads") {
                    ForEach(filteredLeads) { lead in
                        NavigationLink { LeadDetailView(lead: lead) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(displayName(for: lead)).font(.headline)
                                Text("Lead #: \(lead.leadNumber)").font(.caption)
                                Text("Service: \(serviceName(for: lead))").font(.caption)
                                Text("Value: \(lead.estimatedValue, format: .currency(code: "USD"))").font(.caption)
                                Text("Status: \(lead.status.rawValue)").font(.caption)
                                if lead.lifecycleStatus == .archived {
                                    Text("Archived").foregroundStyle(.red).font(.caption)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Leads")
            .searchable(text: $searchText, prompt: "Search leads")
            .sheet(isPresented: $showingNewLead) {
                LeadNewView().environmentObject(store)
            }
        }
    }

    private func displayName(for lead: Lead) -> String {
        if !lead.businessName.isEmpty { return lead.businessName }
        if !lead.contactName.isEmpty { return lead.contactName }
        return "Unnamed Lead"
    }

    private func serviceName(for lead: Lead) -> String {
        lead.serviceRequested == .other
            ? (lead.otherService.isEmpty ? "Other" : lead.otherService)
            : lead.serviceRequested.rawValue
    }
}
