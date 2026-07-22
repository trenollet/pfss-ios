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
    /// current Assignment constraints, the Job's effective scheduled duration,
    /// and Business Operations buffers.
    ///
    /// My Day and the Scheduling Engine already treat a positive
    /// `scheduledDurationOverrideMinutes` value as authoritative. Assignment
    /// records can predate a later Job edit, so the planning snapshot refreshes
    /// only `estimatedDurationMinutes` from that shared calculation. The stored
    /// Assignment is never changed by generating a preview.
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
            assignments: dailyPlannerAssignmentSnapshot()
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

    /// Returns temporary Assignment copies with durations resolved from the
    /// related Job. All other Assignment-owned operational constraints remain
    /// unchanged, including scheduling mode, windows, deadlines, buffers,
    /// crew, priority, lifecycle state, and history.
    private func dailyPlannerAssignmentSnapshot() -> [Assignment] {
        let jobsByID = Dictionary(
            uniqueKeysWithValues: activeJobs.map { ($0.id, $0) }
        )

        return assignmentEngine.assignments.map { storedAssignment in
            guard let job = jobsByID[storedAssignment.jobID] else {
                return storedAssignment
            }

            let effectiveScheduledMinutes = max(
                SchedulingEngine.scheduledMinutes(for: job),
                15
            )

            guard storedAssignment.scheduling.estimatedDurationMinutes !=
                    effectiveScheduledMinutes else {
                return storedAssignment
            }

            var planningAssignment = storedAssignment
            planningAssignment.scheduling.estimatedDurationMinutes =
                effectiveScheduledMinutes
            return planningAssignment
        }
    }
}
