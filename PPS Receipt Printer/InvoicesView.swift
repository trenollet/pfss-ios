//
//  InvoicesView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/11/26.
//

import SwiftUI

enum InvoiceRecordBucket {
    case sent
    case paid
    case pastDue
    case draft

    func contains(
        _ invoice: InvoiceRecord,
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .sent:
            return [.sent, .partiallyPaid].contains(invoice.status)
                && !invoice.isPastDue(relativeTo: date, calendar: calendar)
        case .paid:
            return invoice.status == .paid
        case .pastDue:
            return invoice.isPastDue(relativeTo: date, calendar: calendar)
        case .draft:
            return invoice.status == .draft
        }
    }
}

extension InvoiceRecord {
    func isPastDue(
        relativeTo date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard balanceDue > 0 else { return false }

        if status == .overdue {
            return true
        }

        guard [.sent, .partiallyPaid].contains(status) else {
            return false
        }

        return calendar.startOfDay(for: dueDate)
            < calendar.startOfDay(for: date)
    }
}

struct InvoiceRecordsListView: View {
    @EnvironmentObject var store: AppDataStore

    let statuses: Set<InvoiceStatus>?
    let bucket: InvoiceRecordBucket?
    let title: String
    let customerNumber: String?
    let invoiceFilter: ((InvoiceRecord) -> Bool)?
    @State private var showArchived = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: InvoiceStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateDescending
    @State private var sharedPDFURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isShowingPDFError = false
    @State private var invoiceToView: InvoiceRecord?
    @State private var combinationSelection = InvoiceCombinationSelection()
    @State private var combinationSources: [InvoiceRecord]?

    init(
        statuses: Set<InvoiceStatus>? = nil,
        bucket: InvoiceRecordBucket? = nil,
        title: String = "All Invoices",
        initialSearchText: String = "",
        customerNumber: String? = nil,
        invoiceFilter: ((InvoiceRecord) -> Bool)? = nil
    ) {
        self.statuses = statuses
        self.bucket = bucket
        self.title = title
        self.customerNumber = customerNumber
        self.invoiceFilter = invoiceFilter
        _searchText = State(initialValue: initialSearchText)
        _sortOrder = State(
            initialValue: customerNumber == nil ? .dateDescending : .dateAscending
        )
    }

    private var filteredInvoices: [InvoiceRecord] {
        let lifecycleSource = showArchived
            ? store.archivedInvoices
            : store.activeInvoices
        let source: [InvoiceRecord]
        if let bucket {
            source = lifecycleSource.filter { bucket.contains($0) }
        } else if let statuses {
            source = lifecycleSource.filter { statuses.contains($0.status) }
        } else {
            source = lifecycleSource
        }

        let customFiltered = invoiceFilter.map { filter in
            source.filter(filter)
        } ?? source
        let customerScoped = customerNumber.map { number in
            customFiltered.filter { $0.customerNumber == number }
        } ?? customFiltered
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingInvoices: [InvoiceRecord]

        if query.isEmpty {
            matchingInvoices = customerScoped
        } else {
            matchingInvoices = customerScoped.filter { invoice in
                invoice.invoiceNumber.localizedCaseInsensitiveContains(query)
                    || invoice.customerNumber.localizedCaseInsensitiveContains(query)
                    || customerDisplayName(for: invoice.customerNumber)
                        .localizedCaseInsensitiveContains(query)
                    || invoice.jobNumber.localizedCaseInsensitiveContains(query)
                    || invoice.displayedStatus.localizedCaseInsensitiveContains(query)
            }
        }

        let statusFiltered = selectedStatus.map { status in
            matchingInvoices.filter { $0.status == status }
        } ?? matchingInvoices
        let dateFiltered = statusFiltered.filter {
            dateFilter.includes($0.issueDate)
        }
        return dateFiltered.sorted { first, second in
            switch sortOrder {
            case .dateAscending: return first.issueDate < second.issueDate
            case .dateDescending: return first.issueDate > second.issueDate
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
                if supportsCombination {
                    Section {
                        HStack {
                            if combinationSelection.isSelecting {
                                Button("Cancel") { combinationSelection.cancel() }
                                Spacer()
                                Text("\(combinationSelection.selectedIDs.count) selected")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text("Combine invoices").font(.headline)
                                Spacer()
                            }
                            Button {
                                if !combinationSelection.isSelecting {
                                    showArchived = false
                                    selectedStatus = nil
                                    dateFilter = .all
                                    searchText = ""
                                    combinationSelection.begin()
                                } else if combinationSelection.canContinue {
                                    combinationSources = store.activeInvoices.filter {
                                        combinationSelection.selectedIDs.contains($0.id)
                                    }.sorted { $0.invoiceNumber < $1.invoiceNumber }
                                }
                            } label: {
                                Text("Combine").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(combineColor, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(combinationSelection.isSelecting && !combinationSelection.canContinue)
                            .accessibilityIdentifier("invoiceCombineButton")
                        }
                        if combinationSelection.isSelecting {
                            Text("Select at least 2 invoices. Paid and unpaid invoices can be selected.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle(
                        "Show Archived",
                        isOn: $showArchived
                    )
                    .disabled(combinationSelection.isSelecting)
                }

                Section("Invoices") {
                    if filteredInvoices.isEmpty {
                        Text(
                            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (showArchived ? "No archived invoices." : "No invoices yet.")
                                : "No invoices match your search."
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredInvoices) { invoice in
                            HStack(spacing: 12) {
                            if combinationSelection.isSelecting {
                                Button {
                                    combinationSelection.toggle(invoice.id)
                                } label: {
                                    Image(systemName: combinationSelection.selectedIDs.contains(invoice.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(.blue)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .disabled(invoice.status == .void || invoice.lifecycleStatus != .active
                                          || invoice.combination != nil || invoice.combinedIntoInvoiceID != nil || invoice.paymentCorrection != nil)
                                .accessibilityLabel("Select invoice \(invoice.invoiceNumber)")
                                .accessibilityValue(combinationSelection.selectedIDs.contains(invoice.id) ? "Selected" : "Not selected")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 10) {
                                    Text(
                                        customerDisplayName(
                                            for: invoice.customerNumber
                                        )
                                    )
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .lineLimit(1)

                                    Spacer(minLength: 8)

                                    if !combinationSelection.isSelecting {
                                    Button {
                                        createAndSharePDF(for: invoice)
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 44, height: 44)
                                            .background(.green, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Share invoice")

                                    Button {
                                        invoiceToView = store.invoiceDestination(for: invoice)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 44, height: 44)
                                            .background(.blue, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("View or edit invoice")
                                    }
                                }

                                HStack(spacing: 10) {
                                    Text(
                                        invoice.issueDate,
                                        format: .dateTime
                                            .month()
                                            .day()
                                            .year()
                                    )
                                    .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Text(
                                        invoice.total,
                                        format: .currency(code: "USD")
                                    )
                                    .fontWeight(.semibold)
                                    .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Text(invoice.displayedStatus)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .font(.subheadline)
                            }
                            }
                            .padding(.vertical, 1)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if invoice.lifecycleStatus != .archived && !combinationSelection.isSelecting {
                                    Button(role: .destructive) {
                                        store.archiveInvoice(invoice)
                                    } label: {
                                        Label("Archive", systemImage: "archivebox.fill")
                                    }
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
                get: { invoiceToView != nil },
                set: { isPresented in
                    if !isPresented { invoiceToView = nil }
                }
            )
        ) {
            if let invoiceToView {
                InvoiceDetailView(invoice: invoiceToView)
            }
        }
        .searchable(text: $searchText, prompt: "Search invoices")
        .onChange(of: Set(store.activeInvoices.filter {
            $0.status != .void && $0.combination == nil && $0.combinedIntoInvoiceID == nil && $0.paymentCorrection == nil
        }.map(\.id))) { _, eligibleIDs in
            combinationSelection.reconcile(eligibleIDs: eligibleIDs)
        }
        .sheet(isPresented: Binding(
            get: { combinationSources != nil },
            set: { if !$0 { combinationSources = nil } }
        )) {
            if let combinationSources {
                NavigationStack {
                    InvoiceCombinationReviewView(sources: combinationSources) { saved in
                        self.combinationSources = nil
                        combinationSelection.cancel()
                        invoiceToView = saved
                    }
                }
            }
        }
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
                        Text("All Statuses").tag(InvoiceStatus?.none)
                        ForEach(InvoiceStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Order", selection: $sortOrder) {
                        ForEach(RecordListSortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .navigationTitle("Filter Invoices")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") {
                            selectedStatus = nil
                            dateFilter = .all
                            sortOrder = defaultSortOrder
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingFilters = false }
                    }
                }
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
        .alert("Unable to Share Invoice", isPresented: $isShowingPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfErrorMessage ?? "The invoice PDF could not be created.")
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != defaultSortOrder
    }

    private var supportsCombination: Bool {
        statuses == nil && bucket == nil && customerNumber == nil && invoiceFilter == nil
    }

    private var combineColor: Color {
        !combinationSelection.isSelecting ? .blue : (combinationSelection.canContinue ? .green : .gray)
    }

    private var defaultSortOrder: RecordListSortOrder {
        customerNumber == nil ? .dateDescending : .dateAscending
    }

    private func customerDisplayName(
        for customerNumber: String
    ) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return customerNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return customerNumber
    }

    private func createAndSharePDF(for invoice: InvoiceRecord) {
        let invoice = store.invoiceDestination(for: invoice)
        let customer = store.customers.first {
            $0.customerNumber == invoice.customerNumber
        }
        let site = invoice.siteID.flatMap { siteID in
            store.sites.first { $0.id == siteID }
        }

        do {
            sharedPDFURL = try InvoicePDFRenderer.createPDF(
                invoice: invoice,
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
