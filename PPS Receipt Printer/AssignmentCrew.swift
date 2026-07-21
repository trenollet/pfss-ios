//
//  AssignmentCrew.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation

struct AssignmentCrewMember: Identifiable, Codable, Hashable {
    var id: UUID
    var employeeID: UUID
    var role: AssignmentCrewRole

    var assignedDate: Date
    var removedDate: Date?

    /// Labor credited to this technician for this assignment.
    var laborMinutes: Int

    /// Optional crew-specific note, such as responsibility or equipment role.
    var note: String

    init(
        id: UUID = UUID(),
        employeeID: UUID,
        role: AssignmentCrewRole,
        assignedDate: Date = Date(),
        removedDate: Date? = nil,
        laborMinutes: Int = 0,
        note: String = ""
    ) {
        self.id = id
        self.employeeID = employeeID
        self.role = role
        self.assignedDate = assignedDate
        self.removedDate = removedDate
        self.laborMinutes = max(laborMinutes, 0)
        self.note = note
    }

    var isActive: Bool {
        removedDate == nil
    }
}

struct AssignmentCrew: Codable, Hashable {
    var members: [AssignmentCrewMember]

    init(members: [AssignmentCrewMember] = []) {
        self.members = members
    }

    var activeMembers: [AssignmentCrewMember] {
        members.filter(\.isActive)
    }

    var primaryTechnician: AssignmentCrewMember? {
        activeMembers.first { $0.role == .primary }
    }

    var supportingTechnicians: [AssignmentCrewMember] {
        activeMembers.filter { $0.role == .supporting }
    }

    var primaryTechnicianID: UUID? {
        primaryTechnician?.employeeID
    }

    var supportingTechnicianIDs: [UUID] {
        supportingTechnicians.map(\.employeeID)
    }

    var activeEmployeeIDs: [UUID] {
        activeMembers.map(\.employeeID)
    }

    var totalRecordedLaborMinutes: Int {
        members.reduce(0) { $0 + $1.laborMinutes }
    }

    func containsActiveEmployee(_ employeeID: UUID) -> Bool {
        activeMembers.contains { $0.employeeID == employeeID }
    }

    var validationIssues: [AssignmentCrewValidationIssue] {
        var issues: [AssignmentCrewValidationIssue] = []

        let activePrimaryCount = activeMembers.filter {
            $0.role == .primary
        }.count

        if activePrimaryCount == 0 {
            issues.append(.missingPrimaryTechnician)
        } else if activePrimaryCount > 1 {
            issues.append(.multiplePrimaryTechnicians)
        }

        let activeIDs = activeMembers.map(\.employeeID)
        if Set(activeIDs).count != activeIDs.count {
            issues.append(.duplicateActiveTechnician)
        }

        return issues
    }

    var isValid: Bool {
        validationIssues.isEmpty
    }
}

enum AssignmentCrewValidationIssue: String, Codable, Hashable {
    case missingPrimaryTechnician = "The assignment requires one primary technician."
    case multiplePrimaryTechnicians = "The assignment may have only one active primary technician."
    case duplicateActiveTechnician = "A technician may appear only once in the active crew."
}
