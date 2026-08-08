import Foundation
import Testing
@testable import PPS_Receipt_Printer

struct LeadConversionTests {
    @MainActor
    @Test func conversionNeverOverwritesCustomerWithMatchingPhone() throws {
        let store = AppDataStore(persistenceEnabled: false)
        let existing = Customer(
            customerNumber: "PPS-000001",
            businessName: "Existing Customer",
            contactName: "Existing Contact",
            phone: "405-555-0100",
            email: "existing@example.com",
            leadSource: .referral,
            estimateStatus: .approved,
            assignedEmployee: "",
            followUpDate: Date()
        )
        let lead = Lead(
            leadNumber: "LD-2608-00001",
            businessName: "New Customer",
            contactName: "New Contact",
            phone: "405-555-0100",
            email: "new@example.com",
            leadSource: .doorKnock,
            serviceRequested: .other,
            otherService: "Testing",
            estimatedValue: 100,
            assignedSalesperson: "",
            status: .approved,
            followUpDate: Date(),
            createdDate: Date()
        )
        store.customers = [existing]
        store.leads = [lead]

        let converted = try #require(store.convertLeadToCustomer(lead))

        #expect(store.customers.count == 2)
        #expect(converted.id != existing.id)
        #expect(converted.customerNumber != existing.customerNumber)
        #expect(store.customers.first?.businessName == "Existing Customer")
        #expect(store.leads.first?.status == .converted)
    }
}
