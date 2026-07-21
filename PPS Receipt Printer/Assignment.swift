//
//  Assignment.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation

/// The field-execution record for a Job.
///
/// A Job remains the business record. An Assignment owns operational execution:
/// scheduling constraints, technician ownership, crew participation, dispatch
/// state, field progress, notes, timestamps, and history.
struct Assignment: Identifiable, Codable, Hashable {
    var id: UUID
    var assignmentNumber: String

    /// Business record from which this assignment originated.
    var jobID: UUID
    var jobNumber: String

    /// Denormalized references retained for fast operational lookup.
    var customerNumber: String
    var siteID: UUID?

    var status: AssignmentStatus
    var priority: AssignmentPriority
    var creationSource: AssignmentCreationSource

    var scheduling: AssignmentScheduling
    var crew: AssignmentCrew
    var history: AssignmentHistory

    /// Dispatcher and technician notes that apply to execution of the work.
    var dispatchNotes: String
    var fieldNotes: String

    /// Manual board order within a technician's route/day.
    var routeSequence: Int?

    var createdDate: Date
    var updatedDate: Date

    var dispatchedDate: Date?
    var enRouteDate: Date?
    var onSiteDate: Date?
    var workCompletedDate: Date?
    var invoiceReadyDate: Date?
    var closedDate: Date?
    var cancelledDate: Date?

    var lifecycleStatus: RecordLifecycleStatus

    init(
        id: UUID = UUID(),
        assignmentNumber: String,
        jobID: UUID,
        jobNumber: String,
        customerNumber: String,
        siteID: UUID? = nil,
        status: AssignmentStatus = .scheduled,
        priority: AssignmentPriority = .normal,
        creationSource: AssignmentCreationSource = .jobConversion,
        scheduling: AssignmentScheduling,
        crew: AssignmentCrew = AssignmentCrew(),
        history: AssignmentHistory = AssignmentHistory(),
        dispatchNotes: String = "",
        fieldNotes: String = "",
        routeSequence: Int? = nil,
        createdDate: Date = Date(),
        updatedDate: Date = Date(),
        dispatchedDate: Date? = nil,
        enRouteDate: Date? = nil,
        onSiteDate: Date? = nil,
        workCompletedDate: Date? = nil,
        invoiceReadyDate: Date? = nil,
        closedDate: Date? = nil,
        cancelledDate: Date? = nil,
        lifecycleStatus: RecordLifecycleStatus = .active
    ) {
        self.id = id
        self.assignmentNumber = assignmentNumber
        self.jobID = jobID
        self.jobNumber = jobNumber
        self.customerNumber = customerNumber
        self.siteID = siteID
        self.status = status
        self.priority = priority
        self.creationSource = creationSource
        self.scheduling = scheduling
        self.crew = crew
        self.history = history
        self.dispatchNotes = dispatchNotes
        self.fieldNotes = fieldNotes
        self.routeSequence = routeSequence
        self.createdDate = createdDate
        self.updatedDate = updatedDate
        self.dispatchedDate = dispatchedDate
        self.enRouteDate = enRouteDate
        self.onSiteDate = onSiteDate
        self.workCompletedDate = workCompletedDate
        self.invoiceReadyDate = invoiceReadyDate
        self.closedDate = closedDate
        self.cancelledDate = cancelledDate
        self.lifecycleStatus = lifecycleStatus
    }

    var primaryTechnicianID: UUID? {
        crew.primaryTechnicianID
    }

    var supportingTechnicianIDs: [UUID] {
        crew.supportingTechnicianIDs
    }

    var isOperationallyActive: Bool {
        lifecycleStatus == .active && status.isActive
    }

    var isReadyForDispatch: Bool {
        lifecycleStatus == .active &&
        status == .scheduled &&
        scheduling.isValid &&
        crew.isValid
    }

    var validationIssues: [AssignmentValidationIssue] {
        var issues: [AssignmentValidationIssue] = []

        if assignmentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingAssignmentNumber)
        }

        if jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingJobNumber)
        }

        if customerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingCustomerNumber)
        }

        if !scheduling.isValid {
            issues.append(.invalidScheduling)
        }

        if !crew.isValid {
            issues.append(.invalidCrew)
        }

        return issues
    }

    var isValid: Bool {
        validationIssues.isEmpty
    }
}

enum AssignmentValidationIssue: String, Codable, Hashable {
    case missingAssignmentNumber = "The assignment number is required."
    case missingJobNumber = "The related job number is required."
    case missingCustomerNumber = "The related customer number is required."
    case invalidScheduling = "The assignment scheduling constraints are incomplete or invalid."
    case invalidCrew = "The assignment crew is incomplete or invalid."
}
