//
//  DispatchEngine.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation
import Combine

/// Public Operations API for assignment ownership and dispatch movement.
///
/// `DispatchDecisionEngine` remains responsible for ranking technicians.
/// `DispatchEngine` applies the human-approved decision through
/// `AssignmentEngine`, enforces operating-mode permissions, and returns a
/// concise event while the Assignment history remains the durable audit trail.
@MainActor
final class DispatchEngine: ObservableObject {
    let assignmentEngine: AssignmentEngine

    @Published var policy: DispatchPolicy
    @Published private(set) var lastEvent: DispatchEvent?
    @Published private(set) var lastError: DispatchEngineError?

    private var assignmentObservation: AnyCancellable?

    init(
        assignmentEngine: AssignmentEngine,
        policy: DispatchPolicy? = nil
    ) {
        self.assignmentEngine = assignmentEngine
        self.policy = policy ?? DispatchPolicy()

        assignmentObservation = assignmentEngine.objectWillChange.sink {
            [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Read-Only Dispatch State

    var activeAssignments: [Assignment] {
        assignmentEngine.activeAssignments
    }

    var unassignedAssignments: [Assignment] {
        assignmentEngine.unassignedAssignments
    }

    func assignment(id: UUID) -> Assignment? {
        assignmentEngine.assignment(id: id)
    }

    func authorization(
        for action: DispatchAction,
        actor: DispatchActor,
        assignmentID: UUID,
        affectedTechnicianID: UUID? = nil
    ) -> DispatchAuthorization {
        guard let assignment = assignmentEngine.assignment(id: assignmentID) else {
            return .denied("The assignment could not be found.")
        }

        return policy.authorization(
            for: action,
            actor: actor,
            assignment: assignment,
            affectedTechnicianID: affectedTechnicianID
        )
    }

    // MARK: - Primary Technician Ownership

    @discardableResult
    func assignPrimaryTechnician(
        assignmentID: UUID,
        technician: EmployeeRecord,
        actor: DispatchActor,
        scheduledStart: Date? = nil,
        note: String? = nil,
        isHumanOverride: Bool = false,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        try requireEligibleTechnician(technician)

        var assignment = try requireAssignment(assignmentID)
        let previousPrimaryID = assignment.primaryTechnicianID
        let action: DispatchAction

        if let previousPrimaryID, previousPrimaryID != technician.id {
            action = .reassignPrimaryTechnician
        } else {
            action = .assignPrimaryTechnician
        }

        try requireAuthorization(
            action: action,
            actor: actor,
            assignment: assignment,
            affectedTechnicianID: technician.id
        )

        do {
            if previousPrimaryID == nil {
                assignment = try assignmentEngine.assignPrimaryTechnician(
                    assignmentID: assignmentID,
                    employeeID: technician.id,
                    actorEmployeeID: actor.employeeID,
                    note: dispatchNote(
                        base: note ?? "Primary technician assigned through Dispatch.",
                        isHumanOverride: isHumanOverride
                    ),
                    at: timestamp
                )
            } else if previousPrimaryID != technician.id {
                let reason = normalized(note ?? "")
                guard !reason.isEmpty else {
                    throw DispatchEngineError.reasonRequiredForReassignment
                }

                assignment = try assignmentEngine.replacePrimaryTechnician(
                    assignmentID: assignmentID,
                    with: technician.id,
                    actorEmployeeID: actor.employeeID,
                    reason: dispatchNote(
                        base: reason,
                        isHumanOverride: isHumanOverride
                    ),
                    at: timestamp
                )
            }

            if let scheduledStart {
                var scheduling = assignment.scheduling
                scheduling.mode = .fixedTime
                scheduling.serviceDate = scheduledStart
                scheduling.fixedStartDate = scheduledStart
                scheduling.arrivalWindowStart = nil
                scheduling.arrivalWindowEnd = nil
                scheduling.completionDeadline = nil

                assignment = try assignmentEngine.reschedule(
                    assignmentID: assignmentID,
                    scheduling: scheduling,
                    actorEmployeeID: actor.employeeID,
                    note: dispatchNote(
                        base: "Dispatch set the planned start.",
                        isHumanOverride: isHumanOverride
                    ),
                    at: timestamp
                )
            }
        } catch let error as DispatchEngineError {
            throw record(error)
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: action,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: technician.id,
            previousPrimaryTechnicianID: previousPrimaryID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: normalizedOptional(note),
            wasHumanOverride: isHumanOverride
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    // MARK: - Crew Management

    @discardableResult
    func addSupportingTechnician(
        assignmentID: UUID,
        technician: EmployeeRecord,
        actor: DispatchActor,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        try requireEligibleTechnician(technician)
        let current = try requireAssignment(assignmentID)

        try requireAuthorization(
            action: .addSupportingTechnician,
            actor: actor,
            assignment: current,
            affectedTechnicianID: technician.id
        )

        let assignment: Assignment
        do {
            assignment = try assignmentEngine.addSupportingTechnician(
                assignmentID: assignmentID,
                employeeID: technician.id,
                actorEmployeeID: actor.employeeID,
                note: note,
                at: timestamp
            )
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .addSupportingTechnician,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: technician.id,
            previousPrimaryTechnicianID: current.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: normalizedOptional(note)
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    @discardableResult
    func removeSupportingTechnician(
        assignmentID: UUID,
        technicianID: UUID,
        actor: DispatchActor,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        let current = try requireAssignment(assignmentID)

        try requireAuthorization(
            action: .removeSupportingTechnician,
            actor: actor,
            assignment: current,
            affectedTechnicianID: technicianID
        )

        let cleanReason = normalized(reason)
        guard !cleanReason.isEmpty else {
            throw record(.reasonRequiredForCrewChange)
        }

        let assignment: Assignment
        do {
            assignment = try assignmentEngine.removeSupportingTechnician(
                assignmentID: assignmentID,
                employeeID: technicianID,
                actorEmployeeID: actor.employeeID,
                reason: cleanReason,
                at: timestamp
            )
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .removeSupportingTechnician,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: technicianID,
            previousPrimaryTechnicianID: current.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: cleanReason
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    @discardableResult
    func replaceSupportingTechnician(
        assignmentID: UUID,
        technician: EmployeeRecord,
        actor: DispatchActor,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        try requireEligibleTechnician(technician)
        let current = try requireAssignment(assignmentID)

        try requireAuthorization(
            action: .replaceSupportingTechnician,
            actor: actor,
            assignment: current,
            affectedTechnicianID: technician.id
        )

        let cleanReason = normalized(reason)
        guard !cleanReason.isEmpty else {
            throw record(.reasonRequiredForCrewChange)
        }

        let assignment: Assignment
        do {
            assignment = try assignmentEngine.replaceSupportingTechnician(
                assignmentID: assignmentID,
                with: technician.id,
                actorEmployeeID: actor.employeeID,
                reason: cleanReason,
                at: timestamp
            )
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .replaceSupportingTechnician,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: technician.id,
            previousPrimaryTechnicianID: current.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: cleanReason
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    // MARK: - Dispatch Lifecycle

    @discardableResult
    func dispatch(
        assignmentID: UUID,
        actor: DispatchActor,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        let current = try requireAssignment(assignmentID)

        try requireAuthorization(
            action: .dispatchAssignment,
            actor: actor,
            assignment: current,
            affectedTechnicianID: current.primaryTechnicianID
        )

        guard current.status == .scheduled else {
            throw record(.assignmentCannotBeDispatched(current.status))
        }
        guard current.primaryTechnicianID != nil else {
            throw record(.primaryTechnicianRequired)
        }

        let assignment: Assignment
        do {
            assignment = try assignmentEngine.dispatch(
                assignmentID: assignmentID,
                actorEmployeeID: actor.employeeID,
                note: note ?? "Assignment dispatched through Dispatch Engine.",
                at: timestamp
            )
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .dispatchAssignment,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: assignment.primaryTechnicianID,
            previousPrimaryTechnicianID: current.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: normalizedOptional(note)
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    /// Applies an explicitly authorized lifecycle correction while preserving
    /// the Assignment history entry created by `AssignmentEngine`.
    @discardableResult
    func overrideStatus(
        assignmentID: UUID,
        to newStatus: AssignmentStatus,
        actor: DispatchActor,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        let current = try requireAssignment(assignmentID)

        try requireAuthorization(
            action: .overrideStatus,
            actor: actor,
            assignment: current,
            affectedTechnicianID: current.primaryTechnicianID
        )

        guard let actorEmployeeID = actor.employeeID else {
            throw record(.actorEmployeeRequiredForOverride)
        }

        let cleanReason = normalized(reason)
        guard !cleanReason.isEmpty else {
            throw record(.reasonRequiredForStatusOverride)
        }

        let assignment: Assignment
        do {
            assignment = try assignmentEngine.overrideStatus(
                assignmentID: assignmentID,
                to: newStatus,
                managerEmployeeID: actorEmployeeID,
                reason: cleanReason,
                at: timestamp
            )
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .overrideStatus,
            assignmentID: assignment.id,
            actorEmployeeID: actorEmployeeID,
            affectedTechnicianID: assignment.primaryTechnicianID,
            previousPrimaryTechnicianID: current.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: cleanReason,
            wasHumanOverride: true
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    /// Records a human-approved route position change. Route optimization may
    /// recommend the order, but authorized field staff retain final control.
    @discardableResult
    func reorderRoute(
        assignmentID: UUID,
        routeSequence: Int?,
        actor: DispatchActor,
        reason: String? = nil,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        let current = try requireAssignment(assignmentID)

        try requireAuthorization(
            action: .reorderRoute,
            actor: actor,
            assignment: current,
            affectedTechnicianID: current.primaryTechnicianID
        )

        let assignment: Assignment
        do {
            assignment = try assignmentEngine.updateRouteSequence(
                assignmentID: assignmentID,
                routeSequence: routeSequence,
                actorEmployeeID: actor.employeeID,
                note: normalizedOptional(reason) ?? "Route order changed through Dispatch.",
                at: timestamp
            )
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .reorderRoute,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: assignment.primaryTechnicianID,
            previousPrimaryTechnicianID: current.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: normalizedOptional(reason),
            wasHumanOverride: true
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    // MARK: - Emergency Insertion

    func prepareEmergencyInsertion(
        request: EmergencyInsertionRequest,
        actor: DispatchActor,
        job: JobRecord,
        employees: [EmployeeRecord],
        jobs: [JobRecord],
        calendar: Calendar = .current
    ) throws -> EmergencyInsertionPlan {
        clearError()
        let assignment = try requireAssignment(request.assignmentID)

        try requireAuthorization(
            action: .insertEmergencyWork,
            actor: actor,
            assignment: assignment,
            affectedTechnicianID: request.preferredTechnicianID
        )

        guard assignment.jobID == job.id else {
            throw record(.jobDoesNotMatchAssignment)
        }
        guard !normalized(request.reason).isEmpty else {
            throw record(.emergencyReasonRequired)
        }

        let technicians = employees.filter(isEligibleTechnician)
        let decisions = DispatchDecisionEngine.rankedDecisions(
            for: job,
            employees: technicians,
            jobs: jobs,
            policy: .emergency,
            onOrAfter: request.requestedStart,
            calendar: calendar
        )
        let decisionByEmployeeID = Dictionary(
            uniqueKeysWithValues: decisions.map { ($0.employee.id, $0) }
        )
        let recommendedID = request.preferredTechnicianID ??
            decisions.first?.employee.id

        var options = technicians.map { technician in
            let decision = decisionByEmployeeID[technician.id]
            let proposedStart = decision?.opening.start ?? request.requestedStart

            return EmergencyInsertionOption(
                technicianID: technician.id,
                technicianName: technician.displayName,
                proposedStart: proposedStart,
                proposedRouteSequence: nextRouteSequence(
                    for: technician.id,
                    on: proposedStart,
                    calendar: calendar
                ),
                confidencePercentage: decision?.confidencePercentage ?? 0,
                hasConflictFreeOpening: decision != nil,
                isRecommended: technician.id == recommendedID,
                reasons: decision?.reasons.map(\.message) ?? [
                    "No conflict-free opening was found; selecting this technician is a human override."
                ]
            )
        }

        options.sort { first, second in
            if first.isRecommended != second.isRecommended {
                return first.isRecommended
            }
            if first.hasConflictFreeOpening != second.hasConflictFreeOpening {
                return first.hasConflictFreeOpening
            }
            if first.confidencePercentage != second.confidencePercentage {
                return first.confidencePercentage > second.confidencePercentage
            }
            return first.technicianName.localizedCaseInsensitiveCompare(
                second.technicianName
            ) == .orderedAscending
        }

        guard !options.isEmpty else {
            throw record(.noEligibleTechnicians)
        }

        var warnings: [String] = []
        if decisions.isEmpty {
            warnings.append(
                "No conflict-free technician was found. A human may still select an override."
            )
        }
        if request.preferredTechnicianID != nil,
           options.contains(where: \.isRecommended) == false {
            warnings.append("The preferred technician is inactive or ineligible.")
        }

        return EmergencyInsertionPlan(
            request: request,
            assignmentID: assignment.id,
            options: options,
            warnings: warnings
        )
    }

    @discardableResult
    func applyEmergencyInsertion(
        plan: EmergencyInsertionPlan,
        optionID: UUID,
        employees: [EmployeeRecord],
        actor: DispatchActor,
        at timestamp: Date = Date()
    ) throws -> DispatchResult {
        clearError()
        guard let option = plan.options.first(where: { $0.id == optionID }) else {
            throw record(.emergencyOptionNotFound)
        }
        guard let technician = employees.first(where: { $0.id == option.technicianID }) else {
            throw record(.technicianNotFound(option.technicianID))
        }

        let initial = try requireAssignment(plan.assignmentID)
        try requireAuthorization(
            action: .insertEmergencyWork,
            actor: actor,
            assignment: initial,
            affectedTechnicianID: technician.id
        )

        let reason = normalized(plan.request.reason)
        let override = !option.hasConflictFreeOpening || !option.isRecommended
        var assignment: Assignment

        do {
            assignment = try assignmentEngine.updatePriority(
                assignmentID: initial.id,
                priority: .emergency,
                actorEmployeeID: actor.employeeID,
                note: reason,
                at: timestamp
            )

            assignment = try assignPrimaryTechnician(
                assignmentID: assignment.id,
                technician: technician,
                actor: actor,
                scheduledStart: option.proposedStart,
                note: reason,
                isHumanOverride: override,
                at: timestamp
            ).assignment

            assignment = try assignmentEngine.updateRouteSequence(
                assignmentID: assignment.id,
                routeSequence: option.proposedRouteSequence,
                actorEmployeeID: actor.employeeID,
                note: "Emergency assignment inserted into the route.",
                at: timestamp
            )

            if plan.request.dispatchImmediately {
                assignment = try dispatch(
                    assignmentID: assignment.id,
                    actor: actor,
                    note: "Emergency dispatch: \(reason)",
                    at: timestamp
                ).assignment
            }
        } catch let error as DispatchEngineError {
            throw record(error)
        } catch {
            throw record(.assignmentOperationFailed(error.localizedDescription))
        }

        let event = DispatchEvent(
            action: .insertEmergencyWork,
            assignmentID: assignment.id,
            actorEmployeeID: actor.employeeID,
            affectedTechnicianID: technician.id,
            previousPrimaryTechnicianID: initial.primaryTechnicianID,
            resultingPrimaryTechnicianID: assignment.primaryTechnicianID,
            timestamp: timestamp,
            note: reason,
            wasHumanOverride: override
        )
        return recordSuccess(assignment: assignment, event: event)
    }

    // MARK: - Helpers

    private func requireAssignment(_ id: UUID) throws -> Assignment {
        guard let assignment = assignmentEngine.assignment(id: id) else {
            throw record(.assignmentNotFound(id))
        }
        guard assignment.lifecycleStatus == .active else {
            throw record(.assignmentIsArchived)
        }
        return assignment
    }

    private func requireEligibleTechnician(_ employee: EmployeeRecord) throws {
        guard isEligibleTechnician(employee) else {
            throw record(.employeeIsNotEligibleTechnician(employee.id))
        }
    }

    private func isEligibleTechnician(_ employee: EmployeeRecord) -> Bool {
        employee.isActive &&
        employee.lifecycleStatus == .active &&
        (employee.hasRole(.technician) ||
         employee.hasRole(.manager) ||
         employee.hasRole(.owner))
    }

    private func requireAuthorization(
        action: DispatchAction,
        actor: DispatchActor,
        assignment: Assignment,
        affectedTechnicianID: UUID?
    ) throws {
        let authorization = policy.authorization(
            for: action,
            actor: actor,
            assignment: assignment,
            affectedTechnicianID: affectedTechnicianID
        )

        guard authorization.isAllowed else {
            throw record(.unauthorized(authorization.reason))
        }
    }

    private func nextRouteSequence(
        for technicianID: UUID,
        on date: Date,
        calendar: Calendar
    ) -> Int {
        let sequences = assignmentEngine
            .assignmentsForTechnician(technicianID)
            .filter {
                guard let operationalDate = operationalDate(
                    for: $0.scheduling
                ) else {
                    return false
                }
                return calendar.isDate(operationalDate, inSameDayAs: date)
            }
            .compactMap(\.routeSequence)

        return (sequences.max() ?? 0) + 1
    }

    private func operationalDate(
        for scheduling: AssignmentScheduling
    ) -> Date? {
        switch scheduling.mode {
        case .fixedTime:
            return scheduling.fixedStartDate ?? scheduling.serviceDate
        case .arrivalWindow:
            return scheduling.arrivalWindowStart ?? scheduling.serviceDate
        case .flexibleDay:
            return scheduling.serviceDate
        case .deadline:
            return scheduling.completionDeadline
        }
    }

    private func dispatchNote(base: String, isHumanOverride: Bool) -> String {
        guard isHumanOverride else { return base }
        return "\(base) Human dispatch override accepted."
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = normalized(value)
        return clean.isEmpty ? nil : clean
    }

    private func clearError() {
        lastError = nil
    }

    @discardableResult
    private func record(_ error: DispatchEngineError) -> DispatchEngineError {
        lastError = error
        return error
    }

    private func recordSuccess(
        assignment: Assignment,
        event: DispatchEvent
    ) -> DispatchResult {
        lastError = nil
        lastEvent = event
        return DispatchResult(assignment: assignment, event: event)
    }
}

enum DispatchEngineError: LocalizedError {
    case assignmentNotFound(UUID)
    case assignmentIsArchived
    case technicianNotFound(UUID)
    case employeeIsNotEligibleTechnician(UUID)
    case unauthorized(String)
    case reasonRequiredForReassignment
    case reasonRequiredForCrewChange
    case reasonRequiredForStatusOverride
    case actorEmployeeRequiredForOverride
    case assignmentCannotBeDispatched(AssignmentStatus)
    case primaryTechnicianRequired
    case jobDoesNotMatchAssignment
    case emergencyReasonRequired
    case emergencyOptionNotFound
    case noEligibleTechnicians
    case assignmentOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .assignmentNotFound:
            return "The assignment could not be found."
        case .assignmentIsArchived:
            return "Archived assignments cannot be changed through Dispatch."
        case .technicianNotFound:
            return "The selected technician could not be found."
        case .employeeIsNotEligibleTechnician:
            return "The selected employee is not an active field technician."
        case let .unauthorized(reason):
            return reason
        case .reasonRequiredForReassignment:
            return "A reason is required when reassigning the Primary Technician."
        case .reasonRequiredForCrewChange:
            return "A reason is required when removing a Supporting Technician."
        case .reasonRequiredForStatusOverride:
            return "A reason is required when overriding assignment status."
        case .actorEmployeeRequiredForOverride:
            return "An identified dispatcher, manager, or owner is required for a status override."
        case let .assignmentCannotBeDispatched(status):
            return "An assignment in \(status.rawValue) status cannot be dispatched."
        case .primaryTechnicianRequired:
            return "Assign a Primary Technician before dispatching this assignment."
        case .jobDoesNotMatchAssignment:
            return "The emergency Job does not match the selected Assignment."
        case .emergencyReasonRequired:
            return "An emergency insertion reason is required."
        case .emergencyOptionNotFound:
            return "The selected emergency insertion option is no longer available."
        case .noEligibleTechnicians:
            return "No active eligible technicians are available for this emergency."
        case let .assignmentOperationFailed(message):
            return message
        }
    }
}
