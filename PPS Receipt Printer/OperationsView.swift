//
//  OperationsView.swift
//  PFSS
//
//  Live Operations workspace powered by AppDataStore,
//  SchedulingEngine, Workforce Intelligence, and the Phase 14.6
//  Operational Recommendation Engine.
//

import SwiftUI

struct OperationsView: View {

    @EnvironmentObject private var store: AppDataStore
    @State private var selectedAssignmentID: UUID?
    @State private var operationErrorMessage = ""
    @State private var showingOperationError = false

    private let calendar = Calendar.current

    private var now: Date {
        Date()
    }

    private var activeTechnicians: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.role == .technician }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    private var activeJobs: [JobRecord] {
        store.activeJobs
    }

    private var activeAssignments: [Assignment] {
        store.assignmentEngine.activeAssignments
    }

    private var workforceCredentialAlertCount: Int {
        activeTechnicians.reduce(0) { total, technician in
            total + technician.workforceProfile.certifications.filter {
                let status = $0.status(on: now)
                return status == .expired || status == .expiresSoon
            }.count
        }
    }

    private var todayJobs: [JobRecord] {
        activeJobs
            .filter {
                calendar.isDate(
                    $0.scheduledDate,
                    inSameDayAs: now
                )
            }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var dispatchJobs: [JobRecord] {
        store.assignmentEngine.unassignedAssignments
            .compactMap { assignment in
                activeJobs.first { $0.id == assignment.jobID }
            }
            .sorted { first, second in
                let firstPriority = dispatchPriority(for: first)
                let secondPriority = dispatchPriority(for: second)

                if priorityRank(firstPriority) != priorityRank(secondPriority) {
                    return priorityRank(firstPriority) >
                        priorityRank(secondPriority)
                }

                return first.scheduledDate < second.scheduledDate
            }
    }

    private var technicianModels: [TechnicianStatusModel] {
        activeTechnicians.map(makeTechnicianStatusModel)
    }

    private var dispatchQueueItems: [DispatchQueueItem] {
        dispatchJobs.map(makeDispatchQueueItem)
    }

    private var revenueSummary: RevenueSummary {
        let scheduledRevenue = todayJobs
            .filter {
                $0.status != .cancelled &&
                $0.status != .completed
            }
            .reduce(0.0) {
                $0 + max($1.total, 0)
            }

        let completedRevenue = activeJobs
            .filter { job in
                guard job.status == .completed else {
                    return false
                }

                if let completedDate = job.completedDate {
                    return calendar.isDate(
                        completedDate,
                        inSameDayAs: now
                    )
                }

                return calendar.isDate(
                    job.scheduledDate,
                    inSameDayAs: now
                )
            }
            .reduce(0.0) {
                $0 + max($1.total, 0)
            }

        let todaysInvoices = store.activeInvoices.filter {
            calendar.isDate(
                $0.issueDate,
                inSameDayAs: now
            )
        }

        let invoicedRevenue = todaysInvoices.reduce(0.0) {
            $0 + max($1.total, 0)
        }

        let collectedRevenue = store.activeInvoices
            .filter { invoice in
                guard let paidDate = invoice.paidDate else {
                    return false
                }

                return calendar.isDate(
                    paidDate,
                    inSameDayAs: now
                )
            }
            .reduce(0.0) {
                $0 + max($1.amountPaid, 0)
            }

        return RevenueSummary(
            scheduled: scheduledRevenue,
            completed: completedRevenue,
            invoiced: invoicedRevenue,
            collected: collectedRevenue
        )
    }

    private var recommendationItems: [RecommendationItem] {
        dispatchJobs.compactMap { job in
            guard let result = recommendation(for: job),
                  let candidate = result.bestCandidate else {
                return RecommendationItem(
                    title: "Dispatch Review Needed",
                    detail: "\(customerDisplayName(for: job)) has no eligible technician recommendation yet.",
                    priority: .high
                )
            }

            return RecommendationItem(
                title: "Assign \(candidate.employeeName)",
                detail: recommendationDetail(
                    candidate,
                    customerName: customerDisplayName(for: job)
                ),
                priority: recommendationPriority(
                    for: job,
                    confidencePercentage:
                        candidate.scorePercentage
                )
            )
        }
    }

    private var averageUtilization: Double {
        guard !technicianModels.isEmpty else {
            return 0
        }

        return technicianModels.reduce(0.0) {
            $0 + min(max($1.utilization, 0), 1)
        } / Double(technicianModels.count)
    }

    private var availableTechnicianCount: Int {
        technicianModels.filter {
            $0.status == .available
        }.count
    }

    private var highPriorityDispatchCount: Int {
        dispatchQueueItems.filter {
            $0.priority == .high ||
            $0.priority == .emergency
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    summaryGrid
                }
                .padding()
            }
            .navigationTitle("Operations")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await objectWillChangeRefresh()
            }
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
            .alert("Assignment Error", isPresented: $showingOperationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(operationErrorMessage)
            }
        }
    }

    // MARK: - Summary

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 16
        ) {
            operationsTile(
                title: "Today's Jobs",
                value: "\(todayJobs.count)",
                icon: "calendar",
                subtitle: todayJobsSubtitle,
                color: .blue
            ) {
                OperationsActiveAssignmentsView()
            }

            operationsTile(
                title: "Technicians",
                value: "\(activeTechnicians.count)",
                icon: "person.3.fill",
                subtitle: "\(availableTechnicianCount) available",
                color: .green
            ) {
                OperationsTechniciansView()
            }

            operationsTile(
                title: "Dispatch Queue",
                value: "\(dispatchQueueItems.count)",
                icon: "list.bullet.clipboard",
                subtitle: "\(highPriorityDispatchCount) high priority",
                color: .orange
            ) {
                OperationsDispatchQueueView()
            }

            operationsTile(
                title: "Dispatch Board",
                value: "Open",
                icon: "rectangle.3.group.fill",
                subtitle: "Technician lanes",
                color: .indigo
            ) {
                DispatchBoardView()
            }

            operationsTile(
                title: "Daily Planner",
                value: "Plan",
                icon: "calendar.badge.clock",
                subtitle: "Build the workday",
                color: .cyan
            ) {
                DailyPlanPreviewView()
            }

            operationsTile(
                title: "Workforce Intelligence",
                value: "Review",
                icon: "person.text.rectangle.fill",
                subtitle: workforceCredentialAlertCount > 0
                    ? "\(workforceCredentialAlertCount) credential alerts"
                    : "Skills and readiness",
                color: .purple
            ) {
                WorkforceIntelligenceDashboardView()
            }

            operationsTile(
                title: "Capacity",
                value: averageUtilization.formatted(
                    .percent.precision(.fractionLength(0))
                ),
                icon: "gauge.with.dots.needle.67percent",
                subtitle: capacitySubtitle,
                color: capacityColor
            ) {
                WorkforceCapacityDashboardView()
            }

            operationsTile(
                title: "Revenue",
                value: revenueSummary.collected.formatted(
                    .currency(code: "USD").precision(.fractionLength(0))
                ),
                icon: "dollarsign.circle.fill",
                subtitle: "Collected today",
                color: .green
            ) {
                OperationsRevenueView(summary: revenueSummary)
            }

            operationsTile(
                title: "Recommendations",
                value: "\(recommendationItems.count)",
                icon: "sparkles",
                subtitle: recommendationItems.isEmpty
                    ? "No recommendations"
                    : "Dispatch opportunities",
                color: .yellow
            ) {
                OperationsRecommendationsView(
                    jobs: dispatchJobs,
                    items: recommendationItems,
                    recommendedJobIDs: Set(
                        dispatchJobs.compactMap { job in
                            bestRecommendationCandidate(for: job) == nil
                                ? nil
                                : job.id
                        }
                    ),
                    onAssignRecommended: assignRecommendedTechnician
                )
            }
        }
    }

    // MARK: - Live Model Builders

    private func makeTechnicianStatusModel(
        _ employee: EmployeeRecord
    ) -> TechnicianStatusModel {
        let agenda = SchedulingEngine.dailyAgenda(
            for: employee,
            on: now,
            from: activeJobs,
            calendar: calendar
        )

        let employeeJobsToday = agenda.jobs
        let currentJob = employeeJobsToday.first {
            jobContains($0, date: now)
        }

        let status = technicianStatus(
            employee: employee,
            agenda: agenda,
            currentJob: currentJob
        )

        let revenue = employeeJobsToday
            .filter { $0.status != .cancelled }
            .reduce(0.0) {
                $0 + max($1.total, 0)
            }

        let confidence = dispatchJobs.compactMap {
            bestRecommendationCandidate(for: $0)
        }
        .first {
            $0.employeeID == employee.id
        }
        .map {
            Double($0.scorePercentage) / 100
        }

        return TechnicianStatusModel(
            id: employee.id,
            employeeID: employee.id,
            name: employee.displayName,
            status: status,
            jobsToday: employeeJobsToday.count,
            utilization: agenda.utilization,
            nextOpening: nextOpening(
                for: employee,
                agenda: agenda
            ),
            travelMinutes: 0,
            revenueToday: revenue,
            confidence: confidence
        )
    }

    private func makeDispatchQueueItem(
        _ job: JobRecord
    ) -> DispatchQueueItem {
        let candidate = bestRecommendationCandidate(for: job)

        return DispatchQueueItem(
            id: job.id,
            jobID: job.id,
            customerName: customerDisplayName(for: job),
            address: serviceAddress(for: job),
            estimatedDuration: TimeInterval(
                SchedulingEngine.scheduledMinutes(for: job) * 60
            ),
            priority: dispatchPriority(for: job),
            recommendedTechnician:
                candidate?.employeeName,
            confidence: Double(
                candidate?.scorePercentage ?? 0
            ) / 100
        )
    }

    // MARK: - Dispatch Actions

    private func recommendation(
        for job: JobRecord
    ) -> OperationalRecommendationResult? {
        store.operationalRecommendation(
            for: job,
            policy: dispatchRecommendationPolicy(for: job),
            onOrAfter: max(job.scheduledDate, now),
            calendar: calendar
        )
    }

    private func bestRecommendationCandidate(
        for job: JobRecord
    ) -> OperationalRecommendationCandidate? {
        recommendation(for: job)?.bestCandidate
    }

    /// Builds a complete picker list. Conflict-free candidates retain the
    /// engine's ranking and proposed opening. Other active technicians remain
    /// selectable as explicit human overrides.
    private func technicianOptions(
        for jobID: UUID?
    ) -> [DispatchTechnicianOption] {
        guard let jobID,
              let job = activeJobs.first(where: { $0.id == jobID }) else {
            return []
        }

        guard let recommendation = recommendation(for: job) else {
            return []
        }
        let recommendedID = recommendation.bestCandidate?.employeeID

        return recommendation.candidates
            .map { candidate in
                DispatchTechnicianOption(
                    id: candidate.employeeID,
                    name: candidate.employeeName,
                    confidence: Double(candidate.scorePercentage) / 100,
                    proposedStart: candidate.proposedStartDate
                        ?? job.scheduledDate,
                    isRecommended: candidate.employeeID == recommendedID,
                    hasConflictFreeOpening:
                        candidate.proposedStartDate != nil,
                    rank: candidate.rank,
                    eligibility: candidate.eligibility,
                    evidence: candidate.evidence
                )
            }
            .sorted { first, second in
                if first.isRecommended != second.isRecommended {
                    return first.isRecommended
                }
                if first.rank != second.rank {
                    return (first.rank ?? Int.max) <
                        (second.rank ?? Int.max)
                }
                if first.confidence != second.confidence {
                    return first.confidence > second.confidence
                }
                return first.name.localizedCaseInsensitiveCompare(
                    second.name
                ) == .orderedAscending
            }
    }

    private func assignRecommendedTechnician(
        to jobID: UUID?
    ) {
        guard
            let jobID,
            let job = activeJobs.first(where: {
                $0.id == jobID
            }),
            let recommendation = recommendation(for: job),
            let candidate = recommendation.bestCandidate
        else {
            return
        }

        do {
            _ = try store.assignTechnicianUsingRecommendation(
                candidate.employeeID,
                toJobID: jobID,
                recommendation: recommendation,
                overrideReason: ""
            )
        } catch {
            presentOperationError(error)
        }
    }

    /// Assigns the technician selected by the dispatcher. PFSS uses that
    /// candidate's proposed opening when one exists and records a reason when
    /// the human chooses someone other than the top recommendation.
    private func assignTechnician(
        _ technicianID: UUID,
        to jobID: UUID?,
        overrideReason: String
    ) {
        guard let jobID,
              let job = activeJobs.first(where: { $0.id == jobID }),
              activeTechnicians.contains(where: { $0.id == technicianID }),
              let recommendation = recommendation(for: job) else {
            return
        }

        do {
            _ = try store.assignTechnicianUsingRecommendation(
                technicianID,
                toJobID: jobID,
                recommendation: recommendation,
                overrideReason: overrideReason
            )
        } catch {
            presentOperationError(error)
        }
    }

    private func dispatchRecommendationPolicy(
        for job: JobRecord
    ) -> OperationalRecommendationPolicy {
        dispatchPriority(for: job) == .emergency
            ? .emergency
            : .balanced
    }

    private func recommendationDetail(
        _ candidate: OperationalRecommendationCandidate,
        customerName: String
    ) -> String {
        let opening = candidate.proposedStartDate.map(formattedOpening)
            ?? "after schedule review"
        let warningText = candidate.warnings.isEmpty
            ? ""
            : " Review \(candidate.warnings.count) warning\(candidate.warnings.count == 1 ? "" : "s")."
        return "\(customerName) can be assigned \(opening) with \(candidate.scorePercentage)% confidence.\(warningText)"
    }

    private func presentOperationError(_ error: Error) {
        operationErrorMessage = error.localizedDescription
        showingOperationError = true
    }

    // MARK: - Technician Helpers

    private func technicianStatus(
        employee: EmployeeRecord,
        agenda: TechnicianAgenda,
        currentJob: JobRecord?
    ) -> TechnicianStatus {
        guard agenda.isWorkingDay else {
            return .offline
        }

        if agenda.isOverCapacity {
            return .overtime
        }

        guard let currentJob else {
            return .available
        }

        switch currentJob.workflowState {
        case .traveling:
            return .traveling

        case .arrived,
             .settingUp,
             .working,
             .paused,
             .packingUp:
            return .working

        case .notStarted,
             .workComplete,
             .invoiceCreated,
             .paymentReceived,
             .completed,
             .cancelled:
            return .available
        }
    }

    private func nextOpening(
        for employee: EmployeeRecord,
        agenda: TechnicianAgenda
    ) -> Date? {
        guard agenda.isWorkingDay else {
            return nil
        }

        let dayStart = date(
            on: now,
            minutesAfterMidnight:
                employee.defaultStartMinutes
        )

        let dayEnd = date(
            on: now,
            minutesAfterMidnight:
                employee.defaultEndMinutes
        )

        var cursor = max(now, dayStart)

        for job in agenda.jobs {
            let jobStart = job.scheduledDate
            let jobEnd = calendar.date(
                byAdding: .minute,
                value: SchedulingEngine.scheduledMinutes(
                    for: job
                ),
                to: jobStart
            ) ?? jobStart

            if jobEnd <= cursor {
                continue
            }

            if jobStart > cursor {
                return cursor
            }

            cursor = max(cursor, jobEnd)
        }

        return cursor < dayEnd
            ? cursor
            : nil
    }

    private func jobContains(
        _ job: JobRecord,
        date: Date
    ) -> Bool {
        let end = calendar.date(
            byAdding: .minute,
            value: SchedulingEngine.scheduledMinutes(
                for: job
            ),
            to: job.scheduledDate
        ) ?? job.scheduledDate

        return job.scheduledDate <= date &&
            date < end &&
            job.status != .cancelled &&
            job.status != .completed
    }

    // MARK: - Customer and Site Helpers

    private func customerDisplayName(
        for job: JobRecord
    ) -> String {
        guard let customer = store.activeCustomers.first(
            where: {
                $0.customerNumber == job.customerNumber
            }
        ) else {
            return job.customerNumber.isEmpty
                ? "Unassigned Customer"
                : job.customerNumber
        }

        let businessName = customer.businessName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let contactName = customer.contactName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !businessName.isEmpty {
            return businessName
        }

        if !contactName.isEmpty {
            return contactName
        }

        return customer.customerNumber
    }

    private func serviceAddress(
        for job: JobRecord
    ) -> String {
        guard
            let siteID = job.siteID,
            let site = store.activeSites.first(
                where: {
                    $0.id == siteID
                }
            )
        else {
            return "No service address"
        }

        let address = site.serviceAddress
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return address.isEmpty
            ? "No service address"
            : address
    }

    // MARK: - Priority and Recommendation Helpers

    private func dispatchPriority(
        for job: JobRecord
    ) -> DispatchPriority {
        switch job.assignmentPriority {
        case .low: return .low
        case .normal: return .normal
        case .high: return .high
        case .emergency: return .emergency
        }
    }

    private func priorityRank(
        _ priority: DispatchPriority
    ) -> Int {
        switch priority {
        case .emergency:
            return 4
        case .high:
            return 3
        case .normal:
            return 2
        case .low:
            return 1
        }
    }

    private func recommendationPriority(
        for job: JobRecord,
        confidencePercentage: Int
    ) -> RecommendationPriority {
        switch dispatchPriority(for: job) {
        case .emergency, .high:
            return .high

        case .normal:
            return confidencePercentage >= 80
                ? .medium
                : .high

        case .low:
            return .low
        }
    }

    // MARK: - Presentation Helpers

    private var todayJobsSubtitle: String {
        let remaining = todayJobs.filter {
            $0.status != .completed &&
            $0.status != .cancelled
        }.count

        return "\(remaining) remaining"
    }

    private var capacitySubtitle: String {
        switch averageUtilization {
        case 0..<0.60:
            return "Open capacity"

        case 0.60..<0.85:
            return "Healthy workload"

        case 0.85..<1:
            return "Nearly full"

        default:
            return "At capacity"
        }
    }

    private var capacityColor: Color {
        switch averageUtilization {
        case 0..<0.60:
            return .green

        case 0.60..<0.85:
            return .blue

        case 0.85..<1:
            return .orange

        default:
            return .red
        }
    }

    private func formattedOpening(
        _ date: Date
    ) -> String {
        if calendar.isDateInToday(date) {
            return "today at \(date.formatted(date: .omitted, time: .shortened))"
        }

        if calendar.isDateInTomorrow(date) {
            return "tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(
            .dateTime
                .weekday(.wide)
                .hour()
                .minute()
        )
    }

    private func date(
        on day: Date,
        minutesAfterMidnight: Int
    ) -> Date {
        calendar.date(
            byAdding: .minute,
            value: minutesAfterMidnight,
            to: calendar.startOfDay(for: day)
        ) ?? day
    }

    private func operationsTile<Destination: View>(
        title: String,
        value: String,
        icon: String,
        subtitle: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            DashboardStatCard(
                title: title,
                value: value,
                icon: icon,
                subtitle: subtitle,
                accentColor: color,
                trend: .neutral,
                navigationIndicator: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title)")
    }

    private func objectWillChangeRefresh() async {
        await Task.yield()
    }
}

#Preview {
    OperationsView()
        .environmentObject(AppDataStore())
}
