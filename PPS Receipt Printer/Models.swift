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

enum JobWorkflowState: String, CaseIterable, Identifiable, Codable {
    case notStarted = "Not Started"
    case traveling = "Traveling"
    case arrived = "Arrived"
    case settingUp = "Setting Up"
    case working = "Working"
    case packingUp = "Packing Up"
    case workComplete = "Work Complete"
    case invoiceCreated = "Invoice Created"
    case paymentReceived = "Payment Received"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var id: String { rawValue }
}

enum JobTimelineEventType: String, Codable {
    case assigned
    case travelStarted
    case arrived
    case setupStarted
    case workStarted
    case packUpStarted
    case workCompleted
    case invoiceCreated
    case paymentReceived
    case jobCompleted
    case cancelled
    case note
}

struct JobTimelineEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var type: JobTimelineEventType
    var title: String
    var timestamp: Date
    var employeeID: UUID?
    var note: String?

    init(
        id: UUID = UUID(),
        type: JobTimelineEventType,
        title: String,
        timestamp: Date = Date(),
        employeeID: UUID? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.timestamp = timestamp
        self.employeeID = employeeID
        self.note = note
    }
}

enum EmployeeRole: String, CaseIterable, Identifiable, Codable {
    case owner = "Owner"
    case manager = "Manager"
    case office = "Office"
    case salesperson = "Salesperson"
    case technician = "Technician"

    var id: String { rawValue }

    var canOverrideScheduling: Bool {
        switch self {
        case .owner, .manager:
            return true

        case .office, .salesperson, .technician:
            return false
        }
    }
}

enum Workday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .sunday:
            return "Sunday"
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        }
    }

    var shortName: String {
        String(name.prefix(3))
    }

    static let standardWorkweek: Set<Workday> = [
        .monday,
        .tuesday,
        .wednesday,
        .thursday,
        .friday
    ]
}

struct EmployeeRecord: Identifiable, Codable {
    var id = UUID()

    var firstName: String
    var lastName: String

    var phone: String
    var email: String

    var role: EmployeeRole

    // Stored as minutes after midnight.
    var defaultStartMinutes: Int
    var defaultEndMinutes: Int
    var lunchDurationMinutes: Int

    var workingDays: Set<Workday>

    // A stable name such as "blue", "green", or "orange".
    // We will translate this into a SwiftUI Color in the view layer.
    var colorName: String

    var isActive: Bool

    var createdDate: Date
    var lifecycleStatus: RecordLifecycleStatus

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        phone: String = "",
        email: String = "",
        role: EmployeeRole = .technician,
        defaultStartMinutes: Int = 480,
        defaultEndMinutes: Int = 1020,
        lunchDurationMinutes: Int = 30,
        workingDays: Set<Workday> = Workday.standardWorkweek,
        colorName: String = "blue",
        isActive: Bool = true,
        createdDate: Date = Date(),
        lifecycleStatus: RecordLifecycleStatus = .active
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.role = role
        self.defaultStartMinutes = defaultStartMinutes
        self.defaultEndMinutes = defaultEndMinutes
        self.lunchDurationMinutes = lunchDurationMinutes
        self.workingDays = workingDays
        self.colorName = colorName
        self.isActive = isActive
        self.createdDate = createdDate
        self.lifecycleStatus = lifecycleStatus
    }

    var displayName: String {
        let fullName = "\(firstName) \(lastName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fullName.isEmpty
            ? "Unnamed Employee"
            : fullName
    }

    var dailyCapacityMinutes: Int {
        let workdayMinutes = max(
            defaultEndMinutes - defaultStartMinutes,
            0
        )

        return max(
            workdayMinutes - lunchDurationMinutes,
            0
        )
    }
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

struct BusinessOperationsSettings: Codable, Equatable {
    var averageDrivingSpeedMPH: Double = 30
    var dailyRouteBufferMinutes: Int = 20
    var perStopBufferMinutes: Int = 3
    var includeBuffersInRouteTime: Bool = true

    mutating func normalize() {
        averageDrivingSpeedMPH = min(
            max(averageDrivingSpeedMPH, 5),
            80
        )

        dailyRouteBufferMinutes = min(
            max(dailyRouteBufferMinutes, 0),
            240
        )

        perStopBufferMinutes = min(
            max(perStopBufferMinutes, 0),
            60
        )
    }
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

    var operations = BusinessOperationsSettings()

    private enum CodingKeys: String, CodingKey {
        case businessName
        case contactName
        case phone
        case email
        case website
        case addressLine1
        case addressLine2
        case city
        case state
        case postalCode
        case invoiceHeaderText
        case invoiceFooterText
        case logoData
        case operations
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        businessName = try container.decodeIfPresent(
            String.self,
            forKey: .businessName
        ) ?? ""

        contactName = try container.decodeIfPresent(
            String.self,
            forKey: .contactName
        ) ?? ""

        phone = try container.decodeIfPresent(
            String.self,
            forKey: .phone
        ) ?? ""

        email = try container.decodeIfPresent(
            String.self,
            forKey: .email
        ) ?? ""

        website = try container.decodeIfPresent(
            String.self,
            forKey: .website
        ) ?? ""

        addressLine1 = try container.decodeIfPresent(
            String.self,
            forKey: .addressLine1
        ) ?? ""

        addressLine2 = try container.decodeIfPresent(
            String.self,
            forKey: .addressLine2
        ) ?? ""

        city = try container.decodeIfPresent(
            String.self,
            forKey: .city
        ) ?? ""

        state = try container.decodeIfPresent(
            String.self,
            forKey: .state
        ) ?? ""

        postalCode = try container.decodeIfPresent(
            String.self,
            forKey: .postalCode
        ) ?? ""

        invoiceHeaderText = try container.decodeIfPresent(
            String.self,
            forKey: .invoiceHeaderText
        ) ?? ""

        invoiceFooterText = try container.decodeIfPresent(
            String.self,
            forKey: .invoiceFooterText
        ) ?? ""

        logoData = try container.decodeIfPresent(
            Data.self,
            forKey: .logoData
        )

        operations = try container.decodeIfPresent(
            BusinessOperationsSettings.self,
            forKey: .operations
        ) ?? BusinessOperationsSettings()

        operations.normalize()
    }
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
    var primaryTechnicianID: UUID?
    var secondaryTechnicianID: UUID?
    var scheduledDate: Date
    var scheduledDurationOverrideMinutes: Int? = nil
    var setupStartDate: Date? = nil
    var completedDate: Date?

    var status: JobStatus
    var workflowState: JobWorkflowState = .notStarted
    var timelineEvents: [JobTimelineEvent] = []
    var workNotes: String

    var isRecurring: Bool
    var createdDate: Date

    var lifecycleStatus: RecordLifecycleStatus = .active
}

extension JobRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case jobNumber
        case customerNumber
        case siteID
        case estimateNumber
        case serviceType
        case otherService
        case lineItems
        case subtotal
        case discount
        case total
        case primaryTechnicianID
        case secondaryTechnicianID
        case scheduledDate
        case scheduledDurationOverrideMinutes
        case setupStartDate
        case completedDate
        case status
        case workflowState
        case timelineEvents
        case workNotes
        case isRecurring
        case createdDate
        case lifecycleStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decodeIfPresent(
            UUID.self,
            forKey: .id
        ) ?? UUID()

        jobNumber = try container.decode(
            String.self,
            forKey: .jobNumber
        )

        customerNumber = try container.decode(
            String.self,
            forKey: .customerNumber
        )

        siteID = try container.decodeIfPresent(
            UUID.self,
            forKey: .siteID
        )

        estimateNumber = try container.decodeIfPresent(
            String.self,
            forKey: .estimateNumber
        ) ?? ""

        serviceType = try container.decode(
            ServiceType.self,
            forKey: .serviceType
        )

        otherService = try container.decodeIfPresent(
            String.self,
            forKey: .otherService
        ) ?? ""

        lineItems = try container.decodeIfPresent(
            [ServiceLineItem].self,
            forKey: .lineItems
        ) ?? []

        subtotal = try container.decodeIfPresent(
            Double.self,
            forKey: .subtotal
        ) ?? 0

        discount = try container.decodeIfPresent(
            Double.self,
            forKey: .discount
        ) ?? 0

        total = try container.decodeIfPresent(
            Double.self,
            forKey: .total
        ) ?? 0

        primaryTechnicianID = try container.decodeIfPresent(
            UUID.self,
            forKey: .primaryTechnicianID
        )

        secondaryTechnicianID = try container.decodeIfPresent(
            UUID.self,
            forKey: .secondaryTechnicianID
        )

        scheduledDate = try container.decode(
            Date.self,
            forKey: .scheduledDate
        )

        scheduledDurationOverrideMinutes =
            try container.decodeIfPresent(
                Int.self,
                forKey: .scheduledDurationOverrideMinutes
            )

        setupStartDate = try container.decodeIfPresent(
            Date.self,
            forKey: .setupStartDate
        )

        completedDate = try container.decodeIfPresent(
            Date.self,
            forKey: .completedDate
        )

        status = try container.decodeIfPresent(
            JobStatus.self,
            forKey: .status
        ) ?? .scheduled

        workflowState = try container.decodeIfPresent(
            JobWorkflowState.self,
            forKey: .workflowState
        ) ?? Self.legacyWorkflowState(for: status)

        timelineEvents = try container.decodeIfPresent(
            [JobTimelineEvent].self,
            forKey: .timelineEvents
        ) ?? []

        workNotes = try container.decodeIfPresent(
            String.self,
            forKey: .workNotes
        ) ?? ""

        isRecurring = try container.decodeIfPresent(
            Bool.self,
            forKey: .isRecurring
        ) ?? false

        createdDate = try container.decodeIfPresent(
            Date.self,
            forKey: .createdDate
        ) ?? Date()

        lifecycleStatus = try container.decodeIfPresent(
            RecordLifecycleStatus.self,
            forKey: .lifecycleStatus
        ) ?? .active
    }

    private static func legacyWorkflowState(
        for status: JobStatus
    ) -> JobWorkflowState {
        switch status {
        case .inProgress:
            return .working
        case .completed:
            return .completed
        case .cancelled:
            return .cancelled
        case .toBeScheduled, .scheduled, .assigned:
            return .notStarted
        }
    }
}


extension JobRecord {
    /// The beginning of tracked field time.
    ///
    /// New jobs store this directly in `setupStartDate`. The timeline fallback
    /// also supports jobs completed while Brick 9 was being tested, where the
    /// workflow event was saved but the dedicated timestamp was not.
    var trackedStartDate: Date? {
        if let setupStartDate {
            return setupStartDate
        }

        return timelineEvents
            .filter { $0.type == .setupStarted }
            .map(\.timestamp)
            .min()
    }

    /// The end of tracked field time.
    ///
    /// Prefer the dedicated completion timestamp, then recover it from either
    /// completion event used by the workflow engine.
    var trackedCompletionDate: Date? {
        if let completedDate {
            return completedDate
        }

        return timelineEvents
            .filter {
                $0.type == .jobCompleted ||
                $0.type == .workCompleted
            }
            .map(\.timestamp)
            .max()
    }

    var timeOnJob: TimeInterval? {
        guard let start = trackedStartDate,
              let completion = trackedCompletionDate,
              completion >= start else {
            return nil
        }

        return completion.timeIntervalSince(start)
    }
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

    var estimatedMinutesPerUnit: Int = 0

    private enum CodingKeys: String, CodingKey {
        case id
        case catalogItemID
        case serviceType
        case otherService
        case description
        case quantity
        case unitPrice
        case lineTotal
        case estimatedMinutesPerUnit
    }

    init(
        id: UUID = UUID(),
        catalogItemID: UUID? = nil,
        serviceType: ServiceType,
        otherService: String,
        description: String,
        quantity: Double,
        unitPrice: Double,
        lineTotal: Double,
        estimatedMinutesPerUnit: Int = 0
    ) {
        self.id = id
        self.catalogItemID = catalogItemID
        self.serviceType = serviceType
        self.otherService = otherService
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineTotal = lineTotal
        self.estimatedMinutesPerUnit = estimatedMinutesPerUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decodeIfPresent(
            UUID.self,
            forKey: .id
        ) ?? UUID()

        catalogItemID = try container.decodeIfPresent(
            UUID.self,
            forKey: .catalogItemID
        )

        serviceType = try container.decode(
            ServiceType.self,
            forKey: .serviceType
        )

        otherService = try container.decode(
            String.self,
            forKey: .otherService
        )

        description = try container.decode(
            String.self,
            forKey: .description
        )

        quantity = try container.decode(
            Double.self,
            forKey: .quantity
        )

        unitPrice = try container.decode(
            Double.self,
            forKey: .unitPrice
        )

        lineTotal = try container.decode(
            Double.self,
            forKey: .lineTotal
        )

        estimatedMinutesPerUnit = try container.decodeIfPresent(
            Int.self,
            forKey: .estimatedMinutesPerUnit
        ) ?? 0
    }
}
struct ServiceCatalogItem: Identifiable, Codable {
    var id = UUID()
    var itemName: String
    var itemDescription: String
    var defaultQuantity: Double
    var defaultPrice: Double
    var estimatedMinutesPerUnit: Int = 0
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
        case estimatedMinutesPerUnit
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
        estimatedMinutesPerUnit: Int = 0,
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
        self.estimatedMinutesPerUnit = estimatedMinutesPerUnit
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
        estimatedMinutesPerUnit = try container.decodeIfPresent(
            Int.self,
            forKey: .estimatedMinutesPerUnit
        ) ?? 0

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

