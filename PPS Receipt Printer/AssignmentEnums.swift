//
//  AssignmentEnums.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation

// MARK: - Assignment Lifecycle

enum AssignmentStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case scheduled = "Scheduled"
    case dispatched = "Dispatched"
    case enRoute = "En Route"
    case onSite = "On Site"
    case workComplete = "Work Complete"
    case invoiceReady = "Invoice Ready"
    case closed = "Closed"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    var isActive: Bool {
        switch self {
        case .scheduled, .dispatched, .enRoute, .onSite, .workComplete, .invoiceReady:
            return true
        case .closed, .cancelled:
            return false
        }
    }

    var isTerminal: Bool {
        self == .closed || self == .cancelled
    }

    var sortOrder: Int {
        switch self {
        case .scheduled: return 0
        case .dispatched: return 1
        case .enRoute: return 2
        case .onSite: return 3
        case .workComplete: return 4
        case .invoiceReady: return 5
        case .closed: return 6
        case .cancelled: return 7
        }
    }
}

// MARK: - Scheduling

enum AssignmentSchedulingMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case fixedTime = "Fixed Time"
    case arrivalWindow = "Arrival Window"
    case flexibleDay = "Flexible Day"
    case deadline = "Deadline"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .fixedTime:
            return "Work begins at a specific scheduled time."
        case .arrivalWindow:
            return "The technician may arrive within a defined time window."
        case .flexibleDay:
            return "The assignment may be placed anywhere within the selected workday."
        case .deadline:
            return "The assignment must be completed by a specific date and time."
        }
    }
}

// MARK: - Priority

enum AssignmentPriority: String, CaseIterable, Identifiable, Codable, Hashable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case emergency = "Emergency"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        case .emergency: return 3
        }
    }
}

// MARK: - Crew

enum AssignmentCrewRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case primary = "Primary Technician"
    case supporting = "Supporting Technician"

    var id: String { rawValue }
}

// MARK: - History

enum AssignmentHistoryEventType: String, CaseIterable, Identifiable, Codable, Hashable {
    case created = "Created"
    case schedulingUpdated = "Scheduling Updated"
    case priorityChanged = "Priority Changed"
    case primaryTechnicianAssigned = "Primary Technician Assigned"
    case supportingTechnicianAdded = "Supporting Technician Added"
    case supportingTechnicianReplaced = "Supporting Technician Replaced"
    case technicianRemoved = "Technician Removed"
    case dispatched = "Dispatched"
    case statusChanged = "Status Changed"
    case routeOrderChanged = "Route Order Changed"
    case noteAdded = "Note Added"
    case workCompleted = "Work Completed"
    case invoiceMarkedReady = "Invoice Marked Ready"
    case closed = "Closed"
    case cancelled = "Cancelled"
    case reopened = "Reopened"
    case overrideApplied = "Override Applied"

    var id: String { rawValue }
}

// MARK: - Assignment Source

enum AssignmentCreationSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case jobConversion = "Job Conversion"
    case manual = "Manual"
    case recurringWork = "Recurring Work"
    case emergency = "Emergency"
    case system = "System"

    var id: String { rawValue }
}
