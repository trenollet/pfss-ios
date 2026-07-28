//
//  AssignmentScheduling.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation

struct AssignmentScheduling: Codable, Hashable {
    var mode: AssignmentSchedulingMode

    /// Calendar day on which the work is intended to occur.
    ///
    /// Required for fixed-time, arrival-window, and flexible-day assignments.
    var serviceDate: Date?

    /// Exact planned start for a fixed-time assignment.
    var fixedStartDate: Date?

    /// Earliest and latest acceptable arrival times.
    var arrivalWindowStart: Date?
    var arrivalWindowEnd: Date?

    /// Latest acceptable completion time for a deadline assignment.
    var completionDeadline: Date?

    /// Expected hands-on work duration, excluding travel.
    var estimatedDurationMinutes: Int

    /// Operational buffers used by the Daily Planner and Route Engine.
    var preServiceBufferMinutes: Int
    var postServiceBufferMinutes: Int

    /// Indicates that the customer has acknowledged the current schedule.
    var isCustomerConfirmed: Bool

    /// Optional scheduling-specific instructions.
    var schedulingNotes: String

    init(
        mode: AssignmentSchedulingMode,
        serviceDate: Date? = nil,
        fixedStartDate: Date? = nil,
        arrivalWindowStart: Date? = nil,
        arrivalWindowEnd: Date? = nil,
        completionDeadline: Date? = nil,
        estimatedDurationMinutes: Int,
        preServiceBufferMinutes: Int = 0,
        postServiceBufferMinutes: Int = 0,
        isCustomerConfirmed: Bool = false,
        schedulingNotes: String = ""
    ) {
        self.mode = mode
        self.serviceDate = serviceDate
        self.fixedStartDate = fixedStartDate
        self.arrivalWindowStart = arrivalWindowStart
        self.arrivalWindowEnd = arrivalWindowEnd
        self.completionDeadline = completionDeadline
        self.estimatedDurationMinutes = max(estimatedDurationMinutes, 0)
        self.preServiceBufferMinutes = max(preServiceBufferMinutes, 0)
        self.postServiceBufferMinutes = max(postServiceBufferMinutes, 0)
        self.isCustomerConfirmed = isCustomerConfirmed
        self.schedulingNotes = schedulingNotes
    }

    var totalPlannedMinutes: Int {
        estimatedDurationMinutes + preServiceBufferMinutes + postServiceBufferMinutes
    }

    var earliestPermittedStart: Date? {
        switch mode {
        case .fixedTime:
            return fixedStartDate
        case .arrivalWindow:
            return arrivalWindowStart
        case .flexibleDay:
            return serviceDate
        case .deadline:
            return nil
        }
    }

    var latestPermittedStart: Date? {
        switch mode {
        case .fixedTime:
            return fixedStartDate
        case .arrivalWindow:
            return arrivalWindowEnd
        case .flexibleDay:
            return nil
        case .deadline:
            guard let completionDeadline else { return nil }
            return Calendar.current.date(
                byAdding: .minute,
                value: -totalPlannedMinutes,
                to: completionDeadline
            )
        }
    }

    var validationIssues: [AssignmentSchedulingValidationIssue] {
        var issues: [AssignmentSchedulingValidationIssue] = []

        if estimatedDurationMinutes <= 0 {
            issues.append(.missingEstimatedDuration)
        }

        switch mode {
        case .fixedTime:
            if fixedStartDate == nil {
                issues.append(.missingFixedStart)
            }

        case .arrivalWindow:
            guard let start = arrivalWindowStart,
                  let end = arrivalWindowEnd else {
                issues.append(.missingArrivalWindow)
                return issues
            }

            if end <= start {
                issues.append(.invalidArrivalWindow)
            }

        case .flexibleDay:
            if serviceDate == nil {
                issues.append(.missingServiceDate)
            }

        case .deadline:
            if completionDeadline == nil {
                issues.append(.missingDeadline)
            }
        }

        return issues
    }

    var isValid: Bool {
        validationIssues.isEmpty
    }

    /// Best date for placing this Assignment on operational calendars until
    /// the Daily Planner produces a more specific planned start.
    var operationalDate: Date? {
        switch mode {
        case .fixedTime:
            return fixedStartDate ?? serviceDate
        case .arrivalWindow:
            return arrivalWindowStart ?? serviceDate
        case .flexibleDay:
            return serviceDate
        case .deadline:
            return latestPermittedStart ?? completionDeadline
        }
    }

    var displayDateText: String {
        guard let operationalDate else { return "Date not set" }
        return operationalDate.formatted(date: .abbreviated, time: .omitted)
    }

    var displayTimeText: String {
        switch mode {
        case .fixedTime:
            guard let date = fixedStartDate ?? serviceDate else {
                return "Time not set"
            }
            return date.formatted(date: .omitted, time: .shortened)

        case .arrivalWindow:
            guard let start = arrivalWindowStart,
                  let end = arrivalWindowEnd else {
                return "Window not set"
            }
            return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"

        case .flexibleDay:
            return "Flexible Day"

        case .deadline:
            guard let deadline = completionDeadline else {
                return "Deadline not set"
            }
            return "Due \(deadline.formatted(date: .omitted, time: .shortened))"
        }
    }
}

enum AssignmentSchedulingValidationIssue: String, Codable, Hashable {
    case missingEstimatedDuration = "Estimated duration must be greater than zero."
    case missingFixedStart = "A fixed-time assignment requires a start date and time."
    case missingArrivalWindow = "An arrival-window assignment requires both a start and end time."
    case invalidArrivalWindow = "The arrival-window end must be later than its start."
    case missingServiceDate = "A flexible-day assignment requires a service date."
    case missingDeadline = "A deadline assignment requires a completion deadline."
}
