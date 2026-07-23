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
    /// current Assignment constraints and Business Operations buffers.
    ///
    /// Assignment synchronization already copies the Job's effective duration
    /// into the operational record whenever a Job is created or edited. The
    /// planner must therefore consume the Assignment unchanged. Re-reading the
    /// Job here created two competing duration sources: the Timeline displayed
    /// the Assignment duration while the planner silently evaluated a different
    /// Job duration, producing false arrival-window conflicts.
    func dailyPlan(
        for technician: EmployeeRecord,
        on date: Date,
        calendar: Calendar = .current
    ) -> DailyPlan {
        let planner = DailyPlannerEngine(
            configuration: DailyPlannerConfiguration(
                operations: businessProfile.operations
            ),
            calendar: calendar
        )

        return planner.plan(
            for: technician,
            on: date,
            assignments: assignmentEngine.assignments
        )
    }

    /// Produces synchronized proposals for every active technician. Stable
    /// name ordering keeps Operations UI and tests deterministic.
    func dailyPlans(
        on date: Date,
        calendar: Calendar = .current
    ) -> [DailyPlan] {
        activeEmployees
            .filter { $0.role == .technician }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
            .map {
                dailyPlan(
                    for: $0,
                    on: date,
                    calendar: calendar
                )
            }
    }

}
