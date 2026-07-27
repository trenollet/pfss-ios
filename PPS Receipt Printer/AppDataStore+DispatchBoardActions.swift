//
//  AppDataStore+DispatchBoardActions.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Technician Dispatch Board action boundary
//

import Foundation

enum DispatchBoardRouteMoveDirection {
    case earlier
    case later
}

enum DispatchBoardActionError: LocalizedError {
    case assignmentUnavailable
    case technicianUnavailable
    case reasonRequired
    case routeLaneUnavailable
    case routeBoundaryReached
    case routeAssignmentMismatch

    var errorDescription: String? {
        switch self {
        case .assignmentUnavailable:
            return "The Assignment is no longer available. Refresh the Dispatch Board and try again."
        case .technicianUnavailable:
            return "The selected technician is no longer active or eligible for dispatch."
        case .reasonRequired:
            return "Enter a reason for overriding PFSS's recommendation or changing the Primary Technician."
        case .routeLaneUnavailable:
            return "The Assignment is not currently in a technician route lane."
        case .routeBoundaryReached:
            return "The Assignment is already at the beginning or end of this route."
        case .routeAssignmentMismatch:
            return "One or more jobs no longer belong to this technician's route. Refresh My Day and try again."
        }
    }
}

@MainActor
extension AppDataStore {
    /// Assigns or reassigns work from the Dispatch Board while preserving the
    /// same recommendation audit used by the Operations dispatch queue.
    @discardableResult
    func dispatchBoardAssign(
        assignmentID: UUID,
        technicianID: UUID,
        reason: String = "",
        at timestamp: Date = Date()
    ) throws -> Assignment {
        guard let assignment = assignmentEngine.assignment(id: assignmentID),
              let job = activeJobs.first(where: { $0.id == assignment.jobID }) else {
            throw DispatchBoardActionError.assignmentUnavailable
        }
        guard let technician = activeEmployees.first(where: {
            $0.id == technicianID &&
            $0.isActive &&
            $0.lifecycleStatus == .active &&
            ($0.hasRole(.technician) || $0.hasRole(.manager) || $0.hasRole(.owner))
        }) else {
            throw DispatchBoardActionError.technicianUnavailable
        }

        if assignment.primaryTechnicianID == technicianID {
            return assignment
        }

        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let recommendation = operationalRecommendation(
            for: job,
            purpose: .technicianAssignment,
            policy: assignment.priority == .emergency ? .emergency : .balanced,
            onOrAfter: assignment.scheduling.operationalDate,
            generatedAt: timestamp
        )
        let recommendationIsOverride = recommendation?.bestCandidate?.employeeID != technicianID
        let isReassignment = assignment.primaryTechnicianID != nil

        if (recommendationIsOverride || isReassignment) && cleanReason.isEmpty {
            throw DispatchBoardActionError.reasonRequired
        }

        if let recommendation {
            _ = try assignTechnicianUsingRecommendation(
                technicianID,
                toJobID: job.id,
                recommendation: recommendation,
                overrideReason: cleanReason,
                decidedAt: timestamp
            )
        } else {
            _ = try dispatchEngine.assignPrimaryTechnician(
                assignmentID: assignmentID,
                technician: technician,
                actor: .system,
                note: cleanReason.isEmpty
                    ? "Primary Technician assigned from the Dispatch Board."
                    : "Dispatch Board decision: \(cleanReason)",
                isHumanOverride: true,
                at: timestamp
            )
        }

        guard let updated = assignmentEngine.assignment(id: assignmentID) else {
            throw DispatchBoardActionError.assignmentUnavailable
        }
        return updated
    }

    /// Returns unstarted work to the shared unassigned queue. AssignmentEngine
    /// owns the lifecycle rule and writes the durable history entry.
    @discardableResult
    func dispatchBoardUnassign(
        assignmentID: UUID,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanReason.isEmpty == false else {
            throw DispatchBoardActionError.reasonRequired
        }

        return try assignmentEngine.unassignCrew(
            assignmentID: assignmentID,
            reason: cleanReason,
            at: timestamp
        )
    }

    /// Moves an Assignment one position within its technician lane and writes
    /// the resulting route sequence through DispatchEngine for every changed
    /// stop. This keeps My Day, Route Preview, and the board synchronized.
    func dispatchBoardMoveAssignment(
        assignmentID: UUID,
        direction: DispatchBoardRouteMoveDirection,
        on date: Date,
        reason: String = "Manual route order change from Dispatch Board.",
        calendar: Calendar = .current,
        at timestamp: Date = Date()
    ) throws {
        let snapshot = dispatchBoardSnapshot(
            on: date,
            generatedAt: timestamp,
            calendar: calendar
        )
        guard let lane = snapshot.technicianLanes.first(where: {
            $0.assignments.contains(where: { $0.id == assignmentID })
        }) else {
            throw DispatchBoardActionError.routeLaneUnavailable
        }

        var orderedIDs = lane.assignments.map(\.id)
        guard let currentIndex = orderedIDs.firstIndex(of: assignmentID) else {
            throw DispatchBoardActionError.routeLaneUnavailable
        }

        let targetIndex: Int
        switch direction {
        case .earlier:
            targetIndex = currentIndex - 1
        case .later:
            targetIndex = currentIndex + 1
        }
        guard orderedIDs.indices.contains(targetIndex) else {
            throw DispatchBoardActionError.routeBoundaryReached
        }

        orderedIDs.swapAt(currentIndex, targetIndex)

        for (index, id) in orderedIDs.enumerated() {
            let desiredSequence = index + 1
            guard assignmentEngine.assignment(id: id)?.routeSequence != desiredSequence else {
                continue
            }
            _ = try dispatchEngine.reorderRoute(
                assignmentID: id,
                routeSequence: desiredSequence,
                actor: .system,
                reason: reason,
                at: timestamp
            )
        }

        let orderedAssignments = orderedIDs.compactMap {
            assignmentEngine.assignment(id: $0)
        }
        enqueueRouteChangeOperation(
            technicianID: lane.id,
            orderedJobIDs: orderedAssignments.map(\.jobID),
            orderedAssignmentIDs: orderedIDs,
            reason: reason,
            timestamp: timestamp
        )
    }

    /// Persists a technician-approved My Day order through the same audited
    /// Dispatch boundary used by the board and route-plan screens.
    func applyTechnicianRouteOrder(
        jobIDs: [UUID],
        technician: EmployeeRecord,
        reason: String = "Technician accepted the optimized My Day route.",
        at timestamp: Date = Date()
    ) throws {
        var seenJobIDs = Set<UUID>()
        let uniqueJobIDs = jobIDs.filter {
            seenJobIDs.insert($0).inserted
        }
        let assignments = try uniqueJobIDs.map { jobID in
            guard let assignment = assignment(forJobID: jobID),
                  assignment.crew.containsActiveEmployee(technician.id) else {
                throw DispatchBoardActionError.routeAssignmentMismatch
            }
            return assignment
        }

        let actor = DispatchActor.employee(technician)
        for (index, assignment) in assignments.enumerated() {
            let sequence = index + 1
            guard assignment.routeSequence != sequence else { continue }
            _ = try dispatchEngine.reorderRoute(
                assignmentID: assignment.id,
                routeSequence: sequence,
                actor: actor,
                reason: reason,
                at: timestamp
            )
        }

        enqueueRouteChangeOperation(
            technicianID: technician.id,
            orderedJobIDs: assignments.map(\.jobID),
            orderedAssignmentIDs: assignments.map(\.id),
            reason: reason,
            timestamp: timestamp
        )
    }
}
