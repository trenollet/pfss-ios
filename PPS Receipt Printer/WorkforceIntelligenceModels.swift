//
//  WorkforceIntelligenceModels.swift
//  PPS Receipt Printer
//
//  Phase 14.5 — Workforce Intelligence
//

import Foundation

// MARK: - Skills

enum WorkforceProficiency: Int, CaseIterable, Identifiable, Codable, Comparable {
    case learning = 1
    case capable = 2
    case proficient = 3
    case expert = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .learning: return "Learning"
        case .capable: return "Capable"
        case .proficient: return "Proficient"
        case .expert: return "Expert"
        }
    }

    static func < (
        lhs: WorkforceProficiency,
        rhs: WorkforceProficiency
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WorkforceSkill: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var category: String
    var serviceType: ServiceType?
    var proficiency: WorkforceProficiency
    var yearsOfExperience: Double
    var isVerified: Bool
    var notes: String
    var updatedDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "Service",
        serviceType: ServiceType? = nil,
        proficiency: WorkforceProficiency = .capable,
        yearsOfExperience: Double = 0,
        isVerified: Bool = false,
        notes: String = "",
        updatedDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.serviceType = serviceType
        self.proficiency = proficiency
        self.yearsOfExperience = max(yearsOfExperience, 0)
        self.isVerified = isVerified
        self.notes = notes
        self.updatedDate = updatedDate
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var isValid: Bool {
        !normalizedName.isEmpty
    }
}

// MARK: - Certifications

enum WorkforceCertificationStatus: String, Codable, Hashable {
    case active = "Active"
    case expiresSoon = "Expires Soon"
    case expired = "Expired"
    case inactive = "Inactive"
}

struct WorkforceCertification: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var issuingOrganization: String
    var credentialNumber: String
    var issuedDate: Date?
    var expirationDate: Date?
    var isActive: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        issuingOrganization: String = "",
        credentialNumber: String = "",
        issuedDate: Date? = nil,
        expirationDate: Date? = nil,
        isActive: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.issuingOrganization = issuingOrganization
        self.credentialNumber = credentialNumber
        self.issuedDate = issuedDate
        self.expirationDate = expirationDate
        self.isActive = isActive
        self.notes = notes
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func status(
        on date: Date = Date(),
        warningDays: Int = 30,
        calendar: Calendar = .current
    ) -> WorkforceCertificationStatus {
        guard isActive else { return .inactive }
        guard let expirationDate else { return .active }

        let comparisonDate = calendar.startOfDay(for: date)
        let expirationDay = calendar.startOfDay(for: expirationDate)

        if expirationDay < comparisonDate {
            return .expired
        }

        let warningDate = calendar.date(
            byAdding: .day,
            value: max(warningDays, 0),
            to: comparisonDate
        ) ?? comparisonDate

        return expirationDay <= warningDate ? .expiresSoon : .active
    }

    func isValid(on date: Date = Date()) -> Bool {
        let currentStatus = status(on: date)
        return currentStatus == .active || currentStatus == .expiresSoon
    }
}

// MARK: - Equipment and Vehicle Access

enum WorkforceResourceType: String, CaseIterable, Identifiable, Codable {
    case vehicle = "Vehicle"
    case equipment = "Equipment"
    case tool = "Tool"
    case safetyGear = "Safety Gear"
    case specialty = "Specialty Resource"

    var id: String { rawValue }
}

struct WorkforceResourceAccess: Identifiable, Codable, Hashable {
    var id: UUID
    var resourceID: UUID?
    var name: String
    var type: WorkforceResourceType
    var capabilityTags: [String]
    var isAvailable: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        resourceID: UUID? = nil,
        name: String,
        type: WorkforceResourceType,
        capabilityTags: [String] = [],
        isAvailable: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.resourceID = resourceID
        self.name = name
        self.type = type
        self.capabilityTags = capabilityTags
        self.isAvailable = isAvailable
        self.notes = notes
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

// MARK: - Availability Exceptions

enum WorkforceAvailabilityKind: String, CaseIterable, Identifiable, Codable {
    case unavailable = "Unavailable"
    case available = "Available Override"
    case limited = "Limited Availability"

    var id: String { rawValue }
}

struct WorkforceAvailabilityException: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: WorkforceAvailabilityKind
    var startDate: Date
    var endDate: Date
    var reason: String

    init(
        id: UUID = UUID(),
        kind: WorkforceAvailabilityKind,
        startDate: Date,
        endDate: Date,
        reason: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = max(endDate, startDate)
        self.reason = reason
    }

    func overlaps(_ interval: DateInterval) -> Bool {
        DateInterval(start: startDate, end: endDate)
            .intersects(interval)
    }
}

// MARK: - Historical Metrics

/// A persisted operational snapshot, not the source of truth for assignments.
/// Step 5's engine can refresh it from assignment and job history.
struct WorkforceHistoricalMetrics: Codable, Hashable {
    var completedAssignmentCount: Int
    var totalRecordedLaborMinutes: Int
    var averageAssignmentMinutes: Double?
    var onTimeArrivalRate: Double?
    var firstTimeCompletionRate: Double?
    var averageCustomerRating: Double?
    var lastCompletedAssignmentDate: Date?
    var calculatedDate: Date?

    init(
        completedAssignmentCount: Int = 0,
        totalRecordedLaborMinutes: Int = 0,
        averageAssignmentMinutes: Double? = nil,
        onTimeArrivalRate: Double? = nil,
        firstTimeCompletionRate: Double? = nil,
        averageCustomerRating: Double? = nil,
        lastCompletedAssignmentDate: Date? = nil,
        calculatedDate: Date? = nil
    ) {
        self.completedAssignmentCount = max(completedAssignmentCount, 0)
        self.totalRecordedLaborMinutes = max(totalRecordedLaborMinutes, 0)
        self.averageAssignmentMinutes = Self.nonnegative(averageAssignmentMinutes)
        self.onTimeArrivalRate = Self.fraction(onTimeArrivalRate)
        self.firstTimeCompletionRate = Self.fraction(firstTimeCompletionRate)
        self.averageCustomerRating = averageCustomerRating.map {
            min(max($0, 0), 5)
        }
        self.lastCompletedAssignmentDate = lastCompletedAssignmentDate
        self.calculatedDate = calculatedDate
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(value, 0)
    }

    private static func fraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

// MARK: - Operational Profile

struct WorkforceOperationalProfile: Codable, Hashable {
    var skills: [WorkforceSkill]
    var certifications: [WorkforceCertification]
    var resourceAccess: [WorkforceResourceAccess]
    var availabilityExceptions: [WorkforceAvailabilityException]
    var historicalMetrics: WorkforceHistoricalMetrics
    var maximumDailyAssignments: Int?
    var maximumTravelDistanceMiles: Double?
    var operationalNotes: String

    init(
        skills: [WorkforceSkill] = [],
        certifications: [WorkforceCertification] = [],
        resourceAccess: [WorkforceResourceAccess] = [],
        availabilityExceptions: [WorkforceAvailabilityException] = [],
        historicalMetrics: WorkforceHistoricalMetrics = WorkforceHistoricalMetrics(),
        maximumDailyAssignments: Int? = nil,
        maximumTravelDistanceMiles: Double? = nil,
        operationalNotes: String = ""
    ) {
        self.skills = skills
        self.certifications = certifications
        self.resourceAccess = resourceAccess
        self.availabilityExceptions = availabilityExceptions
        self.historicalMetrics = historicalMetrics
        self.maximumDailyAssignments = maximumDailyAssignments.map { max($0, 1) }
        self.maximumTravelDistanceMiles = maximumTravelDistanceMiles.flatMap {
            guard $0.isFinite else { return nil }
            return max($0, 0)
        }
        self.operationalNotes = operationalNotes
    }

    var hasIntelligenceData: Bool {
        !skills.isEmpty ||
        !certifications.isEmpty ||
        !resourceAccess.isEmpty ||
        !availabilityExceptions.isEmpty ||
        historicalMetrics.calculatedDate != nil ||
        maximumDailyAssignments != nil ||
        maximumTravelDistanceMiles != nil ||
        !operationalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Capability Requirements

/// Engine-neutral requirements that a Job, Assignment, or future catalog item
/// can provide to Workforce Intelligence.
struct WorkforceCapabilityRequirements: Codable, Hashable {
    var requiredServiceType: ServiceType?
    var minimumProficiency: WorkforceProficiency
    var requiredSkillNames: [String]
    var requiredCertificationNames: [String]
    var requiredResourceNames: [String]
    var requiresVehicleAccess: Bool

    init(
        requiredServiceType: ServiceType? = nil,
        minimumProficiency: WorkforceProficiency = .capable,
        requiredSkillNames: [String] = [],
        requiredCertificationNames: [String] = [],
        requiredResourceNames: [String] = [],
        requiresVehicleAccess: Bool = false
    ) {
        self.requiredServiceType = requiredServiceType
        self.minimumProficiency = minimumProficiency
        self.requiredSkillNames = requiredSkillNames
        self.requiredCertificationNames = requiredCertificationNames
        self.requiredResourceNames = requiredResourceNames
        self.requiresVehicleAccess = requiresVehicleAccess
    }

    var isEmpty: Bool {
        requiredServiceType == nil &&
        requiredSkillNames.isEmpty &&
        requiredCertificationNames.isEmpty &&
        requiredResourceNames.isEmpty &&
        !requiresVehicleAccess
    }
}
