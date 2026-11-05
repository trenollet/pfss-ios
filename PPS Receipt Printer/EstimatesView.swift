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
    @State private var sortOrder: RecordListSortOrder = .dateAscending
    @State private var sharedPDFURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isShowingPDFError = false
    @State private var estimateToView: EstimateRecord?

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
            estimate.title.localizedCaseInsensitiveContains(query) ||
            estimate.leadNumber.localizedCaseInsensitiveContains(query) ||
            estimate.customerNumber.localizedCaseInsensitiveContains(query) ||
            recipientDisplayName(for: estimate).localizedCaseInsensitiveContains(query) ||
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
                return recipientDisplayName(for: first)
                    .localizedCaseInsensitiveCompare(
                        recipientDisplayName(for: second)
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
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 10) {
                            Text(recipientDisplayName(for: estimate))
                                .font(.headline)
                                .fontWeight(.bold)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Button {
                                createAndSharePDF(for: estimate)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.green, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Share estimate")

                            Button {
                                estimateToView = estimate
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.blue, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View or edit estimate")
                        }

                        HStack(spacing: 10) {
                            Text(
                                estimate.title.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                                    ? "No Title"
                                    : estimate.title
                            )
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(estimate.status.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 1)
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
        .navigationDestination(
            isPresented: Binding(
                get: { estimateToView != nil },
                set: { isPresented in
                    if !isPresented { estimateToView = nil }
                }
            )
        ) {
            if let estimateToView {
                EstimateDetailView(estimate: estimateToView)
            }
        }
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
                            sortOrder = .dateAscending
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
        .sheet(
            isPresented: Binding(
                get: { sharedPDFURL != nil },
                set: { isPresented in
                    if !isPresented { sharedPDFURL = nil }
                }
            )
        ) {
            if let sharedPDFURL {
                ActivityView(activityItems: [sharedPDFURL])
            }
        }
        .alert("Unable to Share Estimate", isPresented: $isShowingPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfErrorMessage ?? "The estimate PDF could not be created.")
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateAscending
    }

    private func customerDisplayName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: { $0.customerNumber == customerNumber }) else {
            return customerNumber
        }
        if !customer.businessName.isEmpty { return customer.businessName }
        if !customer.contactName.isEmpty { return customer.contactName }
        return customerNumber
    }

    private func recipientDisplayName(for estimate: EstimateRecord) -> String {
        if !estimate.customerNumber.isEmpty,
           store.customers.contains(where: {
               $0.customerNumber == estimate.customerNumber
           }) {
            return customerDisplayName(for: estimate.customerNumber)
        }

        if !estimate.leadNumber.isEmpty,
           let lead = store.leads.first(where: {
               $0.leadNumber == estimate.leadNumber
           }) {
            if !lead.businessName.isEmpty { return lead.businessName }
            if !lead.contactName.isEmpty { return lead.contactName }
            return lead.leadNumber
        }

        if !estimate.customerNumber.isEmpty {
            return estimate.customerNumber
        }
        if !estimate.leadNumber.isEmpty { return estimate.leadNumber }
        return "Unknown recipient"
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

    private func createAndSharePDF(for estimate: EstimateRecord) {
        var renderedEstimate = estimate
        renderedEstimate.lineItems = PricingCalculator.updatedLineItems(
            estimate.lineItems
        )
        renderedEstimate.subtotal = PricingCalculator.subtotal(
            for: renderedEstimate
        )
        renderedEstimate.discount = DiscountCalculator.amount(
            subtotal: renderedEstimate.subtotal,
            method: renderedEstimate.discountMethod,
            inputValue: renderedEstimate.discountInputValue
        )
        renderedEstimate.total = PricingCalculator.total(
            subtotal: renderedEstimate.subtotal,
            discount: renderedEstimate.discount
        )

        let customer = store.customers.first {
            $0.customerNumber == renderedEstimate.customerNumber
        }
        let site = renderedEstimate.siteID.flatMap { siteID in
            store.sites.first { $0.id == siteID }
        }

        do {
            sharedPDFURL = try EstimatePDFRenderer.createPDF(
                estimate: renderedEstimate,
                businessProfile: store.businessProfile,
                customer: customer,
                site: site,
                catalogItems: store.serviceCatalogItems
            )
        } catch {
            pdfErrorMessage = error.localizedDescription
            isShowingPDFError = true
        }
    }
}
