//
//  AppDataStore+DispatchBoard.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Dispatch Board integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
    /// Creates the synchronized board state consumed by DispatchBoardView.
    /// The snapshot is derived from existing engines and never persisted.
    func dispatchBoardSnapshot(
        on date: Date,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> DispatchBoardSnapshot {
        DispatchBoardEngine(calendar: calendar).snapshot(
            on: date,
            generatedAt: generatedAt,
            employees: activeEmployees,
            assignments: assignmentEngine.activeAssignments,
            jobs: activeJobs,
            customers: customers,
            sites: sites,
            dailyPlans: dailyPlans(on: date, calendar: calendar)
        )
    }
}
