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

enum LeadServiceFrequency: String, CaseIterable, Identifiable, Codable {
    case monthly = "Monthly"
    case biWeekly = "Bi-Weekly"
    case weekly = "Weekly"
    case oneTime = "One time"

    var id: String { rawValue }
}

struct LeadQuoteOption: Identifiable, Codable, Equatable {
    var id = UUID()
    var quotedPrice: Double
    var frequency: LeadServiceFrequency
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
    case travelPaused = "Travel Paused"
    case arrived = "Arrived"
    case settingUp = "Setting Up"
    case working = "Working"
    case paused = "Paused"
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
    case travelPaused
    case travelResumed
    case arrived
    case setupStarted
    case workStarted
    case workPaused
    case workResumed
    case packUpStarted
    case workCompleted
    case invoiceCreated
    case invoiceSent
    case paymentReceived
    case jobCompleted
    case cancelled
    case note
    case timelineCorrected
}

struct JobTimelineEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var type: JobTimelineEventType
    var title: String
    var timestamp: Date
    var employeeID: UUID?
    var note: String?
    var correctedEventID: UUID?
    var originalTimestamp: Date?
    var correctedTimestamp: Date?

    init(
        id: UUID = UUID(),
        type: JobTimelineEventType,
        title: String,
        timestamp: Date = Date(),
        employeeID: UUID? = nil,
        note: String? = nil,
        correctedEventID: UUID? = nil,
        originalTimestamp: Date? = nil,
        correctedTimestamp: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.timestamp = timestamp
        self.employeeID = employeeID
        self.note = note
        self.correctedEventID = correctedEventID
        self.originalTimestamp = originalTimestamp
        self.correctedTimestamp = correctedTimestamp
    }
}

enum EmployeeRole: String, CaseIterable, Identifiable, Codable {
    case owner = "Owner"
    case manager = "Manager"
    case office = "Office"
    case salesperson = "Salesperson"
    case technician = "Technician"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .salesperson:
            return "Sales"
        default:
            return rawValue
        }
    }

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

    /// The employee's normal starting location when PFSS does not have a
    /// dependable operational location. This may be a home, shop, yard, or
    /// other business-approved base address.
    var baseAddress: String

    var role: EmployeeRole

    /// Every business role this employee may perform. `role` remains the
    /// compatibility/authorization primary role for older saved records.
    var roles: Set<EmployeeRole>

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

    /// Operational capabilities and preferences used by Workforce Intelligence.
    /// Existing employees decode with an empty profile.
    var workforceProfile: WorkforceOperationalProfile

    /// Per-user field workflow reminder timing. A value of zero disables that
    /// reminder without affecting the other reminder.
    var jobTimerReminderPreferences: JobTimerReminderPreferences

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        phone: String = "",
        email: String = "",
        baseAddress: String = "",
        role: EmployeeRole = .technician,
        roles: Set<EmployeeRole>? = nil,
        defaultStartMinutes: Int = 480,
        defaultEndMinutes: Int = 1020,
        lunchDurationMinutes: Int = 30,
        workingDays: Set<Workday> = Workday.standardWorkweek,
        colorName: String = "blue",
        isActive: Bool = true,
        createdDate: Date = Date(),
        lifecycleStatus: RecordLifecycleStatus = .active,
        workforceProfile: WorkforceOperationalProfile = WorkforceOperationalProfile(),
        jobTimerReminderPreferences: JobTimerReminderPreferences =
            JobTimerReminderPreferences()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.baseAddress = baseAddress
        let selectedRoles = Self.validRoles(roles, fallback: role)
        self.roles = selectedRoles
        self.role = selectedRoles.contains(role)
            ? role
            : Self.preferredPrimaryRole(in: selectedRoles)
        self.defaultStartMinutes = defaultStartMinutes
        self.defaultEndMinutes = defaultEndMinutes
        self.lunchDurationMinutes = lunchDurationMinutes
        self.workingDays = workingDays
        self.colorName = colorName
        self.isActive = isActive
        self.createdDate = createdDate
        self.lifecycleStatus = lifecycleStatus
        self.workforceProfile = workforceProfile
        self.jobTimerReminderPreferences = jobTimerReminderPreferences
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

    func hasRole(_ role: EmployeeRole) -> Bool {
        roles.contains(role) || (roles.isEmpty && self.role == role)
    }

    var roleDisplayText: String {
        EmployeeRole.allCases
            .filter(hasRole)
            .map(\.displayName)
            .joined(separator: ", ")
    }

    var normalizedBaseAddress: String? {
        let address = baseAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return address.isEmpty ? nil : address
    }

    var canOverrideScheduling: Bool {
        roles.contains { $0.canOverrideScheduling } || role.canOverrideScheduling
    }

    mutating func normalizeRoles() {
        roles = Self.validRoles(roles, fallback: role)
        role = Self.preferredPrimaryRole(in: roles)
    }

    private static func validRoles(
        _ roles: Set<EmployeeRole>?,
        fallback: EmployeeRole
    ) -> Set<EmployeeRole> {
        guard let roles, roles.isEmpty == false else { return [fallback] }
        return roles
    }

    private static func preferredPrimaryRole(
        in roles: Set<EmployeeRole>
    ) -> EmployeeRole {
        EmployeeRole.allCases.first(where: roles.contains) ?? .technician
    }
}

extension EmployeeRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case firstName
        case lastName
        case phone
        case email
        case baseAddress
        case role
        case roles
        case defaultStartMinutes
        case defaultEndMinutes
        case lunchDurationMinutes
        case workingDays
        case colorName
        case isActive
        case createdDate
        case lifecycleStatus
        case workforceProfile
        case jobTimerReminderPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        baseAddress = try container.decodeIfPresent(
            String.self,
            forKey: .baseAddress
        ) ?? ""
        let legacyRole = try container.decodeIfPresent(
            EmployeeRole.self,
            forKey: .role
        ) ?? .technician
        roles = try container.decodeIfPresent(
            Set<EmployeeRole>.self,
            forKey: .roles
        ) ?? [legacyRole]
        roles = Self.validRoles(roles, fallback: legacyRole)
        role = roles.contains(legacyRole)
            ? legacyRole
            : Self.preferredPrimaryRole(in: roles)
        defaultStartMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .defaultStartMinutes
        ) ?? 480
        defaultEndMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .defaultEndMinutes
        ) ?? 1020
        lunchDurationMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .lunchDurationMinutes
        ) ?? 30
        workingDays = try container.decodeIfPresent(
            Set<Workday>.self,
            forKey: .workingDays
        ) ?? Workday.standardWorkweek
        colorName = try container.decodeIfPresent(
            String.self,
            forKey: .colorName
        ) ?? "blue"
        isActive = try container.decodeIfPresent(
            Bool.self,
            forKey: .isActive
        ) ?? true
        createdDate = try container.decodeIfPresent(
            Date.self,
            forKey: .createdDate
        ) ?? Date()
        lifecycleStatus = try container.decodeIfPresent(
            RecordLifecycleStatus.self,
            forKey: .lifecycleStatus
        ) ?? .active
        workforceProfile = try container.decodeIfPresent(
            WorkforceOperationalProfile.self,
            forKey: .workforceProfile
        ) ?? WorkforceOperationalProfile()
        jobTimerReminderPreferences = try container.decodeIfPresent(
            JobTimerReminderPreferences.self,
            forKey: .jobTimerReminderPreferences
        ) ?? JobTimerReminderPreferences()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(phone, forKey: .phone)
        try container.encode(email, forKey: .email)
        try container.encode(baseAddress, forKey: .baseAddress)
        try container.encode(role, forKey: .role)
        try container.encode(
            roles.sorted { $0.rawValue < $1.rawValue },
            forKey: .roles
        )
        try container.encode(defaultStartMinutes, forKey: .defaultStartMinutes)
        try container.encode(defaultEndMinutes, forKey: .defaultEndMinutes)
        try container.encode(lunchDurationMinutes, forKey: .lunchDurationMinutes)
        try container.encode(
            workingDays.sorted { $0.rawValue < $1.rawValue },
            forKey: .workingDays
        )
        try container.encode(colorName, forKey: .colorName)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lifecycleStatus, forKey: .lifecycleStatus)
        try container.encode(workforceProfile, forKey: .workforceProfile)
        try container.encode(
            jobTimerReminderPreferences,
            forKey: .jobTimerReminderPreferences
        )
    }
}

struct JobTimerReminderPreferences: Codable, Equatable {
    var arrivalToSetupMinutes: Int
    var setupToWorkMinutes: Int

    init(
        arrivalToSetupMinutes: Int = 5,
        setupToWorkMinutes: Int = 5
    ) {
        self.arrivalToSetupMinutes = max(arrivalToSetupMinutes, 0)
        self.setupToWorkMinutes = max(setupToWorkMinutes, 0)
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
    /// Optional for backward compatibility with leads created before Location.
    var location: String? = nil
    var phone: String
    var email: String
    /// Free-form sales context retained throughout the lead lifecycle.
    /// Optional for backward compatibility with leads created before this field.
    var notes: String? = nil
    var leadSource: LeadSource
    var serviceRequested: ServiceType
    var otherService: String
    var estimatedValue: Double
    /// Each proposed price and its corresponding service frequency.
    /// The first price remains mirrored to `estimatedValue` for compatibility.
    var quoteOptions: [LeadQuoteOption]? = nil
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
    /// Dispatch constraints selected while the Job is created. Keeping these
    /// on the business record allows recurring occurrences to inherit them.
    var assignmentSchedulingMode: AssignmentSchedulingMode = .fixedTime
    var arrivalWindowEnd: Date? = nil
    var completionDeadline: Date? = nil
    var assignmentPriority: AssignmentPriority = .normal
    var setupStartDate: Date? = nil
    var completedDate: Date?

    var status: JobStatus
    var workflowState: JobWorkflowState = .notStarted
    var timelineEvents: [JobTimelineEvent] = []
    var workNotes: String

    var isRecurring: Bool
    var recurrenceFrequency: JobRecurrenceFrequency? = nil
    var recurrenceSeriesID: UUID? = nil
    var recurrenceSequence: Int = 0
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
        case assignmentSchedulingMode
        case arrivalWindowEnd
        case completionDeadline
        case assignmentPriority
        case setupStartDate
        case completedDate
        case status
        case workflowState
        case timelineEvents
        case workNotes
        case isRecurring
        case recurrenceFrequency
        case recurrenceSeriesID
        case recurrenceSequence
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

        assignmentSchedulingMode = try container.decodeIfPresent(
            AssignmentSchedulingMode.self,
            forKey: .assignmentSchedulingMode
        ) ?? .fixedTime

        arrivalWindowEnd = try container.decodeIfPresent(
            Date.self,
            forKey: .arrivalWindowEnd
        )

        completionDeadline = try container.decodeIfPresent(
            Date.self,
            forKey: .completionDeadline
        )

        assignmentPriority = try container.decodeIfPresent(
            AssignmentPriority.self,
            forKey: .assignmentPriority
        ) ?? .normal

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

        recurrenceFrequency = try container.decodeIfPresent(
            JobRecurrenceFrequency.self,
            forKey: .recurrenceFrequency
        )

        recurrenceSeriesID = try container.decodeIfPresent(
            UUID.self,
            forKey: .recurrenceSeriesID
        )

        recurrenceSequence = try container.decodeIfPresent(
            Int.self,
            forKey: .recurrenceSequence
        ) ?? 0

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
