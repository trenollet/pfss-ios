import SwiftUI

struct LeadRecordsListView: View {
    @EnvironmentObject private var store: AppDataStore
    let statuses: Set<LeadStatus>?
    let title: String
    @State private var showArchived = false
    @State private var showingNewLead = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: LeadStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateAscending

    init(
        statuses: Set<LeadStatus>? = nil,
        title: String = "All Leads",
        initialSearchText: String = ""
    ) {
        self.statuses = statuses
        self.title = title
        _searchText = State(initialValue: initialSearchText)
    }

    private var filteredLeads: [Lead] {
        let lifecycleSource = showArchived ? store.archivedLeads : store.activeLeads
        let source = statuses.map { accepted in
            lifecycleSource.filter { accepted.contains($0.status) }
        } ?? lifecycleSource
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? source : source.filter {
            $0.leadNumber.localizedCaseInsensitiveContains(query) ||
            $0.businessName.localizedCaseInsensitiveContains(query) ||
            $0.contactName.localizedCaseInsensitiveContains(query) ||
            $0.phone.localizedCaseInsensitiveContains(query) ||
            $0.email.localizedCaseInsensitiveContains(query) ||
            $0.status.rawValue.localizedCaseInsensitiveContains(query) ||
            serviceName(for: $0).localizedCaseInsensitiveContains(query)
        }
        let statusFiltered = selectedStatus.map { status in searched.filter { $0.status == status } } ?? searched
        let dateFiltered = statusFiltered.filter { dateFilter.includes($0.followUpDate) }
        return dateFiltered.sorted { first, second in
            switch sortOrder {
            case .dateAscending: return first.followUpDate < second.followUpDate
            case .dateDescending: return first.followUpDate > second.followUpDate
            case .nameAscending:
                return displayName(for: first).localizedCaseInsensitiveCompare(displayName(for: second)) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
                Section {
                    Button("Add New Lead") { showingNewLead = true }
                    Toggle("Show Archived", isOn: $showArchived)
                }
                Section("Leads") {
                    ForEach(filteredLeads) { lead in
                        NavigationLink { LeadDetailView(lead: lead) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(displayName(for: lead))
                                    .font(.title3.weight(.bold))
                                Text("Lead #: \(lead.leadNumber)").font(.caption)
                                Text("Service: \(serviceName(for: lead))").font(.caption)
                                Text("Value: \(lead.estimatedValue, format: .currency(code: "USD"))").font(.caption)
                                HStack {
                                    Label(lead.status.rawValue, systemImage: leadStatusSymbol(lead.status))
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(leadStatusColor(lead.status))
                                    Spacer()
                                    Label(
                                        lead.followUpDate.formatted(date: .abbreviated, time: .shortened),
                                        systemImage: "calendar"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(listDateColor)
                                }
                                if lead.lifecycleStatus == .archived {
                                    Text("Archived").foregroundStyle(.red).font(.caption)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search leads")
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
                    Picker("Follow-up Date", selection: $dateFilter) {
                        ForEach(RecordDateFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Status", selection: $selectedStatus) {
                        Text("All Statuses").tag(LeadStatus?.none)
                        ForEach(LeadStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Order", selection: $sortOrder) {
                        ForEach(RecordListSortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .navigationTitle("Filter Leads")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { selectedStatus = nil; dateFilter = .all; sortOrder = .dateAscending }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } }
                }
            }
        }
        .sheet(isPresented: $showingNewLead) {
            LeadNewView().environmentObject(store)
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateAscending
    }

    private var listDateColor: Color {
        Color(red: 0.20, green: 0.95, blue: 0.42)
    }

    private func leadStatusColor(_ status: LeadStatus) -> Color {
        switch status {
        case .newLead, .followUpRequired: return .red
        case .estimateScheduled, .estimateGiven: return .blue
        case .approved, .converted: return .green
        case .rejected: return .secondary
        }
    }

    private func leadStatusSymbol(_ status: LeadStatus) -> String {
        switch status {
        case .newLead, .followUpRequired: return "exclamationmark.circle.fill"
        case .estimateScheduled, .estimateGiven: return "calendar.circle.fill"
        case .approved, .converted: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
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
