//
//  SchedulingCalculator.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/13/26.
//

import Foundation

struct SchedulingCalculator {
    static func estimatedMinutes(
        for lineItem: ServiceLineItem
    ) -> Int {
        let rawMinutes =
            Double(lineItem.estimatedMinutesPerUnit)
            * lineItem.quantity

        return max(
            Int(rawMinutes.rounded()),
            0
        )
    }

    static func estimatedMinutes(
        for lineItems: [ServiceLineItem]
    ) -> Int {
        lineItems.reduce(0) { total, item in
            total + estimatedMinutes(for: item)
        }
    }
    static func scheduledMinutes(
        for job: JobRecord
    ) -> Int {
        if let overrideMinutes =
            job.scheduledDurationOverrideMinutes,
           overrideMinutes > 0 {

            return overrideMinutes
        }

        return estimatedMinutes(
            for: job.lineItems
        )
    }

    static func formattedDuration(
        minutes: Int
    ) -> String {
        let safeMinutes = max(minutes, 0)

        guard safeMinutes > 0 else {
            return "Not Estimated"
        }

        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60

        switch (hours, remainingMinutes) {
        case (0, let minutes):
            return "\(minutes) min"

        case (let hours, 0):
            return hours == 1
                ? "1 hr"
                : "\(hours) hr"

        default:
            let hourText = hours == 1
                ? "1 hr"
                : "\(hours) hr"

            return "\(hourText) \(remainingMinutes) min"
        }
    }

    static func formattedDuration(
        for lineItems: [ServiceLineItem]
    ) -> String {
        formattedDuration(
            minutes: estimatedMinutes(
                for: lineItems
            )
        )
    }
    static func formattedScheduledDuration(
        for job: JobRecord
    ) -> String {
        formattedDuration(
            minutes: scheduledMinutes(for: job)
        )
    }
    static func isEmployee(
        _ employeeID: UUID,
        assignedTo job: JobRecord
    ) -> Bool {
        job.primaryTechnicianID == employeeID
            || job.secondaryTechnicianID == employeeID
    }

    static func scheduledJobs(
        for employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> [JobRecord] {
        jobs.filter { job in
            guard job.lifecycleStatus == .active else {
                return false
            }

            guard job.status != .cancelled else {
                return false
            }

            guard isEmployee(
                employee.id,
                assignedTo: job
            ) else {
                return false
            }

            return calendar.isDate(
                job.scheduledDate,
                inSameDayAs: date
            )
        }
    }

    static func scheduledMinutes(
        for employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        excludingJobID: UUID? = nil,
        calendar: Calendar = .current
    ) -> Int {
        scheduledJobs(
            for: employee,
            on: date,
            from: jobs,
            calendar: calendar
        )
        .filter { job in
            job.id != excludingJobID
        }
        .reduce(0) { total, job in
            total + scheduledMinutes(for: job)
        }
    }

    static func isWorkingDay(
        _ date: Date,
        for employee: EmployeeRecord,
        calendar: Calendar = .current
    ) -> Bool {
        let weekdayNumber = calendar.component(
            .weekday,
            from: date
        )

        guard let workday = Workday(
            rawValue: weekdayNumber
        ) else {
            return false
        }

        return employee.workingDays.contains(workday)
    }

    static func capacityMinutes(
        for employee: EmployeeRecord,
        on date: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard employee.isActive,
              employee.lifecycleStatus == .active,
              isWorkingDay(
                  date,
                  for: employee,
                  calendar: calendar
              ) else {
            return 0
        }

        return employee.dailyCapacityMinutes
    }

    static func remainingMinutes(
        for employee: EmployeeRecord,
        on date: Date,
        from jobs: [JobRecord],
        excludingJobID: UUID? = nil,
        calendar: Calendar = .current
    ) -> Int {
        let capacity = capacityMinutes(
            for: employee,
            on: date,
            calendar: calendar
        )

        let scheduled = scheduledMinutes(
            for: employee,
            on: date,
            from: jobs,
            excludingJobID: excludingJobID,
            calendar: calendar
        )

        return capacity - scheduled
    }

    static func projectedRemainingMinutes(
        afterAssigning job: JobRecord,
        to employee: EmployeeRecord,
        from jobs: [JobRecord],
        calendar: Calendar = .current
    ) -> Int {
        let remainingBeforeJob = remainingMinutes(
            for: employee,
            on: job.scheduledDate,
            from: jobs,
            excludingJobID: job.id,
            calendar: calendar
        )

        return remainingBeforeJob
            - scheduledMinutes(for: job)
    }
}
