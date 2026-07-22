//
//  AppDataStore+WorkforceIntelligence.swift
//  PPS Receipt Printer
//
//  Phase 14.5 — Workforce Intelligence integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
    func workforceSnapshot(
        for employee: EmployeeRecord,
        on date: Date
    ) -> WorkforceTechnicianSnapshot {
        WorkforceIntelligenceEngine().snapshot(
            for: employee,
            on: date,
            assignments: assignmentStore.assignments
        )
    }

    func workforceSnapshot(
        for employee: EmployeeRecord,
        on date: Date,
        requirements: WorkforceCapabilityRequirements
    ) -> WorkforceTechnicianSnapshot {
        WorkforceIntelligenceEngine().snapshot(
            for: employee,
            on: date,
            assignments: assignmentStore.assignments,
            requirements: requirements
        )
    }

    func workforceSnapshots(
        on date: Date
    ) -> [WorkforceTechnicianSnapshot] {
        WorkforceIntelligenceEngine().snapshots(
            for: activeEmployees.filter { $0.role == .technician },
            on: date,
            assignments: assignmentStore.assignments
        )
    }

    func workforceSnapshots(
        on date: Date,
        requirements: WorkforceCapabilityRequirements
    ) -> [WorkforceTechnicianSnapshot] {
        WorkforceIntelligenceEngine().snapshots(
            for: activeEmployees.filter { $0.role == .technician },
            on: date,
            assignments: assignmentStore.assignments,
            requirements: requirements
        )
    }

    /// Refreshes the persisted historical snapshot from Assignment history.
    /// Assignments remain the source of truth.
    func refreshWorkforceHistoricalMetrics() {
        let intelligence = WorkforceIntelligenceEngine()
        let assignments = assignmentStore.assignments

        employees = employees.map { employee in
            var updated = employee
            updated.workforceProfile.historicalMetrics =
                intelligence.historicalMetrics(
                    for: employee,
                    assignments: assignments
                )
            return updated
        }
    }
}
