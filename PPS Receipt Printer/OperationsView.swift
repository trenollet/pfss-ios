//
//  OperationsView.swift
//  PFSS
//
//  Live Operations workspace powered by AppDataStore,
//  SchedulingEngine, and DispatchDecisionEngine.
//

import SwiftUI

struct OperationsView: View {

    @EnvironmentObject private var store: AppDataStore

    private let calendar = Calendar.current
    private let forecastDayCount = 4

    private var now: Date {
        Date()
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: now)
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
        activeJobs
            .filter { job in
                job.primaryTechnicianID == nil &&
                job.status != .completed &&
                job.status != .cancelled
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

    private var capacityForecasts: [CapacityForecast] {
        (0..<forecastDayCount).compactMap { dayOffset in
            guard let date = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: startOfToday
            ) else {
                return nil
            }

            let summaries = activeTechnicians.map {
                SchedulingEngine.capacitySummary(
                    for: $0,
                    on: date,
                    from: activeJobs,
                    calendar: calendar
                )
            }

            let workingSummaries = summaries.filter(\.isWorkingDay)

            let utilization: Double

            if workingSummaries.isEmpty {
                utilization = 0
            } else {
                utilization = workingSummaries.reduce(0.0) {
                    $0 + min(max($1.utilizationFraction, 0), 1)
                } / Double(workingSummaries.count)
            }

            return CapacityForecast(
                day: forecastDayName(
                    for: date,
                    dayOffset: dayOffset
                ),
                utilization: utilization
            )
        }
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
            guard let decision = bestDecision(for: job) else {
                return RecommendationItem(
                    title: "Dispatch Review Needed",
                    detail: "\(customerDisplayName(for: job)) has no conflict-free technician recommendation yet.",
                    priority: .high
                )
            }

            return RecommendationItem(
                title: "Assign \(decision.employee.displayName)",
                detail: "\(customerDisplayName(for: job)) can be scheduled \(formattedOpening(decision.opening.start)) with \(decision.confidencePercentage)% confidence.",
                priority: recommendationPriority(
                    for: job,
                    confidencePercentage:
                        decision.confidencePercentage
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
                    technicianSection
                    dispatchSection
                    capacitySection
                    revenueSection
                    recommendationsSection
                }
                .padding()
            }
            .navigationTitle("Operations")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await objectWillChangeRefresh()
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
            DashboardStatCard(
                title: "Today's Jobs",
                value: "\(todayJobs.count)",
                icon: "calendar",
                subtitle: todayJobsSubtitle,
                accentColor: .blue,
                trend: .neutral
            )

            DashboardStatCard(
                title: "Technicians",
                value: "\(activeTechnicians.count)",
                icon: "person.3.fill",
                subtitle: "\(availableTechnicianCount) available",
                accentColor: .green,
                trend: .neutral
            )

            DashboardStatCard(
                title: "Dispatch Queue",
                value: "\(dispatchQueueItems.count)",
                icon: "list.bullet.clipboard",
                subtitle: "\(highPriorityDispatchCount) high priority",
                accentColor: .orange,
                trend: highPriorityDispatchCount > 0
                    ? .up
                    : .neutral
            )

            DashboardStatCard(
                title: "Capacity",
                value: averageUtilization.formatted(
                    .percent.precision(.fractionLength(0))
                ),
                icon: "gauge.with.dots.needle.67percent",
                subtitle: capacitySubtitle,
                accentColor: capacityColor,
                trend: averageUtilization >= 0.85
                    ? .up
                    : .neutral
            )
        }
    }

    // MARK: - Technician Status

    private var technicianSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Technician Status",
                systemImage: "person.2.fill"
            )

            if technicianModels.isEmpty {
                emptyCard(
                    title: "No active technicians",
                    message: "Add active technician employees to begin tracking daily capacity."
                )
            } else {
                ForEach(technicianModels) { technician in
                    TechnicianStatusCard(model: technician)
                }
            }
        }
    }

    // MARK: - Dispatch Queue

    private var dispatchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Dispatch Queue",
                systemImage: "list.bullet.clipboard.fill"
            )

            if dispatchQueueItems.isEmpty {
                emptyCard(
                    title: "Dispatch queue is clear",
                    message: "All active jobs currently have a primary technician assignment."
                )
            } else {
                ForEach(dispatchQueueItems) { item in
                    DispatchQueueCard(
                        item: item,
                        technicianOptions: technicianOptions(
                            for: item.jobID
                        ),
                        onAssign: { technicianID in
                            assignTechnician(
                                technicianID,
                                to: item.jobID
                            )
                        }
                    )
                }
            }
        }
    }

    // MARK: - Capacity

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Capacity",
                systemImage: "chart.bar.fill"
            )

            CapacityForecastCard(
                forecasts: capacityForecasts,
                subtitle: "Next \(forecastDayCount) operating days"
            )
        }
    }

    // MARK: - Revenue

    private var revenueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Revenue",
                systemImage: "dollarsign.circle.fill"
            )

            RevenueSummaryCard(
                summary: revenueSummary,
                subtitle: "Today"
            )
        }
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Recommendations",
                systemImage: "sparkles"
            )

            if recommendationItems.isEmpty {
                emptyCard(
                    title: "No recommendations",
                    message: "New recommendations will appear when a job needs dispatch attention."
                )
            } else {
                ForEach(
                    Array(
                        zip(
                            dispatchJobs,
                            recommendationItems
                        )
                    ),
                    id: \.0.id
                ) { job, recommendation in
                    RecommendationCard(
                        item: recommendation,
                        action: bestDecision(for: job) == nil
                            ? nil
                            : {
                                assignRecommendedTechnician(
                                    to: job.id
                                )
                            }
                    )
                }
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
            bestDecision(for: $0)
        }
        .first {
            $0.employee.id == employee.id
        }
        .map {
            Double($0.confidencePercentage) / 100
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
        let decision = bestDecision(for: job)

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
                decision?.employee.displayName,
            confidence: Double(
                decision?.confidencePercentage ?? 0
            ) / 100
        )
    }

    // MARK: - Dispatch Actions

    private func bestDecision(
        for job: JobRecord
    ) -> DispatchDecision? {
        DispatchDecisionEngine.bestDecision(
            for: job,
            employees: activeTechnicians,
            jobs: activeJobs,
            policy: .balancedWorkload,
            onOrAfter: max(job.scheduledDate, now),
            calendar: calendar
        )
    }

    private func rankedDecisions(
        for job: JobRecord
    ) -> [DispatchDecision] {
        DispatchDecisionEngine.rankedDecisions(
            for: job,
            employees: activeTechnicians,
            jobs: activeJobs,
            policy: .balancedWorkload,
            onOrAfter: max(job.scheduledDate, now),
            calendar: calendar
        )
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

        let decisions = rankedDecisions(for: job)
        let decisionByEmployeeID = Dictionary(
            uniqueKeysWithValues: decisions.map {
                ($0.employee.id, $0)
            }
        )
        let recommendedID = decisions.first?.employee.id

        return activeTechnicians
            .map { technician in
                let decision = decisionByEmployeeID[technician.id]

                return DispatchTechnicianOption(
                    id: technician.id,
                    name: technician.displayName,
                    confidence: Double(
                        decision?.confidencePercentage ?? 0
                    ) / 100,
                    proposedStart: decision?.opening.start
                        ?? job.scheduledDate,
                    isRecommended: technician.id == recommendedID,
                    hasConflictFreeOpening: decision != nil
                )
            }
            .sorted { first, second in
                if first.isRecommended != second.isRecommended {
                    return first.isRecommended
                }
                if first.hasConflictFreeOpening != second.hasConflictFreeOpening {
                    return first.hasConflictFreeOpening
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
            var job = activeJobs.first(where: {
                $0.id == jobID
            }),
            let decision = bestDecision(for: job)
        else {
            return
        }

        job.primaryTechnicianID = decision.employee.id
        job.scheduledDate = decision.opening.start

        if job.status == .toBeScheduled {
            job.status = .assigned
        }

        store.updateJob(job)
    }

    /// Assigns the technician selected by the dispatcher. When that technician
    /// has a conflict-free recommendation, PFSS adopts the proposed opening.
    /// A manual override keeps the job's existing scheduled date so the human
    /// decision is never silently moved to another time.
    private func assignTechnician(
        _ technicianID: UUID,
        to jobID: UUID?
    ) {
        guard let jobID,
              var job = activeJobs.first(where: { $0.id == jobID }),
              activeTechnicians.contains(where: { $0.id == technicianID }) else {
            return
        }

        let selectedDecision = rankedDecisions(for: job).first {
            $0.employee.id == technicianID
        }

        job.primaryTechnicianID = technicianID

        if let selectedDecision {
            job.scheduledDate = selectedDecision.opening.start
        }

        if job.status == .toBeScheduled {
            job.status = .assigned
        }

        store.updateJob(job)
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
        if job.scheduledDate < startOfToday {
            return .emergency
        }

        if calendar.isDate(
            job.scheduledDate,
            inSameDayAs: now
        ) {
            return .high
        }

        guard let threeDaysFromNow = calendar.date(
            byAdding: .day,
            value: 3,
            to: startOfToday
        ) else {
            return .normal
        }

        if job.scheduledDate < threeDaysFromNow {
            return .normal
        }

        return .low
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

    private func forecastDayName(
        for date: Date,
        dayOffset: Int
    ) -> String {
        switch dayOffset {
        case 0:
            return "Today"

        case 1:
            return "Tomorrow"

        default:
            return date.formatted(
                .dateTime.weekday(.wide)
            )
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

    private func sectionHeader(
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2.bold())
    }

    private func emptyCard(
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .dashboardCardStyle()
    }

    private func objectWillChangeRefresh() async {
        await Task.yield()
    }
}

#Preview {
    OperationsView()
        .environmentObject(AppDataStore())
}
