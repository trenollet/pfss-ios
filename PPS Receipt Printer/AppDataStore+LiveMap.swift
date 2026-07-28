//
//  AppDataStore+LiveMap.swift
//  PPS Receipt Printer
//
//  Phase 14.9 – Live Map integration boundary
//

import Foundation

@MainActor
extension AppDataStore {
    /// Builds the geographic lens from the same Dispatch Board state used by
    /// Operations. Generating or refreshing the map never changes records.
    func liveMapSnapshot(
        on date: Date,
        technicianObservations: [LiveTechnicianLocationObservation] = [],
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) async -> LiveMapSnapshot {
        let board = dispatchBoardSnapshot(
            on: date,
            generatedAt: generatedAt,
            calendar: calendar
        )

        let relevantIDs = Set(
            board.technicianLanes
                .flatMap(\.assignments)
                .map(\.id)
                + board.unassignedItems.map(\.id)
        )
        let relevantAssignments = assignmentEngine.assignments.filter {
            relevantIDs.contains($0.id)
        }
        let locations = await RouteLocationResolver().resolveLocations(
            for: relevantAssignments,
            sites: sites
        )
        let colorNames = activeEmployees.reduce(into: [UUID: String]()) {
            result, employee in
            result[employee.id] = employee.colorName
        }

        return LiveMapEngine().snapshot(
            board: board,
            assignmentLocations: locations,
            technicianObservations: technicianObservations,
            technicianColorNames: colorNames,
            generatedAt: generatedAt,
            calendar: calendar
        )
    }
}
