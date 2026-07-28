//
//  LiveMapModels.swift
//  PPS Receipt Printer
//
//  Phase 14.9 – Live Map View
//

import Foundation

enum LiveMapLocationState: String, Codable, Hashable {
    case live = "Live"
    case stale = "Stale"
    case notReported = "Not Reporting"
    case permissionDenied = "Permission Denied"
    case restricted = "Restricted"
    case servicesDisabled = "Location Disabled"
    case unavailable = "Unavailable"
}

/// A real location observation supplied by a device or, later, the PFSS sync
/// service. An absent coordinate is intentional and must never be replaced by
/// a fabricated technician location.
struct LiveTechnicianLocationObservation: Identifiable, Codable, Hashable {
    var id: UUID { technicianID }
    let technicianID: UUID
    let coordinate: RouteCoordinate?
    let recordedAt: Date?
    let horizontalAccuracyMeters: Double?
    let state: LiveMapLocationState
}

struct LiveMapTechnicianPin: Identifiable, Hashable {
    var id: UUID { technicianID }
    let technicianID: UUID
    let technicianName: String
    let technicianColorName: String
    let operationalState: DispatchBoardTechnicianState
    let locationState: LiveMapLocationState
    let coordinate: RouteCoordinate?
    let recordedAt: Date?
    let currentAssignmentID: UUID?
    let nextAssignmentID: UUID?
    let destinationAssignmentID: UUID?
    let destinationName: String?
    let estimatedArrival: Date?
}

struct LiveMapAssignmentPin: Identifiable, Hashable {
    let id: UUID
    let jobID: UUID
    let customerName: String
    let siteName: String
    let siteAddress: String
    let serviceName: String
    let status: AssignmentStatus
    let priority: AssignmentPriority
    let schedulingMode: AssignmentSchedulingMode
    let coordinate: RouteCoordinate
    let routeSequence: Int?
    let primaryTechnicianID: UUID?
    let plannedStart: Date?
    let plannedEnd: Date?
    let estimatedArrival: Date?
    let isCurrent: Bool
}

struct LiveMapRouteSegment: Identifiable, Hashable {
    let id: String
    let technicianID: UUID
    let sequence: Int
    let start: RouteCoordinate
    let end: RouteCoordinate
    let destinationAssignmentID: UUID
}

enum LiveMapAlertKind: String, Codable, Hashable {
    case missingAssignmentLocation = "Missing Assignment Location"
    case technicianNotReporting = "Technician Not Reporting"
    case staleTechnicianLocation = "Stale Technician Location"
    case technicianLocationUnavailable = "Technician Location Unavailable"
}

struct LiveMapAlert: Identifiable, Hashable {
    let id: String
    let kind: LiveMapAlertKind
    let title: String
    let message: String
    let assignmentID: UUID?
    let technicianID: UUID?
}

struct LiveMapSnapshot: Hashable {
    let date: Date
    let generatedAt: Date
    let technicianPins: [LiveMapTechnicianPin]
    let assignmentPins: [LiveMapAssignmentPin]
    let routeSegments: [LiveMapRouteSegment]
    let alerts: [LiveMapAlert]

    var reportingTechnicianCount: Int {
        technicianPins.filter { $0.coordinate != nil }.count
    }

    var locatedAssignmentCount: Int { assignmentPins.count }
}
