//
//  OperationsHubDestinationViews.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 4.5 – Focused, searchable Operations destinations.
//

import SwiftUI

// MARK: - Active Assignments

struct OperationsActiveAssignmentsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var selectedAssignmentID: UUID?

    private var filteredAssignments: [Assignment] {
        let assignments = store.assignmentEngine.activeAssignments.sorted {
            switch ($0.scheduling.serviceDate, $1.scheduling.serviceDate) {
            case let (firstDate?, secondDate?) where firstDate != secondDate:
                return firstDate < secondDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return $0.assignmentNumber.localizedStandardCompare(
                $1.assignmentNumber
            ) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return assignments }

        return assignments.filter { assignment in
            searchableText(for: assignment)
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if filteredAssignments.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty
                            ? "No Active Assignments"
                            : "No Matching Assignments",
                        systemImage: searchText.isEmpty
                            ? "briefcase"
                            : "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "Active operational work will appear here."
                                : "Try a customer, site, job, assignment, or technician name."
                        )
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(filteredAssignments) { assignment in
                        Button {
                            selectedAssignmentID = assignment.id
                        } label: {
                            AssignmentCard(
                                assignment: assignment,
                                employees: store.activeEmployees,
                                customers: store.customers,
                                sites: store.sites
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens assignment details")
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Active Assignments")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "Search active assignments"
        )
        .navigationDestination(item: $selectedAssignmentID) { assignmentID in
            AssignmentDetailView(
                engine: store.assignmentEngine,
                dispatchEngine: store.dispatchEngine,
                assignmentID: assignmentID,
                employees: store.activeEmployees,
                customers: store.customers,
                sites: store.sites
            )
        }
    }

    private func searchableText(for assignment: Assignment) -> String {
        let employeeNames = store.activeEmployees
            .filter {
                $0.id == assignment.primaryTechnicianID ||
                assignment.supportingTechnicianIDs.contains($0.id)
            }
            .map(\.displayName)

        let customer = store.customers.first {
            $0.customerNumber == assignment.customerNumber
        }
        let site = assignment.siteID.flatMap { siteID in
            store.sites.first { $0.id == siteID }
        }

        return ([
            assignment.assignmentNumber,
            assignment.jobNumber,
            assignment.customerNumber,
            customer?.businessName ?? "",
            customer?.contactName ?? "",
            site?.siteName ?? "",
            site?.serviceAddress ?? "",
            assignment.status.rawValue
        ] + employeeNames).joined(separator: " ")
    }
}

// MARK: - Technicians

struct OperationsTechniciansView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""

    private var technicians: [EmployeeRecord] {
        let source = store.activeEmployees
            .filter { $0.role == .technician }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return source }

        return source.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.email.localizedCaseInsensitiveContains(query) ||
            $0.phone.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if technicians.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Technicians" : "No Matching Technicians",
                    systemImage: searchText.isEmpty ? "person.3" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Active technicians will appear here."
                            : "Try another name, email address, or phone number."
                    )
                )
            } else {
                ForEach(technicians) { technician in
                    NavigationLink {
                        EmployeeDetailView(employee: technician)
                            .environmentObject(store)
                    } label: {
                        technicianRow(technician)
                    }
                }
            }
        }
        .navigationTitle("Technicians")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search technicians")
    }

    private func technicianRow(_ technician: EmployeeRecord) -> some View {
        let summary = SchedulingCalculator.capacitySummary(
            for: technician,
            on: Date(),
            from: store.activeJobs
        )

        return HStack(spacing: 12) {
            Circle()
                .fill(technicianColor(named: technician.colorName))
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(technician.displayName)
                    .font(.headline)
                Text("\(summary.assignedJobCount) jobs • \(SchedulingCalculator.formattedDuration(minutes: summary.scheduledMinutes)) scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func technicianColor(named colorName: String) -> Color {
        switch colorName.lowercased() {
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .blue
        }
    }
}

// MARK: - Dispatch Queue

struct OperationsDispatchQueueView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var selectedAssignmentID: UUID?
    @State private var operationErrorMessage = ""
    @State private var showingOperationError = false

    private var jobs: [JobRecord] {
        let activeJobs = store.activeJobs
        let source = store.assignmentEngine.unassignedAssignments
            .compactMap { assignment in
                activeJobs.first { $0.id == assignment.jobID }
            }
            .sorted { first, second in
                if priorityRank(first.assignmentPriority) != priorityRank(second.assignmentPriority) {
                    return priorityRank(first.assignmentPriority) > priorityRank(second.assignmentPriority)
                }
                return first.scheduledDate < second.scheduledDate
            }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return source }

        return source.filter {
            searchableText(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if jobs.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Dispatch Queue Is Clear" : "No Matching Work",
                        systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "All active jobs currently have a primary technician assignment."
                                : "Try a customer, address, job, service, or priority."
                        )
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(jobs) { job in
                        DispatchQueueCard(
                            item: queueItem(for: job),
                            technicianOptions: technicianOptions(for: job),
                            onAssign: { technicianID, overrideReason in
                                assign(
                                    technicianID,
                                    to: job,
                                    overrideReason: overrideReason
                                )
                            },
                            onViewDetails: {
                                selectedAssignmentID = store.assignment(forJobID: job.id)?.id
                            }
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dispatch Queue")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search dispatch queue")
        .navigationDestination(item: $selectedAssignmentID) { assignmentID in
            AssignmentDetailView(
                engine: store.assignmentEngine,
                dispatchEngine: store.dispatchEngine,
                assignmentID: assignmentID,
                employees: store.activeEmployees,
                customers: store.customers,
                sites: store.sites
            )
        }
        .alert("Dispatch Error", isPresented: $showingOperationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(operationErrorMessage)
        }
    }

    private func queueItem(for job: JobRecord) -> DispatchQueueItem {
        let recommendation = store.operationalRecommendation(
            for: job,
            policy: job.assignmentPriority == .emergency ? .emergency : .balanced,
            onOrAfter: max(job.scheduledDate, Date()),
            calendar: .current
        )
        let candidate = recommendation?.bestCandidate

        return DispatchQueueItem(
            id: job.id,
            jobID: job.id,
            customerName: customerName(for: job),
            address: site(for: job)?.serviceAddress ?? "No service address",
            estimatedDuration: TimeInterval(
                SchedulingEngine.scheduledMinutes(for: job) * 60
            ),
            priority: dispatchPriority(job.assignmentPriority),
            recommendedTechnician: candidate?.employeeName,
            confidence: Double(candidate?.scorePercentage ?? 0) / 100
        )
    }

    private func technicianOptions(for job: JobRecord) -> [DispatchTechnicianOption] {
        let recommendation = store.operationalRecommendation(
            for: job,
            policy: job.assignmentPriority == .emergency ? .emergency : .balanced,
            onOrAfter: max(job.scheduledDate, Date()),
            calendar: .current
        )
        guard let recommendation else { return [] }
        let recommendedID = recommendation.bestCandidate?.employeeID

        return recommendation.candidates.map { candidate in
            DispatchTechnicianOption(
                id: candidate.employeeID,
                name: candidate.employeeName,
                confidence: Double(candidate.scorePercentage) / 100,
                proposedStart: candidate.proposedStartDate ?? job.scheduledDate,
                isRecommended: candidate.employeeID == recommendedID,
                hasConflictFreeOpening: candidate.proposedStartDate != nil,
                rank: candidate.rank,
                eligibility: candidate.eligibility,
                evidence: candidate.evidence
            )
        }
        .sorted {
            if $0.isRecommended != $1.isRecommended { return $0.isRecommended }
            return ($0.rank ?? Int.max) < ($1.rank ?? Int.max)
        }
    }

    private func assign(
        _ technicianID: UUID,
        to job: JobRecord,
        overrideReason: String
    ) {
        let recommendation = store.operationalRecommendation(
            for: job,
            policy: job.assignmentPriority == .emergency ? .emergency : .balanced,
            onOrAfter: max(job.scheduledDate, Date()),
            calendar: .current
        )

        guard let recommendation else {
            operationErrorMessage = "PFSS could not build a current technician recommendation for this Job."
            showingOperationError = true
            return
        }

        do {
            _ = try store.assignTechnicianUsingRecommendation(
                technicianID,
                toJobID: job.id,
                recommendation: recommendation,
                overrideReason: overrideReason
            )
        } catch {
            operationErrorMessage = error.localizedDescription
            showingOperationError = true
        }
    }

    private func searchableText(for job: JobRecord) -> String {
        [
            job.jobNumber,
            job.serviceType.rawValue,
            customerName(for: job),
            site(for: job)?.siteName ?? "",
            site(for: job)?.serviceAddress ?? "",
            job.assignmentPriority.rawValue
        ].joined(separator: " ")
    }

    private func customerName(for job: JobRecord) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == job.customerNumber
        }) else { return job.customerNumber }

        if customer.businessName.isEmpty == false { return customer.businessName }
        if customer.contactName.isEmpty == false { return customer.contactName }
        return customer.customerNumber
    }

    private func site(for job: JobRecord) -> CustomerSite? {
        guard let siteID = job.siteID else { return nil }
        return store.sites.first { $0.id == siteID }
    }

    private func dispatchPriority(_ priority: AssignmentPriority) -> DispatchPriority {
        switch priority {
        case .low: .low
        case .normal: .normal
        case .high: .high
        case .emergency: .emergency
        }
    }

    private func priorityRank(_ priority: AssignmentPriority) -> Int {
        switch priority {
        case .low: 1
        case .normal: 2
        case .high: 3
        case .emergency: 4
        }
    }
}

// MARK: - Revenue

struct OperationsRevenueView: View {
    let summary: RevenueSummary

    var body: some View {
        ScrollView {
            RevenueSummaryCard(
                summary: summary,
                subtitle: "Today"
            )
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Revenue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recommendations

struct OperationsRecommendationsView: View {
    let jobs: [JobRecord]
    let items: [RecommendationItem]
    let recommendedJobIDs: Set<UUID>
    let onAssignRecommended: (UUID?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Recommendations",
                        systemImage: "sparkles",
                        description: Text(
                            "New recommendations will appear when a Job needs dispatch attention."
                        )
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(
                        Array(zip(jobs, items)),
                        id: \.0.id
                    ) { job, recommendation in
                        RecommendationCard(
                            item: recommendation,
                            action: recommendedJobIDs.contains(job.id)
                                ? { onAssignRecommended(job.id) }
                                : nil
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
    }
}
