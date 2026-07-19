//
//  SchedulingEngine.swift
//  PPS Receipt Printer
//
//  Brick 12 — Scheduling and dispatch integration
//  Authoritative business API for scheduling validation, availability,
//  future-opening discovery, technician agendas, and dispatch candidates.
//

import Foundation

// MARK: - Scheduling Results

enum SchedulingConflictKind: String, Codable, CaseIterable {
    case inactiveEmployee
    case nonWorkingDay
    case outsideWorkingHours
    case overlappingJob
    case overDailyCapacity
}

struct SchedulingConflict: Identifiable {
    let id = UUID()
    let kind: SchedulingConflictKind
    let message: String
    let employeeID: UUID
    let conflictingJobID: UUID?
}

struct SchedulingValidationResult {
    let employee: EmployeeRecord
    let job: JobRecord
    let proposedStart: Date
    let proposedEnd: Date
    let conflicts: [SchedulingConflict]

    var isValid: Bool {
        conflicts.isEmpty
    }
}

struct SchedulingAvailabilityResult {
    let employee: EmployeeRecord
    let date: Date
    let capacitySummary: EmployeeCapacitySummary
    let conflicts: [SchedulingConflict]

    var isAvailable: Bool {
        conflicts.isEmpty
    }
}

struct AvailableOpening: Identifiable {
    let id = UUID()
    let employee: EmployeeRecord
    let start: Date
    let end: Date

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }

    /// Retained for compatibility. This indicates that the opening duration
    /// consumes the employee's configured daily capacity exactly.
    var isExactFit: Bool {
        employee.dailyCapacityMinutes == durationMinutes
    }
}

struct AvailableEmployee: Identifiable {
    let id = UUID()
    let employee: EmployeeRecord
    let capacitySummary: EmployeeCapacitySummary
    let conflicts: [SchedulingConflict]
    let earliestAvailableOpening: AvailableOpening?

    var isAvailable: Bool {
        conflicts.isEmpty && earliestAvailableOpening != nil
    }

    var remainingMinutes: Int {
        capacitySummary.remainingMinutes
    }

    /// Baseline scheduling score. DispatchDecisionEngine applies the selected
    /// decision policy and produces the final explainable ranking.
    var recommendationScore: Double {
        guard isAvailable else { return 0 }

        let availableCapacityBonus = min(
            Double(max(remainingMinutes, 0)) / 30.0,
            20.0
        )

        let utilizationBonus = max(
            0,
            10.0 - capacitySummary.utilizationFraction * 10.0
        )

        return 100.0 + availableCapacityBonus + utilizationBonus
    }
}

struct SchedulingTimeSlot: Identifiable {
    let id = UUID()
    let employee: EmployeeRecord
    let start: Date
    let end: Date

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }
}

struct TechnicianAgenda {
    let employee: EmployeeRecord
    let date: Date
    let jobs: [JobRecord]
    let capacitySummary: EmployeeCapacitySummary
    let conflicts: [SchedulingConflict]

    var scheduledMinutes: Int { capacitySummary.scheduledMinutes }
    var remainingMinutes: Int { capacitySummary.remainingMinutes }
    var utilization: Double { capacitySummary.utilizationFraction }
    var utilizationPercentage: Int { capacitySummary.utilizationPercentage }
    var isWorkingDay: Bool { capacitySummary.isWorkingDay }
    var jobCount: Int { jobs.count }
    var hasConflicts: Bool { !conflicts.isEmpty }
    var isFullyBooked: Bool { remainingMinutes <= 0 }
    var isOverCapacity: Bool { remainingMinutes < 0 }
}

// MARK: - Scheduling Engine

struct SchedulingEngine {

    private static let defaultSlotIntervalMinutes = 15
    private static let defaultFutureSearchDays = 30

    // MARK: Technician Agenda

    static func dailyAgenda(
        for employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> TechnicianAgenda {
        let scheduledJobs = SchedulingCalculator
            .scheduledJobs(
                for: employee,
                on: date,
                from: jobs,
                calendar: calendar
            )
            .sorted { first, second in
                if first.scheduledDate != second.scheduledDate {
                    return first.scheduledDate < second.scheduledDate
                }
                return first.id.uuidString < second.id.uuidString
            }

        let summary = capacitySummary(
            for: employee,
            on: date,
            from: jobs,
            calendar: calendar
        )

        let allConflicts = scheduledJobs.flatMap { job in
            conflicts(
                for: job,
                assigning: employee,
                at: job.scheduledDate,
                from: jobs,
                calendar: calendar
            )
        }

        return TechnicianAgenda(
            employee: employee,
            date: date,
            jobs: scheduledJobs,
            capacitySummary: summary,
            conflicts: allConflicts
        )
    }

    // MARK: Duration and Capacity Facade

    static func estimatedMinutes(for lineItem: ServiceLineItem) -> Int {
        SchedulingCalculator.estimatedMinutes(for: lineItem)
    }

    static func estimatedMinutes(for lineItems: [ServiceLineItem]) -> Int {
        SchedulingCalculator.estimatedMinutes(for: lineItems)
    }

    static func scheduledMinutes(for job: JobRecord) -> Int {
        SchedulingCalculator.scheduledMinutes(for: job)
    }

    static func capacitySummary(
        for employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> EmployeeCapacitySummary {
        SchedulingCalculator.capacitySummary(
            for: employee,
            on: date,
            from: jobs,
            calendar: calendar
        )
    }

    // MARK: Validation

    static func conflicts(
        for job: JobRecord,
        assigning employee: EmployeeRecord,
        at proposedStart: Date? = nil,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> [SchedulingConflict] {
        let start = proposedStart ?? job.scheduledDate
        let duration = scheduledMinutes(for: job)
        let end = calendar.date(
            byAdding: .minute,
            value: duration,
            to: start
        ) ?? start

        guard isActive(employee) else {
            return [
                SchedulingConflict(
                    kind: .inactiveEmployee,
                    message: "Employee is inactive.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            ]
        }

        var results: [SchedulingConflict] = []

        if !SchedulingCalculator.isWorkingDay(
            start,
            for: employee,
            calendar: calendar
        ) {
            results.append(
                SchedulingConflict(
                    kind: .nonWorkingDay,
                    message: "Employee is not scheduled to work on this day.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            )
        }

        if !isWithinWorkingHours(
            start: start,
            end: end,
            employee: employee,
            calendar: calendar
        ) {
            results.append(
                SchedulingConflict(
                    kind: .outsideWorkingHours,
                    message: "Job falls outside the employee's working hours.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            )
        }

        let assignedJobs = SchedulingCalculator
            .scheduledJobs(
                for: employee,
                on: start,
                from: jobs,
                calendar: calendar
            )
            .filter { $0.id != job.id }

        for existingJob in assignedJobs {
            let existingStart = existingJob.scheduledDate
            let existingEnd = calendar.date(
                byAdding: .minute,
                value: scheduledMinutes(for: existingJob),
                to: existingStart
            ) ?? existingStart

            if intervalsOverlap(start, end, existingStart, existingEnd) {
                results.append(
                    SchedulingConflict(
                        kind: .overlappingJob,
                        message: "Job overlaps an existing assignment.",
                        employeeID: employee.id,
                        conflictingJobID: existingJob.id
                    )
                )
            }
        }

        let projectedRemaining = SchedulingCalculator.remainingMinutes(
            for: employee,
            on: start,
            from: jobs,
            excludingJobID: job.id,
            calendar: calendar
        ) - duration

        if projectedRemaining < 0 {
            results.append(
                SchedulingConflict(
                    kind: .overDailyCapacity,
                    message: "Assignment exceeds the employee's daily capacity.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            )
        }

        return results
    }

    static func validate(
        job: JobRecord,
        assigning employee: EmployeeRecord,
        at proposedStart: Date? = nil,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> SchedulingValidationResult {
        let start = proposedStart ?? job.scheduledDate
        let end = calendar.date(
            byAdding: .minute,
            value: scheduledMinutes(for: job),
            to: start
        ) ?? start

        return SchedulingValidationResult(
            employee: employee,
            job: job,
            proposedStart: start,
            proposedEnd: end,
            conflicts: conflicts(
                for: job,
                assigning: employee,
                at: start,
                from: jobs,
                calendar: calendar
            )
        )
    }

    // MARK: Point-in-Time Availability

    static func availableEmployees(
        for job: JobRecord,
        at proposedStart: Date? = nil,
        employees: [EmployeeRecord],
        jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> [SchedulingAvailabilityResult] {
        let start = proposedStart ?? job.scheduledDate

        return employees
            .filter { employee in
            employee.isActive && employee.lifecycleStatus == .active
        }
            .map { employee in
                SchedulingAvailabilityResult(
                    employee: employee,
                    date: start,
                    capacitySummary: capacitySummary(
                        for: employee,
                        on: start,
                        from: jobs,
                        calendar: calendar
                    ),
                    conflicts: conflicts(
                        for: job,
                        assigning: employee,
                        at: start,
                        from: jobs,
                        calendar: calendar
                    )
                )
            }
            .sorted { first, second in
                if first.isAvailable != second.isAvailable {
                    return first.isAvailable
                }

                if first.capacitySummary.remainingMinutes != second.capacitySummary.remainingMinutes {
                    return first.capacitySummary.remainingMinutes > second.capacitySummary.remainingMinutes
                }

                return compareEmployeeNames(
                    first.employee,
                    second.employee
                )
            }
    }

    // MARK: Time Slots

    static func candidateTimeSlots(
        for job: JobRecord,
        employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        intervalMinutes: Int = defaultSlotIntervalMinutes,
        calendar: Calendar = .current
    ) -> [SchedulingTimeSlot] {
        let duration = scheduledMinutes(for: job)
        let safeInterval = max(intervalMinutes, 1)

        guard duration > 0,
              isActive(employee),
              SchedulingCalculator.isWorkingDay(
                  date,
                  for: employee,
                  calendar: calendar
              ),
              let workStart = dateAtMinutesAfterMidnight(
                  employee.defaultStartMinutes,
                  on: date,
                  calendar: calendar
              ),
              let workEnd = dateAtMinutesAfterMidnight(
                  employee.defaultEndMinutes,
                  on: date,
                  calendar: calendar
              ),
              workStart < workEnd else {
            return []
        }

        var slots: [SchedulingTimeSlot] = []
        var candidateStart = workStart

        while let candidateEnd = calendar.date(
            byAdding: .minute,
            value: duration,
            to: candidateStart
        ), candidateEnd <= workEnd {
            let validation = validate(
                job: job,
                assigning: employee,
                at: candidateStart,
                from: jobs,
                calendar: calendar
            )

            if validation.isValid {
                slots.append(
                    SchedulingTimeSlot(
                        employee: employee,
                        start: candidateStart,
                        end: candidateEnd
                    )
                )
            }

            guard let nextStart = calendar.date(
                byAdding: .minute,
                value: safeInterval,
                to: candidateStart
            ) else {
                break
            }

            candidateStart = nextStart
        }

        return slots
    }

    // MARK: Opening Discovery

    static func availableOpenings(
        for job: JobRecord,
        employees: [EmployeeRecord],
        on date: Date? = nil,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> [AvailableOpening] {
        let targetDate = date ?? job.scheduledDate

        return employees
            .filter { employee in
            employee.isActive && employee.lifecycleStatus == .active
        }
            .flatMap { employee in
                candidateTimeSlots(
                    for: job,
                    employee: employee,
                    on: targetDate,
                    from: jobs,
                    calendar: calendar
                )
                .map { slot in
                    AvailableOpening(
                        employee: employee,
                        start: slot.start,
                        end: slot.end
                    )
                }
            }
            .sorted { first, second in
            if first.start != second.start {
                return first.start < second.start
            }
            if first.end != second.end {
                return first.end < second.end
            }
            return compareEmployeeNames(first.employee, second.employee)
        }
    }

    /// Returns the first valid opening on or after the supplied date.
    /// Unlike the earlier implementation, this method searches future working
    /// days instead of stopping after the first calendar day.
    static func nextAvailableOpening(
        for job: JobRecord,
        employee: EmployeeRecord,
        onOrAfter date: Date? = nil,
        from jobs: [JobRecord],
        searchDays: Int = defaultFutureSearchDays,
        intervalMinutes: Int = defaultSlotIntervalMinutes,
        calendar: Calendar = .current
    ) -> AvailableOpening? {
        guard isActive(employee) else { return nil }

        let requestedStart = date ?? job.scheduledDate
        let safeSearchDays = max(searchDays, 1)

        for dayOffset in 0..<safeSearchDays {
            guard let searchDate = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: requestedStart
            ) else {
                continue
            }

            let slots = candidateTimeSlots(
                for: job,
                employee: employee,
                on: searchDate,
                from: jobs,
                intervalMinutes: intervalMinutes,
                calendar: calendar
            )

            let eligibleSlots: [SchedulingTimeSlot]

            if dayOffset == 0 {
                eligibleSlots = slots.filter { $0.start >= requestedStart }
            } else {
                eligibleSlots = slots
            }

            guard let firstSlot = eligibleSlots.first else {
                continue
            }

            return AvailableOpening(
                employee: employee,
                start: firstSlot.start,
                end: firstSlot.end
            )
        }

        return nil
    }

    /// Produces the scheduling candidates consumed by DispatchDecisionEngine.
    /// Conflict and capacity data are evaluated at each employee's discovered
    /// opening, so a technician is not incorrectly rejected merely because the
    /// originally requested time was unavailable.
    static func availableEmployeeRecommendations(
        for job: JobRecord,
        employees: [EmployeeRecord],
        onOrAfter date: Date? = nil,
        from jobs: [JobRecord],
        searchDays: Int = defaultFutureSearchDays,
        intervalMinutes: Int = defaultSlotIntervalMinutes,
        calendar: Calendar = .current
    ) -> [AvailableEmployee] {
        let requestedStart = date ?? job.scheduledDate

        return employees
            .filter { employee in
            employee.isActive && employee.lifecycleStatus == .active
        }
            .map { employee in
                let opening = nextAvailableOpening(
                    for: job,
                    employee: employee,
                    onOrAfter: requestedStart,
                    from: jobs,
                    searchDays: searchDays,
                    intervalMinutes: intervalMinutes,
                    calendar: calendar
                )

                let evaluationDate = opening?.start ?? requestedStart
                let openingConflicts: [SchedulingConflict]

                if let opening {
                    openingConflicts = conflicts(
                        for: job,
                        assigning: employee,
                        at: opening.start,
                        from: jobs,
                        calendar: calendar
                    )
                } else {
                    openingConflicts = availabilityFailureConflicts(
                        for: job,
                        employee: employee,
                        requestedStart: requestedStart,
                        from: jobs,
                        calendar: calendar
                    )
                }

                return AvailableEmployee(
                    employee: employee,
                    capacitySummary: capacitySummary(
                        for: employee,
                        on: evaluationDate,
                        from: jobs,
                        calendar: calendar
                    ),
                    conflicts: openingConflicts,
                    earliestAvailableOpening: opening
                )
            }
            .sorted { first, second in
                if first.isAvailable != second.isAvailable {
                    return first.isAvailable
                }

                let firstStart = first.earliestAvailableOpening?.start
                let secondStart = second.earliestAvailableOpening?.start

                switch (firstStart, secondStart) {
                case let (.some(lhs), .some(rhs)) where lhs != rhs:
                    return lhs < rhs
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }

                if first.recommendationScore != second.recommendationScore {
                    return first.recommendationScore > second.recommendationScore
                }

                return compareEmployeeNames(
                    first.employee,
                    second.employee
                )
            }
    }

    // MARK: Private Helpers

    private static func isActive(_ employee: EmployeeRecord) -> Bool {
        employee.isActive && employee.lifecycleStatus == .active
    }

    private static func availabilityFailureConflicts(
        for job: JobRecord,
        employee: EmployeeRecord,
        requestedStart: Date,
        from jobs: [JobRecord],
        calendar: Calendar
    ) -> [SchedulingConflict] {
        let directConflicts = conflicts(
            for: job,
            assigning: employee,
            at: requestedStart,
            from: jobs,
            calendar: calendar
        )

        if !directConflicts.isEmpty {
            return directConflicts
        }

        return [
            SchedulingConflict(
                kind: .overDailyCapacity,
                message: "No valid opening was found within the scheduling search window.",
                employeeID: employee.id,
                conflictingJobID: nil
            )
        ]
    }

    private static func openingComesBefore(
        _ first: AvailableOpening,
        _ second: AvailableOpening
    ) -> Bool {
        if first.start != second.start {
            return first.start < second.start
        }

        if first.end != second.end {
            return first.end < second.end
        }

        return compareEmployeeNames(first.employee, second.employee)
    }

    private static func compareEmployeeNames(
        _ first: EmployeeRecord,
        _ second: EmployeeRecord
    ) -> Bool {
        first.displayName.localizedCaseInsensitiveCompare(second.displayName)
            == .orderedAscending
    }

    private static func intervalsOverlap(
        _ firstStart: Date,
        _ firstEnd: Date,
        _ secondStart: Date,
        _ secondEnd: Date
    ) -> Bool {
        firstStart < secondEnd && secondStart < firstEnd
    }

    private static func isWithinWorkingHours(
        start: Date,
        end: Date,
        employee: EmployeeRecord,
        calendar: Calendar
    ) -> Bool {
        guard let workStart = dateAtMinutesAfterMidnight(
            employee.defaultStartMinutes,
            on: start,
            calendar: calendar
        ),
        let workEnd = dateAtMinutesAfterMidnight(
            employee.defaultEndMinutes,
            on: start,
            calendar: calendar
        ) else {
            return false
        }

        return start >= workStart && end <= workEnd
    }

    private static func dateAtMinutesAfterMidnight(
        _ minutes: Int,
        on date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            byAdding: .minute,
            value: max(minutes, 0),
            to: calendar.startOfDay(for: date)
        )
    }
}
