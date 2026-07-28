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
        let routePlans = Dictionary(
            uniqueKeysWithValues: board.technicianLanes.compactMap { lane in
                acceptedRoutePlan(
                    for: lane.id,
                    on: date,
                    calendar: calendar
                ).map { (lane.id, $0) }
            }
        )
        return OperationsTimelineEngine(calendar: calendar).snapshot(
            board: board,
            assignments: assignmentEngine.assignments,
            jobs: activeJobs,
            employees: activeEmployees,
            routePlansByTechnicianID: routePlans
        )
    }
}
