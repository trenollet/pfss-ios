//
//  AppDataStore.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation
import Combine

@MainActor
final class AppDataStore: ObservableObject {
    private let fieldOperationsEngine = FieldOperationsEngine()
    let assignmentStore: AssignmentStore
    let assignmentEngine: AssignmentEngine
    let dispatchEngine: DispatchEngine
    private var assignmentObservation: AnyCancellable?
    @Published var customers: [Customer] = [] {
        didSet { saveData() }
    }
    @Published var sites: [CustomerSite] = [] {
        didSet { saveData() }
    }
    @Published var leads: [Lead] = [] {
        didSet { saveData() }
    }
    @Published var estimates: [EstimateRecord] = [] {
        didSet { saveData() }
    }
    @Published var jobs: [JobRecord] = [] {
        didSet { saveData() }
    }
    @Published var invoices: [InvoiceRecord] = [] {
        didSet { saveData() }
    }
    @Published var businessProfile = BusinessProfile() {
        didSet { saveData() }
    }
    @Published var serviceCatalogItems: [ServiceCatalogItem] = [] {
        didSet { saveData() }
    }
    @Published var recommendationRules: [RecommendationRule] = [] {
        didSet { saveData() }
    }
    @Published var employees: [EmployeeRecord] = [] {
        didSet { saveData() }
    }
    
    var activeCustomers: [Customer] {
        customers.filter { $0.lifecycleStatus == .active }
    }

    var activeSites: [CustomerSite] {
        sites.filter { $0.lifecycleStatus == .active }
    }

    var activeLeads: [Lead] {
        leads.filter { $0.lifecycleStatus == .active }
    }

    var activeEstimates: [EstimateRecord] {
        estimates.filter { $0.lifecycleStatus == .active }
    }
    
    var activeEmployees: [EmployeeRecord] {
        employees.filter {
            $0.isActive &&
            $0.lifecycleStatus == .active
        }
    }
    var archivedEmployees: [EmployeeRecord] {
        employees.filter {
            $0.lifecycleStatus == .archived
        }
    }
    var archivedCustomers: [Customer] {
        customers.filter { $0.lifecycleStatus == .archived }
    }

    var archivedSites: [CustomerSite] {
        sites.filter { $0.lifecycleStatus == .archived }
    }

    var archivedLeads: [Lead] {
        leads.filter { $0.lifecycleStatus == .archived }
    }

    var archivedEstimates: [EstimateRecord] {
        estimates.filter { $0.lifecycleStatus == .archived }
    }
    
    var activeJobs: [JobRecord] {
        jobs.filter { $0.lifecycleStatus == .active }
    }

    var archivedJobs: [JobRecord] {
        jobs.filter { $0.lifecycleStatus == .archived }
    }
    var activeInvoices: [InvoiceRecord] {
        invoices.filter { $0.lifecycleStatus == .active }
    }

    var archivedInvoices: [InvoiceRecord] {
        invoices.filter { $0.lifecycleStatus == .archived }
    }
    
    var activeServiceCatalogItems: [ServiceCatalogItem] {
        serviceCatalogItems.filter { $0.lifecycleStatus == .active }
    }

    var archivedServiceCatalogItems: [ServiceCatalogItem] {
        serviceCatalogItems.filter { $0.lifecycleStatus == .archived }
    }
    private var nextCustomerNumber = 1 {
        didSet { saveData() }
    }

    private var recordSequencesByMonth: [String: Int] = [:] {
        didSet { saveData() }
    }

    private let saveFileName = "pps-field-manager-data.json"

    init() {
        let assignmentStore = AssignmentStore()
        let assignmentEngine = AssignmentEngine(store: assignmentStore)
        self.assignmentStore = assignmentStore
        self.assignmentEngine = assignmentEngine
        self.dispatchEngine = DispatchEngine(
            assignmentEngine: assignmentEngine,
            policy: DispatchPolicy(operatingMode: .hybrid)
        )

        loadData()
        materializePendingRecurringJobs()
        synchronizeAssignmentsFromJobs()

        assignmentStore.onAssignmentsChanged = { [weak self] assignments in
            self?.synchronizeJobsFromAssignments(assignments)
            self?.saveData()
        }
        assignmentObservation = assignmentStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        synchronizeJobsFromAssignments(assignmentStore.assignments)
    }

    func generateCustomerNumber() -> String {
        let number = String(format: "PPS-%06d", nextCustomerNumber)
        nextCustomerNumber += 1
        return number
    }

    func updateCustomer(_ customer: Customer) {
        if let index = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[index] = customer
        }
    }
    
    func generateLeadNumber(for date: Date = Date()) -> String {
        generateMonthlyNumber(prefix: "LD", date: date)
    }

    func generateEstimateNumber(for date: Date = Date()) -> String {
        generateMonthlyNumber(prefix: "EST", date: date)
    }

    func updateEstimate(_ estimate: EstimateRecord) {
        if let index = estimates.firstIndex(where: { $0.id == estimate.id }) {
            estimates[index] = estimate
        }
    }
    
    func generateInvoiceNumber(for date: Date = Date()) -> String {
        generateMonthlyNumber(prefix: "INV", date: date)
    }

    func generateReceiptNumber(for date: Date = Date()) -> String {
        generateMonthlyNumber(prefix: "RCT", date: date)
    }

    func generateJobNumber(for date: Date = Date()) -> String {
        generateMonthlyNumber(prefix: "JOB", date: date)
    }

    func addCustomer(_ customer: Customer) {
        customers.append(customer)
    }

    func addSite(_ site: CustomerSite) {
        sites.append(site)
    }
    
    func updateSite(_ site: CustomerSite) {
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        }
    }
    func addLead(_ lead: Lead) {
        leads.append(lead)
    }

    func updateLead(_ lead: Lead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index] = lead
        }
    }
    
    func addEstimate(_ estimate: EstimateRecord) {
        estimates.append(estimate)
    }
    
    func addEmployee(
        _ employee: EmployeeRecord
    ) {
        employees.append(employee)
    }

    func updateEmployee(
        _ employee: EmployeeRecord
    ) {
        guard let index = employees.firstIndex(where: {
            $0.id == employee.id
        }) else {
            return
        }

        employees[index] = employee
    }

    func archiveEmployee(
        _ employee: EmployeeRecord
    ) {
        guard let index = employees.firstIndex(where: {
            $0.id == employee.id
        }) else {
            return
        }

        employees[index].lifecycleStatus = .archived
        employees[index].isActive = false
    }

    func restoreEmployee(
        _ employee: EmployeeRecord
    ) {
        guard let index = employees.firstIndex(where: {
            $0.id == employee.id
        }) else {
            return
        }

        employees[index].lifecycleStatus = .active
        employees[index].isActive = true
    }
    
    func addRecommendationRule(_ rule: RecommendationRule) {
        recommendationRules.append(rule)
    }

    func updateRecommendationRule(_ rule: RecommendationRule) {
        if let index = recommendationRules.firstIndex(where: { $0.id == rule.id }) {
            recommendationRules[index] = rule
        }
    }

    func deleteRecommendationRule(_ rule: RecommendationRule) {
        recommendationRules.removeAll { $0.id == rule.id }
    }
    func sites(for customerNumber: String) -> [CustomerSite] {
        sites.filter { $0.customerNumber == customerNumber }
    }

    func archiveCustomer(_ customer: Customer) {
        var updated = customer
        updated.lifecycleStatus = .archived
        updateCustomer(updated)
    }

    func archiveSite(_ site: CustomerSite) {
        var updated = site
        updated.lifecycleStatus = .archived
        updateSite(updated)
    }

    func archiveLead(_ lead: Lead) {
        var updated = lead
        updated.lifecycleStatus = .archived
        updateLead(updated)
    }

    func archiveEstimate(_ estimate: EstimateRecord) {
        var updated = estimate
        updated.lifecycleStatus = .archived
        updateEstimate(updated)
    }
    
    func restoreCustomer(_ customer: Customer) {
        var updated = customer
        updated.lifecycleStatus = .active
        updateCustomer(updated)
    }

    func restoreSite(_ site: CustomerSite) {
        var updated = site
        updated.lifecycleStatus = .active
        updateSite(updated)
    }

    func restoreLead(_ lead: Lead) {
        var updated = lead
        updated.lifecycleStatus = .active
        updateLead(updated)
    }

    func restoreEstimate(_ estimate: EstimateRecord) {
        var updated = estimate
        updated.lifecycleStatus = .active
        updateEstimate(updated)
    }
    
    func addJob(_ job: JobRecord) {
        var storedJob = job
        prepareRecurrenceIdentity(for: &storedJob)
        jobs.append(storedJob)
        ensureNextOccurrence(after: storedJob, includeInitialOccurrence: true)
        synchronizeAssignmentsFromJobs()
    }

    func updateJob(_ job: JobRecord) {
        if let originalIndex = jobs.firstIndex(where: { $0.id == job.id }) {
            let previousJob = jobs[originalIndex]

            if previousJob.isRecurring && !job.isRecurring {
                removeUnstartedFutureOccurrences(after: previousJob)
            }

            var storedJob = job
            prepareRecurrenceIdentity(for: &storedJob)

            guard let currentIndex = jobs.firstIndex(where: {
                $0.id == storedJob.id
            }) else {
                return
            }

            jobs[currentIndex] = storedJob
            ensureNextOccurrence(
                after: storedJob,
                includeInitialOccurrence: storedJob.recurrenceSequence == 0
            )
            synchronizeAssignmentsFromJobs()
        }
    }

    // MARK: - Assignment Integration

    func assignment(forJobID jobID: UUID) -> Assignment? {
        assignmentEngine.assignmentsForJob(jobID)
            .first { $0.lifecycleStatus == .active }
    }

    /// Creates the V1 operational record for eligible legacy and new jobs.
    /// Phase 14 intentionally maintains one active Assignment per Job.
    @discardableResult
    func synchronizeAssignmentsFromJobs() -> Int {
        var createdCount = 0

        for job in jobs where isAssignmentEligible(job) {
            if let existingAssignment = assignment(forJobID: job.id) {
                synchronizeRecurringSchedule(
                    from: job,
                    to: existingAssignment
                )
                continue
            }

            do {
                _ = try assignmentEngine.createAssignment(
                    jobID: job.id,
                    jobNumber: job.jobNumber,
                    customerNumber: job.customerNumber,
                    siteID: job.siteID,
                    scheduling: assignmentScheduling(for: job),
                    primaryTechnicianID: job.primaryTechnicianID,
                    supportingTechnicianIDs: [job.secondaryTechnicianID].compactMap { $0 },
                    priority: assignmentPriority(for: job),
                    source: job.isRecurring ? .recurringWork : .jobConversion,
                    note: "Created from the existing PFSS job workflow."
                )
                createdCount += 1
            } catch {
                print("Failed to create assignment for \(job.jobNumber): \(error.localizedDescription)")
            }
        }

        return createdCount
    }

    /// A generated recurring Job can be moved off a weekend after its
    /// Assignment already exists in persisted data. Keep the unstarted
    /// recurring Assignment aligned so the Dispatch Queue and My Day use the
    /// corrected business-day date instead of restoring the old weekend date.
    private func synchronizeRecurringSchedule(
        from job: JobRecord,
        to assignment: Assignment
    ) {
        guard job.isRecurring,
              assignment.creationSource == .recurringWork,
              assignment.scheduling.mode == .fixedTime,
              assignment.status == .scheduled || assignment.status == .dispatched,
              assignment.scheduling.operationalDate != job.scheduledDate else {
            return
        }

        var scheduling = assignment.scheduling
        scheduling.serviceDate = job.scheduledDate
        scheduling.fixedStartDate = job.scheduledDate

        do {
            _ = try assignmentEngine.reschedule(
                assignmentID: assignment.id,
                scheduling: scheduling,
                note: "Recurring occurrence moved to the nearest PFSS business day."
            )
        } catch {
            print(
                "Failed to align recurring assignment \(assignment.assignmentNumber): " +
                error.localizedDescription
            )
        }
    }

    /// Applies a Dispatch Board decision through AssignmentEngine and mirrors
    /// the operational owner/start time to the related Job record.
    @discardableResult
    func assignTechnician(
        _ technicianID: UUID,
        toJobID jobID: UUID,
        scheduledStart: Date? = nil,
        isHumanOverride: Bool = false
    ) throws -> Assignment {
        guard var job = jobs.first(where: { $0.id == jobID }) else {
            throw AssignmentIntegrationError.jobNotFound(jobID)
        }

        if assignment(forJobID: jobID) == nil {
            synchronizeAssignmentsFromJobs()
        }

        guard let assignment = assignment(forJobID: jobID) else {
            throw AssignmentIntegrationError.assignmentUnavailable(jobID)
        }

        guard let technician = activeEmployees.first(where: {
            $0.id == technicianID
        }) else {
            throw AssignmentIntegrationError.employeeNotFound(technicianID)
        }

        let result = try dispatchEngine.assignPrimaryTechnician(
            assignmentID: assignment.id,
            technician: technician,
            actor: .system,
            scheduledStart: scheduledStart,
            note: assignment.primaryTechnicianID == nil
                ? "Assigned from the Operations dispatch queue."
                : "Dispatcher reassigned the primary technician.",
            isHumanOverride: isHumanOverride
        )

        if let scheduledStart {
            job.scheduledDate = scheduledStart
        }

        job.primaryTechnicianID = technicianID
        if job.status == .toBeScheduled || job.status == .scheduled {
            job.status = .assigned
        }

        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        }

        return result.assignment
    }

    /// Keeps the established Job-based scheduling and My Day screens aligned
    /// while Assignment remains the authoritative operational record.
    private func synchronizeJobsFromAssignments(_ assignments: [Assignment]) {
        var synchronizedJobs = jobs
        var didChange = false

        for assignment in assignments {
            guard let index = synchronizedJobs.firstIndex(where: {
                $0.id == assignment.jobID
            }) else {
                continue
            }

            var job = synchronizedJobs[index]
            let original = job

            job.primaryTechnicianID = assignment.primaryTechnicianID
            job.secondaryTechnicianID = assignment.supportingTechnicianIDs.first

            if let operationalDate = assignment.scheduling.operationalDate {
                job.scheduledDate = operationalDate
            }

            switch assignment.status {
            case .scheduled:
                job.status = assignment.primaryTechnicianID == nil
                    ? .scheduled
                    : .assigned
                job.workflowState = .notStarted

            case .dispatched:
                job.status = .assigned
                job.workflowState = .notStarted

            case .enRoute:
                job.status = .inProgress
                job.workflowState = .traveling

            case .onSite:
                job.status = .inProgress
                job.workflowState = .arrived

            case .workComplete:
                job.status = .inProgress
                job.workflowState = .workComplete

            case .invoiceReady:
                job.status = .inProgress
                job.workflowState = .invoiceCreated

            case .closed:
                job.status = .completed
                job.workflowState = .completed
                job.completedDate = assignment.closedDate ?? job.completedDate

            case .cancelled:
                job.status = .cancelled
                job.workflowState = .cancelled
            }

            if job.primaryTechnicianID != original.primaryTechnicianID ||
                job.secondaryTechnicianID != original.secondaryTechnicianID ||
                job.scheduledDate != original.scheduledDate ||
                job.status != original.status ||
                job.workflowState != original.workflowState ||
                job.completedDate != original.completedDate {
                synchronizedJobs[index] = job
                didChange = true
            }
        }

        if didChange {
            jobs = synchronizedJobs
        }
    }

    private func isAssignmentEligible(_ job: JobRecord) -> Bool {
        job.lifecycleStatus == .active &&
            job.status != .completed &&
            job.status != .cancelled
    }

    private func assignmentScheduling(for job: JobRecord) -> AssignmentScheduling {
        AssignmentScheduling(
            mode: .fixedTime,
            serviceDate: job.scheduledDate,
            fixedStartDate: job.scheduledDate,
            estimatedDurationMinutes: max(
                SchedulingEngine.scheduledMinutes(for: job),
                15
            ),
            isCustomerConfirmed: true,
            schedulingNotes: "Imported from Job \(job.jobNumber)."
        )
    }

    private func assignmentPriority(for job: JobRecord) -> AssignmentPriority {
        let today = Calendar.current.startOfDay(for: Date())
        if job.scheduledDate < today { return .emergency }
        if Calendar.current.isDateInToday(job.scheduledDate) { return .high }
        return .normal
    }

    private func removeUnstartedFutureOccurrences(after job: JobRecord) {
        guard let seriesID = job.recurrenceSeriesID else { return }

        jobs.removeAll {
            $0.id != job.id &&
            $0.recurrenceSeriesID == seriesID &&
            $0.recurrenceSequence > job.recurrenceSequence &&
            ($0.status == .toBeScheduled || $0.status == .scheduled)
        }
    }

    /// Keeps one upcoming occurrence available for dispatch without generating
    /// an unlimited series of future jobs.
    private func ensureNextOccurrence(
        after job: JobRecord,
        includeInitialOccurrence: Bool
    ) {
        guard job.lifecycleStatus == .active,
              job.isRecurring,
              let frequency = job.recurrenceFrequency,
              includeInitialOccurrence || job.status == .completed else {
            return
        }

        let seriesID = job.recurrenceSeriesID ?? job.id
        let nextSequence = job.recurrenceSequence + 1
        let anchorDate = jobs.first(where: {
            $0.recurrenceSeriesID == seriesID &&
            $0.recurrenceSequence == 0
        })?.scheduledDate ?? job.scheduledDate

        guard let nextDate = frequency.occurrenceDate(
            from: anchorDate,
            occurrence: nextSequence
        ) else {
            return
        }

        if let existingIndex = jobs.firstIndex(where: {
            $0.recurrenceSeriesID == seriesID &&
            $0.recurrenceSequence == nextSequence
        }) {
            guard jobs[existingIndex].status == .toBeScheduled ||
                    jobs[existingIndex].status == .scheduled else {
                return
            }
            jobs[existingIndex].recurrenceFrequency = frequency
            jobs[existingIndex].scheduledDate = nextDate
            return
        }

        var nextJob = job
        nextJob.id = UUID()
        nextJob.jobNumber = generateJobNumber(for: nextDate)
        nextJob.primaryTechnicianID = nil
        nextJob.secondaryTechnicianID = nil
        nextJob.scheduledDate = nextDate
        nextJob.setupStartDate = nil
        nextJob.completedDate = nil
        nextJob.status = .toBeScheduled
        nextJob.workflowState = .notStarted
        nextJob.timelineEvents = []
        nextJob.createdDate = Date()
        nextJob.lifecycleStatus = .active
        nextJob.recurrenceSeriesID = seriesID
        nextJob.recurrenceSequence = nextSequence
        jobs.append(nextJob)
    }

    private func prepareRecurrenceIdentity(for job: inout JobRecord) {
        guard job.isRecurring, job.recurrenceFrequency != nil else {
            job.recurrenceFrequency = nil
            job.recurrenceSeriesID = nil
            job.recurrenceSequence = 0
            return
        }

        if job.recurrenceSeriesID == nil {
            job.recurrenceSeriesID = job.id
        }
    }

    private func materializePendingRecurringJobs() {
        let candidates = jobs.filter {
            $0.isRecurring &&
            $0.recurrenceFrequency != nil &&
            ($0.recurrenceSequence == 0 || $0.status == .completed)
        }

        for candidate in candidates {
            var normalized = candidate
            prepareRecurrenceIdentity(for: &normalized)
            if let index = jobs.firstIndex(where: { $0.id == normalized.id }) {
                jobs[index] = normalized
            }
            ensureNextOccurrence(
                after: normalized,
                includeInitialOccurrence: normalized.recurrenceSequence == 0
            )
        }
    }

    @discardableResult
    func addTechnicianNote(
        jobID: UUID,
        text: String,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> JobTimelineEvent? {
        let trimmedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty,
              let index = jobs.firstIndex(where: {
                  $0.id == jobID
              }) else {
            return nil
        }

        let event = JobTimelineEvent(
            type: .note,
            title: "Technician Note",
            timestamp: timestamp,
            employeeID: employeeID,
            note: trimmedText
        )

        jobs[index].timelineEvents.append(event)
        return event
    }
    func workflowContext(
        for jobID: UUID
    ) -> JobWorkflowContext? {
        guard let job = jobs.first(where: {
            $0.id == jobID
        }) else {
            return nil
        }

        let invoice = invoices.first {
            $0.jobNumber == job.jobNumber
        }

        return fieldOperationsEngine.context(
            for: job,
            invoice: invoice
        )
    }

    @discardableResult
    func performWorkflowAction(
        jobID: UUID,
        action: JobWorkflowAction,
        employeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        if action == .createInvoice {
            let created = createInvoiceFromJob(jobID: jobID) != nil
            if created {
                synchronizeAssignmentWorkflow(
                    jobID: jobID,
                    action: action,
                    employeeID: employeeID,
                    at: timestamp
                )
            }
            return created
        }

        if action == .recordPayment {
            jobs[index] =
                fieldOperationsEngine.recordPaymentReceived(
                    for: jobs[index],
                    employeeID: employeeID,
                    at: timestamp
                )

            return true
        }

        guard let updated =
                fieldOperationsEngine.transition(
                    job: jobs[index],
                    action: action,
                    employeeID: employeeID,
                    at: timestamp
                )
        else {
            return false
        }

        jobs[index] = updated
        synchronizeAssignmentWorkflow(
            jobID: jobID,
            action: action,
            employeeID: employeeID,
            at: timestamp
        )
        return true
    }

    /// Keeps the Assignment lifecycle aligned with the established My Day
    /// field workflow without duplicating lifecycle rules outside the engine.
    private func synchronizeAssignmentWorkflow(
        jobID: UUID,
        action: JobWorkflowAction,
        employeeID: UUID?,
        at timestamp: Date
    ) {
        guard var assignment = assignment(forJobID: jobID) else { return }

        do {
            switch action {
            case .startTravel:
                if assignment.status == .scheduled {
                    assignment = try assignmentEngine.dispatch(
                        assignmentID: assignment.id,
                        actorEmployeeID: employeeID,
                        note: "Dispatched by the My Day workflow.",
                        at: timestamp
                    )
                }
                if assignment.status == .dispatched {
                    _ = try assignmentEngine.beginTravel(
                        assignmentID: assignment.id,
                        actorEmployeeID: employeeID,
                        at: timestamp
                    )
                }

            case .markArrived:
                if assignment.status == .enRoute {
                    _ = try assignmentEngine.arrive(
                        assignmentID: assignment.id,
                        actorEmployeeID: employeeID,
                        at: timestamp
                    )
                }

            case .finishWork:
                if assignment.status == .onSite {
                    _ = try assignmentEngine.complete(
                        assignmentID: assignment.id,
                        actorEmployeeID: employeeID,
                        at: timestamp
                    )
                }

            case .createInvoice:
                if assignment.status == .workComplete {
                    _ = try assignmentEngine.markInvoiceReady(
                        assignmentID: assignment.id,
                        actorEmployeeID: employeeID,
                        at: timestamp
                    )
                }

            case .completeJob:
                if assignment.status == .workComplete ||
                    assignment.status == .invoiceReady {
                    _ = try assignmentEngine.close(
                        assignmentID: assignment.id,
                        actorEmployeeID: employeeID,
                        at: timestamp
                    )
                }

            case .startSetup, .startWork, .startPackUp,
                 .recordPayment, .viewDetails:
                break
            }
        } catch {
            print("Failed to synchronize Assignment workflow: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func startSetup(
        jobID: UUID,
        employeeID: UUID? = nil,
        startedAt: Date = Date()
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        guard jobs[index].status == .toBeScheduled ||
              jobs[index].status == .scheduled ||
              jobs[index].status == .assigned
        else {
            return false
        }

        var updated = jobs[index]
        updated.status = .inProgress
        updated.workflowState = .settingUp

        if updated.setupStartDate == nil {
            updated.setupStartDate = startedAt
        }

        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .setupStarted,
                title: "Setup Started",
                timestamp: startedAt,
                employeeID: employeeID
            )
        )

        jobs[index] = updated
        return true
    }

    @discardableResult
    func startJob(
        jobID: UUID,
        employeeID: UUID? = nil,
        startedAt: Date = Date()
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        guard jobs[index].status == .inProgress,
              jobs[index].workflowState == .settingUp
        else {
            return false
        }

        var updated = jobs[index]
        updated.workflowState = .working
        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .workStarted,
                title: "Job Started",
                timestamp: startedAt,
                employeeID: employeeID
            )
        )

        jobs[index] = updated
        return true
    }

    @discardableResult
    func completeJob(
        jobID: UUID,
        employeeID: UUID? = nil,
        completedAt: Date = Date()
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        guard jobs[index].status == .inProgress,
              jobs[index].workflowState == .working
        else {
            return false
        }

        var updated = jobs[index]
        // Field work is complete, but the overall workflow is not closed yet.
        // Keep the job reportable as completed while leaving the workflow at
        // workComplete so Create Invoice remains the next valid action.
        updated.workflowState = .workComplete
        updated.status = .completed

        if updated.completedDate == nil {
            updated.completedDate = completedAt
        }

        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .jobCompleted,
                title: "Job Completed",
                timestamp: completedAt,
                employeeID: employeeID
            )
        )
        jobs[index] = updated
        return true
    }

    func archiveJob(_ job: JobRecord) {
        var updated = job
        updated.lifecycleStatus = .archived
        updateJob(updated)
    }

    func restoreJob(_ job: JobRecord) {
        var updated = job
        updated.lifecycleStatus = .active
        updateJob(updated)
    }
    
    func addServiceCatalogItem(_ item: ServiceCatalogItem) {
        serviceCatalogItems.append(item)
    }

    func updateServiceCatalogItem(_ item: ServiceCatalogItem) {
        if let index = serviceCatalogItems.firstIndex(where: { $0.id == item.id }) {
            serviceCatalogItems[index] = item
        }
    }
    func recordCatalogItemUsed(_ item: ServiceCatalogItem) {
        if let index = serviceCatalogItems.firstIndex(where: { $0.id == item.id }) {
            serviceCatalogItems[index].usageCount += 1
            serviceCatalogItems[index].lastUsedDate = Date()
        }
    }
    func archiveServiceCatalogItem(_ item: ServiceCatalogItem) {
        var updated = item
        updated.lifecycleStatus = .archived
        updateServiceCatalogItem(updated)
    }

    func restoreServiceCatalogItem(_ item: ServiceCatalogItem) {
        var updated = item
        updated.lifecycleStatus = .active
        updateServiceCatalogItem(updated)
    }
    func addInvoice(_ invoice: InvoiceRecord) {
        invoices.append(invoice)
    }

    func updateInvoice(_ invoice: InvoiceRecord) {
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[index] = invoice
        }
    }

    func invoice(for job: JobRecord) -> InvoiceRecord? {
        invoices.first { invoice in
            invoice.jobNumber == job.jobNumber
        }
    }

    func invoice(forJobID jobID: UUID) -> InvoiceRecord? {
        guard let job = jobs.first(where: { $0.id == jobID }) else {
            return nil
        }

        return invoice(for: job)
    }

    func archiveInvoice(_ invoice: InvoiceRecord) {
        var updated = invoice
        updated.lifecycleStatus = .archived
        updateInvoice(updated)
    }

    func restoreInvoice(_ invoice: InvoiceRecord) {
        var updated = invoice
        updated.lifecycleStatus = .active
        updateInvoice(updated)
    }
    func convertLeadToCustomer(_ lead: Lead) {
        guard !customers.contains(where: { $0.phone == lead.phone && !$0.phone.isEmpty }) else {
            return
        }

        let customer = Customer(
            customerNumber: generateCustomerNumber(),
            businessName: lead.businessName,
            contactName: lead.contactName,
            phone: lead.phone,
            email: lead.email,
            leadSource: lead.leadSource,
            estimateStatus: .approved,
            assignedEmployee: lead.assignedSalesperson,
            followUpDate: lead.followUpDate
        )

        customers.append(customer)

        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index].status = .converted
        }
    }

    func createJobFromEstimate(_ estimate: EstimateRecord) {
        let job = JobRecord(
            jobNumber: generateJobNumber(),
            customerNumber: estimate.customerNumber,
            siteID: estimate.siteID,
            estimateNumber: estimate.estimateNumber,
            serviceType: estimate.serviceType,
            otherService: estimate.otherService,
            subtotal: estimate.subtotal,
            discount: estimate.discount,
            total: estimate.total,
            primaryTechnicianID: nil,
            secondaryTechnicianID: nil,
            scheduledDate: Date(),
            completedDate: nil,
            status: .toBeScheduled,
            workNotes: estimate.serviceDetails,
            isRecurring: false,
            createdDate: Date()
        )

        jobs.append(job)

        if let index = estimates.firstIndex(where: { $0.id == estimate.id }) {
            estimates[index].status = .converted
        }
    }
    
    @discardableResult
    func createInvoiceFromJob(_ job: JobRecord) -> InvoiceRecord? {
        createInvoiceFromJob(jobID: job.id)
    }

    /// Creates or returns the invoice using the persisted job as the source of
    /// truth. Using the job ID prevents an older view copy from blocking or
    /// reversing the workflow transition.
    @discardableResult
    func createInvoiceFromJob(jobID: UUID) -> InvoiceRecord? {
        guard let jobIndex = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return nil
        }

        let persistedJob = jobs[jobIndex]

        if let existingInvoice = invoices.first(where: {
            $0.jobNumber == persistedJob.jobNumber
        }) {
            if jobs[jobIndex].workflowState != .invoiceCreated &&
               jobs[jobIndex].workflowState != .paymentReceived {
                jobs[jobIndex].workflowState = .invoiceCreated
            }
            return existingInvoice
        }

        // Field completion may be represented by the status, the workflow
        // state, or both. Accept either representation for compatibility with
        // jobs saved during earlier Brick 9 test builds.
        let fieldWorkIsComplete =
            persistedJob.status == .completed ||
            persistedJob.workflowState == .workComplete ||
            persistedJob.workflowState == .completed

        guard fieldWorkIsComplete else {
            return nil
        }

        let issueDate = Date()
        let dueDate = Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: issueDate
        ) ?? issueDate

        let updatedLineItems = PricingCalculator.updatedLineItems(
            persistedJob.lineItems
        )
        let subtotal = PricingCalculator.subtotal(
            for: updatedLineItems
        )
        let total = PricingCalculator.total(
            subtotal: subtotal,
            discount: persistedJob.discount
        )

        let invoice = InvoiceRecord(
            invoiceNumber: generateInvoiceNumber(),
            customerNumber: persistedJob.customerNumber,
            siteID: persistedJob.siteID,
            jobNumber: persistedJob.jobNumber,
            lineItems: updatedLineItems,
            subtotal: subtotal,
            discount: persistedJob.discount,
            total: total,
            amountPaid: 0,
            balanceDue: total,
            status: .draft,
            issueDate: issueDate,
            dueDate: dueDate,
            paidDate: nil,
            notes: persistedJob.workNotes
        )

        invoices.append(invoice)

        jobs[jobIndex].status = .completed
        jobs[jobIndex].workflowState = .invoiceCreated

        if !jobs[jobIndex].timelineEvents.contains(where: {
            $0.type == .invoiceCreated
        }) {
            jobs[jobIndex].timelineEvents.append(
                JobTimelineEvent(
                    type: .invoiceCreated,
                    title: "Invoice Created",
                    timestamp: issueDate,
                    employeeID: persistedJob.primaryTechnicianID
                )
            )
        }

        return invoice
    }
    
    func seedRecommendationRulesIfNeeded() {
        guard recommendationRules.isEmpty else { return }

        let catalog = activeServiceCatalogItems

        func item(named name: String) -> ServiceCatalogItem? {
            catalog.first {
                $0.itemName.localizedCaseInsensitiveContains(name)
            }
        }

        guard
            let windows = item(named: "Window"),
            let tracks = item(named: "Track"),
            let screens = item(named: "Screen")
        else {
            return
        }

        recommendationRules.append(
            RecommendationRule(
                triggerCatalogItemID: windows.id,
                recommendedCatalogItemIDs: [
                    tracks.id,
                    screens.id
                ],
                notes: "Default recommendation"
            )
        )
    }
    
    private func generateMonthlyNumber(prefix: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMM"
        let monthPrefix = formatter.string(from: date)

        let sequenceKey = "\(prefix)-\(monthPrefix)"
        let nextSequence = (recordSequencesByMonth[sequenceKey] ?? 0) + 1
        recordSequencesByMonth[sequenceKey] = nextSequence

        return "\(prefix)-\(monthPrefix)-\(String(format: "%05d", nextSequence))"
    }

    private func saveData() {
        let snapshot = AppDataSnapshot(
            customers: customers,
            sites: sites,
            leads: leads,
            estimates: estimates,
            jobs: jobs,
            invoices: invoices,
            businessProfile: businessProfile,
            serviceCatalogItems: serviceCatalogItems,
            nextCustomerNumber: nextCustomerNumber,
            recordSequencesByMonth: recordSequencesByMonth,
            recommendationRules: recommendationRules,
            employees: employees,
            assignments: assignmentStore.assignments
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: saveFileURL(), options: [.atomic])
        } catch {
            print("Failed to save app data: \(error.localizedDescription)")
        }
    }

    private func loadData() {
        let url = saveFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(AppDataSnapshot.self, from: data)

            customers = snapshot.customers
            sites = snapshot.sites
            leads = snapshot.leads
            estimates = snapshot.estimates
            jobs = snapshot.jobs
            invoices = snapshot.invoices
            businessProfile = snapshot.businessProfile
            serviceCatalogItems = snapshot.serviceCatalogItems
            nextCustomerNumber = snapshot.nextCustomerNumber
            recordSequencesByMonth = snapshot.recordSequencesByMonth
            recommendationRules = snapshot.recommendationRules
            employees = snapshot.employees
            try assignmentStore.replaceAll(with: snapshot.assignments)
            seedRecommendationRulesIfNeeded()
        } catch {
            print("Failed to load app data: \(error.localizedDescription)")
        }
    }

    private func saveFileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(saveFileName)
    }
}

private struct AppDataSnapshot: Codable {
    var customers: [Customer]
    var sites: [CustomerSite]
    var leads: [Lead]
    var estimates: [EstimateRecord]
    var jobs: [JobRecord]
    var invoices: [InvoiceRecord]
    var businessProfile: BusinessProfile
    var serviceCatalogItems: [ServiceCatalogItem]
    var nextCustomerNumber: Int
    var recordSequencesByMonth: [String: Int]
    var recommendationRules: [RecommendationRule]
    var employees: [EmployeeRecord] = []
    var assignments: [Assignment] = []

    private enum CodingKeys: String, CodingKey {
        case customers
        case sites
        case leads
        case estimates
        case jobs
        case invoices
        case businessProfile
        case serviceCatalogItems
        case nextCustomerNumber
        case recordSequencesByMonth
        case recommendationRules
        case employees
        case assignments
    }

    init(
        customers: [Customer],
        sites: [CustomerSite],
        leads: [Lead],
        estimates: [EstimateRecord],
        jobs: [JobRecord],
        invoices: [InvoiceRecord],
        businessProfile: BusinessProfile,
        serviceCatalogItems: [ServiceCatalogItem],
        nextCustomerNumber: Int,
        recordSequencesByMonth: [String: Int],
        recommendationRules: [RecommendationRule],
        employees: [EmployeeRecord] = [],
        assignments: [Assignment] = []
    ) {
        self.customers = customers
        self.sites = sites
        self.leads = leads
        self.estimates = estimates
        self.jobs = jobs
        self.invoices = invoices
        self.businessProfile = businessProfile
        self.serviceCatalogItems = serviceCatalogItems
        self.nextCustomerNumber = nextCustomerNumber
        self.recordSequencesByMonth = recordSequencesByMonth
        self.recommendationRules = recommendationRules
        self.employees = employees
        self.assignments = assignments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        customers = try container.decode(
            [Customer].self,
            forKey: .customers
        )

        sites = try container.decode(
            [CustomerSite].self,
            forKey: .sites
        )

        leads = try container.decode(
            [Lead].self,
            forKey: .leads
        )

        estimates = try container.decode(
            [EstimateRecord].self,
            forKey: .estimates
        )

        jobs = try container.decode(
            [JobRecord].self,
            forKey: .jobs
        )

        invoices = try container.decodeIfPresent(
            [InvoiceRecord].self,
            forKey: .invoices
        ) ?? []

        businessProfile = try container.decodeIfPresent(
            BusinessProfile.self,
            forKey: .businessProfile
        ) ?? BusinessProfile()
        
        serviceCatalogItems = try container.decode(
            [ServiceCatalogItem].self,
            forKey: .serviceCatalogItems
        )
        employees = try container.decodeIfPresent(
            [EmployeeRecord].self,
            forKey: .employees
        ) ?? []
        assignments = try container.decodeIfPresent(
            [Assignment].self,
            forKey: .assignments
        ) ?? []
        nextCustomerNumber = try container.decode(
            Int.self,
            forKey: .nextCustomerNumber
        )

        recordSequencesByMonth = try container.decode(
            [String: Int].self,
            forKey: .recordSequencesByMonth
        )

        recommendationRules = try container.decodeIfPresent(
            [RecommendationRule].self,
            forKey: .recommendationRules
        ) ?? []
    }
}

private enum AssignmentIntegrationError: LocalizedError {
    case jobNotFound(UUID)
    case assignmentUnavailable(UUID)
    case employeeNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .jobNotFound:
            return "The related job could not be found."
        case .assignmentUnavailable:
            return "The operational assignment could not be created or loaded."
        case .employeeNotFound:
            return "The selected technician could not be found or is inactive."
        }
    }
}
