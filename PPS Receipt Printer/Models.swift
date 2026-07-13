//
//  models.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation

enum ServiceType: String, CaseIterable, Identifiable, Codable {
    case windowCleaning = "Window Cleaning"
    case pressureWashing = "Pressure Washing"
    case gutterCleaning = "Gutter Cleaning"
    case handymanServices = "Handyman Services"
    case other = "Other"

    var id: String { rawValue }
}
enum CatalogItemType: String, CaseIterable, Identifiable, Codable {
    case service = "Service"
    case material = "Material"
    case fee = "Fee"

    var id: String { rawValue }
}

enum TaxTreatment: String, CaseIterable, Identifiable, Codable {
    case nonTaxable = "Non-Taxable"
    case taxable = "Taxable"
    case taxIncluded = "Tax Included"
    case exempt = "Exempt"

    var id: String { rawValue }
}

enum LeadSource: String, CaseIterable, Identifiable, Codable {
    case website = "Website"
    case phoneCall = "Phone Call"
    case socialMedia = "Social Media"
    case google = "Google"
    case referral = "Referral"
    case doorKnock = "Door Knock"
    case repeatCustomer = "Repeat Customer"
    case other = "Other"

    var id: String { rawValue }
}

enum EstimateStatus: String, CaseIterable, Identifiable, Codable {
    case newLead = "New Lead"
    case estimateGiven = "Estimate Given"
    case followUpRequired = "Follow Up Required"
    case approved = "Approved"
    case rejected = "Rejected"
    case jobScheduled = "Job Scheduled"
    case completed = "Completed"

    var id: String { rawValue }
}
enum EstimateRecordStatus: String, CaseIterable, Identifiable, Codable {
    case draft = "Draft"
    case sent = "Sent"
    case approved = "Approved"
    case rejected = "Rejected"
    case expired = "Expired"
    case converted = "Converted"

    var id: String { rawValue }
}
enum DocumentType: String, CaseIterable, Identifiable, Codable {
    case estimate = "Estimate"
    case invoice = "Invoice"
    case receipt = "Receipt"

    var id: String { rawValue }
}
enum LeadStatus: String, CaseIterable, Identifiable, Codable {
    case newLead = "New Lead"
    case estimateScheduled = "Estimate Scheduled"
    case estimateGiven = "Estimate Given"
    case followUpRequired = "Follow Up Required"
    case approved = "Approved"
    case rejected = "Rejected"
    case converted = "Converted"

    var id: String { rawValue }
}
enum PaymentStatus: String, CaseIterable, Identifiable, Codable {
    case unpaid = "Unpaid"
    case paid = "Paid"
    case depositPaid = "Deposit Paid"

    var id: String { rawValue }
}
enum InvoiceStatus: String, CaseIterable, Identifiable, Codable {
    case draft = "Draft"
    case sent = "Sent"
    case partiallyPaid = "Partially Paid"
    case paid = "Paid"
    case overdue = "Overdue"
    case void = "Void"

    var id: String { rawValue }
}

enum RecordLifecycleStatus: String, CaseIterable, Identifiable, Codable {
    case active = "Active"
    case archived = "Archived"

    var id: String { rawValue }
}
enum JobStatus: String, CaseIterable, Identifiable, Codable {
    case toBeScheduled = "To Be Scheduled"
    case scheduled = "Scheduled"
    case assigned = "Assigned"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var id: String { rawValue }
}

struct Customer: Identifiable, Codable {
    var id = UUID()
    var customerNumber: String
    var businessName: String
    var contactName: String
    var phone: String
    var email: String
    var leadSource: LeadSource
    var estimateStatus: EstimateStatus
    var assignedEmployee: String
    var followUpDate: Date
    var lifecycleStatus: RecordLifecycleStatus = .active
}

struct Lead: Identifiable, Codable {
    var id = UUID()
    var leadNumber: String
    var businessName: String
    var contactName: String
    var phone: String
    var email: String
    var leadSource: LeadSource
    var serviceRequested: ServiceType
    var otherService: String
    var estimatedValue: Double
    var assignedSalesperson: String
    var status: LeadStatus
    var followUpDate: Date
    var createdDate: Date
    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct EstimateRecord: Identifiable, Codable, WorkOrder {
    var id = UUID()
    var estimateNumber: String
    var leadNumber: String
    var customerNumber: String
    var siteID: UUID?
    var serviceType: ServiceType
    var otherService: String
    var serviceDetails: String
    var lineItems: [ServiceLineItem] = []
    var subtotal: Double
    var discount: Double
    var total: Double
    var salesperson: String
    var status: EstimateRecordStatus
    var createdDate: Date
    var expirationDate: Date
    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct CustomerSite: Identifiable, Codable {
    var id = UUID()
    var customerNumber: String
    var siteName: String
    var serviceAddress: String
    var propertyType: String
    var accessNotes: String
    var workNotes: String
    var lifecycleStatus: RecordLifecycleStatus = .active
}

struct BusinessProfile: Codable {
    var businessName: String = ""
    var contactName: String = ""

    var phone: String = ""
    var email: String = ""
    var website: String = ""

    var addressLine1: String = ""
    var addressLine2: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""

    var invoiceHeaderText: String = ""
    var invoiceFooterText: String = ""

    var logoData: Data?
}


struct JobRecord: Identifiable, Codable, WorkOrder {
    var id = UUID()
    var jobNumber: String

    var customerNumber: String
    var siteID: UUID?
    var estimateNumber: String

    var serviceType: ServiceType
    var otherService: String
    var lineItems: [ServiceLineItem] = []
    var subtotal: Double
    var discount: Double
    var total: Double
    var primaryTechnician: String
    var secondaryTechnician: String
    var scheduledDate: Date
    var completedDate: Date?

    var status: JobStatus
    var workNotes: String

    var isRecurring: Bool
    var createdDate: Date

    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct InvoiceRecord: Identifiable, Codable, WorkOrder {
    var id = UUID()

    var invoiceNumber: String
    var customerNumber: String
    var siteID: UUID?
    var jobNumber: String

    var lineItems: [ServiceLineItem] = []

    var subtotal: Double
    var discount: Double
    var total: Double

    var amountPaid: Double
    var balanceDue: Double

    var status: InvoiceStatus

    var issueDate: Date
    var dueDate: Date
    var paidDate: Date?

    var notes: String

    var lifecycleStatus: RecordLifecycleStatus = .active
}
struct ServiceLineItem: Identifiable, Codable {
    var id = UUID()

    var catalogItemID: UUID?

    var serviceType: ServiceType
    var otherService: String

    var description: String
    var quantity: Double
    var unitPrice: Double
    var lineTotal: Double
}
struct ServiceCatalogItem: Identifiable, Codable {
    var id = UUID()
    var itemName: String
    var itemDescription: String
    var defaultQuantity: Double
    var defaultPrice: Double
    var itemType: CatalogItemType = .service
    var taxTreatment: TaxTreatment = .nonTaxable
    var usageCount: Int = 0
    var lastUsedDate: Date?
    var lifecycleStatus: RecordLifecycleStatus = .active

    private enum CodingKeys: String, CodingKey {
        case id
        case itemName
        case itemDescription
        case defaultQuantity
        case defaultPrice
        case itemType
        case taxTreatment
        case usageCount
        case lastUsedDate
        case lifecycleStatus
    }

    init(
        id: UUID = UUID(),
        itemName: String,
        itemDescription: String,
        defaultQuantity: Double,
        defaultPrice: Double,
        itemType: CatalogItemType = .service,
        taxTreatment: TaxTreatment = .nonTaxable,
        usageCount: Int = 0,
        lastUsedDate: Date? = nil,
        lifecycleStatus: RecordLifecycleStatus = .active
    ) {
        self.id = id
        self.itemName = itemName
        self.itemDescription = itemDescription
        self.defaultQuantity = defaultQuantity
        self.defaultPrice = defaultPrice
        self.itemType = itemType
        self.taxTreatment = taxTreatment
        self.usageCount = usageCount
        self.lastUsedDate = lastUsedDate
        self.lifecycleStatus = lifecycleStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        itemName = try container.decode(String.self, forKey: .itemName)
        itemDescription = try container.decode(String.self, forKey: .itemDescription)
        defaultQuantity = try container.decode(Double.self, forKey: .defaultQuantity)
        defaultPrice = try container.decode(Double.self, forKey: .defaultPrice)

        itemType = try container.decodeIfPresent(
            CatalogItemType.self,
            forKey: .itemType
        ) ?? .service

        taxTreatment = try container.decodeIfPresent(
            TaxTreatment.self,
            forKey: .taxTreatment
        ) ?? .nonTaxable

        usageCount = try container.decodeIfPresent(
            Int.self,
            forKey: .usageCount
        ) ?? 0

        lastUsedDate = try container.decodeIfPresent(
            Date.self,
            forKey: .lastUsedDate
        )

        lifecycleStatus = try container.decodeIfPresent(
            RecordLifecycleStatus.self,
            forKey: .lifecycleStatus
        ) ?? .active
    }
}
protocol WorkOrder {
    var lineItems: [ServiceLineItem] { get set }
    var discount: Double { get set }
}

extension WorkOrder {
    var calculatedSubtotal: Double {
        PricingCalculator.subtotal(for: lineItems)
    }

    var calculatedTotal: Double {
        PricingCalculator.total(
            subtotal: calculatedSubtotal,
            discount: discount
        )
    }
}
