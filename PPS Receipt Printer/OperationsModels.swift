//
//  OperationsModels.swift
//  PFSS
//
//  UI models for the Operations workspace.
//

import Foundation

// MARK: - Technician

struct TechnicianStatusModel: Identifiable, Hashable {

    let id: UUID

    var employeeID: UUID?
    var name: String

    var status: TechnicianStatus

    var jobsToday: Int
    var utilization: Double        // 0.0 - 1.0

    var nextOpening: Date?

    var travelMinutes: Int

    var revenueToday: Double

    var confidence: Double?

    init(
        id: UUID = UUID(),
        employeeID: UUID? = nil,
        name: String,
        status: TechnicianStatus = .available,
        jobsToday: Int = 0,
        utilization: Double = 0,
        nextOpening: Date? = nil,
        travelMinutes: Int = 0,
        revenueToday: Double = 0,
        confidence: Double? = nil
    ) {

        self.id = id
        self.employeeID = employeeID
        self.name = name
        self.status = status
        self.jobsToday = jobsToday
        self.utilization = utilization
        self.nextOpening = nextOpening
        self.travelMinutes = travelMinutes
        self.revenueToday = revenueToday
        self.confidence = confidence
    }
}

enum TechnicianStatus: String, CaseIterable {

    case available
    case working
    case traveling
    case travelPaused
    case lunch
    case offline
    case overtime

    var displayName: String {

        switch self {

        case .available:
            return "Available"

        case .working:
            return "Working"

        case .traveling:
            return "Traveling"

        case .travelPaused:
            return "Travel Paused"

        case .lunch:
            return "Lunch"

        case .offline:
            return "Offline"

        case .overtime:
            return "Overtime"
        }
    }
}

// MARK: - Dispatch Queue

struct DispatchQueueItem: Identifiable, Hashable {

    let id: UUID

    var jobID: UUID?

    var customerName: String
    var address: String

    var estimatedDuration: TimeInterval

    var priority: DispatchPriority

    var recommendedTechnician: String?

    var confidence: Double

    init(
        id: UUID = UUID(),
        jobID: UUID? = nil,
        customerName: String,
        address: String,
        estimatedDuration: TimeInterval,
        priority: DispatchPriority = .normal,
        recommendedTechnician: String? = nil,
        confidence: Double = 0
    ) {

        self.id = id
        self.jobID = jobID
        self.customerName = customerName
        self.address = address
        self.estimatedDuration = estimatedDuration
        self.priority = priority
        self.recommendedTechnician = recommendedTechnician
        self.confidence = confidence
    }
}

enum DispatchPriority: String, CaseIterable {

    case low
    case normal
    case high
    case emergency
}

// MARK: - Capacity

struct CapacityForecast: Identifiable, Hashable {

    let id = UUID()

    var day: String

    var utilization: Double
}

// MARK: - Revenue

struct RevenueSummary: Hashable {

    var scheduled: Double

    var completed: Double

    var invoiced: Double

    var collected: Double
}

// MARK: - Recommendations

struct RecommendationItem: Identifiable, Hashable {

    let id = UUID()

    var title: String

    var detail: String

    var priority: RecommendationPriority
}

enum RecommendationPriority: String, CaseIterable {

    case low
    case medium
    case high
}
