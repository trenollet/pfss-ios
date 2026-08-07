//
//  RecordHubViews.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 4.6 – Searchable record workflow hubs.
//

import SwiftUI

private let activeJobStatuses: Set<JobStatus> = [
    .toBeScheduled,
    .scheduled,
    .assigned,
    .inProgress
]

struct InvoicesView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""

    var body: some View {
        RecordHubLayout(
            title: "Invoices",
            searchText: $searchText,
            layoutKey: "pfss.tile-layout.invoices.v1",
            tileIDs: ["sent", "paid", "pastDue", "draft", "all"]
        ) { tileID in
            switch tileID {
            case "sent":
            RecordHubTile(
                title: "Sent",
                count: store.activeInvoices.filter {
                    InvoiceRecordBucket.sent.contains($0)
                }.count,
                icon: "paperplane.fill",
                color: .blue
            ) {
                InvoiceRecordsListView(bucket: .sent, title: "Sent Invoices")
            }
            case "paid":
            RecordHubTile(
                title: "Paid",
                count: store.activeInvoices.filter {
                    InvoiceRecordBucket.paid.contains($0)
                }.count,
                icon: "checkmark.circle.fill",
                color: .green
            ) {
                InvoiceRecordsListView(bucket: .paid, title: "Paid Invoices")
            }
            case "pastDue":
            RecordHubTile(
                title: "Past Due",
                count: store.activeInvoices.filter {
                    InvoiceRecordBucket.pastDue.contains($0)
                }.count,
                icon: "exclamationmark.triangle.fill",
                color: .red
            ) {
                InvoiceRecordsListView(bucket: .pastDue, title: "Past Due Invoices")
            }
            case "draft":
            RecordHubTile(
                title: "Draft",
                count: store.activeInvoices.filter {
                    InvoiceRecordBucket.draft.contains($0)
                }.count,
                icon: "doc.badge.ellipsis",
                color: .orange
            ) {
                InvoiceRecordsListView(bucket: .draft, title: "Draft Invoices")
            }
            case "all":
            RecordHubTile(
                title: "All",
                count: store.activeInvoices.count,
                icon: "doc.text.fill",
                color: .purple
            ) {
                InvoiceRecordsListView()
            }
            default:
                EmptyView()
            }
        } supplement: {
            searchTile(
                query: searchText,
                count: matchingInvoiceCount,
                destination: InvoiceRecordsListView(
                    title: "Invoice Search",
                    initialSearchText: searchText
                )
            )
        }
    }

    private var matchingInvoiceCount: Int {
        let query = normalized(searchText)
        guard !query.isEmpty else { return 0 }
        return store.activeInvoices.filter {
            searchableInvoiceText($0, store: store).localizedCaseInsensitiveContains(query)
        }.count
    }
}

struct JobsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showingNewJob = false

    var body: some View {
        RecordHubLayout(
            title: "Jobs",
            searchText: $searchText,
            layoutKey: "pfss.tile-layout.jobs.v1",
            tileIDs: ["new", "active", "completed", "all"]
        ) { tileID in
            switch tileID {
            case "new":
            RecordHubActionTile(
                title: "New Job",
                value: "Add",
                icon: "plus.circle.fill",
                color: .blue
            ) {
                showingNewJob = true
            }
            case "active":
            RecordHubTile(
                title: "Active",
                count: store.activeJobs.filter { activeJobStatuses.contains($0.status) }.count,
                icon: "wrench.and.screwdriver.fill",
                color: .orange
            ) {
                JobRecordsListView(statuses: activeJobStatuses, title: "Active Jobs")
            }
            case "completed":
            RecordHubTile(
                title: "Completed",
                count: store.activeJobs.filter { $0.status == .completed }.count,
                icon: "checkmark.circle.fill",
                color: .green
            ) {
                JobRecordsListView(statuses: [.completed], title: "Completed Jobs")
            }
            case "all":
            RecordHubTile(
                title: "All",
                count: store.activeJobs.count,
                icon: "list.bullet.clipboard.fill",
                color: .purple
            ) {
                JobRecordsListView()
            }
            default:
                EmptyView()
            }
        } supplement: {
            searchTile(
                query: searchText,
                count: matchingJobCount,
                destination: JobRecordsListView(
                    title: "Job Search",
                    initialSearchText: searchText
                )
            )
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobNewView().environmentObject(store)
            }
        }
    }

    private var matchingJobCount: Int {
        let query = normalized(searchText)
        guard !query.isEmpty else { return 0 }
        return store.activeJobs.filter {
            searchableJobText($0, store: store).localizedCaseInsensitiveContains(query)
        }.count
    }
}

struct CustomersView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showingNewCustomer = false

    private let followUpStatuses: Set<EstimateStatus> = [
        .followUpRequired,
        .estimateGiven
    ]

    var body: some View {
        RecordHubLayout(
            title: "Customers",
            searchText: $searchText,
            layoutKey: "pfss.tile-layout.customers.v1",
            tileIDs: ["new", "newLead", "followUp", "all"]
        ) { tileID in
            switch tileID {
            case "new":
            RecordHubActionTile(
                title: "New Customer",
                value: "Add",
                icon: "person.crop.circle.badge.plus",
                color: .blue
            ) {
                showingNewCustomer = true
            }
            case "newLead":
            RecordHubTile(
                title: "New Lead",
                count: store.activeCustomers.filter { $0.estimateStatus == .newLead }.count,
                icon: "person.badge.plus",
                color: .cyan
            ) {
                CustomerRecordsListView(statuses: [.newLead], title: "New Lead Customers")
            }
            case "followUp":
            RecordHubTile(
                title: "Follow Up",
                count: store.activeCustomers.filter { followUpStatuses.contains($0.estimateStatus) }.count,
                icon: "arrow.trianglehead.clockwise",
                color: .orange
            ) {
                CustomerRecordsListView(statuses: followUpStatuses, title: "Customer Follow Up")
            }
            case "all":
            RecordHubTile(
                title: "All",
                count: store.activeCustomers.count,
                icon: "person.2.fill",
                color: .purple
            ) {
                CustomerRecordsListView()
            }
            default:
                EmptyView()
            }
        } supplement: {
            searchTile(
                query: searchText,
                count: matchingCustomerCount,
                destination: CustomerRecordsListView(
                    title: "Customer Search",
                    initialSearchText: searchText
                )
            )
        }
        .sheet(isPresented: $showingNewCustomer) {
            CustomerNewView().environmentObject(store)
        }
    }

    private var matchingCustomerCount: Int {
        let query = normalized(searchText)
        guard !query.isEmpty else { return 0 }
        return store.activeCustomers.filter {
            searchableCustomerText($0).localizedCaseInsensitiveContains(query)
        }.count
    }
}

struct LeadsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showingNewLead = false

    private let followUpStatuses: Set<LeadStatus> = [
        .followUpRequired,
        .estimateScheduled,
        .estimateGiven
    ]

    var body: some View {
        RecordHubLayout(
            title: "Leads",
            searchText: $searchText,
            layoutKey: "pfss.tile-layout.leads.v1",
            tileIDs: ["new", "followUp", "all"]
        ) { tileID in
            switch tileID {
            case "new":
            RecordHubActionTile(
                title: "New Lead",
                value: "Add",
                icon: "person.crop.circle.badge.plus",
                color: .blue
            ) {
                showingNewLead = true
            }
            case "followUp":
            RecordHubTile(
                title: "Follow Up",
                count: store.activeLeads.filter { followUpStatuses.contains($0.status) }.count,
                icon: "arrow.trianglehead.clockwise",
                color: .orange
            ) {
                LeadRecordsListView(statuses: followUpStatuses, title: "Lead Follow Up")
            }
            case "all":
            RecordHubTile(
                title: "All",
                count: store.activeLeads.count,
                icon: "person.text.rectangle.fill",
                color: .purple
            ) {
                LeadRecordsListView()
            }
            default:
                EmptyView()
            }
        } supplement: {
            searchTile(
                query: searchText,
                count: matchingLeadCount,
                destination: LeadRecordsListView(
                    title: "Lead Search",
                    initialSearchText: searchText
                )
            )
        }
        .sheet(isPresented: $showingNewLead) {
            LeadNewView().environmentObject(store)
        }
    }

    private var matchingLeadCount: Int {
        let query = normalized(searchText)
        guard !query.isEmpty else { return 0 }
        return store.activeLeads.filter {
            searchableLeadText($0).localizedCaseInsensitiveContains(query)
        }.count
    }
}

struct EstimatesView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showingNewEstimate = false

    private let followUpStatuses: Set<EstimateRecordStatus> = [.sent, .expired]

    var body: some View {
        RecordHubLayout(
            title: "Estimates",
            searchText: $searchText,
            layoutKey: "pfss.tile-layout.estimates.v1",
            tileIDs: ["new", "inProgress", "followUp", "all"]
        ) { tileID in
            switch tileID {
            case "new":
            RecordHubActionTile(
                title: "New Estimate",
                value: "Add",
                icon: "doc.badge.plus",
                color: .blue
            ) {
                showingNewEstimate = true
            }
            case "inProgress":
            RecordHubTile(
                title: "In Progress",
                count: store.activeEstimates.filter { $0.status == .draft }.count,
                icon: "pencil.and.list.clipboard",
                color: .orange
            ) {
                EstimateRecordsListView(statuses: [.draft], title: "Estimates In Progress")
            }
            case "followUp":
            RecordHubTile(
                title: "Follow Up",
                count: store.activeEstimates.filter { followUpStatuses.contains($0.status) }.count,
                icon: "arrow.trianglehead.clockwise",
                color: .cyan
            ) {
                EstimateRecordsListView(statuses: followUpStatuses, title: "Estimate Follow Up")
            }
            case "all":
            RecordHubTile(
                title: "All",
                count: store.activeEstimates.count,
                icon: "doc.text.fill",
                color: .purple
            ) {
                EstimateRecordsListView()
            }
            default:
                EmptyView()
            }
        } supplement: {
            searchTile(
                query: searchText,
                count: matchingEstimateCount,
                destination: EstimateRecordsListView(
                    title: "Estimate Search",
                    initialSearchText: searchText
                )
            )
        }
        .sheet(isPresented: $showingNewEstimate) {
            NavigationStack {
                EstimateNewView().environmentObject(store)
            }
        }
    }

    private var matchingEstimateCount: Int {
        let query = normalized(searchText)
        guard !query.isEmpty else { return 0 }
        return store.activeEstimates.filter {
            searchableEstimateText($0, store: store).localizedCaseInsensitiveContains(query)
        }.count
    }
}

private struct RecordHubLayout<Tile: View, Supplement: View>: View {
    let title: String
    @Binding var searchText: String
    let layoutKey: String
    let tileIDs: [String]
    let tile: (String) -> Tile
    let supplement: Supplement

    init(
        title: String,
        searchText: Binding<String>,
        layoutKey: String,
        tileIDs: [String],
        @ViewBuilder tile: @escaping (String) -> Tile,
        @ViewBuilder supplement: () -> Supplement
    ) {
        self.title = title
        _searchText = searchText
        self.layoutKey = layoutKey
        self.tileIDs = tileIDs
        self.tile = tile
        self.supplement = supplement()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CustomizableTileGrid(
                    storageKey: layoutKey,
                    defaultTileIDs: tileIDs,
                    tile: tile
                )

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    supplement
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
    }
}

private struct RecordHubTile<Destination: View>: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    var centered = false
    let destination: Destination

    init(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        centered: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.count = count
        self.icon = icon
        self.color = color
        self.centered = centered
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            DashboardStatCard(
                title: title,
                value: count.formatted(),
                icon: icon,
                subtitle: count == 1 ? "1 record" : "\(count) records",
                accentColor: color,
                navigationIndicator: true
            )
        }
        .buttonStyle(.plain)
        .gridCellColumns(centered ? 2 : 1)
        .frame(maxWidth: centered ? 360 : .infinity)
    }
}

private struct RecordHubActionTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DashboardStatCard(
                title: title,
                value: value,
                icon: icon,
                subtitle: "Create new record",
                accentColor: color,
                navigationIndicator: true
            )
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder
private func searchTile<Destination: View>(
    query: String,
    count: Int,
    destination: Destination
) -> some View {
    if !normalized(query).isEmpty {
        RecordHubTile(
            title: "Search Results",
            count: count,
            icon: "magnifyingglass",
            color: .blue,
            centered: true
        ) {
            destination
        }
    }
}

private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func searchableInvoiceText(_ invoice: InvoiceRecord, store: AppDataStore) -> String {
    let customer = store.customers.first { $0.customerNumber == invoice.customerNumber }
    return [
        invoice.invoiceNumber,
        invoice.customerNumber,
        customer?.businessName ?? "",
        customer?.contactName ?? "",
        invoice.jobNumber,
        invoice.status.rawValue
    ].joined(separator: " ")
}

private func searchableJobText(_ job: JobRecord, store: AppDataStore) -> String {
    let customer = store.customers.first { $0.customerNumber == job.customerNumber }
    let site = store.sites.first { $0.id == job.siteID }
    let employee = store.employees.first { $0.id == job.primaryTechnicianID }
    return [
        job.jobNumber,
        job.customerNumber,
        customer?.businessName ?? "",
        customer?.contactName ?? "",
        site?.siteName ?? "",
        site?.serviceAddress ?? "",
        job.serviceType.rawValue,
        job.otherService,
        employee?.displayName ?? "",
        job.status.rawValue,
        job.workNotes
    ].joined(separator: " ")
}

private func searchableCustomerText(_ customer: Customer) -> String {
    [
        customer.customerNumber,
        customer.businessName,
        customer.contactName,
        customer.phone,
        customer.email,
        customer.estimateStatus.rawValue
    ].joined(separator: " ")
}

private func searchableLeadText(_ lead: Lead) -> String {
    [
        lead.leadNumber,
        lead.businessName,
        lead.contactName,
        lead.location ?? "",
        lead.phone,
        lead.email,
        lead.status.rawValue,
        lead.serviceRequested.rawValue,
        lead.otherService,
        lead.notes ?? ""
    ].joined(separator: " ")
}

private func searchableEstimateText(_ estimate: EstimateRecord, store: AppDataStore) -> String {
    let customer = store.customers.first { $0.customerNumber == estimate.customerNumber }
    let site = store.sites.first { $0.id == estimate.siteID }
    return [
        estimate.estimateNumber,
        estimate.customerNumber,
        customer?.businessName ?? "",
        customer?.contactName ?? "",
        site?.siteName ?? "",
        site?.serviceAddress ?? "",
        estimate.status.rawValue,
        estimate.salesperson,
        estimate.serviceDetails
    ].joined(separator: " ")
}
