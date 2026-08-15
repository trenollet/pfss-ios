//
//  AppDataStore.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation
import Combine

enum PFSSDataPortabilityAuthorizationError: LocalizedError, Equatable {
    case ownerRequired

    var errorDescription: String? {
        "Only the company Owner can export, inspect, restore, or clear company data."
    }
}

enum PFSSCloudSynchronizationAccessStatus: Equatable {
    case checking
    case available
    case suspended
    case accountHold(PFSSAccountHold)
    case unavailable(String)
}

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
    @Published private(set) var cloudRole: PFSSTenantRole = .member
    @Published private(set) var cloudEmployeeID: UUID?
    @Published private(set) var cloudSynchronizationAccessStatus:
        PFSSCloudSynchronizationAccessStatus = .checking
    var onPersistentDataSaved: (() -> Void)?
    var onServerConflictResolutionRequested:
        ((String, OfflineConflictResolution, String, [String]) async throws
            -> PFSSCloudflareConflictResolutionReceipt)?
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
    @Published var recurringWorkTemplates: [RecurringWorkTemplate] = [] {
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
    var activeRecurringWorkTemplates: [RecurringWorkTemplate] {
        recurringWorkTemplates.filter { $0.status == .active }
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
    private let persistenceEnabled: Bool
    private let cloudIdentityDefaults: UserDefaults
    private let persistsCloudIdentity: Bool
    private static let cloudRoleCacheKey = "PFSSAuthenticatedCloudRole"
    private static let cloudEmployeeIDCacheKey =
        "PFSSAuthenticatedCloudEmployeeID"
    private static let cloudAccountHoldCacheKey = "PFSSCloudAccountHold"
    private var isApplyingRestoredSnapshot = false
    var isApplyingRemoteSynchronization = false
    var synchronizedRecordState: [String: Data] = [:]
    var synchronizedRecordRevisions: [String: String] = [:]
    private var hasInitializedSynchronizedRecordState = false

    init(
        offlineOperationQueue: OfflineOperationQueue? = nil,
        offlineSynchronizationMode: OfflineSynchronizationMode = .localOnly,
        offlineConnectivityMonitor: OfflineConnectivityMonitor? = nil,
        offlineSynchronizationAdapter: (any OfflineSynchronizationAdapter)? = nil,
        persistenceEnabled: Bool = true,
        cloudIdentityDefaults: UserDefaults? = nil
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
        self.persistenceEnabled = persistenceEnabled
        self.cloudIdentityDefaults = cloudIdentityDefaults ?? .standard
        self.persistsCloudIdentity = persistenceEnabled || cloudIdentityDefaults != nil
        if self.persistsCloudIdentity,
           let cachedRole = self.cloudIdentityDefaults.string(
               forKey: Self.cloudRoleCacheKey
           ).flatMap(PFSSTenantRole.init(rawValue:)) {
            cloudRole = cachedRole
            cloudEmployeeID = self.cloudIdentityDefaults.string(
                forKey: Self.cloudEmployeeIDCacheKey
            ).flatMap(UUID.init(uuidString:))
        }
        if self.persistsCloudIdentity,
           let cachedHoldData = self.cloudIdentityDefaults.data(
               forKey: Self.cloudAccountHoldCacheKey
           ),
           let cachedHold = try? JSONDecoder().decode(
               PFSSAccountHold.self,
               from: cachedHoldData
           ) {
            cloudSynchronizationAccessStatus = .accountHold(cachedHold)
        }
        self.synchronizedRecordRevisions = UserDefaults.standard
            .dictionary(forKey: "PFSSSynchronizedRecordRevisions")
            as? [String: String] ?? [:]
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
        offlineSynchronizationService?.onOperationSupersededByCloud = {
            [weak self] operation, revision in
            var acceptedOperation = operation
            acceptedOperation.metadata["remoteRevision"] = revision
            self?.applyRemoteRecordOperations([acceptedOperation])
        }
        removeLeakedOfflineTestFixturesIfNeeded()
        migrateLegacyRecurringWorkIfNeeded()
        materializeRecurringWorkHorizon()
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
        synchronizedRecordState = makeSynchronizedRecordState()
        hasInitializedSynchronizedRecordState = true
    }

    func startOfflineServices() {
        offlineConnectivityMonitor.start()
        offlineSynchronizationService?.start()
    }

    var canOverrideSynchronizationConflicts: Bool {
        cloudRole == .owner || cloudRole == .manager
    }

    var canManageCompany: Bool {
        cloudRole == .owner || cloudRole == .manager
    }

    var authenticatedCloudEmployee: EmployeeRecord? {
        guard let cloudEmployeeID else { return nil }
        return employees.first { $0.id == cloudEmployeeID }
    }

    @discardableResult
    func updateAuthenticatedJobTimerReminderPreferences(
        _ preferences: JobTimerReminderPreferences
    ) -> Bool {
        guard let cloudEmployeeID,
              let index = employees.firstIndex(where: {
                  $0.id == cloudEmployeeID
              }) else { return false }
        employees[index].jobTimerReminderPreferences = preferences
        saveData()
        return true
    }

    var shouldPresentAuthenticatedUserInfo: Bool {
        cloudRole != .owner
    }

    var usesAuthenticatedMyDayIdentity: Bool {
        cloudRole != .owner
    }

    var authenticatedMyDayEmployee: EmployeeRecord? {
        guard usesAuthenticatedMyDayIdentity,
              let employee = authenticatedCloudEmployee,
              employee.isActive,
              employee.lifecycleStatus == .active,
              employee.hasRole(.technician) else {
            return nil
        }
        return employee
    }

    var shouldPresentAdminDashboardTile: Bool {
        cloudRole == .owner
    }

    func updateCloudRole(_ role: PFSSTenantRole) {
        cloudRole = role
        removeOwnerRecoveryAccessIfNeeded(for: role)
    }

    func updateCloudIdentity(
        role: PFSSTenantRole,
        employeeID: String?,
        displayName: String? = nil,
        email: String? = nil
    ) {
        cloudRole = role
        cloudEmployeeID = employeeID.flatMap(UUID.init(uuidString:))
            ?? matchingEmployeeID(displayName: displayName, email: email)
        if persistsCloudIdentity {
            cloudIdentityDefaults.set(role.rawValue, forKey: Self.cloudRoleCacheKey)
            if let cloudEmployeeID {
                cloudIdentityDefaults.set(
                    cloudEmployeeID.uuidString,
                    forKey: Self.cloudEmployeeIDCacheKey
                )
            } else {
                cloudIdentityDefaults.removeObject(
                    forKey: Self.cloudEmployeeIDCacheKey
                )
            }
        }
        removeOwnerRecoveryAccessIfNeeded(for: role)
        relinkActiveOperationsToAuthenticatedEmployeeIfNeeded()
    }

    private func matchingEmployeeID(
        displayName: String?,
        email: String?
    ) -> UUID? {
        let normalizedEmail = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalizedEmail, !normalizedEmail.isEmpty,
           let employee = employees.first(where: {
               $0.email.trimmingCharacters(in: .whitespacesAndNewlines)
                   .lowercased() == normalizedEmail
           }) {
            return employee.id
        }

        let normalizedName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedName, !normalizedName.isEmpty else { return nil }
        let matches = employees.filter {
            $0.displayName.compare(
                normalizedName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
        return matches.count == 1 ? matches[0].id : nil
    }

    func clearCachedCloudIdentity() {
        cloudRole = .member
        cloudEmployeeID = nil
        cloudIdentityDefaults.removeObject(forKey: Self.cloudRoleCacheKey)
        cloudIdentityDefaults.removeObject(forKey: Self.cloudEmployeeIDCacheKey)
    }

    func updateCloudSynchronizationAccessStatus(
        _ status: PFSSCloudSynchronizationAccessStatus
    ) {
        if case .accountHold = cloudSynchronizationAccessStatus,
           case .unavailable = status {
            // A cached server hold remains authoritative while offline. Only a
            // successful authenticated request may restore local operations.
            return
        }
        cloudSynchronizationAccessStatus = status
        switch status {
        case let .accountHold(hold):
            if let data = try? JSONEncoder().encode(hold) {
                cloudIdentityDefaults.set(
                    data,
                    forKey: Self.cloudAccountHoldCacheKey
                )
            }
        case .available:
            cloudIdentityDefaults.removeObject(
                forKey: Self.cloudAccountHoldCacheKey
            )
        case .checking, .suspended, .unavailable:
            break
        }
    }

    private func removeOwnerRecoveryAccessIfNeeded(for role: PFSSTenantRole) {
        guard role != .owner else { return }
        PFSSOwnerRecoverySecurity.revokeLocalAccess()
    }

    func generateCustomerNumber() -> String {
        while true {
            let number: String
            if let deviceScope = offlineRecordNumberDeviceScope {
                number = String(
                    format: "PPS-%@-%06d",
                    deviceScope,
                    nextCustomerNumber
                )
            } else {
                number = String(format: "PPS-%06d", nextCustomerNumber)
            }
            nextCustomerNumber += 1
            if !customers.contains(where: { $0.customerNumber == number }) {
                return number
            }
        }
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
        upsertRecurringWorkTemplate(from: storedJob)
        materializeRecurringWorkHorizon()
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
            if storedJob.recurrenceSequence == 0 {
                upsertRecurringWorkTemplate(from: storedJob)
            }

            if recurringSeriesSettingsChanged(
                from: previousJob,
                to: storedJob
            ),
               let templateID = storedJob.recurringWorkTemplateID,
               let frequency = storedJob.recurrenceFrequency,
               let template = recurringWorkTemplates.first(where: {
                   $0.id == templateID
               }) {
                updateRecurringWorkSeries(
                    templateID: templateID,
                    frequency: frequency,
                    endMode: storedJob.recurrenceEndMode,
                    endDate: storedJob.recurrenceEndDate,
                    occurrenceCount: storedJob.recurrenceOccurrenceCount,
                    siteID: template.prototype.siteID
                )
                return
            }

            materializeRecurringWorkHorizon()
            synchronizeAssignmentsFromJobs()
        }
    }

    private func recurringSeriesSettingsChanged(
        from previousJob: JobRecord,
        to updatedJob: JobRecord
    ) -> Bool {
        guard previousJob.isRecurring,
              updatedJob.isRecurring,
              previousJob.recurringWorkTemplateID != nil,
              updatedJob.recurringWorkTemplateID != nil else {
            return false
        }

        return previousJob.recurrenceFrequency != updatedJob.recurrenceFrequency ||
            previousJob.recurrenceEndMode != updatedJob.recurrenceEndMode ||
            previousJob.recurrenceEndDate != updatedJob.recurrenceEndDate ||
            previousJob.recurrenceOccurrenceCount != updatedJob.recurrenceOccurrenceCount
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
                // Assignment deliberately models travel at a broader level
                // than the field workflow. Preserve a technician's paused
                // travel state instead of flattening it back to Traveling
                // whenever another Assignment publishes a store update.
                if job.workflowState != .travelPaused {
                    job.workflowState = .traveling
                }

            case .onSite:
                job.status = .inProgress
                // Setup, active work, pauses, and pack-up are all legitimate
                // refinements of Assignment's On Site state.
                let onSiteStates: Set<JobWorkflowState> = [
                    .arrived,
                    .settingUp,
                    .working,
                    .paused,
                    .packingUp
                ]
                if !onSiteStates.contains(job.workflowState) {
                    job.workflowState = .arrived
                }

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
        nextJob.workStartDate = nil
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
            job.recurrenceEndMode = .noEnd
            job.recurrenceEndDate = nil
            job.recurrenceOccurrenceCount = nil
            job.recurrenceSeriesID = nil
            job.recurrenceSequence = 0
            job.recurringWorkTemplateID = nil
            job.recurringWorkOccurrenceKey = nil
            return
        }

        if job.recurrenceSeriesID == nil {
            job.recurrenceSeriesID = job.id
        }
        if job.recurringWorkTemplateID == nil {
            job.recurringWorkTemplateID = job.recurrenceSeriesID
        }
        if let templateID = job.recurringWorkTemplateID,
           job.recurringWorkOccurrenceKey == nil {
            job.recurringWorkOccurrenceKey = RecurringWorkEngine().occurrenceKey(
                templateID: templateID,
                occurrenceIndex: job.recurrenceSequence
            )
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

    /// Corrects a lifecycle timestamp while retaining the original value in
    /// an audit event. Only an Owner or Manager may perform this operation.
    @discardableResult
    func correctTimelineTimestamp(
        jobID: UUID,
        eventID: UUID,
        correctedTimestamp: Date,
        reason: String,
        actorEmployeeID: UUID,
        correctedAt: Date = Date()
    ) -> JobTimelineEvent? {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty,
              let actor = employees.first(where: { $0.id == actorEmployeeID }),
              actor.canOverrideScheduling || (
                  canManageCompany && actor.id == cloudEmployeeID
              ),
              let jobIndex = jobs.firstIndex(where: { $0.id == jobID }),
              let eventIndex = jobs[jobIndex].timelineEvents.firstIndex(where: {
                  $0.id == eventID && $0.type != .timelineCorrected
              }) else { return nil }

        let correctedType = jobs[jobIndex].timelineEvents[eventIndex].type
        let originalTimestamp = jobs[jobIndex].timelineEvents[eventIndex].timestamp
        guard originalTimestamp != correctedTimestamp else { return nil }
        let correctedTitle = jobs[jobIndex].timelineEvents[eventIndex].title
        jobs[jobIndex].timelineEvents[eventIndex].timestamp = correctedTimestamp

        // Keep the dedicated timestamps used by labor reporting consistent
        // with their corrected audit events.
        switch correctedType {
        case .setupStarted:
            jobs[jobIndex].setupStartDate = correctedTimestamp
        case .workStarted:
            jobs[jobIndex].workStartDate = correctedTimestamp
        case .workCompleted, .jobCompleted:
            jobs[jobIndex].completedDate = correctedTimestamp
        default:
            break
        }

        let auditEvent = JobTimelineEvent(
            type: .timelineCorrected,
            title: "Timeline Corrected: \(correctedTitle)",
            timestamp: correctedAt,
            employeeID: actorEmployeeID,
            note: trimmedReason,
            correctedEventID: eventID,
            originalTimestamp: originalTimestamp,
            correctedTimestamp: correctedTimestamp
        )
        jobs[jobIndex].timelineEvents.append(auditEvent)
        enqueueTimelineCorrectionOperation(
            job: jobs[jobIndex],
            eventID: eventID,
            originalTimestamp: originalTimestamp,
            correctedTimestamp: correctedTimestamp,
            reason: trimmedReason,
            actorEmployeeID: actorEmployeeID,
            correctedAt: correctedAt
        )
        return auditEvent
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
            invoice: invoice,
            assignment: assignment(forJobID: job.id)
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
        updateJobStartReminder(for: updated, after: action)
        return true
    }

    private func updateJobStartReminder(
        for job: JobRecord,
        after action: JobWorkflowAction
    ) {
        switch action {
        case .markArrived:
            let minutes = authenticatedCloudEmployee?
                .jobTimerReminderPreferences.arrivalToSetupMinutes ?? 5
            PFSSJobStartReminderService.shared.scheduleAfterArrival(
                for: job,
                minutes: minutes
            )
        case .startSetup:
            let minutes = authenticatedCloudEmployee?
                .jobTimerReminderPreferences.setupToWorkMinutes ?? 5
            PFSSJobStartReminderService.shared.scheduleAfterSetup(
                for: job,
                minutes: minutes
            )
        case .startWork, .finishWork, .completeJob:
            PFSSJobStartReminderService.shared.cancel(for: job.id)
        case .startTravel, .pauseTravel, .resumeTravel, .pauseWork,
             .resumeWork, .startPackUp, .createInvoice, .recordPayment,
             .viewDetails:
            break
        }
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

            case .pauseTravel, .resumeTravel, .startSetup, .startWork,
                 .pauseWork, .resumeWork, .startPackUp,
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
            var updated = serviceCatalogItems[index]
            updated.usageCount += 1
            updated.lastUsedDate = Date()
            serviceCatalogItems[index] = updated
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

        let previousInvoice = invoices[index]
        let previousStatus = previousInvoice.status
        // A status or payment update must not silently reprice a historical
        // invoice. Explicit editor/tax actions recalculate before this call.
        var normalizedInvoice = InvoiceEngine.normalizedPaymentState(
            for: invoice
        )
        if ReceiptEngine.requiresReceipt(
            previous: previousInvoice,
            proposed: normalizedInvoice
        ) {
            normalizedInvoice = ReceiptEngine.recordingPayment(
                previous: previousInvoice,
                proposed: normalizedInvoice,
                receiptNumber: generateReceiptNumber(),
                timestamp: Date()
            )
        }
        invoices[index] = normalizedInvoice
        if previousStatus != normalizedInvoice.status {
            enqueueInvoiceOperation(
                invoice: normalizedInvoice,
                previousStatus: previousStatus,
                timestamp: Date()
            )
        }
        synchronizeCompletedJobFromInvoice(
            normalizedInvoice,
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
    @discardableResult
    func convertLeadToCustomer(_ lead: Lead) -> Customer? {
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

        var convertedLead = lead
        convertedLead.status = .converted
        updateLead(convertedLead)

        return customer
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

        if let existingInvoice = InvoiceEngine.existingInvoice(
            forJobNumber: persistedJob.jobNumber,
            in: invoices
        ) {
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
            persistedJob.lineItems.map(snapshotCatalogClassification)
        )
        let taxSnapshot = companyStandardTaxSnapshot(
            lines: updatedLineItems,
            discount: persistedJob.discount,
            calculatedAt: issueDate
        )
        let invoice = InvoiceEngine.makeDraft(from: .init(
            invoiceNumber: generateInvoiceNumber(),
            customerNumber: persistedJob.customerNumber,
            siteID: persistedJob.siteID,
            jobNumber: persistedJob.jobNumber,
            lineItems: updatedLineItems,
            discount: persistedJob.discount,
            taxSnapshot: taxSnapshot,
            issueDate: issueDate,
            dueDate: dueDate,
            notes: persistedJob.workNotes
        ))

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

    func applyCompanyStandardTaxToUncalculatedDraftInvoices() {
        guard businessProfile.taxSettings.isConfigured else { return }
        var updated = invoices
        var changed = false
        for index in updated.indices where
            updated[index].status == .draft && updated[index].taxSnapshot == nil {
            let lines = PricingCalculator.updatedLineItems(
                updated[index].lineItems.map(snapshotCatalogClassification)
            )
            guard let snapshot = companyStandardTaxSnapshot(
                lines: lines,
                discount: updated[index].discount,
                calculatedAt: updated[index].issueDate
            ) else { continue }
            updated[index].lineItems = lines
            updated[index].taxSnapshot = snapshot
            updated[index].subtotal = PricingCalculator.subtotal(for: lines)
            updated[index] = InvoiceEngine.applyingTax(
                snapshot,
                to: updated[index],
                at: updated[index].issueDate
            )
            changed = true
        }
        if changed { invoices = updated }
    }

    private func companyStandardTaxSnapshot(
        lines: [ServiceLineItem],
        discount: Double,
        calculatedAt: Date
    ) -> TaxCalculationSnapshot? {
        let settings = businessProfile.taxSettings
        guard settings.isConfigured,
              Calendar.current.startOfDay(for: settings.effectiveDate)
                <= Calendar.current.startOfDay(for: calculatedAt) else {
            return nil
        }
        let quote = TaxRateQuote(
            jurisdiction: settings.jurisdictionName,
            rate: Decimal(settings.standardRatePercent / 100),
            source: "Company Standard Rate · Verified by \(settings.verifiedBy)",
            effectiveDate: settings.effectiveDate
        )
        return try? TaxEngine.calculate(
            lines: lines,
            discount: Decimal(discount),
            quote: quote,
            calculatedAt: calculatedAt
        )
    }

    private func snapshotCatalogClassification(
        _ line: ServiceLineItem
    ) -> ServiceLineItem {
        guard let catalogItemID = line.catalogItemID,
              let catalogItem = serviceCatalogItems.first(where: {
                  $0.id == catalogItemID
              }) else { return line }
        var snapshot = line
        if snapshot.catalogItemNameSnapshot == nil {
            snapshot.catalogItemNameSnapshot = catalogItem.itemName
        }
        if snapshot.catalogItemTypeSnapshot == nil {
            snapshot.catalogItemTypeSnapshot = catalogItem.itemType
        }
        if snapshot.taxTreatmentSnapshot == nil {
            snapshot.taxTreatmentSnapshot = catalogItem.taxTreatment
        }
        return snapshot
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

        let deviceScope = offlineRecordNumberDeviceScope
        let sequenceKey = [prefix, monthPrefix, deviceScope]
            .compactMap { $0 }
            .joined(separator: "-")

        while true {
            let nextSequence = (recordSequencesByMonth[sequenceKey] ?? 0) + 1
            recordSequencesByMonth[sequenceKey] = nextSequence
            let components = [
                prefix,
                monthPrefix,
                deviceScope,
                String(format: "%05d", nextSequence)
            ].compactMap { $0 }
            let number = components.joined(separator: "-")
            guard !recordNumberAlreadyExists(number, prefix: prefix) else {
                continue
            }
            return number
        }
    }

    /// Disconnected devices cannot safely share a tenant-wide sequential
    /// counter. A stable device scope preserves readable record numbers while
    /// making locally created identities collision-resistant until sync.
    private var offlineRecordNumberDeviceScope: String? {
        guard offlineSynchronizationMode.requiresRemoteQueue,
              offlineConnectivityMonitor.status != .online else {
            return nil
        }
        let key = "PFSSCloudflareBetaDeviceID"
        let deviceID: UUID
        if let saved = cloudIdentityDefaults.string(forKey: key),
           let existing = UUID(uuidString: saved) {
            deviceID = existing
        } else {
            deviceID = UUID()
            cloudIdentityDefaults.set(
                deviceID.uuidString.lowercased(),
                forKey: key
            )
        }
        return String(
            deviceID.uuidString
                .replacingOccurrences(of: "-", with: "")
                .prefix(6)
        ).uppercased()
    }

    private func recordNumberAlreadyExists(
        _ number: String,
        prefix: String
    ) -> Bool {
        switch prefix {
        case "LD":
            return leads.contains { $0.leadNumber == number }
        case "EST":
            return estimates.contains { $0.estimateNumber == number }
        case "JOB":
            return jobs.contains { $0.jobNumber == number }
        case "INV":
            return invoices.contains { $0.invoiceNumber == number }
        case "RCT":
            return false
        default:
            return false
        }
    }

    private func saveData() {
        guard persistenceEnabled, !isApplyingRestoredSnapshot else {
            return
        }

        let snapshot = PFSSDataSnapshot(
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
            assignments: assignmentStore.assignments,
            recurringWorkTemplates: recurringWorkTemplates
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: saveFileURL(), options: [.atomic])
            synchronizeChangedRecordsIfNeeded()
            onPersistentDataSaved?()
        } catch {
            print("Failed to save app data: \(error.localizedDescription)")
        }
    }

    private func synchronizeChangedRecordsIfNeeded() {
        let current = makeSynchronizedRecordState()
        defer { synchronizedRecordState = current }
        guard offlineSynchronizationMode.requiresRemoteQueue,
              !isApplyingRemoteSynchronization,
              hasInitializedSynchronizedRecordState else { return }

        enqueueChangedRecords(customers, type: .customer, current: current)
        enqueueChangedRecords(sites, type: .site, current: current)
        enqueueChangedRecords(leads, type: .lead, current: current)
        enqueueChangedRecords(estimates, type: .estimate, current: current)
        enqueueChangedRecords(jobs, type: .job, current: current)
        if canManageCompany {
            enqueueChangedRecords(
                recurringWorkTemplates,
                type: .recurringWork,
                current: current
            )
        }
        enqueueChangedRecords(invoices, type: .invoice, current: current)
        enqueueChangedRecords(employees, type: .employee, current: current)
        enqueueChangedRecords(serviceCatalogItems, type: .catalog, current: current)
        enqueueChangedRecords(assignmentStore.assignments, type: .assignment, current: current)
        if canManageCompany {
            let profileKey = synchronizationKey(
                type: .custom,
                id: Self.businessProfileSynchronizationID
            )
            if current[profileKey] != synchronizedRecordState[profileKey] {
                enqueueBusinessProfileSynchronization()
            }
        }
    }

    private func enqueueChangedRecords<Value: Encodable & Identifiable>(
        _ values: [Value],
        type: OfflineEntityType,
        current: [String: Data]
    ) where Value.ID == UUID {
        for value in values {
            let key = synchronizationKey(type: type, id: value.id)
            guard current[key] != synchronizedRecordState[key] else { continue }
            enqueueRecordMutation(entityType: type, entityID: value.id, value: value)
        }
    }

    func makeSynchronizedRecordState() -> [String: Data] {
        var result: [String: Data] = [:]
        appendSynchronizedRecords(customers, type: .customer, to: &result)
        appendSynchronizedRecords(sites, type: .site, to: &result)
        appendSynchronizedRecords(leads, type: .lead, to: &result)
        appendSynchronizedRecords(estimates, type: .estimate, to: &result)
        appendSynchronizedRecords(jobs, type: .job, to: &result)
        appendSynchronizedRecords(
            recurringWorkTemplates,
            type: .recurringWork,
            to: &result
        )
        appendSynchronizedRecords(invoices, type: .invoice, to: &result)
        appendSynchronizedRecords(employees, type: .employee, to: &result)
        appendSynchronizedRecords(serviceCatalogItems, type: .catalog, to: &result)
        appendSynchronizedRecords(assignmentStore.assignments, type: .assignment, to: &result)
        if let data = try? Self.recordSynchronizationEncoder.encode(businessProfile) {
            result[synchronizationKey(
                type: .custom,
                id: Self.businessProfileSynchronizationID
            )] = data
        }
        return result
    }

    static let businessProfileSynchronizationID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    )!

    private func appendSynchronizedRecords<Value: Encodable & Identifiable>(
        _ values: [Value],
        type: OfflineEntityType,
        to result: inout [String: Data]
    ) where Value.ID == UUID {
        for value in values {
            if let data = try? Self.recordSynchronizationEncoder.encode(value) {
                result[synchronizationKey(type: type, id: value.id)] = data
            }
        }
    }

    func synchronizationKey(type: OfflineEntityType, id: UUID) -> String {
        type.rawValue + ":" + id.uuidString.lowercased()
    }

    func saveSynchronizedRecordRevisions() {
        UserDefaults.standard.set(
            synchronizedRecordRevisions,
            forKey: "PFSSSynchronizedRecordRevisions"
        )
    }

    private func loadData() {
        guard persistenceEnabled else {
            return
        }

        let url = saveFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(PFSSDataSnapshot.self, from: data)

            customers = snapshot.customers
            sites = snapshot.sites
            leads = snapshot.leads
            estimates = snapshot.estimates
            jobs = snapshot.jobs
            recurringWorkTemplates = snapshot.recurringWorkTemplates
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

    /// Produces a provider-neutral, integrity-checked PFSS archive. Transport
    /// providers such as iCloud, Google Drive, or Cloudflare move this data but
    /// do not define its schema.
    func createPortableArchive(
        createdAt: Date = Date(),
        archiveService: PFSSArchiveService? = nil
    ) throws -> Data {
        let archiveService = archiveService ?? PFSSArchiveService()
        let snapshot = PFSSDataSnapshot(
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
            assignments: assignmentStore.assignments,
            recurringWorkTemplates: recurringWorkTemplates
        )
        return try archiveService.createArchive(
            payload: PFSSArchivePayload(
                appData: snapshot,
                pendingOperations: offlineOperationQueue.orderedOperations
            ),
            businessName: businessProfile.businessName,
            createdAt: createdAt
        )
    }

    func createOwnerRecoveryArchive(createdAt: Date = Date()) throws -> Data {
        try requireOwnerRecoveryAuthorization()
        return try createPortableArchive(createdAt: createdAt)
    }

    func inspectOwnerRecoveryArchive(
        _ archiveData: Data
    ) throws -> PFSSValidatedArchive {
        try requireOwnerRecoveryAuthorization()
        return try inspectPortableArchive(archiveData)
    }

    func restoreOwnerRecoveryArchive(
        _ archiveData: Data,
        backupService: PFSSLocalBackupService? = nil,
        restoredAt: Date = Date()
    ) throws -> PFSSRestoreResult {
        try requireOwnerRecoveryAuthorization()
        return try restorePortableArchive(
            archiveData,
            backupService: backupService,
            restoredAt: restoredAt
        )
    }

    func clearOwnerLocalData() throws {
        try requireOwnerRecoveryAuthorization()
        try clearAllLocalData()
    }

    func requireOwnerRecoveryAuthorization() throws {
        guard cloudRole == .owner else {
            throw PFSSDataPortabilityAuthorizationError.ownerRequired
        }
    }

    /// Validates and decodes an archive for preview without changing live data.
    func inspectPortableArchive(
        _ archiveData: Data,
        archiveService: PFSSArchiveService? = nil
    ) throws -> PFSSValidatedArchive {
        let archiveService = archiveService ?? PFSSArchiveService()
        return try archiveService.validateAndDecode(archiveData)
    }

    var hasLocalCompanyData: Bool {
        !businessProfile.businessName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ||
        !customers.isEmpty || !sites.isEmpty || !leads.isEmpty ||
        !estimates.isEmpty || !jobs.isEmpty || !invoices.isEmpty ||
        !serviceCatalogItems.isEmpty || !employees.isEmpty ||
        !assignmentStore.assignments.isEmpty
    }

    /// Hydrates a newly enrolled, empty installation from PFSS Cloud without
    /// copying another device's pending operation queue or creating an
    /// exportable local recovery archive.
    @discardableResult
    func applySynchronizationBootstrap(
        _ archiveData: Data,
        archiveService: PFSSArchiveService? = nil
    ) throws -> Bool {
        guard !hasLocalCompanyData else { return false }
        let archiveService = archiveService ?? PFSSArchiveService()
        let validated = try archiveService.validateAndDecode(archiveData)
        let currentPayload = portableArchivePayload()
        let bootstrapPayload = PFSSArchivePayload(
            appData: validated.payload.appData,
            pendingOperations: []
        )

        isApplyingRestoredSnapshot = true
        do {
            try applyPortableArchivePayload(bootstrapPayload)
            isApplyingRestoredSnapshot = false
            saveData()
            return true
        } catch {
            do {
                try applyPortableArchivePayload(currentPayload)
                isApplyingRestoredSnapshot = false
                saveData()
            } catch {
                isApplyingRestoredSnapshot = false
                throw PFSSRestoreError.rollbackFailed(
                    error.localizedDescription
                )
            }
            throw PFSSRestoreError.restoreFailed(
                error.localizedDescription
            )
        }
    }

    /// Restores a fully validated archive only after saving the current state
    /// as a durable local safety backup. A failed mutation rolls back in memory
    /// and on disk before returning an error.
    func restorePortableArchive(
        _ archiveData: Data,
        archiveService: PFSSArchiveService? = nil,
        backupService: PFSSLocalBackupService? = nil,
        restoredAt: Date = Date()
    ) throws -> PFSSRestoreResult {
        let archiveService = archiveService ?? PFSSArchiveService()
        let backupService = backupService ?? PFSSLocalBackupService()
        let validated = try archiveService.validateAndDecode(archiveData)
        let currentPayload = portableArchivePayload()
        let safetyData = try archiveService.createArchive(
            payload: currentPayload,
            businessName: businessProfile.businessName,
            createdAt: restoredAt
        )
        let safetyBackup = try backupService.save(
            safetyData,
            kind: .preRestoreSafety,
            createdAt: restoredAt
        )

        isApplyingRestoredSnapshot = true
        do {
            try applyPortableArchivePayload(validated.payload)
            isApplyingRestoredSnapshot = false
            saveData()
        } catch {
            do {
                try applyPortableArchivePayload(currentPayload)
                isApplyingRestoredSnapshot = false
                saveData()
            } catch {
                isApplyingRestoredSnapshot = false
                throw PFSSRestoreError.rollbackFailed(
                    error.localizedDescription
                )
            }
            throw PFSSRestoreError.restoreFailed(
                error.localizedDescription
            )
        }

        return PFSSRestoreResult(
            restoredManifest: validated.manifest,
            safetyBackup: safetyBackup
        )
    }

    /// Removes all local business and operational state after the owner has
    /// completed the Data Management view's two confirmation steps. Portable
    /// backup files are intentionally outside this store and remain available
    /// for recovery.
    func clearAllLocalData() throws {
        let currentPayload = portableArchivePayload()
        let emptyPayload = PFSSArchivePayload(
            appData: PFSSDataSnapshot(
                customers: [],
                sites: [],
                leads: [],
                estimates: [],
                jobs: [],
                invoices: [],
                businessProfile: BusinessProfile(),
                serviceCatalogItems: [],
                nextCustomerNumber: 1,
                recordSequencesByMonth: [:],
                recommendationRules: [],
                employees: [],
                assignments: [],
                recurringWorkTemplates: []
            ),
            pendingOperations: []
        )

        isApplyingRestoredSnapshot = true
        do {
            try applyPortableArchivePayload(emptyPayload)
            acceptedRoutePlans = [:]
            isApplyingRestoredSnapshot = false
            saveData()
        } catch {
            do {
                try applyPortableArchivePayload(currentPayload)
                isApplyingRestoredSnapshot = false
                saveData()
            } catch {
                isApplyingRestoredSnapshot = false
                throw PFSSRestoreError.rollbackFailed(
                    error.localizedDescription
                )
            }
            throw PFSSRestoreError.restoreFailed(
                error.localizedDescription
            )
        }
    }

    private func portableArchivePayload() -> PFSSArchivePayload {
        PFSSArchivePayload(
            appData: PFSSDataSnapshot(
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
                assignments: assignmentStore.assignments,
                recurringWorkTemplates: recurringWorkTemplates
            ),
            pendingOperations: offlineOperationQueue.orderedOperations
        )
    }

    private func applyPortableArchivePayload(
        _ payload: PFSSArchivePayload
    ) throws {
        let snapshot = payload.appData
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
        try offlineOperationQueue.replaceAll(
            with: payload.pendingOperations
        )
    }

    /// Removes fixtures written by early offline integration tests before the
    /// primary AppDataStore persistence boundary became injectable.
    ///
    /// The marker is intentionally exact so customer and operational data can
    /// never be mistaken for test content.
    private func removeLeakedOfflineTestFixturesIfNeeded() {
        guard persistenceEnabled else {
            return
        }

        let testCustomerNumber = "PPS-OFFLINE-TEST"
        let leakedJobs = jobs.filter {
            $0.customerNumber == testCustomerNumber &&
            (
                $0.jobNumber.hasPrefix("JOB-OFFLINE-") ||
                $0.jobNumber == "JOB-LOCAL-ONLY"
            )
        }

        let leakedAssignments = assignmentStore.assignments.filter {
            $0.customerNumber == testCustomerNumber &&
            (
                $0.jobNumber.hasPrefix("JOB-OFFLINE-") ||
                $0.jobNumber == "JOB-LOCAL-ONLY"
            )
        }
        let hasLeakedInvoice = invoices.contains {
            $0.customerNumber == testCustomerNumber &&
            (
                $0.jobNumber.hasPrefix("JOB-OFFLINE-") ||
                $0.jobNumber == "JOB-LOCAL-ONLY"
            )
        }

        guard !leakedJobs.isEmpty ||
                !leakedAssignments.isEmpty ||
                hasLeakedInvoice else {
            return
        }

        let leakedJobIDs = Set(
            leakedJobs.map(\.id) + leakedAssignments.map(\.jobID)
        )
        let leakedJobNumbers = Set(
            leakedJobs.map(\.jobNumber) + leakedAssignments.map(\.jobNumber)
        )

        jobs.removeAll { leakedJobIDs.contains($0.id) }
        invoices.removeAll {
            $0.customerNumber == testCustomerNumber ||
            leakedJobNumbers.contains($0.jobNumber)
        }

        let retainedAssignments = assignmentStore.assignments.filter {
            !leakedJobIDs.contains($0.jobID) &&
            !leakedJobNumbers.contains($0.jobNumber) &&
            $0.customerNumber != testCustomerNumber
        }

        do {
            try assignmentStore.replaceAll(with: retainedAssignments)
            saveData()
        } catch {
            print(
                "Failed to remove leaked offline test fixtures: " +
                error.localizedDescription
            )
        }
    }
}

struct PFSSDataSnapshot: Codable {
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
    var recurringWorkTemplates: [RecurringWorkTemplate] = []

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
        case recurringWorkTemplates
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
        assignments: [Assignment] = [],
        recurringWorkTemplates: [RecurringWorkTemplate] = []
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
        self.recurringWorkTemplates = recurringWorkTemplates
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
        recurringWorkTemplates = try container.decodeIfPresent(
            [RecurringWorkTemplate].self,
            forKey: .recurringWorkTemplates
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
