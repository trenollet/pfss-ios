//
//  AppDataStore+Timeline.swift
//  PPS Receipt Printer
//
//  Phase 14.8 – Timeline integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
    func operationsTimelineSnapshot(
        on date: Date,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> OperationsTimelineSnapshot {
        let board = dispatchBoardSnapshot(
            on: date,
            generatedAt: generatedAt,
            calendar: calendar
        )
        return OperationsTimelineEngine(calendar: calendar).snapshot(
            board: board,
            assignments: assignmentEngine.assignments,
            employees: activeEmployees
        )
    }
}
