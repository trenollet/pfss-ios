//
//  LiveMapEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.9 – Live Map View
//

import Foundation

/// Deterministically converts the synchronized Dispatch Board state into the
/// geographic lens used by the Live Map. It never mutates Assignments, Jobs,
/// routes, or employee records.
@MainActor
struct LiveMapEngine {
    let staleLocationInterval: TimeInterval

    init(staleLocationInterval: TimeInterval = 5 * 60) {
        self.staleLocationInterval = max(staleLocationInterval, 0)
    }

    func snapshot(
        board: DispatchBoardSnapshot,
        assignmentLocations: [RouteAssignmentLocation],
        technicianObservations: [LiveTechnicianLocationObservation],
        technicianColorNames: [UUID: String],
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> LiveMapSnapshot {
        let locationsByAssignment = assignmentLocations.reduce(
            into: [UUID: RouteAssignmentLocation]()
        ) { result, location in
            result[location.assignmentID] = location
        }
        let observationsByTechnician = technicianObservations.reduce(
            into: [UUID: LiveTechnicianLocationObservation]()
        ) { result, observation in
            // A caller may provide multiple device readings. Retain the most
            // recent instead of allowing duplicate identifiers to trap.
            let existing = result[observation.technicianID]
            if (observation.recordedAt ?? .distantPast)
                >= (existing?.recordedAt ?? .distantPast) {
                result[observation.technicianID] = observation
            }
        }

        let allItems = board.technicianLanes.flatMap(\.assignments)
            + board.unassignedItems
        let itemsByID = allItems.reduce(
            into: [UUID: DispatchBoardAssignmentItem]()
        ) { result, item in
            result[item.id] = item
        }

        let assignmentPins = allItems.compactMap { item -> LiveMapAssignmentPin? in
            guard let location = locationsByAssignment[item.id] else {
                return nil
            }
            return LiveMapAssignmentPin(
                id: item.id,
                jobID: item.jobID,
                customerName: item.customerName,
                siteName: item.siteName,
                siteAddress: location.displayAddress,
                serviceName: item.serviceName,
                status: item.status,
                priority: item.priority,
                schedulingMode: item.schedulingMode,
                coordinate: location.coordinate,
                routeSequence: item.routeSequence,
                primaryTechnicianID: item.primaryTechnicianID,
                plannedStart: item.plannedStart,
                plannedEnd: item.plannedEnd,
                estimatedArrival: item.estimatedArrival,
                isCurrent: item.isCurrent
            )
        }
        .sorted(by: stablePinOrder)

        let technicianPins = board.technicianLanes.map { lane in
            let rawObservation = observationsByTechnician[lane.id]
            let observation = normalizedObservation(
                rawObservation,
                generatedAt: generatedAt
            )
            let destinationID = lane.currentAssignmentID
                ?? lane.nextAssignmentID
            let destination = destinationID.flatMap { itemsByID[$0] }

            return LiveMapTechnicianPin(
                technicianID: lane.id,
                technicianName: lane.technicianName,
                technicianColorName: technicianColorNames[lane.id] ?? "blue",
                operationalState: lane.technicianState,
                locationState: observation?.state ?? .notReported,
                coordinate: observation?.coordinate,
                recordedAt: observation?.recordedAt,
                currentAssignmentID: lane.currentAssignmentID,
                nextAssignmentID: lane.nextAssignmentID,
                destinationAssignmentID: destinationID,
                destinationName: destination?.customerName,
                estimatedArrival: destination?.estimatedArrival
                    ?? destination?.plannedStart
            )
        }
        .sorted { (first: LiveMapTechnicianPin, second: LiveMapTechnicianPin) in
            first.technicianName.localizedCaseInsensitiveCompare(
                second.technicianName
            ) == .orderedAscending
        }

        let routeSegments = board.technicianLanes.flatMap { lane in
            segments(
                for: lane,
                technicianCoordinate: technicianPins.first {
                    $0.technicianID == lane.id
                }?.coordinate,
                locationsByAssignment: locationsByAssignment
            )
        }

        var alerts = allItems.compactMap { item -> LiveMapAlert? in
            guard locationsByAssignment[item.id] == nil else { return nil }
            return LiveMapAlert(
                id: "missing-assignment-\(item.id.uuidString)",
                kind: .missingAssignmentLocation,
                title: "\(item.customerName) · \(item.siteName)",
                message: "This Assignment has no resolved service location and cannot be placed on the map.",
                assignmentID: item.id,
                technicianID: item.primaryTechnicianID
            )
        }

        if calendar.isDate(board.date, inSameDayAs: generatedAt) {
            alerts.append(contentsOf: technicianPins.compactMap {
                technicianAlert(for: $0)
            })
        }

        return LiveMapSnapshot(
            date: board.date,
            generatedAt: generatedAt,
            technicianPins: technicianPins,
            assignmentPins: assignmentPins,
            routeSegments: routeSegments,
            alerts: alerts.sorted { $0.title < $1.title }
        )
    }

    private func normalizedObservation(
        _ observation: LiveTechnicianLocationObservation?,
        generatedAt: Date
    ) -> LiveTechnicianLocationObservation? {
        guard let observation else { return nil }
        guard observation.state == .live,
              observation.coordinate?.isValid == true,
              let recordedAt = observation.recordedAt else {
            return observation
        }

        guard generatedAt.timeIntervalSince(recordedAt)
                > staleLocationInterval else {
            return observation
        }

        return LiveTechnicianLocationObservation(
            technicianID: observation.technicianID,
            coordinate: observation.coordinate,
            recordedAt: recordedAt,
            horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
            state: .stale
        )
    }

    private func segments(
        for lane: DispatchBoardTechnicianLane,
        technicianCoordinate: RouteCoordinate?,
        locationsByAssignment: [UUID: RouteAssignmentLocation]
    ) -> [LiveMapRouteSegment] {
        let ordered = lane.assignments
            .filter { locationsByAssignment[$0.id] != nil }
            .sorted(by: stableBoardItemOrder)

        var previous = technicianCoordinate
        var result: [LiveMapRouteSegment] = []

        for (index, item) in ordered.enumerated() {
            guard let destination = locationsByAssignment[item.id]?.coordinate
            else { continue }

            if let start = previous {
                result.append(
                    LiveMapRouteSegment(
                        id: "\(lane.id.uuidString)-\(index)-\(item.id.uuidString)",
                        technicianID: lane.id,
                        sequence: index + 1,
                        start: start,
                        end: destination,
                        destinationAssignmentID: item.id
                    )
                )
            }
            previous = destination
        }
        return result
    }

    private func technicianAlert(
        for pin: LiveMapTechnicianPin
    ) -> LiveMapAlert? {
        let kind: LiveMapAlertKind
        let message: String

        switch pin.locationState {
        case .live:
            return nil
        case .stale:
            kind = .staleTechnicianLocation
            message = "The last device location is older than five minutes."
        case .notReported:
            kind = .technicianNotReporting
            message = "No device is currently reporting a location for this technician."
        case .permissionDenied, .restricted, .servicesDisabled, .unavailable:
            kind = .technicianLocationUnavailable
            message = "Location is unavailable: \(pin.locationState.rawValue)."
        }

        return LiveMapAlert(
            id: "technician-\(pin.technicianID.uuidString)-\(pin.locationState.rawValue)",
            kind: kind,
            title: pin.technicianName,
            message: message,
            assignmentID: pin.destinationAssignmentID,
            technicianID: pin.technicianID
        )
    }

    private func stableBoardItemOrder(
        _ first: DispatchBoardAssignmentItem,
        _ second: DispatchBoardAssignmentItem
    ) -> Bool {
        let firstSequence = first.routeSequence ?? Int.max
        let secondSequence = second.routeSequence ?? Int.max
        if firstSequence != secondSequence {
            return firstSequence < secondSequence
        }

        let firstStart = first.plannedStart ?? .distantFuture
        let secondStart = second.plannedStart ?? .distantFuture
        if firstStart != secondStart { return firstStart < secondStart }
        return first.id.uuidString < second.id.uuidString
    }

    private func stablePinOrder(
        _ first: LiveMapAssignmentPin,
        _ second: LiveMapAssignmentPin
    ) -> Bool {
        let firstSequence = first.routeSequence ?? Int.max
        let secondSequence = second.routeSequence ?? Int.max
        if firstSequence != secondSequence {
            return firstSequence < secondSequence
        }
        let firstStart = first.plannedStart ?? .distantFuture
        let secondStart = second.plannedStart ?? .distantFuture
        if firstStart != secondStart { return firstStart < secondStart }
        return first.id.uuidString < second.id.uuidString
    }
}
