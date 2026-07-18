//
//  AppDataStore.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation
import Combine

final class AppDataStore: ObservableObject {
    private let fieldOperationsEngine = FieldOperationsEngine()
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
        loadData()
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
        jobs.append(job)
    }

    func updateJob(_ job: JobRecord) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        }
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
            guard createInvoiceFromJob(jobs[index]) != nil else {
                return false
            }

            jobs[index] =
                fieldOperationsEngine.recordInvoiceCreated(
                    for: jobs[index],
                    employeeID: employeeID,
                    at: timestamp
                )

            return true
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
        return true
    }

    @discardableResult
    func startJob(
        jobID: UUID
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        guard jobs[index].status == .scheduled ||
              jobs[index].status == .assigned
        else {
            return false
        }

        jobs[index].status = .inProgress
        jobs[index].workflowState = .working
        jobs[index].timelineEvents.append(
            JobTimelineEvent(
                type: .workStarted,
                title: "Work Started"
            )
        )
        return true
    }

    @discardableResult
    func completeJob(
        jobID: UUID,
        completedAt: Date = Date()
    ) -> Bool {
        guard let index = jobs.firstIndex(where: {
            $0.id == jobID
        }) else {
            return false
        }

        var updated = jobs[index]
        updated.workflowState = .completed
        updated.status = .completed
        updated.completedDate = completedAt
        updated.timelineEvents.append(
            JobTimelineEvent(
                type: .jobCompleted,
                title: "Job Completed",
                timestamp: completedAt
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
        guard job.status == .completed else {
            return nil
        }

        guard !invoices.contains(where: { $0.jobNumber == job.jobNumber }) else {
            return nil
        }

        let issueDate = Date()
        let dueDate = Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: issueDate
        ) ?? issueDate

        let updatedLineItems = PricingCalculator.updatedLineItems(
            job.lineItems
        )

        let subtotal = PricingCalculator.subtotal(
            for: updatedLineItems
        )

        let total = PricingCalculator.total(
            subtotal: subtotal,
            discount: job.discount
        )

        let invoice = InvoiceRecord(
            invoiceNumber: generateInvoiceNumber(),
            customerNumber: job.customerNumber,
            siteID: job.siteID,
            jobNumber: job.jobNumber,
            lineItems: updatedLineItems,
            subtotal: subtotal,
            discount: job.discount,
            total: total,
            amountPaid: 0,
            balanceDue: total,
            status: .draft,
            issueDate: issueDate,
            dueDate: dueDate,
            paidDate: nil,
            notes: job.workNotes
        )

        invoices.append(invoice)
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
            employees: employees
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
        employees: [EmployeeRecord] = []
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
