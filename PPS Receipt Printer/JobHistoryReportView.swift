//
//  JobHistoryReportView.swift
//  PPS Receipt Printer
//
//  Brick 9: Automatic Time Tracking
//

import SwiftUI

struct JobHistoryReportView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var statusFilter: JobHistoryInvoiceFilter = .all
    @State private var dateFilter: RecordDateFilter = .all
    @State private var sortOrder: RecordListSortOrder = .dateDescending

    private var filteredJobs: [JobRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.jobs
            .filter { lifecycleContext(for: $0).presentation.isClosed }
            .filter { dateFilter.includes(reportDate(for: $0)) }
            .filter { statusFilter.includes(store.invoice(for: $0)?.status) }
            .filter { job in
                query.isEmpty || searchableText(for: job)
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { first, second in
                switch sortOrder {
                case .dateAscending:
                    return reportDate(for: first) < reportDate(for: second)
                case .dateDescending:
                    return reportDate(for: first) > reportDate(for: second)
                case .nameAscending:
                    return customerName(for: first.customerNumber)
                        .localizedCaseInsensitiveCompare(
                            customerName(for: second.customerNumber)
                        ) == .orderedAscending
                }
            }
    }

    var body: some View {
        List {
            if filteredJobs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty && !hasActiveFilters
                        ? "No Job History"
                        : "No Matching Job History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        searchText.isEmpty && !hasActiveFilters
                            ? "Completed jobs will appear here."
                            : "Try changing the search or filters."
                    )
                )
            } else {
                ForEach(filteredJobs) { job in
                    NavigationLink {
                        JobDetailView(job: job)
                    } label: {
                        jobHistoryRow(job)
                    }
                }
            }
        }
        .navigationTitle("Job History Report")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search job history")
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
                        ForEach(RecordDateFilter.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }

                    Picker("Invoice Status", selection: $statusFilter) {
                        ForEach(JobHistoryInvoiceFilter.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }

                    Picker("Order", selection: $sortOrder) {
                        ForEach(RecordListSortOrder.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }
                .navigationTitle("Filter Job History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { resetFilters() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingFilters = false }
                    }
                }
            }
        }
    }

    private func jobHistoryRow(_ job: JobRecord) -> some View {
        let status = store.invoice(for: job)?.status
        let presentation = lifecycleContext(for: job).presentation

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(customerName(for: job.customerNumber))
                    .font(.title3.weight(.bold))

                Spacer()

                Label(
                    presentation.statusTitle,
                    systemImage: presentation.statusSystemImage
                )
                .font(.body.weight(.bold))
                .foregroundStyle(presentation.accent.color)
            }

            Text("Job: \(job.jobNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Invoice") {
                Text(status?.rawValue ?? "Not Invoiced")
                    .foregroundStyle(invoiceStatusColor(status))
            }

            LabeledContent("Date") {
                Text(reportDate(for: job).formatted(date: .abbreviated, time: .shortened))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 0.20, green: 0.95, blue: 0.42))
            }

            LabeledContent("Technician(s)") {
                Text(technicianNames(for: job))
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Time on Job") {
                Text(formattedTimeOnJob(for: job)).fontWeight(.semibold)
            }
        }
        .padding(.vertical, 5)
    }

    private var hasActiveFilters: Bool {
        statusFilter != .all || dateFilter != .all || sortOrder != .dateDescending
    }

    private func resetFilters() {
        statusFilter = .all
        dateFilter = .all
        sortOrder = .dateDescending
    }

    private func searchableText(for job: JobRecord) -> String {
        [
            job.jobNumber,
            job.customerNumber,
            customerName(for: job.customerNumber),
            technicianNames(for: job),
            store.invoice(for: job)?.status.rawValue ?? "Not Invoiced"
        ].joined(separator: " ")
    }

    private func customerName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else { return customerNumber }

        if !customer.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customer.businessName
        }
        if !customer.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customer.contactName
        }
        return customerNumber
    }

    private func technicianNames(for job: JobRecord) -> String {
        let IDs = [job.primaryTechnicianID, job.secondaryTechnicianID].compactMap { $0 }
        let names = IDs.compactMap { employeeID in
            store.employees.first(where: { $0.id == employeeID })?.displayName
        }
        return names.isEmpty ? "Unassigned" : names.joined(separator: ", ")
    }

    private func formattedTimeOnJob(for job: JobRecord) -> String {
        guard let duration = lifecycleContext(for: job).timeDetails.timeOnJob else {
            return "—"
        }
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, let minutes): return "\(minutes) min"
        case (let hours, 0): return hours == 1 ? "1 hr" : "\(hours) hrs"
        default:
            return "\(hours == 1 ? "1 hr" : "\(hours) hrs") \(minutes) min"
        }
    }

    private func invoiceStatusColor(_ status: InvoiceStatus?) -> Color {
        switch status {
        case .paid: return .green
        case .overdue: return .red
        case .sent: return .blue
        case .partiallyPaid: return .orange
        case .draft: return .secondary
        case .void: return .secondary
        case nil: return .secondary
        }
    }

    private func invoiceStatusSymbol(_ status: InvoiceStatus?) -> String {
        switch status {
        case .paid: return "checkmark.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .sent: return "paperplane.fill"
        case .partiallyPaid: return "circle.lefthalf.filled"
        case .draft: return "doc.badge.ellipsis"
        case .void: return "xmark.circle.fill"
        case nil: return "doc.text"
        }
    }

    private func reportDate(for job: JobRecord) -> Date {
        lifecycleContext(for: job).timeDetails.completed ?? job.scheduledDate
    }

    private func lifecycleContext(for job: JobRecord) -> JobWorkflowContext {
        FieldOperationsEngine().context(
            for: job,
            invoice: store.invoice(for: job),
            assignment: store.assignment(forJobID: job.id)
        )
    }
}

private enum JobHistoryInvoiceFilter: String, CaseIterable, Identifiable {
    case all = "All Statuses"
    case notInvoiced = "Not Invoiced"
    case draft = "Draft"
    case sent = "Sent"
    case partiallyPaid = "Partially Paid"
    case paid = "Paid"
    case overdue = "Overdue"
    case void = "Void"

    var id: String { rawValue }

    func includes(_ status: InvoiceStatus?) -> Bool {
        switch self {
        case .all: return true
        case .notInvoiced: return status == nil
        case .draft: return status == .draft
        case .sent: return status == .sent
        case .partiallyPaid: return status == .partiallyPaid
        case .paid: return status == .paid
        case .overdue: return status == .overdue
        case .void: return status == .void
        }
    }
}
