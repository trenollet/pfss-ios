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
    let offlineOperationQueue: OfflineOperationQueue
    let offlineSynchronizationMode: OfflineSynchronizationMode
    let offlineConnectivityMonitor: OfflineConnectivityMonitor
    let offlineSynchronizationService: OfflineSynchronizationService?
    private var assignmentObservation: AnyCancellable?
    private var offlineQueueObservation: AnyCancellable?
    @Published var lastOfflineOperationError: String?
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
    /// Accepted or freshly refreshed road routes for the current app session.
    /// Assignment.routeSequence remains the durable source of route order;
    /// these plans retain MapKit leg timing for Timeline presentation.
    @Published var acceptedRoutePlans: [String: RoutePlan] = [:]
    
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

    init(
        offlineOperationQueue: OfflineOperationQueue? = nil,
        offlineSynchronizationMode: OfflineSynchronizationMode = .localOnly,
        offlineConnectivityMonitor: OfflineConnectivityMonitor? = nil,
        offlineSynchronizationAdapter: (any OfflineSynchronizationAdapter)? = nil
    ) {
        let assignmentStore = AssignmentStore()
        let assignmentEngine = AssignmentEngine(store: assignmentStore)
        let operationQueue = offlineOperationQueue ?? OfflineOperationQueue()
        let connectivityMonitor = offlineConnectivityMonitor
            ?? OfflineConnectivityMonitor()
        self.assignmentStore = assignmentStore
        self.assignmentEngine = assignmentEngine
        self.offlineOperationQueue = operationQueue
        self.offlineSynchronizationMode = offlineSynchronizationMode
        self.offlineConnectivityMonitor = connectivityMonitor
        if offlineSynchronizationMode.requiresRemoteQueue,
           let offlineSynchronizationAdapter {
            self.offlineSynchronizationService = OfflineSynchronizationService(
                queue: operationQueue,
                connectivity: connectivityMonitor,
                adapter: offlineSynchronizationAdapter
            )
        } else {
            self.offlineSynchronizationService = nil
        }
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
        offlineQueueObservation = operationQueue.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        synchronizeJobsFromAssignments(assignmentStore.assignments)
    }

    func startOfflineServices() {
        offlineConnectivityMonitor.start()
        offlineSynchronizationService?.start()
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
                synchronizeAssignmentPlanning(
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
    private func synchronizeAssignmentPlanning(
        from job: JobRecord,
        to assignment: Assignment
    ) {
        guard assignment.status == .scheduled || assignment.status == .dispatched else {
            return
        }

        let scheduling = assignmentScheduling(for: job)

        if assignment.scheduling != scheduling {
            do {
                _ = try assignmentEngine.reschedule(
                    assignmentID: assignment.id,
                    scheduling: scheduling,
                    note: "Assignment planning synchronized from Job \(job.jobNumber)."
                )
            } catch {
                print(
                    "Failed to align assignment \(assignment.assignmentNumber): " +
                    error.localizedDescription
                )
            }
        }

        if assignment.priority != job.assignmentPriority {
            do {
                _ = try assignmentEngine.updatePriority(
                    assignmentID: assignment.id,
                    priority: job.assignmentPriority,
                    note: "Priority synchronized from Job \(job.jobNumber)."
                )
            } catch {
                print(
                    "Failed to align priority for \(assignment.assignmentNumber): " +
                    error.localizedDescription
                )
            }
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
                switch assignment.scheduling.mode {
                case .fixedTime, .arrivalWindow:
                    job.scheduledDate = operationalDate
                case .flexibleDay, .deadline:
                    job.scheduledDate = Calendar.current.startOfDay(
                        for: operationalDate
                    )
                }
            }

            job.assignmentSchedulingMode = assignment.scheduling.mode
            job.arrivalWindowEnd = assignment.scheduling.arrivalWindowEnd
            job.completionDeadline = assignment.scheduling.completionDeadline
            job.assignmentPriority = assignment.priority

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
                job.assignmentSchedulingMode != original.assignmentSchedulingMode ||
                job.arrivalWindowEnd != original.arrivalWindowEnd ||
                job.completionDeadline != original.completionDeadline ||
                job.assignmentPriority != original.assignmentPriority ||
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
        let duration = max(
            SchedulingEngine.scheduledMinutes(for: job),
            15
        )

        let serviceDate: Date?
        let fixedStart: Date?
        let windowStart: Date?
        let windowEnd: Date?
        let deadline: Date?

        switch job.assignmentSchedulingMode {
        case .fixedTime:
            serviceDate = job.scheduledDate
            fixedStart = job.scheduledDate
            windowStart = nil
            windowEnd = nil
            deadline = nil
        case .arrivalWindow:
            serviceDate = job.scheduledDate
            fixedStart = nil
            windowStart = job.scheduledDate
            windowEnd = job.arrivalWindowEnd ?? Calendar.current.date(
                byAdding: .hour,
                value: 2,
                to: job.scheduledDate
            )
            deadline = nil
        case .flexibleDay:
            serviceDate = Calendar.current.startOfDay(
                for: job.scheduledDate
            )
            fixedStart = nil
            windowStart = nil
            windowEnd = nil
            deadline = nil
        case .deadline:
            serviceDate = Calendar.current.startOfDay(
                for: job.completionDeadline ?? job.scheduledDate
            )
            fixedStart = nil
            windowStart = nil
            windowEnd = nil
            deadline = job.completionDeadline ?? job.scheduledDate
        }

        return AssignmentScheduling(
            mode: job.assignmentSchedulingMode,
            serviceDate: serviceDate,
            fixedStartDate: fixedStart,
            arrivalWindowStart: windowStart,
            arrivalWindowEnd: windowEnd,
            completionDeadline: deadline,
            estimatedDurationMinutes: duration,
            isCustomerConfirmed: true,
            schedulingNotes: "Imported from Job \(job.jobNumber)."
        )
    }

    private func assignmentPriority(for job: JobRecord) -> AssignmentPriority {
        job.assignmentPriority
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
            jobs[existingIndex].arrivalWindowEnd = shiftedPlanningDate(
                job.arrivalWindowEnd,
                toDayContaining: nextDate
            )
            jobs[existingIndex].completionDeadline = shiftedPlanningDate(
                job.completionDeadline,
                toDayContaining: nextDate
            )
            return
        }

        var nextJob = job
        nextJob.id = UUID()
        nextJob.jobNumber = generateJobNumber(for: nextDate)
        nextJob.primaryTechnicianID = nil
        nextJob.secondaryTechnicianID = nil
        nextJob.scheduledDate = nextDate
        nextJob.arrivalWindowEnd = shiftedPlanningDate(
            job.arrivalWindowEnd,
            toDayContaining: nextDate
        )
        nextJob.completionDeadline = shiftedPlanningDate(
            job.completionDeadline,
            toDayContaining: nextDate
        )
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

    private func shiftedPlanningDate(
        _ source: Date?,
        toDayContaining target: Date
    ) -> Date? {
        guard let source else { return nil }
        let calendar = Calendar.current
        let time = calendar.dateComponents(
            [.hour, .minute, .second],
            from: source
        )
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: target
        )
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
        enqueueTechnicianNoteOperation(
            jobID: jobID,
            event: event,
            text: trimmedText
        )
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
        note: String? = nil,
        at timestamp: Date = Date()
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        let invoice = invoices.first {
            $0.jobNumber == jobs[index].jobNumber
        }

        if action == .createInvoice {
            guard fieldOperationsEngine.validate(
                job: jobs[index],
                action: action,
                invoice: invoice
            ).canProceed else {
                return false
            }

            let created = createInvoiceFromJob(jobID: jobID) != nil
            if created {
                synchronizeAssignmentWorkflow(
                    jobID: jobID,
                    action: action,
                    employeeID: employeeID,
                    at: timestamp
                )
                enqueueWorkflowOperation(
                    jobID: jobID,
                    action: action,
                    employeeID: employeeID,
                    note: note,
                    timestamp: timestamp
                )
            }
            return created
        }

        guard let updated =
                fieldOperationsEngine.transition(
                    job: jobs[index],
                    action: action,
                    employeeID: employeeID,
                    note: note,
                    invoice: invoice,
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
        enqueueWorkflowOperation(
            jobID: jobID,
            action: action,
            employeeID: employeeID,
            note: note,
            timestamp: timestamp
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

            case .startSetup, .startWork, .pauseWork, .resumeWork, .startPackUp,
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
        performWorkflowAction(
            jobID: jobID,
            action: .startSetup,
            employeeID: employeeID,
            at: startedAt
        )
    }

    @discardableResult
    func startJob(
        jobID: UUID,
        employeeID: UUID? = nil,
        startedAt: Date = Date()
    ) -> Bool {
        performWorkflowAction(
            jobID: jobID,
            action: .startWork,
            employeeID: employeeID,
            at: startedAt
        )
    }

    @discardableResult
    func completeJob(
        jobID: UUID,
        employeeID: UUID? = nil,
        completedAt: Date = Date()
    ) -> Bool {
        guard let job = jobs.first(where: { $0.id == jobID }) else {
            return false
        }

        if job.workflowState == .working {
            guard performWorkflowAction(
                jobID: jobID,
                action: .startPackUp,
                employeeID: employeeID,
                at: completedAt
            ) else {
                return false
            }
        }

        return performWorkflowAction(
            jobID: jobID,
            action: .finishWork,
            employeeID: employeeID,
            at: completedAt
        )
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
        guard let index = invoices.firstIndex(where: {
            $0.id == invoice.id
        }) else {
            return
        }

        let previousStatus = invoices[index].status
        invoices[index] = invoice
        if previousStatus != invoice.status {
            enqueueInvoiceOperation(
                invoice: invoice,
                previousStatus: previousStatus,
                timestamp: Date()
            )
        }
        synchronizeCompletedJobFromInvoice(
            invoice,
            previousStatus: previousStatus
        )
    }

    private func synchronizeCompletedJobFromInvoice(
        _ invoice: InvoiceRecord,
        previousStatus: InvoiceStatus
    ) {
        let completesTechnicianWork: Bool
        switch invoice.status {
        case .sent, .partiallyPaid, .paid, .overdue:
            completesTechnicianWork = true
        case .draft, .void:
            completesTechnicianWork = false
        }

        guard completesTechnicianWork,
              let jobIndex = jobs.firstIndex(where: {
                  $0.jobNumber == invoice.jobNumber
              }) else {
            return
        }

        let timestamp = invoice.status == .paid
            ? (invoice.paidDate ?? Date())
            : Date()

        switch invoice.status {
        case .sent, .overdue:
            if previousStatus != invoice.status &&
                !jobs[jobIndex].timelineEvents.contains(where: {
                    $0.type == .invoiceSent
                }) {
                jobs[jobIndex].timelineEvents.append(
                    JobTimelineEvent(
                        type: .invoiceSent,
                        title: "Invoice Sent",
                        timestamp: timestamp,
                        employeeID: jobs[jobIndex].primaryTechnicianID
                    )
                )
            }

        case .partiallyPaid, .paid:
            if !jobs[jobIndex].timelineEvents.contains(where: {
                $0.type == .paymentReceived
            }) {
                jobs[jobIndex].timelineEvents.append(
                    JobTimelineEvent(
                        type: .paymentReceived,
                        title: "Payment Received",
                        timestamp: timestamp,
                        employeeID: jobs[jobIndex].primaryTechnicianID
                    )
                )
            }

        case .draft, .void:
            break
        }

        if jobs[jobIndex].workflowState != .completed {
            _ = performWorkflowAction(
                jobID: jobs[jobIndex].id,
                action: .completeJob,
                employeeID: jobs[jobIndex].primaryTechnicianID,
                note: invoice.status == .paid
                    ? "Job completed after payment was received."
                    : "Job completed after the invoice was sent.",
                at: timestamp
            )
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

        // Creating a draft invoice is a billing handoff, not the end of the
        // technician workflow. The Job becomes complete when that invoice is
        // sent or payment is recorded through updateInvoice(_:).
        jobs[jobIndex].status = .inProgress
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
