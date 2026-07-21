//
//  AssignmentStore.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation
import Combine

/// The authoritative in-memory collection of operational assignments.
///
/// `AssignmentStore` owns assignment CRUD, lookup, filtering, active-work
/// collections, and guarded lifecycle transitions. Views and higher-level
/// engines should mutate assignments through this store rather than editing
/// stored values directly.
@MainActor
final class AssignmentStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var assignments: [Assignment]

    /// Increments after every successful mutation. This is useful for future
    /// persistence, synchronization, analytics, and UI refresh diagnostics.
    @Published private(set) var revision: UInt64 = 0

    /// Optional persistence/synchronization hook. The store invokes this after
    /// a successful mutation with a normalized snapshot of all assignments.
    var onAssignmentsChanged: (([Assignment]) -> Void)?

    // MARK: - Initialization

    init(assignments: [Assignment] = []) {
        self.assignments = Self.normalized(assignments)
    }

    // MARK: - CRUD

    /// Inserts a new assignment.
    ///
    /// - Parameters:
    ///   - assignment: Assignment to insert.
    ///   - allowMultipleActiveAssignmentsForJob: Allows more than one active
    ///     assignment for the same job when work is intentionally split.
    func add(
        _ assignment: Assignment,
        allowMultipleActiveAssignmentsForJob: Bool = false
    ) throws {
        guard assignments.contains(where: { $0.id == assignment.id }) == false else {
            throw AssignmentStoreError.duplicateAssignmentID(assignment.id)
        }

        guard assignments.contains(where: {
            $0.assignmentNumber.caseInsensitiveCompare(assignment.assignmentNumber) == .orderedSame
        }) == false else {
            throw AssignmentStoreError.duplicateAssignmentNumber(assignment.assignmentNumber)
        }

        try validate(
            assignment,
            excludingAssignmentID: nil,
            allowMultipleActiveAssignmentsForJob: allowMultipleActiveAssignmentsForJob
        )

        var inserted = assignment
        let now = Date()
        inserted.createdDate = min(inserted.createdDate, now)
        inserted.updatedDate = now

        if inserted.history.events.isEmpty {
            inserted.history.append(
                AssignmentHistoryEvent(
                    type: .created,
                    title: "Assignment created",
                    timestamp: now,
                    resultingStatus: inserted.status,
                    metadata: [
                        "assignmentNumber": inserted.assignmentNumber,
                        "jobNumber": inserted.jobNumber,
                        "creationSource": inserted.creationSource.rawValue
                    ]
                )
            )
        }

        assignments.append(inserted)
        commitMutation()
    }

    /// Replaces an existing assignment after validation.
    ///
    /// Use lifecycle methods such as `changeStatus` for status changes so that
    /// transition rules, timestamps, and history remain consistent.
    func update(
        _ assignment: Assignment,
        allowMultipleActiveAssignmentsForJob: Bool = false
    ) throws {
        guard let index = index(of: assignment.id) else {
            throw AssignmentStoreError.assignmentNotFound(assignment.id)
        }

        let current = assignments[index]

        guard current.status == assignment.status else {
            throw AssignmentStoreError.directStatusMutationNotAllowed(
                current: current.status,
                requested: assignment.status
            )
        }

        guard assignments.contains(where: {
            $0.id != assignment.id &&
            $0.assignmentNumber.caseInsensitiveCompare(assignment.assignmentNumber) == .orderedSame
        }) == false else {
            throw AssignmentStoreError.duplicateAssignmentNumber(assignment.assignmentNumber)
        }

        try validate(
            assignment,
            excludingAssignmentID: assignment.id,
            allowMultipleActiveAssignmentsForJob: allowMultipleActiveAssignmentsForJob
        )

        var replacement = assignment
        replacement.createdDate = current.createdDate
        replacement.updatedDate = Date()
        assignments[index] = replacement
        commitMutation()
    }

    /// Removes an assignment from the store.
    ///
    /// Permanent deletion should normally be limited to drafts/test data.
    /// Closed operational records should generally be archived instead.
    @discardableResult
    func delete(id: UUID) throws -> Assignment {
        guard let index = index(of: id) else {
            throw AssignmentStoreError.assignmentNotFound(id)
        }

        let removed = assignments.remove(at: index)
        commitMutation()
        return removed
    }

    /// Archives one assignment without deleting its operational history.
    func archive(id: UUID) throws {
        try mutateAssignment(id: id) { assignment, now in
            guard assignment.lifecycleStatus != .archived else { return }
            assignment.lifecycleStatus = .archived
            assignment.updatedDate = now
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .statusChanged,
                    title: "Assignment archived",
                    timestamp: now,
                    previousStatus: assignment.status,
                    resultingStatus: assignment.status,
                    metadata: ["lifecycleStatus": RecordLifecycleStatus.archived.rawValue]
                )
            )
        }
    }

    /// Restores an archived assignment to the active record collection.
    func restore(id: UUID) throws {
        try mutateAssignment(id: id) { assignment, now in
            guard assignment.lifecycleStatus != .active else { return }
            assignment.lifecycleStatus = .active
            assignment.updatedDate = now
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .reopened,
                    title: "Assignment restored",
                    timestamp: now,
                    previousStatus: assignment.status,
                    resultingStatus: assignment.status,
                    metadata: ["lifecycleStatus": RecordLifecycleStatus.active.rawValue]
                )
            )
        }
    }

    /// Replaces the complete store snapshot. Intended for persistence restore,
    /// migration, import, or synchronization—not routine view mutations.
    func replaceAll(with assignments: [Assignment]) throws {
        let duplicateIDs = Dictionary(grouping: assignments, by: \.id)
            .filter { $0.value.count > 1 }
            .map(\.key)

        guard duplicateIDs.isEmpty else {
            throw AssignmentStoreError.duplicateAssignmentID(duplicateIDs[0])
        }

        let duplicateNumbers = Dictionary(
            grouping: assignments,
            by: { $0.assignmentNumber.lowercased() }
        )
        .filter { $0.value.count > 1 }
        .map(\.key)

        guard duplicateNumbers.isEmpty else {
            throw AssignmentStoreError.duplicateAssignmentNumber(duplicateNumbers[0])
        }

        self.assignments = Self.normalized(assignments)
        commitMutation()
    }

    // MARK: - Lookup

    func assignment(id: UUID) -> Assignment? {
        assignments.first { $0.id == id }
    }

    func assignment(number: String) -> Assignment? {
        assignments.first {
            $0.assignmentNumber.caseInsensitiveCompare(number) == .orderedSame
        }
    }

    func assignmentsForJob(_ jobID: UUID) -> [Assignment] {
        sorted(assignments.filter { $0.jobID == jobID })
    }

    func assignmentsForJobNumber(_ jobNumber: String) -> [Assignment] {
        sorted(assignments.filter {
            $0.jobNumber.caseInsensitiveCompare(jobNumber) == .orderedSame
        })
    }

    func assignmentsForCustomerNumber(_ customerNumber: String) -> [Assignment] {
        sorted(assignments.filter {
            $0.customerNumber.caseInsensitiveCompare(customerNumber) == .orderedSame
        })
    }

    func assignmentsForSite(_ siteID: UUID) -> [Assignment] {
        sorted(assignments.filter { $0.siteID == siteID })
    }

    func assignmentsForTechnician(_ technicianID: UUID) -> [Assignment] {
        sorted(assignments.filter {
            $0.crew.containsActiveEmployee(technicianID)
        })
    }

    func primaryAssignments(for technicianID: UUID) -> [Assignment] {
        sorted(assignments.filter {
            $0.primaryTechnicianID == technicianID
        })
    }

    func supportingAssignments(for technicianID: UUID) -> [Assignment] {
        sorted(assignments.filter {
            $0.supportingTechnicianIDs.contains(technicianID)
        })
    }

    func assignments(
        on date: Date,
        calendar: Calendar = .current,
        includeArchived: Bool = false
    ) -> [Assignment] {
        sorted(assignments.filter { assignment in
            guard includeArchived || assignment.lifecycleStatus == .active else {
                return false
            }

            guard let operationalDate = assignment.scheduling.operationalDate else {
                return false
            }

            return calendar.isDate(operationalDate, inSameDayAs: date)
        })
    }

    // MARK: - Computed Collections

    var activeAssignments: [Assignment] {
        sorted(assignments.filter(\.isOperationallyActive))
    }

    var completedAssignments: [Assignment] {
        sorted(assignments.filter {
            $0.lifecycleStatus == .active &&
            ($0.status == .workComplete ||
             $0.status == .invoiceReady ||
             $0.status == .closed)
        })
    }

    var closedAssignments: [Assignment] {
        sorted(assignments.filter {
            $0.lifecycleStatus == .active && $0.status == .closed
        })
    }

    var cancelledAssignments: [Assignment] {
        sorted(assignments.filter {
            $0.lifecycleStatus == .active && $0.status == .cancelled
        })
    }

    var archivedAssignments: [Assignment] {
        sorted(assignments.filter { $0.lifecycleStatus == .archived })
    }

    var unscheduledAssignments: [Assignment] {
        sorted(assignments.filter {
            $0.lifecycleStatus == .active &&
            $0.status == .scheduled &&
            $0.scheduling.hasUsableSchedule == false
        })
    }

    var unassignedAssignments: [Assignment] {
        sorted(assignments.filter {
            $0.lifecycleStatus == .active &&
            $0.status.isActive &&
            $0.primaryTechnicianID == nil
        })
    }

    var readyForDispatchAssignments: [Assignment] {
        sorted(assignments.filter(\.isReadyForDispatch))
    }

    var highPriorityAssignments: [Assignment] {
        sorted(assignments.filter {
            $0.isOperationallyActive &&
            ($0.priority == .high || $0.priority == .emergency)
        })
    }

    var todayAssignments: [Assignment] {
        assignments(on: Date())
    }

    var tomorrowAssignments: [Assignment] {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else {
            return []
        }
        return assignments(on: tomorrow)
    }

    var overdueAssignments: [Assignment] {
        overdueAssignments(relativeTo: Date())
    }

    func overdueAssignments(relativeTo date: Date) -> [Assignment] {
        sorted(assignments.filter { assignment in
            guard assignment.lifecycleStatus == .active,
                  assignment.status.isActive,
                  assignment.status != .workComplete,
                  assignment.status != .invoiceReady,
                  let dueDate = assignment.scheduling.operationalDueDate else {
                return false
            }

            return dueDate < date
        })
    }

    // MARK: - Filtering

    func filtered(
        status: AssignmentStatus? = nil,
        priority: AssignmentPriority? = nil,
        technicianID: UUID? = nil,
        jobID: UUID? = nil,
        customerNumber: String? = nil,
        lifecycleStatus: RecordLifecycleStatus? = .active,
        date: Date? = nil,
        calendar: Calendar = .current,
        searchText: String = ""
    ) -> [Assignment] {
        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return sorted(assignments.filter { assignment in
            if let status, assignment.status != status { return false }
            if let priority, assignment.priority != priority { return false }
            if let technicianID,
               assignment.crew.containsActiveEmployee(technicianID) == false {
                return false
            }
            if let jobID, assignment.jobID != jobID { return false }
            if let customerNumber,
               assignment.customerNumber.caseInsensitiveCompare(customerNumber) != .orderedSame {
                return false
            }
            if let lifecycleStatus,
               assignment.lifecycleStatus != lifecycleStatus {
                return false
            }
            if let date {
                guard let operationalDate = assignment.scheduling.operationalDate,
                      calendar.isDate(operationalDate, inSameDayAs: date) else {
                    return false
                }
            }

            guard normalizedSearch.isEmpty == false else { return true }

            return assignment.assignmentNumber.lowercased().contains(normalizedSearch) ||
                assignment.jobNumber.lowercased().contains(normalizedSearch) ||
                assignment.customerNumber.lowercased().contains(normalizedSearch) ||
                assignment.dispatchNotes.lowercased().contains(normalizedSearch) ||
                assignment.fieldNotes.lowercased().contains(normalizedSearch) ||
                assignment.scheduling.schedulingNotes.lowercased().contains(normalizedSearch)
        })
    }

    // MARK: - Lifecycle

    /// Applies a guarded status transition and records lifecycle timestamps and
    /// history. Use `overrideStatus` only when an authorized human intentionally
    /// needs to bypass the normal workflow.
    func changeStatus(
        assignmentID: UUID,
        to newStatus: AssignmentStatus,
        actorEmployeeID: UUID? = nil,
        note: String? = nil,
        at timestamp: Date = Date()
    ) throws {
        try mutateAssignment(id: assignmentID, timestamp: timestamp) { assignment, now in
            let previousStatus = assignment.status

            guard previousStatus != newStatus else { return }

            guard Self.allowedTransitions[previousStatus, default: []].contains(newStatus) else {
                throw AssignmentStoreError.invalidStatusTransition(
                    from: previousStatus,
                    to: newStatus
                )
            }

            try Self.applyTransitionPrerequisites(
                assignment: assignment,
                from: previousStatus,
                to: newStatus
            )

            assignment.status = newStatus
            assignment.updatedDate = now
            Self.applyLifecycleTimestamp(to: &assignment, for: newStatus, at: now)
            assignment.history.append(
                Self.statusHistoryEvent(
                    from: previousStatus,
                    to: newStatus,
                    actorEmployeeID: actorEmployeeID,
                    note: note,
                    timestamp: now,
                    wasOverride: false
                )
            )
        }
    }

    /// Intentionally bypasses normal lifecycle transition rules while retaining
    /// a durable audit trail. Authorization is expected to be enforced by the
    /// caller or the future Assignment Engine.
    func overrideStatus(
        assignmentID: UUID,
        to newStatus: AssignmentStatus,
        actorEmployeeID: UUID,
        reason: String,
        at timestamp: Date = Date()
    ) throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.isEmpty == false else {
            throw AssignmentStoreError.overrideReasonRequired
        }

        try mutateAssignment(id: assignmentID, timestamp: timestamp) { assignment, now in
            let previousStatus = assignment.status
            guard previousStatus != newStatus else { return }

            assignment.status = newStatus
            assignment.updatedDate = now
            Self.applyLifecycleTimestamp(to: &assignment, for: newStatus, at: now)
            assignment.history.append(
                Self.statusHistoryEvent(
                    from: previousStatus,
                    to: newStatus,
                    actorEmployeeID: actorEmployeeID,
                    note: trimmedReason,
                    timestamp: now,
                    wasOverride: true
                )
            )
        }
    }

    /// Reopens a closed or cancelled assignment as scheduled work.
    func reopen(
        assignmentID: UUID,
        actorEmployeeID: UUID,
        reason: String,
        at timestamp: Date = Date()
    ) throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.isEmpty == false else {
            throw AssignmentStoreError.overrideReasonRequired
        }

        try mutateAssignment(id: assignmentID, timestamp: timestamp) { assignment, now in
            guard assignment.status == .closed || assignment.status == .cancelled else {
                throw AssignmentStoreError.assignmentIsNotTerminal(assignment.status)
            }

            let previousStatus = assignment.status
            assignment.status = .scheduled
            assignment.lifecycleStatus = .active
            assignment.updatedDate = now
            assignment.closedDate = nil
            assignment.cancelledDate = nil
            assignment.history.append(
                AssignmentHistoryEvent(
                    type: .reopened,
                    title: "Assignment reopened",
                    timestamp: now,
                    actorEmployeeID: actorEmployeeID,
                    previousStatus: previousStatus,
                    resultingStatus: .scheduled,
                    note: trimmedReason
                )
            )
        }
    }

    /// Archives all closed or cancelled records currently retained as active.
    @discardableResult
    func archiveCompleted(at timestamp: Date = Date()) -> Int {
        var archivedCount = 0

        for index in assignments.indices {
            guard assignments[index].lifecycleStatus == .active,
                  assignments[index].status == .closed || assignments[index].status == .cancelled else {
                continue
            }

            assignments[index].lifecycleStatus = .archived
            assignments[index].updatedDate = timestamp
            assignments[index].history.append(
                AssignmentHistoryEvent(
                    type: .statusChanged,
                    title: "Assignment archived",
                    timestamp: timestamp,
                    previousStatus: assignments[index].status,
                    resultingStatus: assignments[index].status,
                    metadata: ["lifecycleStatus": RecordLifecycleStatus.archived.rawValue]
                )
            )
            archivedCount += 1
        }

        if archivedCount > 0 {
            commitMutation()
        }

        return archivedCount
    }

    // MARK: - Statistics

    var assignmentCount: Int { assignments.count }
    var activeCount: Int { activeAssignments.count }
    var completedCount: Int { completedAssignments.count }
    var closedCount: Int { closedAssignments.count }
    var cancelledCount: Int { cancelledAssignments.count }
    var archivedCount: Int { archivedAssignments.count }
    var unassignedCount: Int { unassignedAssignments.count }
    var overdueCount: Int { overdueAssignments.count }

    func count(status: AssignmentStatus) -> Int {
        assignments.lazy.filter { $0.status == status }.count
    }

    func count(priority: AssignmentPriority) -> Int {
        assignments.lazy.filter { $0.priority == priority }.count
    }

    // MARK: - Sorting

    func sorted(
        _ source: [Assignment],
        by order: AssignmentSortOrder = .operational
    ) -> [Assignment] {
        source.sorted { lhs, rhs in
            switch order {
            case .operational:
                return Self.isOrderedOperationally(lhs, before: rhs)

            case .scheduledDate:
                return Self.compareOptionalDates(
                    lhs.scheduling.operationalDate,
                    rhs.scheduling.operationalDate,
                    fallbackLHS: lhs.assignmentNumber,
                    fallbackRHS: rhs.assignmentNumber
                )

            case .priority:
                if lhs.priority.sortOrder != rhs.priority.sortOrder {
                    return lhs.priority.sortOrder > rhs.priority.sortOrder
                }
                return Self.isOrderedOperationally(lhs, before: rhs)

            case .status:
                if lhs.status.sortOrder != rhs.status.sortOrder {
                    return lhs.status.sortOrder < rhs.status.sortOrder
                }
                return Self.isOrderedOperationally(lhs, before: rhs)

            case .routeSequence:
                let leftSequence = lhs.routeSequence ?? Int.max
                let rightSequence = rhs.routeSequence ?? Int.max
                if leftSequence != rightSequence {
                    return leftSequence < rightSequence
                }
                return Self.isOrderedOperationally(lhs, before: rhs)

            case .assignmentNumber:
                return lhs.assignmentNumber.localizedStandardCompare(rhs.assignmentNumber) == .orderedAscending
            }
        }
    }

    // MARK: - Private Mutation Support

    private func index(of assignmentID: UUID) -> Int? {
        assignments.firstIndex { $0.id == assignmentID }
    }

    private func mutateAssignment(
        id: UUID,
        timestamp: Date = Date(),
        mutation: (inout Assignment, Date) throws -> Void
    ) throws {
        guard let index = index(of: id) else {
            throw AssignmentStoreError.assignmentNotFound(id)
        }

        var workingCopy = assignments[index]
        try mutation(&workingCopy, timestamp)
        assignments[index] = workingCopy
        commitMutation()
    }

    private func validate(
        _ assignment: Assignment,
        excludingAssignmentID: UUID?,
        allowMultipleActiveAssignmentsForJob: Bool
    ) throws {
        guard assignment.assignmentNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw AssignmentStoreError.invalidAssignment([.missingAssignmentNumber])
        }

        guard assignment.jobNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw AssignmentStoreError.invalidAssignment([.missingJobNumber])
        }

        guard assignment.customerNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false else {
            throw AssignmentStoreError.invalidAssignment([.missingCustomerNumber])
        }

        if allowMultipleActiveAssignmentsForJob == false,
           assignment.isOperationallyActive,
           assignments.contains(where: {
               $0.id != excludingAssignmentID &&
               $0.jobID == assignment.jobID &&
               $0.isOperationallyActive
           }) {
            throw AssignmentStoreError.activeAssignmentAlreadyExistsForJob(assignment.jobID)
        }
    }

    private func commitMutation() {
        assignments = Self.normalized(assignments)
        revision &+= 1
        onAssignmentsChanged?(assignments)
    }

    private static func normalized(_ assignments: [Assignment]) -> [Assignment] {
        assignments.sorted(by: isOrderedOperationally)
    }

    // MARK: - Lifecycle Rules

    private static let allowedTransitions: [AssignmentStatus: Set<AssignmentStatus>] = [
        .scheduled: [.dispatched, .cancelled],
        .dispatched: [.scheduled, .enRoute, .cancelled],
        .enRoute: [.dispatched, .onSite, .cancelled],
        .onSite: [.enRoute, .workComplete, .cancelled],
        .workComplete: [.onSite, .invoiceReady, .closed],
        .invoiceReady: [.workComplete, .closed],
        .closed: [],
        .cancelled: []
    ]

    private static func applyTransitionPrerequisites(
        assignment: Assignment,
        from previousStatus: AssignmentStatus,
        to newStatus: AssignmentStatus
    ) throws {
        switch newStatus {
        case .dispatched:
            guard assignment.scheduling.isValid else {
                throw AssignmentStoreError.assignmentNotReadyForDispatch(
                    assignment.id,
                    reason: "Scheduling is incomplete or invalid."
                )
            }
            guard assignment.crew.isValid else {
                throw AssignmentStoreError.assignmentNotReadyForDispatch(
                    assignment.id,
                    reason: "A valid primary technician is required."
                )
            }

        case .enRoute, .onSite:
            guard assignment.primaryTechnicianID != nil else {
                throw AssignmentStoreError.primaryTechnicianRequired(assignment.id)
            }

        case .workComplete:
            guard previousStatus == .onSite else {
                throw AssignmentStoreError.invalidStatusTransition(
                    from: previousStatus,
                    to: newStatus
                )
            }

        case .scheduled, .invoiceReady, .closed, .cancelled:
            break
        }
    }

    private static func applyLifecycleTimestamp(
        to assignment: inout Assignment,
        for status: AssignmentStatus,
        at timestamp: Date
    ) {
        switch status {
        case .scheduled:
            break
        case .dispatched:
            assignment.dispatchedDate = assignment.dispatchedDate ?? timestamp
        case .enRoute:
            assignment.enRouteDate = assignment.enRouteDate ?? timestamp
        case .onSite:
            assignment.onSiteDate = assignment.onSiteDate ?? timestamp
        case .workComplete:
            assignment.workCompletedDate = assignment.workCompletedDate ?? timestamp
        case .invoiceReady:
            assignment.invoiceReadyDate = assignment.invoiceReadyDate ?? timestamp
        case .closed:
            assignment.closedDate = assignment.closedDate ?? timestamp
        case .cancelled:
            assignment.cancelledDate = assignment.cancelledDate ?? timestamp
        }
    }

    private static func statusHistoryEvent(
        from previousStatus: AssignmentStatus,
        to newStatus: AssignmentStatus,
        actorEmployeeID: UUID?,
        note: String?,
        timestamp: Date,
        wasOverride: Bool
    ) -> AssignmentHistoryEvent {
        let eventType: AssignmentHistoryEventType
        let title: String

        if wasOverride {
            eventType = .overrideApplied
            title = "Status override applied"
        } else {
            switch newStatus {
            case .dispatched:
                eventType = .dispatched
                title = "Assignment dispatched"
            case .workComplete:
                eventType = .workCompleted
                title = "Work completed"
            case .invoiceReady:
                eventType = .invoiceMarkedReady
                title = "Invoice marked ready"
            case .closed:
                eventType = .closed
                title = "Assignment closed"
            case .cancelled:
                eventType = .cancelled
                title = "Assignment cancelled"
            default:
                eventType = .statusChanged
                title = "Assignment status changed"
            }
        }

        return AssignmentHistoryEvent(
            type: eventType,
            title: title,
            timestamp: timestamp,
            actorEmployeeID: actorEmployeeID,
            previousStatus: previousStatus,
            resultingStatus: newStatus,
            note: note,
            metadata: ["override": wasOverride ? "true" : "false"]
        )
    }

    // MARK: - Sort Helpers

    private static func isOrderedOperationally(
        _ lhs: Assignment,
        before rhs: Assignment
    ) -> Bool {
        if lhs.lifecycleStatus != rhs.lifecycleStatus {
            return lhs.lifecycleStatus == .active
        }

        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder > rhs.priority.sortOrder
        }

        let leftDate = lhs.scheduling.operationalDate
        let rightDate = rhs.scheduling.operationalDate

        if leftDate != rightDate {
            return compareOptionalDates(
                leftDate,
                rightDate,
                fallbackLHS: lhs.assignmentNumber,
                fallbackRHS: rhs.assignmentNumber
            )
        }

        let leftSequence = lhs.routeSequence ?? Int.max
        let rightSequence = rhs.routeSequence ?? Int.max
        if leftSequence != rightSequence {
            return leftSequence < rightSequence
        }

        if lhs.status.sortOrder != rhs.status.sortOrder {
            return lhs.status.sortOrder < rhs.status.sortOrder
        }

        return lhs.assignmentNumber.localizedStandardCompare(rhs.assignmentNumber) == .orderedAscending
    }

    private static func compareOptionalDates(
        _ lhs: Date?,
        _ rhs: Date?,
        fallbackLHS: String,
        fallbackRHS: String
    ) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left != right { return left < right }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        return fallbackLHS.localizedStandardCompare(fallbackRHS) == .orderedAscending
    }
}

// MARK: - Supporting Types

enum AssignmentSortOrder: String, CaseIterable, Identifiable {
    case operational = "Operational"
    case scheduledDate = "Scheduled Date"
    case priority = "Priority"
    case status = "Status"
    case routeSequence = "Route Sequence"
    case assignmentNumber = "Assignment Number"

    var id: String { rawValue }
}

enum AssignmentStoreError: LocalizedError, Equatable {
    case assignmentNotFound(UUID)
    case duplicateAssignmentID(UUID)
    case duplicateAssignmentNumber(String)
    case activeAssignmentAlreadyExistsForJob(UUID)
    case invalidAssignment([AssignmentValidationIssue])
    case directStatusMutationNotAllowed(
        current: AssignmentStatus,
        requested: AssignmentStatus
    )
    case invalidStatusTransition(from: AssignmentStatus, to: AssignmentStatus)
    case assignmentNotReadyForDispatch(UUID, reason: String)
    case primaryTechnicianRequired(UUID)
    case overrideReasonRequired
    case assignmentIsNotTerminal(AssignmentStatus)

    var errorDescription: String? {
        switch self {
        case let .assignmentNotFound(id):
            return "Assignment \(id.uuidString) was not found."

        case let .duplicateAssignmentID(id):
            return "An assignment with ID \(id.uuidString) already exists."

        case let .duplicateAssignmentNumber(number):
            return "Assignment number \(number) already exists."

        case let .activeAssignmentAlreadyExistsForJob(jobID):
            return "Job \(jobID.uuidString) already has an active assignment."

        case let .invalidAssignment(issues):
            return issues.map(\.rawValue).joined(separator: " ")

        case let .directStatusMutationNotAllowed(current, requested):
            return "Assignment status cannot be changed directly from \(current.rawValue) to \(requested.rawValue). Use changeStatus or overrideStatus."

        case let .invalidStatusTransition(from, to):
            return "The assignment cannot move directly from \(from.rawValue) to \(to.rawValue)."

        case let .assignmentNotReadyForDispatch(id, reason):
            return "Assignment \(id.uuidString) is not ready for dispatch. \(reason)"

        case let .primaryTechnicianRequired(id):
            return "Assignment \(id.uuidString) requires a primary technician."

        case .overrideReasonRequired:
            return "A reason is required for an override or reopen action."

        case let .assignmentIsNotTerminal(status):
            return "Only closed or cancelled assignments may be reopened. Current status: \(status.rawValue)."
        }
    }
}

// MARK: - Scheduling Query Helpers

private extension AssignmentScheduling {
    var operationalDate: Date? {
        switch mode {
        case .fixedTime:
            return fixedStartDate ?? serviceDate
        case .arrivalWindow:
            return arrivalWindowStart ?? serviceDate
        case .flexibleDay:
            return serviceDate
        case .deadline:
            return serviceDate ?? completionDeadline
        }
    }

    var operationalDueDate: Date? {
        switch mode {
        case .fixedTime:
            guard let start = fixedStartDate else { return nil }
            return Calendar.current.date(
                byAdding: .minute,
                value: totalPlannedMinutes,
                to: start
            )
        case .arrivalWindow:
            return arrivalWindowEnd
        case .flexibleDay:
            guard let serviceDate else { return nil }
            return Calendar.current.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: serviceDate
            )
        case .deadline:
            return completionDeadline
        }
    }

    var hasUsableSchedule: Bool {
        isValid && operationalDate != nil
    }
}
