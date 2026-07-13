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
}
