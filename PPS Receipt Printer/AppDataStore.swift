//
//  AppDataStore.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation
import Combine

final class AppDataStore: ObservableObject {
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

    func sites(for customerNumber: String) -> [CustomerSite] {
        sites.filter { $0.customerNumber == customerNumber }
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
            nextCustomerNumber: nextCustomerNumber,
            recordSequencesByMonth: recordSequencesByMonth
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
            nextCustomerNumber = snapshot.nextCustomerNumber
            recordSequencesByMonth = snapshot.recordSequencesByMonth
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
    var nextCustomerNumber: Int
    var recordSequencesByMonth: [String: Int]
}
