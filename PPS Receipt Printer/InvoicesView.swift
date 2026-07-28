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
    @State private var showArchived = false
    @State private var searchText: String
    @State private var showingFilters = false
    @State private var selectedStatus: InvoiceStatus?
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateDescending

    init(
        statuses: Set<InvoiceStatus>? = nil,
        bucket: InvoiceRecordBucket? = nil,
        title: String = "All Invoices",
        initialSearchText: String = ""
    ) {
        self.statuses = statuses
        self.bucket = bucket
        self.title = title
        _searchText = State(initialValue: initialSearchText)
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

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingInvoices: [InvoiceRecord]

        if query.isEmpty {
            matchingInvoices = source
        } else {
            matchingInvoices = source.filter { invoice in
                invoice.invoiceNumber.localizedCaseInsensitiveContains(query)
                    || invoice.customerNumber.localizedCaseInsensitiveContains(query)
                    || customerDisplayName(for: invoice.customerNumber)
                        .localizedCaseInsensitiveContains(query)
                    || invoice.jobNumber.localizedCaseInsensitiveContains(query)
                    || invoice.status.rawValue.localizedCaseInsensitiveContains(query)
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
                Section {
                    Toggle(
                        "Show Archived",
                        isOn: $showArchived
                    )
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
                            NavigationLink {
                                InvoiceDetailView(invoice: invoice)
                            } label: {
                                VStack(
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    HStack {
                                        Text(invoice.invoiceNumber)
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        Text(invoice.status.rawValue)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    Text(
                                        "Customer: \(customerDisplayName(for: invoice.customerNumber))"
                                    )
                                    .font(.caption)
                                    
                                    if !invoice.jobNumber.isEmpty {
                                        Text("Job: \(invoice.jobNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    HStack {
                                        Text(
                                            invoice.issueDate,
                                            format: .dateTime
                                                .month()
                                                .day()
                                                .year()
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(
                                            invoice.balanceDue,
                                            format: .currency(code: "USD")
                                        )
                                        .fontWeight(.semibold)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if invoice.lifecycleStatus != .archived {
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
        .searchable(text: $searchText, prompt: "Search invoices")
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
                            sortOrder = .dateDescending
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingFilters = false }
                    }
                }
            }
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != nil || dateFilter != .all || sortOrder != .dateDescending
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
}
