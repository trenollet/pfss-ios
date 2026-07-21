//
//  AssignmentEngine.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation
import Combine

/// The public Operations API for the Assignment domain.
///
/// Views and higher-level engines should use this type instead of modifying an
/// `Assignment` or calling mutation methods on `AssignmentStore` directly.
/// Centralizing operations here ensures that validation, business rules,
/// lifecycle transitions, audit history, and future synchronization hooks are
/// applied consistently.
@MainActor
final class AssignmentEngine: ObservableObject {

    // MARK: - Dependencies and Published State

    let store: AssignmentStore

    @Published private(set) var lastOperation: AssignmentOperation?
    @Published private(set) var lastError: AssignmentEngineError?

    private var storeObservation: AnyCancellable?
    private let assignmentNumberPrefix: String

    init(
        store: AssignmentStore,
        assignmentNumberPrefix: String = "ASN"
    ) {
        self.store = store
        self.assignmentNumberPrefix = assignmentNumberPrefix

        storeObservation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Read-Only Operations API

    var assignments: [Assignment] { store.assignments }
    var activeAssignments: [Assignment] { store.activeAssignments }
    var completedAssignments: [Assignment] { store.completedAssignments }
    var readyForDispatchAssignments: [Assignment] { store.readyForDispatchAssignments }
    var unassignedAssignments: [Assignment] { store.unassignedAssignments }
    var unscheduledAssignments: [Assignment] { store.unscheduledAssignments }
    var overdueAssignments: [Assignment] { store.overdueAssignments }

    func assignment(id: UUID) -> Assignment? {
        store.assignment(id: id)
    }

    func assignment(number: String) -> Assignment? {
        store.assignment(number: number)
    }

    func assignments(on date: Date, calendar: Calendar = .current) -> [Assignment] {
        store.assignments(on: date, calendar: calendar)
    }

    func assignmentsForJob(_ jobID: UUID) -> [Assignment] {
        store.assignments.filter { $0.jobID == jobID }
    }

    func assignmentsForTechnician(_ employeeID: UUID) -> [Assignment] {
        store.assignments.filter { $0.crew.containsActiveEmployee(employeeID) }
    }

    // MARK: - Creation

    /// Creates and stores an Assignment after applying creation rules.
    ///
    /// An assignment number is generated when the supplied value is blank.
    /// A creation history event is added before insertion. The store remains
    /// responsible for uniqueness and the V1 one-active-assignment-per-job rule.
    @discardableResult
    func createAssignment(
        assignmentNumber: String? = nil,
        jobID: UUID,
        jobNumber: String,
        customerNumber: String,
        siteID: UUID? = nil,
        scheduling: AssignmentScheduling,
        primaryTechnicianID: UUID? = nil,
        supportingTechnicianIDs: [UUID] = [],
        priority: AssignmentPriority = .normal,
        source: AssignmentCreationSource = .jobConversion,
        dispatchNotes: String = "",
        fieldNotes: String = "",
        routeSequence: Int? = nil,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        allowMultipleActiveAssignmentsForJob: Bool = false,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        clearError()

        let cleanJobNumber = normalizedRequired(jobNumber)
        let cleanCustomerNumber = normalizedRequired(customerNumber)

        guard cleanJobNumber.isEmpty == false else {
            throw record(.missingRequiredValue("Job number"))
        }
        guard cleanCustomerNumber.isEmpty == false else {
            throw record(.missingRequiredValue("Customer number"))
        }

        let crew = try buildCrew(
            primaryTechnicianID: primaryTechnicianID,
            supportingTechnicianIDs: supportingTechnicianIDs,
            timestamp: timestamp
        )

        let number = normalizedRequired(assignmentNumber ?? "").isEmpty
            ? generateAssignmentNumber(at: timestamp)
            : normalizedRequired(assignmentNumber ?? "")

        var assignment = Assignment(
            assignmentNumber: number,
            jobID: jobID,
            jobNumber: cleanJobNumber,
            customerNumber: cleanCustomerNumber,
            siteID: siteID,
            status: .scheduled,
            priority: priority,
            creationSource: source,
            scheduling: scheduling,
            crew: crew,
            dispatchNotes: dispatchNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            fieldNotes: fieldNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            routeSequence: normalizedRouteSequence(routeSequence),
            createdDate: timestamp,
            updatedDate: timestamp
        )

        assignment.history.append(
            AssignmentHistoryEvent(
                type: .created,
                title: "Assignment created",
                timestamp: timestamp,
                actorEmployeeID: actorEmployeeID,
                resultingStatus: .scheduled,
                note: normalizedOptional(note),
                metadata: [
                    "assignmentNumber": number,
                    "jobNumber": cleanJobNumber,
                    "creationSource": source.rawValue
                ]
            )
        )

        let validation = validateAssignment(assignment)
        guard validation.state != .invalid else {
            throw record(.validationFailed(validation.messages))
        }

        do {
            try store.add(
                assignment,
                allowMultipleActiveAssignmentsForJob: allowMultipleActiveAssignmentsForJob
            )
        } catch {
            throw record(.storeFailure(message(for: error)))
        }

        guard let inserted = store.assignment(id: assignment.id) else {
            throw record(.assignmentNotFound(assignment.id))
        }

        recordSuccess(.created, assignmentID: inserted.id, at: timestamp)
        return inserted
    }

    // MARK: - Scheduling

    @discardableResult
    func schedule(
        assignmentID: UUID,
        scheduling: AssignmentScheduling,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        guard scheduling.isValid else {
            throw record(.invalidScheduling)
        }

        return try updateScheduling(
            assignmentID: assignmentID,
            scheduling: scheduling,
            title: "Assignment scheduled",
            actorEmployeeID: actorEmployeeID,
            note: note,
            timestamp: timestamp,
            operation: .scheduled
        )
    }

    @discardableResult
    func reschedule(
        assignmentID: UUID,
        scheduling: AssignmentScheduling,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        guard scheduling.isValid else {
            throw record(.invalidScheduling)
        }

        return try updateScheduling(
            assignmentID: assignmentID,
            scheduling: scheduling,
            title: "Assignment rescheduled",
            actorEmployeeID: actorEmployeeID,
            note: note,
            timestamp: timestamp,
            operation: .rescheduled
        )
    }

    /// Replaces the current constraints with a caller-created unscheduled
    /// scheduling value. `AssignmentScheduling` owns mode-specific defaults;
    /// accepting the value here avoids duplicating those rules in this engine.
    @discardableResult
    func unschedule(
        assignmentID: UUID,
        unscheduledScheduling: AssignmentScheduling,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try updateScheduling(
            assignmentID: assignmentID,
            scheduling: unscheduledScheduling,
            title: "Assignment removed from schedule",
            actorEmployeeID: actorEmployeeID,
            note: note,
            timestamp: timestamp,
            operation: .unscheduled
        )
    }

    // MARK: - Dispatch and Lifecycle

    @discardableResult
    func transitionStatus(
        assignmentID: UUID,
        to newStatus: AssignmentStatus,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        clearError()
        let current = try requireAssignment(assignmentID)

        guard current.lifecycleStatus == .active else {
            throw record(.archivedAssignmentCannotBeModified)
        }

        if newStatus == .dispatched {
            let validation = validateForDispatch(current)
            guard validation.state != .invalid else {
                throw record(.validationFailed(validation.messages))
            }
        }

        do {
            try store.changeStatus(
                assignmentID: assignmentID,
                to: newStatus,
                actorEmployeeID: actorEmployeeID,
                note: normalizedOptional(note),
                at: timestamp
            )
        } catch {
            throw record(.storeFailure(message(for: error)))
        }

        let result = try requireAssignment(assignmentID)
        recordSuccess(operation(for: newStatus), assignmentID: assignmentID, at: timestamp)
        return result
    }

    @discardableResult
    func dispatch(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try transitionStatus(
            assignmentID: assignmentID,
            to: .dispatched,
            actorEmployeeID: actorEmployeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func beginTravel(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try transitionStatus(
            assignmentID: assignmentID,
            to: .enRoute,
            actorEmployeeID: actorEmployeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func arrive(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try transitionStatus(
            assignmentID: assignmentID,
            to: .onSite,
            actorEmployeeID: actorEmployeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func complete(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        let assignment = try requireAssignment(assignmentID)
        guard assignment.status == .onSite else {
            throw record(.workCanOnlyCompleteFromOnSite(current: assignment.status))
        }
        return try transitionStatus(
            assignmentID: assignmentID,
            to: .workComplete,
            actorEmployeeID: actorEmployeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func markInvoiceReady(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try transitionStatus(
            assignmentID: assignmentID,
            to: .invoiceReady,
            actorEmployeeID: actorEmployeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func close(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try transitionStatus(
            assignmentID: assignmentID,
            to: .closed,
            actorEmployeeID: actorEmployeeID,
            note: note,
            at: timestamp
        )
    }

    @discardableResult
    func cancel(
        assignmentID: UUID,
        actorEmployeeID: UUID? = nil,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        let assignment = try requireAssignment(assignmentID)
        let cleanReason = normalizedRequired(reason)

        guard cleanReason.isEmpty == false else {
            throw record(.reasonRequired("Cancellation"))
        }
        guard assignment.status != .invoiceReady && assignment.status != .closed else {
            throw record(.cannotCancelAfterInvoiceReady)
        }

        return try transitionStatus(
            assignmentID: assignmentID,
            to: .cancelled,
            actorEmployeeID: actorEmployeeID,
            note: cleanReason,
            at: timestamp
        )
    }

    @discardableResult
    func overrideStatus(
        assignmentID: UUID,
        to newStatus: AssignmentStatus,
        managerEmployeeID: UUID,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        clearError()
        _ = try requireAssignment(assignmentID)
        let cleanReason = normalizedRequired(reason)
        guard cleanReason.isEmpty == false else {
            throw record(.reasonRequired("Status override"))
        }

        do {
            try store.overrideStatus(
                assignmentID: assignmentID,
                to: newStatus,
                actorEmployeeID: managerEmployeeID,
                reason: cleanReason,
                at: timestamp
            )
        } catch {
            throw record(.storeFailure(message(for: error)))
        }

        let result = try requireAssignment(assignmentID)
        recordSuccess(.statusOverridden, assignmentID: assignmentID, at: timestamp)
        return result
    }

    @discardableResult
    func reopen(
        assignmentID: UUID,
        managerEmployeeID: UUID,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        clearError()
        let cleanReason = normalizedRequired(reason)
        guard cleanReason.isEmpty == false else {
            throw record(.reasonRequired("Reopen"))
        }

        do {
            try store.reopen(
                assignmentID: assignmentID,
                actorEmployeeID: managerEmployeeID,
                reason: cleanReason,
                at: timestamp
            )
        } catch {
            throw record(.storeFailure(message(for: error)))
        }

        let result = try requireAssignment(assignmentID)
        recordSuccess(.reopened, assignmentID: assignmentID, at: timestamp)
        return result
    }

    // MARK: - Crew

    @discardableResult
    func assignPrimaryTechnician(
        assignmentID: UUID,
        employeeID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .primaryTechnicianAssigned
        ) { assignment in
            try self.requireCrewEditable(assignment)

            if assignment.crew.primaryTechnicianID == employeeID {
                throw AssignmentEngineError.technicianAlreadyAssigned(employeeID)
            }
            if assignment.crew.containsActiveEmployee(employeeID) {
                throw AssignmentEngineError.technicianAlreadyAssigned(employeeID)
            }
            guard assignment.crew.primaryTechnicianID == nil else {
                throw AssignmentEngineError.primaryTechnicianAlreadyAssigned
            }

            assignment.crew.members.append(
                AssignmentCrewMember(
                    employeeID: employeeID,
                    role: .primary,
                    assignedDate: timestamp,
                    note: normalizedRequired(note ?? "")
                )
            )
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .primaryTechnicianAssigned,
                    title: "Primary technician assigned",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    affectedEmployeeID: employeeID,
                    note: normalizedOptional(note)
                )
            )
        }
    }

    @discardableResult
    func replacePrimaryTechnician(
        assignmentID: UUID,
        with employeeID: UUID,
        actorEmployeeID: UUID? = nil,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        let cleanReason = normalizedRequired(reason)
        guard cleanReason.isEmpty == false else {
            throw record(.reasonRequired("Primary technician replacement"))
        }

        return try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .primaryTechnicianReplaced
        ) { assignment in
            try self.requireCrewEditable(assignment)
            guard let formerID = assignment.crew.primaryTechnicianID else {
                throw AssignmentEngineError.primaryTechnicianRequired
            }
            guard formerID != employeeID else {
                throw AssignmentEngineError.technicianAlreadyAssigned(employeeID)
            }
            guard assignment.crew.containsActiveEmployee(employeeID) == false else {
                throw AssignmentEngineError.technicianAlreadyAssigned(employeeID)
            }

            for index in assignment.crew.members.indices where
                assignment.crew.members[index].employeeID == formerID &&
                assignment.crew.members[index].isActive {
                assignment.crew.members[index].removedDate = timestamp
            }
            assignment.crew.members.append(
                AssignmentCrewMember(
                    employeeID: employeeID,
                    role: .primary,
                    assignedDate: timestamp,
                    note: cleanReason
                )
            )
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .primaryTechnicianAssigned,
                    title: "Primary technician replaced",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    affectedEmployeeID: employeeID,
                    note: cleanReason,
                    metadata: ["formerEmployeeID": formerID.uuidString]
                )
            )
        }
    }

    @discardableResult
    func addSupportingTechnician(
        assignmentID: UUID,
        employeeID: UUID,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .supportingTechnicianAdded
        ) { assignment in
            try self.requireCrewEditable(assignment)
            guard assignment.crew.containsActiveEmployee(employeeID) == false else {
                throw AssignmentEngineError.technicianAlreadyAssigned(employeeID)
            }

            assignment.crew.members.append(
                AssignmentCrewMember(
                    employeeID: employeeID,
                    role: .supporting,
                    assignedDate: timestamp,
                    note: normalizedRequired(note ?? "")
                )
            )
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .supportingTechnicianAdded,
                    title: "Supporting technician added",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    affectedEmployeeID: employeeID,
                    note: normalizedOptional(note)
                )
            )
        }
    }

    @discardableResult
    func removeSupportingTechnician(
        assignmentID: UUID,
        employeeID: UUID,
        actorEmployeeID: UUID? = nil,
        reason: String,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        let cleanReason = normalizedRequired(reason)
        guard cleanReason.isEmpty == false else {
            throw record(.reasonRequired("Technician removal"))
        }

        return try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .technicianRemoved
        ) { assignment in
            try self.requireCrewEditable(assignment)
            guard let index = assignment.crew.members.firstIndex(where: {
                $0.employeeID == employeeID && $0.role == .supporting && $0.isActive
            }) else {
                throw AssignmentEngineError.supportingTechnicianNotFound(employeeID)
            }

            assignment.crew.members[index].removedDate = timestamp
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .technicianRemoved,
                    title: "Supporting technician removed",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    affectedEmployeeID: employeeID,
                    note: cleanReason
                )
            )
        }
    }

    @discardableResult
    func recordLabor(
        assignmentID: UUID,
        employeeID: UUID,
        laborMinutes: Int,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        guard laborMinutes >= 0 else {
            throw record(.laborMinutesCannotBeNegative)
        }

        return try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .laborRecorded,
            allowTerminal: true
        ) { assignment in
            guard let index = assignment.crew.members.lastIndex(where: {
                $0.employeeID == employeeID
            }) else {
                throw AssignmentEngineError.technicianNotFound(employeeID)
            }

            let previous = assignment.crew.members[index].laborMinutes
            assignment.crew.members[index].laborMinutes = laborMinutes
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .noteAdded,
                    title: "Technician labor recorded",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    affectedEmployeeID: employeeID,
                    note: normalizedOptional(note),
                    metadata: [
                        "previousMinutes": String(previous),
                        "newMinutes": String(laborMinutes)
                    ]
                )
            )
        }
    }

    // MARK: - Operational Details

    @discardableResult
    func updatePriority(
        assignmentID: UUID,
        priority: AssignmentPriority,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .priorityUpdated
        ) { assignment in
            let previous = assignment.priority
            assignment.priority = priority
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .priorityChanged,
                    title: "Assignment priority changed",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    note: normalizedOptional(note),
                    metadata: [
                        "previousPriority": previous.rawValue,
                        "newPriority": priority.rawValue
                    ]
                )
            )
        }
    }

    @discardableResult
    func updateRouteSequence(
        assignmentID: UUID,
        routeSequence: Int?,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: .routeSequenceUpdated
        ) { assignment in
            let previous = assignment.routeSequence
            assignment.routeSequence = normalizedRouteSequence(routeSequence)
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .routeOrderChanged,
                    title: "Route order changed",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    note: normalizedOptional(note),
                    metadata: [
                        "previousSequence": previous.map(String.init) ?? "none",
                        "newSequence": assignment.routeSequence.map(String.init) ?? "none"
                    ]
                )
            )
        }
    }

    @discardableResult
    func updateDispatchNotes(
        assignmentID: UUID,
        notes: String,
        actorEmployeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try updateNotes(
            assignmentID: assignmentID,
            notes: notes,
            isDispatchNote: true,
            actorEmployeeID: actorEmployeeID,
            timestamp: timestamp
        )
    }

    @discardableResult
    func updateFieldNotes(
        assignmentID: UUID,
        notes: String,
        actorEmployeeID: UUID? = nil,
        at timestamp: Date = Date()
    ) throws -> Assignment {
        try updateNotes(
            assignmentID: assignmentID,
            notes: notes,
            isDispatchNote: false,
            actorEmployeeID: actorEmployeeID,
            timestamp: timestamp
        )
    }

    // MARK: - Records Management

    func archive(assignmentID: UUID) throws {
        clearError()
        let assignment = try requireAssignment(assignmentID)
        guard assignment.status.isTerminal else {
            throw record(.activeAssignmentCannotBeArchived)
        }
        do {
            try store.archive(id: assignmentID)
        } catch {
            throw record(.storeFailure(message(for: error)))
        }
        recordSuccess(.archived, assignmentID: assignmentID)
    }

    func restore(assignmentID: UUID) throws {
        clearError()
        do {
            try store.restore(id: assignmentID)
        } catch {
            throw record(.storeFailure(message(for: error)))
        }
        recordSuccess(.restored, assignmentID: assignmentID)
    }

    @discardableResult
    func delete(assignmentID: UUID) throws -> Assignment {
        clearError()
        let assignment = try requireAssignment(assignmentID)
        guard assignment.status == .scheduled || assignment.status == .cancelled else {
            throw record(.operationalHistoryMustBeArchived)
        }
        do {
            let deleted = try store.delete(id: assignmentID)
            recordSuccess(.deleted, assignmentID: assignmentID)
            return deleted
        } catch {
            throw record(.storeFailure(message(for: error)))
        }
    }

    // MARK: - Validation

    func validateAssignment(id: UUID) -> AssignmentValidationResult {
        guard let assignment = store.assignment(id: id) else {
            return .invalid(["The assignment could not be found."])
        }
        return validateAssignment(assignment)
    }

    func validateAssignment(_ assignment: Assignment) -> AssignmentValidationResult {
        var invalid: [String] = []
        var warnings: [String] = []

        if assignment.assignmentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid.append("An assignment number is required.")
        }
        if assignment.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid.append("A job number is required.")
        }
        if assignment.customerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid.append("A customer number is required.")
        }
        if assignment.scheduling.isValid == false {
            invalid.append("Scheduling constraints are incomplete or invalid.")
        }

        if assignment.primaryTechnicianID == nil {
            warnings.append("A primary technician has not been assigned.")
        }
        if assignment.routeSequence == nil {
            warnings.append("The assignment does not yet have a route position.")
        }

        if invalid.isEmpty == false { return .invalid(invalid + warnings) }
        if warnings.isEmpty == false { return .warning(warnings) }
        return .ready
    }

    func validateForDispatch(id: UUID) -> AssignmentValidationResult {
        guard let assignment = store.assignment(id: id) else {
            return .invalid(["The assignment could not be found."])
        }
        return validateForDispatch(assignment)
    }

    private func validateForDispatch(_ assignment: Assignment) -> AssignmentValidationResult {
        var messages: [String] = []

        if assignment.lifecycleStatus != .active {
            messages.append("Archived assignments cannot be dispatched.")
        }
        if assignment.status != .scheduled {
            messages.append("Only scheduled assignments can be dispatched.")
        }
        if assignment.scheduling.isValid == false {
            messages.append("Scheduling must be complete before dispatch.")
        }
        if assignment.crew.isValid == false || assignment.primaryTechnicianID == nil {
            messages.append("A valid primary technician is required before dispatch.")
        }

        return messages.isEmpty ? .ready : .invalid(messages)
    }

    // MARK: - Analytics

    var analytics: AssignmentAnalyticsSnapshot {
        AssignmentAnalyticsSnapshot(
            total: store.assignmentCount,
            active: store.activeCount,
            completed: store.completedCount,
            closed: store.closedCount,
            cancelled: store.cancelledCount,
            archived: store.archivedCount,
            readyForDispatch: store.readyForDispatchAssignments.count,
            overdue: store.overdueAssignments.count,
            unassigned: store.unassignedAssignments.count
        )
    }

    // MARK: - Recommendation Hooks

    /// Extension point for the Workforce/Recommendation Engine.
    func recommendTechnician(for assignmentID: UUID) -> UUID? {
        nil
    }

    /// Extension point for the Daily Planner Engine.
    func recommendSchedule(for assignmentID: UUID) -> AssignmentScheduling? {
        nil
    }

    /// Extension point for route optimization and emergency insertion.
    func recommendRoutePosition(for assignmentID: UUID) -> Int? {
        nil
    }

    // MARK: - Private Mutation Helpers

    private func updateScheduling(
        assignmentID: UUID,
        scheduling: AssignmentScheduling,
        title: String,
        actorEmployeeID: UUID?,
        note: String?,
        timestamp: Date,
        operation: AssignmentOperation.Kind
    ) throws -> Assignment {
        try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: operation
        ) { assignment in
            guard assignment.status == .scheduled || assignment.status == .dispatched else {
                throw AssignmentEngineError.schedulingCannotChange(current: assignment.status)
            }
            assignment.scheduling = scheduling
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .schedulingUpdated,
                    title: title,
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    note: normalizedOptional(note),
                    metadata: ["mode": scheduling.mode.rawValue]
                )
            )
        }
    }

    private func updateNotes(
        assignmentID: UUID,
        notes: String,
        isDispatchNote: Bool,
        actorEmployeeID: UUID?,
        timestamp: Date
    ) throws -> Assignment {
        try mutateEditableAssignment(
            assignmentID: assignmentID,
            at: timestamp,
            operation: isDispatchNote ? .dispatchNotesUpdated : .fieldNotesUpdated,
            allowTerminal: true
        ) { assignment in
            let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if isDispatchNote {
                assignment.dispatchNotes = cleanNotes
            } else {
                assignment.fieldNotes = cleanNotes
            }
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .noteAdded,
                    title: isDispatchNote ? "Dispatch notes updated" : "Field notes updated",
                    timestamp: timestamp,
                    actorEmployeeID: actorEmployeeID,
                    note: cleanNotes.isEmpty ? "Notes cleared" : cleanNotes,
                    metadata: ["noteType": isDispatchNote ? "dispatch" : "field"]
                )
            )
        }
    }

    private func mutateEditableAssignment(
        assignmentID: UUID,
        at timestamp: Date,
        operation: AssignmentOperation.Kind,
        allowTerminal: Bool = false,
        mutation: (inout Assignment) throws -> Void
    ) throws -> Assignment {
        clearError()
        var assignment = try requireAssignment(assignmentID)

        guard assignment.lifecycleStatus == .active else {
            throw record(.archivedAssignmentCannotBeModified)
        }
        if allowTerminal == false && assignment.status.isTerminal {
            throw record(.terminalAssignmentCannotBeModified(assignment.status))
        }

        do {
            try mutation(&assignment)
            assignment.updatedDate = timestamp
            try store.update(assignment)
        } catch let error as AssignmentEngineError {
            throw record(error)
        } catch {
            throw record(.storeFailure(message(for: error)))
        }

        let result = try requireAssignment(assignmentID)
        recordSuccess(operation, assignmentID: assignmentID, at: timestamp)
        return result
    }

    private func requireCrewEditable(_ assignment: Assignment) throws {
        guard assignment.status == .scheduled || assignment.status == .dispatched else {
            throw AssignmentEngineError.crewCannotChangeAfterTravelBegins(
                current: assignment.status
            )
        }
    }

    private func requireAssignment(_ assignmentID: UUID) throws -> Assignment {
        guard let assignment = store.assignment(id: assignmentID) else {
            throw record(.assignmentNotFound(assignmentID))
        }
        return assignment
    }

    private func buildCrew(
        primaryTechnicianID: UUID?,
        supportingTechnicianIDs: [UUID],
        timestamp: Date
    ) throws -> AssignmentCrew {
        var uniqueSupportingIDs: [UUID] = []
        var seen = Set<UUID>()

        for employeeID in supportingTechnicianIDs {
            if employeeID == primaryTechnicianID {
                throw record(.technicianCannotHoldMultipleCrewRoles(employeeID))
            }
            guard seen.insert(employeeID).inserted else {
                throw record(.technicianAlreadyAssigned(employeeID))
            }
            uniqueSupportingIDs.append(employeeID)
        }

        var members: [AssignmentCrewMember] = []
        if let primaryTechnicianID {
            members.append(
                AssignmentCrewMember(
                    employeeID: primaryTechnicianID,
                    role: .primary,
                    assignedDate: timestamp
                )
            )
        }
        members.append(contentsOf: uniqueSupportingIDs.map {
            AssignmentCrewMember(
                employeeID: $0,
                role: .supporting,
                assignedDate: timestamp
            )
        })
        return AssignmentCrew(members: members)
    }

    private func generateAssignmentNumber(at timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: timestamp)
        let stem = "\(assignmentNumberPrefix)-\(day)-"

        let used = Set(store.assignments.compactMap { assignment -> Int? in
            guard assignment.assignmentNumber.hasPrefix(stem) else { return nil }
            return Int(assignment.assignmentNumber.dropFirst(stem.count))
        })

        var sequence = 1
        while used.contains(sequence) { sequence += 1 }
        return stem + String(format: "%03d", sequence)
    }

    private func normalizedRouteSequence(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return value > 0 ? value : nil
    }

    private func normalizedRequired(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = normalizedRequired(value)
        return clean.isEmpty ? nil : clean
    }

    private func operation(for status: AssignmentStatus) -> AssignmentOperation.Kind {
        switch status {
        case .scheduled: return .scheduled
        case .dispatched: return .dispatched
        case .enRoute: return .travelBegan
        case .onSite: return .arrived
        case .workComplete: return .completed
        case .invoiceReady: return .invoiceMarkedReady
        case .closed: return .closed
        case .cancelled: return .cancelled
        }
    }

    private func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    @discardableResult
    private func record(_ error: AssignmentEngineError) -> AssignmentEngineError {
        lastError = error
        return error
    }

    private func clearError() {
        lastError = nil
    }

    private func recordSuccess(
        _ kind: AssignmentOperation.Kind,
        assignmentID: UUID,
        at timestamp: Date = Date()
    ) {
        lastError = nil
        lastOperation = AssignmentOperation(
            kind: kind,
            assignmentID: assignmentID,
            timestamp: timestamp
        )
    }
}

// MARK: - Validation Result

enum AssignmentValidationState: String, Codable, Hashable {
    case ready
    case warning
    case invalid
}

struct AssignmentValidationResult: Codable, Hashable {
    let state: AssignmentValidationState
    let messages: [String]

    static let ready = AssignmentValidationResult(state: .ready, messages: [])

    static func warning(_ messages: [String]) -> AssignmentValidationResult {
        AssignmentValidationResult(state: .warning, messages: messages)
    }

    static func invalid(_ messages: [String]) -> AssignmentValidationResult {
        AssignmentValidationResult(state: .invalid, messages: messages)
    }
}

// MARK: - Operation Diagnostics

struct AssignmentOperation: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case created
        case scheduled
        case rescheduled
        case unscheduled
        case dispatched
        case travelBegan
        case arrived
        case completed
        case invoiceMarkedReady
        case closed
        case cancelled
        case reopened
        case statusOverridden
        case primaryTechnicianAssigned
        case primaryTechnicianReplaced
        case supportingTechnicianAdded
        case technicianRemoved
        case laborRecorded
        case priorityUpdated
        case routeSequenceUpdated
        case dispatchNotesUpdated
        case fieldNotesUpdated
        case archived
        case restored
        case deleted
    }

    let id: UUID
    let kind: Kind
    let assignmentID: UUID
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        assignmentID: UUID,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.assignmentID = assignmentID
        self.timestamp = timestamp
    }
}

struct AssignmentAnalyticsSnapshot: Codable, Hashable {
    let total: Int
    let active: Int
    let completed: Int
    let closed: Int
    let cancelled: Int
    let archived: Int
    let readyForDispatch: Int
    let overdue: Int
    let unassigned: Int
}

// MARK: - Errors

enum AssignmentEngineError: LocalizedError, Equatable {
    case assignmentNotFound(UUID)
    case missingRequiredValue(String)
    case validationFailed([String])
    case invalidScheduling
    case reasonRequired(String)
    case archivedAssignmentCannotBeModified
    case terminalAssignmentCannotBeModified(AssignmentStatus)
    case schedulingCannotChange(current: AssignmentStatus)
    case crewCannotChangeAfterTravelBegins(current: AssignmentStatus)
    case primaryTechnicianRequired
    case primaryTechnicianAlreadyAssigned
    case technicianAlreadyAssigned(UUID)
    case technicianCannotHoldMultipleCrewRoles(UUID)
    case technicianNotFound(UUID)
    case supportingTechnicianNotFound(UUID)
    case laborMinutesCannotBeNegative
    case workCanOnlyCompleteFromOnSite(current: AssignmentStatus)
    case cannotCancelAfterInvoiceReady
    case activeAssignmentCannotBeArchived
    case operationalHistoryMustBeArchived
    case storeFailure(String)

    var errorDescription: String? {
        switch self {
        case let .assignmentNotFound(id):
            return "Assignment \(id.uuidString) was not found."
        case let .missingRequiredValue(name):
            return "\(name) is required."
        case let .validationFailed(messages):
            return messages.joined(separator: " ")
        case .invalidScheduling:
            return "The scheduling constraints are incomplete or invalid."
        case let .reasonRequired(operation):
            return "A reason is required for \(operation.lowercased())."
        case .archivedAssignmentCannotBeModified:
            return "Archived assignments must be restored before they can be modified."
        case let .terminalAssignmentCannotBeModified(status):
            return "An assignment in \(status.rawValue) status must be reopened before it can be modified."
        case let .schedulingCannotChange(status):
            return "Scheduling cannot be changed while the assignment is \(status.rawValue)."
        case let .crewCannotChangeAfterTravelBegins(status):
            return "The crew cannot be changed after travel begins. Current status: \(status.rawValue)."
        case .primaryTechnicianRequired:
            return "A primary technician is required."
        case .primaryTechnicianAlreadyAssigned:
            return "This assignment already has a primary technician. Use replacePrimaryTechnician instead."
        case let .technicianAlreadyAssigned(id):
            return "Technician \(id.uuidString) is already assigned to this crew."
        case let .technicianCannotHoldMultipleCrewRoles(id):
            return "Technician \(id.uuidString) cannot be both primary and supporting on the same assignment."
        case let .technicianNotFound(id):
            return "Technician \(id.uuidString) is not present in the assignment crew history."
        case let .supportingTechnicianNotFound(id):
            return "Technician \(id.uuidString) is not an active supporting technician on this assignment."
        case .laborMinutesCannotBeNegative:
            return "Labor minutes cannot be negative."
        case let .workCanOnlyCompleteFromOnSite(status):
            return "Work can be completed only from On Site status. Current status: \(status.rawValue)."
        case .cannotCancelAfterInvoiceReady:
            return "An assignment cannot be cancelled after its invoice is ready. Use an authorized override if correction is required."
        case .activeAssignmentCannotBeArchived:
            return "Active work cannot be archived. Close or cancel the assignment first."
        case .operationalHistoryMustBeArchived:
            return "Assignments with operational history must be archived instead of permanently deleted."
        case let .storeFailure(message):
            return message
        }
    }
}
//
//  AssignmentEngine.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/21/26.
//

import Foundation
