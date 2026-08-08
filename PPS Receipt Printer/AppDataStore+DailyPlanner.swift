//
//  AppDataStore+DailyPlanner.swift
//  PPS Receipt Printer
//
//  Phase 14.3 – Daily Planner integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
    /// Builds a non-mutating proposal for one technician and day using the
    /// current Assignment source of truth and Business Operations buffers.
    func dailyPlan(
        for technician: EmployeeRecord,
        on date: Date,
        calendar: Calendar = .current,
        transitionTravelMinutesOverride: Int? = nil,
        includingJobIDs: Set<UUID>? = nil
    ) -> DailyPlan {
        let planner = DailyPlannerEngine(
            configuration: DailyPlannerConfiguration(
                operations: businessProfile.operations,
                transitionTravelMinutesOverride: transitionTravelMinutesOverride
            ),
            calendar: calendar
        )

        let assignments = assignmentEngine.assignments.filter { assignment in
            guard let includingJobIDs else { return true }
            return includingJobIDs.contains(assignment.jobID)
        }

        return planner.plan(
            for: technician,
            on: date,
            assignments: assignments
        )
    }

    /// Produces synchronized proposals for every active technician. Stable
    /// name ordering keeps Operations UI and tests deterministic.
    func dailyPlans(
        on date: Date,
        calendar: Calendar = .current,
        transitionTravelMinutesOverride: Int? = nil
    ) -> [DailyPlan] {
        activeEmployees
            .filter { $0.hasRole(.technician) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
            .map {
                dailyPlan(
                    for: $0,
                    on: date,
                    calendar: calendar,
                    transitionTravelMinutesOverride: transitionTravelMinutesOverride
                )
            }
    }
}
