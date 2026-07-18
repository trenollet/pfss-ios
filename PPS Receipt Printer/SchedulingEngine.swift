//
//  SchedulingEngine.swift
//  PPS Receipt Printer
//
//  Brick 11 — Authoritative scheduling business engine.
//

import Foundation

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

struct SchedulingTimeSlot: Identifiable {
    let id = UUID()
    let employee: EmployeeRecord
    let start: Date
    let end: Date

    var durationMinutes: Int {
        max(
            Int(end.timeIntervalSince(start) / 60),
            0
        )
    }
}

struct TechnicianAgenda {
    let employee: EmployeeRecord
    let date: Date

    let jobs: [JobRecord]

    let capacitySummary: EmployeeCapacitySummary

    let conflicts: [SchedulingConflict]

    var scheduledMinutes: Int {
        capacitySummary.scheduledMinutes
    }

    var remainingMinutes: Int {
        capacitySummary.remainingMinutes
    }

    var utilization: Double {
        capacitySummary.utilization
    }

    var jobCount: Int {
        jobs.count
    }

    var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    var isFullyBooked: Bool {
        remainingMinutes <= 0
    }

    var isOverCapacity: Bool {
        remainingMinutes < 0
    }
}

struct SchedulingEngine {
    
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
            .sorted {
                $0.scheduledDate < $1.scheduledDate
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
    
    static func estimatedMinutes(
        for lineItem: ServiceLineItem
    ) -> Int {
        SchedulingCalculator.estimatedMinutes(
            for: lineItem
        )
    }

    static func estimatedMinutes(
        for lineItems: [ServiceLineItem]
    ) -> Int {
        SchedulingCalculator.estimatedMinutes(
            for: lineItems
        )
    }

    static func scheduledMinutes(
        for job: JobRecord
    ) -> Int {
        SchedulingCalculator.scheduledMinutes(
            for: job
        )
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

        var conflicts: [SchedulingConflict] = []

        guard employee.isActive,
              employee.lifecycleStatus == .active else {
            conflicts.append(
                SchedulingConflict(
                    kind: .inactiveEmployee,
                    message: "Employee is inactive.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            )

            return conflicts
        }

        if !SchedulingCalculator.isWorkingDay(
            start,
            for: employee,
            calendar: calendar
        ) {
            conflicts.append(
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
            conflicts.append(
                SchedulingConflict(
                    kind: .outsideWorkingHours,
                    message: "Job falls outside the employee's working hours.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            )
        }

        let assignedJobs = SchedulingCalculator.scheduledJobs(
            for: employee,
            on: start,
            from: jobs,
            calendar: calendar
        )
        .filter { existingJob in
            existingJob.id != job.id
        }

        for existingJob in assignedJobs {
            let existingStart = existingJob.scheduledDate
            let existingEnd = calendar.date(
                byAdding: .minute,
                value: scheduledMinutes(for: existingJob),
                to: existingStart
            ) ?? existingStart

            if intervalsOverlap(
                start,
                end,
                existingStart,
                existingEnd
            ) {
                conflicts.append(
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
            conflicts.append(
                SchedulingConflict(
                    kind: .overDailyCapacity,
                    message: "Assignment exceeds the employee's daily capacity.",
                    employeeID: employee.id,
                    conflictingJobID: nil
                )
            )
        }

        return conflicts
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

    static func availableEmployees(
        for job: JobRecord,
        at proposedStart: Date? = nil,
        employees: [EmployeeRecord],
        jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> [SchedulingAvailabilityResult] {
        employees
            .filter { employee in
                employee.isActive
                    && employee.lifecycleStatus == .active
            }
            .map { employee in
                let start = proposedStart ?? job.scheduledDate

                return SchedulingAvailabilityResult(
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

                if first.capacitySummary.remainingMinutes
                    != second.capacitySummary.remainingMinutes {
                    return first.capacitySummary.remainingMinutes
                        > second.capacitySummary.remainingMinutes
                }

                return first.employee.displayName
                    .localizedCaseInsensitiveCompare(
                        second.employee.displayName
                    ) == .orderedAscending
            }
    }

    static func candidateTimeSlots(
        for job: JobRecord,
        employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        intervalMinutes: Int = 15,
        calendar: Calendar = .current
    ) -> [SchedulingTimeSlot] {
        let duration = scheduledMinutes(for: job)
        let safeInterval = max(intervalMinutes, 1)

        guard duration > 0,
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
              ) else {
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

    private static func intervalsOverlap(
        _ firstStart: Date,
        _ firstEnd: Date,
        _ secondStart: Date,
        _ secondEnd: Date
    ) -> Bool {
        firstStart < secondEnd
            && secondStart < firstEnd
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

        return start >= workStart
            && end <= workEnd
    }

    private static func dateAtMinutesAfterMidnight(
        _ minutes: Int,
        on date: Date,
        calendar: Calendar
    ) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)

        return calendar.date(
            byAdding: .minute,
            value: max(minutes, 0),
            to: startOfDay
        )
    }
}
