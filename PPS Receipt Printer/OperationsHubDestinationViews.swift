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
            .filter { $0.hasRole(.technician) }
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
    @State private var routeAwareRecommendations: [UUID: OperationalRecommendationResult] = [:]

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
        .task(id: jobs.map(\.id)) {
            await refreshRecommendations()
        }
    }

    private func recommendation(
        for job: JobRecord
    ) -> OperationalRecommendationResult? {
        routeAwareRecommendations[job.id]
    }

    private func refreshRecommendations() async {
        routeAwareRecommendations = [:]
        await Task.yield()

        // Show locally calculated recommendations immediately. Route-aware
        // evidence replaces each result progressively as it becomes available.
        for job in jobs {
            if Task.isCancelled { return }
            if let result = store.operationalRecommendation(
                for: job,
                policy: job.assignmentPriority == .emergency ? .emergency : .balanced,
                onOrAfter: max(job.scheduledDate, Date()),
                calendar: .current
            ) {
                routeAwareRecommendations[job.id] = result
            }
        }

        for job in jobs {
            if Task.isCancelled { return }
            if let result = await store.routeAwareOperationalRecommendation(
                for: job,
                policy: job.assignmentPriority == .emergency ? .emergency : .balanced,
                onOrAfter: max(job.scheduledDate, Date()),
                calendar: .current
            ) {
                routeAwareRecommendations[job.id] = result
            }
            await Task.yield()
        }
    }

    private func queueItem(for job: JobRecord) -> DispatchQueueItem {
        let recommendation = recommendation(for: job)
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
        let recommendation = recommendation(for: job)
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
                evidence: candidate.evidence,
                distanceMiles: candidate.distanceMiles,
                travelMinutes: candidate.travelMinutes
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
        let recommendation = recommendation(for: job)

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
    private enum DrillDown: Hashable, Identifiable {
        case scheduled(RevenueSummaryPeriod)
        case invoiced(RevenueSummaryPeriod)
        case outstanding(RevenueSummaryPeriod)

        var id: String {
            switch self {
            case let .scheduled(period): "scheduled-\(period)"
            case let .invoiced(period): "invoiced-\(period)"
            case let .outstanding(period): "outstanding-\(period)"
            }
        }
    }

    @EnvironmentObject private var store: AppDataStore
    private let calendar = Calendar.current
    private let now = Date()
    @State private var drillDown: DrillDown?
    @State private var emptyNotice: String?
    @State private var emptyNoticeTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                NavigationLink {
                    OperationsRevenueForecastsView()
                } label: {
                    Text("Forecasts")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.green, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                ForEach(RevenueSummaryPeriod.allCases, id: \.self) { period in
                    let summary = RevenueSummaryEngine.summary(
                        for: period,
                        jobs: store.activeJobs,
                        invoices: store.invoices,
                        now: now,
                        calendar: calendar
                    )
                    RevenueSummaryCard(
                        summary: summary,
                        title: period.title,
                        subtitle: period.subtitle(now: now, calendar: calendar),
                        showsScheduledRevenue: period != .annual,
                        onSelectInvoiced: period == .annual ? nil : {
                            open(
                                .invoiced(period),
                                value: summary.invoiced,
                                emptyMessage: "There are no invoices to display for this period."
                            )
                        },
                        onSelectScheduled: period == .annual ? nil : {
                            open(
                                .scheduled(period),
                                value: summary.scheduled,
                                emptyMessage: "There are no scheduled jobs to display for this period."
                            )
                        },
                        onSelectOutstanding: {
                            open(
                                .outstanding(period),
                                value: summary.outstanding,
                                emptyMessage: "There are no outstanding invoices to display for this period."
                            )
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Revenue")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $drillDown) { destination in
            drillDownView(destination)
        }
        .overlay(alignment: .top) {
            if let emptyNotice {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                    Text(emptyNotice)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 4)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.width > 20
                                || value.translation.height < -20 {
                                dismissEmptyNotice()
                            }
                        }
                )
            }
        }
        .onDisappear {
            emptyNoticeTask?.cancel()
        }
    }

    @ViewBuilder
    private func drillDownView(_ destination: DrillDown) -> some View {
        switch destination {
        case let .scheduled(period):
            JobRecordsListView(
                title: "Scheduled Jobs",
                jobFilter: { job in
                    period.dateInterval(now: now, calendar: calendar)
                        .contains(job.scheduledDate)
                        && job.status != .cancelled
                        && job.status != .completed
                }
            )
        case let .invoiced(period):
            InvoiceRecordsListView(
                title: "Invoices",
                invoiceFilter: { invoice in
                    period.dateInterval(now: now, calendar: calendar)
                        .contains(invoice.issueDate)
                        && invoice.status != .void
                }
            )
        case let .outstanding(period):
            InvoiceRecordsListView(
                title: "Outstanding Invoices",
                invoiceFilter: { invoice in
                    period.dateInterval(now: now, calendar: calendar)
                        .contains(invoice.issueDate)
                        && invoice.status != .void
                        && invoice.balanceDue > 0
                }
            )
        }
    }

    private func open(
        _ destination: DrillDown,
        value: Double,
        emptyMessage: String
    ) {
        guard value > 0 else {
            showEmptyNotice(emptyMessage)
            return
        }
        drillDown = destination
    }

    private func showEmptyNotice(_ message: String) {
        emptyNoticeTask?.cancel()
        withAnimation(.snappy) {
            emptyNotice = message
        }
        emptyNoticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissEmptyNotice()
            }
        }
    }

    private func dismissEmptyNotice() {
        emptyNoticeTask?.cancel()
        emptyNoticeTask = nil
        withAnimation(.snappy) {
            emptyNotice = nil
        }
    }
}

private struct OperationsRevenueForecastsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedPeriod: RevenueForecastPeriod?
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Text("Projected job value from today through the end of each period. Scheduled and assigned jobs only; completed, canceled, archived, unscheduled, and already-started jobs are excluded. This is not collected revenue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(RevenueForecastPeriod.allCases) { period in
                    let now = Date()
                    let forecast = RevenueForecastEngine.forecast(
                        for: period,
                        jobs: store.activeJobs,
                        now: now,
                        calendar: calendar
                    )
                    Button {
                        selectedPeriod = period
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(period.title).font(.headline)
                                    Text("\(period.label(offset: 0, now: now, calendar: calendar)) · \(period.subtitle(now: now, calendar: calendar))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(forecast.amount, format: .currency(code: "USD"))
                                .font(.system(size: 30, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Text("\(forecast.jobs.count) scheduled \(forecast.jobs.count == 1 ? "job" : "jobs")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows forecast totals for upcoming periods")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Forecasts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPeriod) { period in
            OperationsRevenueForecastDetailView(period: period)
        }
    }
}

private struct OperationsRevenueForecastDetailView: View {
    @EnvironmentObject private var store: AppDataStore
    let period: RevenueForecastPeriod
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Text("Projected value of scheduled and assigned jobs. The current period starts with today; later periods show their full calendar range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(0..<period.numberOfPeriods, id: \.self) { offset in
                    let now = Date()
                    let forecast = RevenueForecastEngine.forecast(
                        for: period,
                        jobs: store.activeJobs,
                        now: now,
                        calendar: calendar,
                        offset: offset
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text(period.label(offset: offset, now: now, calendar: calendar))
                            .font(.headline)
                        Text(period.subtitle(now: now, calendar: calendar, offset: offset))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(forecast.amount, format: .currency(code: "USD"))
                            .font(.system(size: 28, weight: .bold))
                            .monospacedDigit()
                        Text("\(forecast.jobs.count) scheduled \(forecast.jobs.count == 1 ? "job" : "jobs")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(period.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recommendations

struct OperationsRecommendationsView: View {
    @EnvironmentObject private var store: AppDataStore
    let jobs: [JobRecord]
    @State private var recommendations: [UUID: OperationalRecommendationResult] = [:]
    @State private var operationErrorMessage = ""
    @State private var showingOperationError = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if jobs.isEmpty {
                    ContentUnavailableView(
                        "No Recommendations",
                        systemImage: "sparkles",
                        description: Text(
                            "New recommendations will appear when a Job needs dispatch attention."
                        )
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(jobs) { job in
                        RecommendationCard(
                            item: recommendationItem(for: job),
                            action: recommendations[job.id]?.bestCandidate == nil
                                ? nil
                                : { assignRecommendedTechnician(to: job) }
                        )
                        .overlay(alignment: .topTrailing) {
                            if recommendations[job.id] == nil {
                                ProgressView()
                                    .padding(12)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: jobs.map(\.id)) {
            await refreshRecommendations()
        }
        .alert("Assignment Error", isPresented: $showingOperationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(operationErrorMessage)
        }
    }

    private func refreshRecommendations() async {
        recommendations = [:]
        await Task.yield()

        for job in jobs {
            if Task.isCancelled { return }
            if let result = store.operationalRecommendation(
                for: job,
                policy: policy(for: job),
                onOrAfter: max(job.scheduledDate, Date()),
                calendar: .current
            ) {
                recommendations[job.id] = result
            }
        }

        for job in jobs {
            if Task.isCancelled { return }
            if let result = await store.routeAwareOperationalRecommendation(
                for: job,
                policy: policy(for: job),
                onOrAfter: max(job.scheduledDate, Date()),
                calendar: .current
            ) {
                recommendations[job.id] = result
            }
            await Task.yield()
        }
    }

    private func recommendationItem(for job: JobRecord) -> RecommendationItem {
        guard let candidate = recommendations[job.id]?.bestCandidate else {
            return RecommendationItem(
                title: "Evaluating Dispatch Options",
                detail: "PFSS is reviewing eligible technicians and route evidence.",
                priority: .medium
            )
        }

        let opening = candidate.proposedStartDate?.formatted(
            date: .abbreviated,
            time: .shortened
        ) ?? "after schedule review"
        return RecommendationItem(
            title: "Assign \(candidate.employeeName)",
            detail: "Recommended \(opening) with \(candidate.scorePercentage)% confidence.",
            priority: job.assignmentPriority == .emergency ||
                job.assignmentPriority == .high ? .high : .medium
        )
    }

    private func assignRecommendedTechnician(to job: JobRecord) {
        guard let recommendation = recommendations[job.id],
              let candidate = recommendation.bestCandidate else { return }
        do {
            _ = try store.assignTechnicianUsingRecommendation(
                candidate.employeeID,
                toJobID: job.id,
                recommendation: recommendation,
                overrideReason: ""
            )
        } catch {
            operationErrorMessage = error.localizedDescription
            showingOperationError = true
        }
    }

    private func policy(for job: JobRecord) -> OperationalRecommendationPolicy {
        job.assignmentPriority == .emergency ? .emergency : .balanced
    }
}
