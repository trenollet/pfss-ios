//
//  DispatchModels.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation

/// Determines who may control dispatch decisions for the business.
enum DispatchOperatingMode: String, CaseIterable, Identifiable, Codable {
    case dispatcherManaged = "Dispatcher Managed"
    case selfManaged = "Technician Self-Managed"
    case hybrid = "Hybrid"

    var id: String { rawValue }
}

/// Mutating commands owned by the Dispatch domain.
enum DispatchAction: String, CaseIterable, Identifiable, Codable {
    case assignPrimaryTechnician = "Assign Primary Technician"
    case reassignPrimaryTechnician = "Reassign Primary Technician"
    case addSupportingTechnician = "Add Supporting Technician"
    case replaceSupportingTechnician = "Replace Supporting Technician"
    case removeSupportingTechnician = "Remove Supporting Technician"
    case dispatchAssignment = "Dispatch Assignment"
    case insertEmergencyWork = "Insert Emergency Work"
    case reorderRoute = "Reorder Route"
    case overrideStatus = "Override Status"

    var id: String { rawValue }
}

/// Identity and role used when evaluating Dispatch permissions.
struct DispatchActor: Codable {
    var employeeID: UUID?
    var role: EmployeeRole?
    var roles: Set<EmployeeRole>?
    var isSystem: Bool

    init(
        employeeID: UUID? = nil,
        role: EmployeeRole? = nil,
        roles: Set<EmployeeRole>? = nil,
        isSystem: Bool = false
    ) {
        self.employeeID = employeeID
        self.role = role
        self.roles = roles
        self.isSystem = isSystem
    }

    static let system = DispatchActor(isSystem: true)

    static func employee(_ employee: EmployeeRecord) -> DispatchActor {
        DispatchActor(
            employeeID: employee.id,
            role: employee.role,
            roles: employee.roles
        )
    }
}

struct DispatchAuthorization {
    let isAllowed: Bool
    let reason: String

    static let allowed = DispatchAuthorization(
        isAllowed: true,
        reason: "Authorized"
    )

    static func denied(_ reason: String) -> DispatchAuthorization {
        DispatchAuthorization(isAllowed: false, reason: reason)
    }
}

/// Durable configuration for Dispatch permission behavior.
struct DispatchPolicy: Codable {
    var operatingMode: DispatchOperatingMode

    init(operatingMode: DispatchOperatingMode = .hybrid) {
        self.operatingMode = operatingMode
    }

    func authorization(
        for action: DispatchAction,
        actor: DispatchActor,
        assignment: Assignment,
        affectedTechnicianID: UUID? = nil
    ) -> DispatchAuthorization {
        if actor.isSystem {
            return .allowed
        }

        guard let employeeID = actor.employeeID else {
            return .denied("A known employee is required for this dispatch action.")
        }

        let actorRoles = actor.roles.flatMap { $0.isEmpty ? nil : $0 }
            ?? actor.role.map { Set([$0]) }
            ?? []

        guard actorRoles.isEmpty == false else {
            return .denied("At least one employee role is required for this dispatch action.")
        }

        if actorRoles.contains(.owner) || actorRoles.contains(.manager) {
            return .allowed
        }

        if actorRoles.contains(.office), operatingMode != .selfManaged {
            return .allowed
        }

        if actorRoles.contains(.technician), operatingMode != .dispatcherManaged {
            return technicianAuthorization(
                action: action,
                employeeID: employeeID,
                assignment: assignment,
                affectedTechnicianID: affectedTechnicianID
            )
        }

        if actorRoles.contains(.office) {
            return .denied(
                "Office dispatch actions are disabled in Technician Self-Managed mode."
            )
        }

        if actorRoles.contains(.technician) {
            return .denied(
                "Technician dispatch actions are disabled in Dispatcher Managed mode."
            )
        }

        return .denied("The employee's selected roles do not provide dispatch authority.")
    }

    private func technicianAuthorization(
        action: DispatchAction,
        employeeID: UUID,
        assignment: Assignment,
        affectedTechnicianID: UUID?
    ) -> DispatchAuthorization {
        let isPrimary = assignment.primaryTechnicianID == employeeID
        let isCrewMember = assignment.crew.containsActiveEmployee(employeeID)

        switch action {
        case .assignPrimaryTechnician:
            guard assignment.primaryTechnicianID == nil,
                  affectedTechnicianID == employeeID else {
                return .denied("A technician may only assign an unowned assignment to themselves.")
            }
            return .allowed

        case .reassignPrimaryTechnician:
            return .denied("Technician reassignment requires office, manager, or owner authority.")

        case .addSupportingTechnician,
             .replaceSupportingTechnician,
             .removeSupportingTechnician:
            return isPrimary
                ? .allowed
                : .denied("Only the Primary Technician may manage this assignment's supporting crew.")

        case .dispatchAssignment:
            return isPrimary
                ? .allowed
                : .denied("A technician may dispatch only an assignment they own.")

        case .insertEmergencyWork:
            guard affectedTechnicianID == nil || affectedTechnicianID == employeeID else {
                return .denied("A technician may insert emergency work only into their own route.")
            }
            return .allowed

        case .reorderRoute:
            return isCrewMember
                ? .allowed
                : .denied("A technician may reorder only a route containing their assignment.")

        case .overrideStatus:
            return .denied("Technicians cannot override assignment lifecycle rules.")
        }
    }
}

/// A concise record returned after every successful Dispatch command.
struct DispatchEvent: Identifiable {
    let id: UUID
    let action: DispatchAction
    let assignmentID: UUID
    let actorEmployeeID: UUID?
    let affectedTechnicianID: UUID?
    let previousPrimaryTechnicianID: UUID?
    let resultingPrimaryTechnicianID: UUID?
    let timestamp: Date
    let note: String?
    let wasHumanOverride: Bool

    init(
        id: UUID = UUID(),
        action: DispatchAction,
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        affectedTechnicianID: UUID? = nil,
        previousPrimaryTechnicianID: UUID? = nil,
        resultingPrimaryTechnicianID: UUID? = nil,
        timestamp: Date = Date(),
        note: String? = nil,
        wasHumanOverride: Bool = false
    ) {
        self.id = id
        self.action = action
        self.assignmentID = assignmentID
        self.actorEmployeeID = actorEmployeeID
        self.affectedTechnicianID = affectedTechnicianID
        self.previousPrimaryTechnicianID = previousPrimaryTechnicianID
        self.resultingPrimaryTechnicianID = resultingPrimaryTechnicianID
        self.timestamp = timestamp
        self.note = note
        self.wasHumanOverride = wasHumanOverride
    }
}

struct DispatchResult {
    let assignment: Assignment
    let event: DispatchEvent
}

struct EmergencyInsertionRequest: Identifiable {
    let id: UUID
    let assignmentID: UUID
    let requestedStart: Date
    let preferredTechnicianID: UUID?
    let reason: String
    let dispatchImmediately: Bool

    init(
        id: UUID = UUID(),
        assignmentID: UUID,
        requestedStart: Date = Date(),
        preferredTechnicianID: UUID? = nil,
        reason: String,
        dispatchImmediately: Bool = true
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.requestedStart = requestedStart
        self.preferredTechnicianID = preferredTechnicianID
        self.reason = reason
        self.dispatchImmediately = dispatchImmediately
    }
}

struct EmergencyInsertionOption: Identifiable {
    let id: UUID
    let technicianID: UUID
    let technicianName: String
    let proposedStart: Date
    let proposedRouteSequence: Int
    let confidencePercentage: Int
    let hasConflictFreeOpening: Bool
    let isRecommended: Bool
    let reasons: [String]

    init(
        id: UUID = UUID(),
        technicianID: UUID,
        technicianName: String,
        proposedStart: Date,
        proposedRouteSequence: Int,
        confidencePercentage: Int,
        hasConflictFreeOpening: Bool,
        isRecommended: Bool,
        reasons: [String]
    ) {
        self.id = id
        self.technicianID = technicianID
        self.technicianName = technicianName
        self.proposedStart = proposedStart
        self.proposedRouteSequence = max(proposedRouteSequence, 1)
        self.confidencePercentage = min(max(confidencePercentage, 0), 100)
        self.hasConflictFreeOpening = hasConflictFreeOpening
        self.isRecommended = isRecommended
        self.reasons = reasons
    }
}

struct EmergencyInsertionPlan {
    let request: EmergencyInsertionRequest
    let assignmentID: UUID
    let options: [EmergencyInsertionOption]
    let warnings: [String]

    var recommendedOption: EmergencyInsertionOption? {
        options.first(where: \.isRecommended) ?? options.first
    }
}
