//
//  MileageDetectionEngine.swift
//  PPS Receipt Printer
//
//  Phase 19 – Battery-neutral, UI-independent trip detection rules.
//

import Foundation

struct MileageDetectionEngine: Codable {
    private(set) var state: MileageTrackingState = .idle
    private(set) var rejectedPointCount = 0

    let context: MileageTrackingContext
    var configuration: MileageDetectionConfiguration

    private var anchor: MileageTripPoint?
    private var startCandidates: [MileageTripPoint] = []
    private var activeTripID: UUID?
    private var activeRoute: [MileageTripPoint] = []
    private var stoppingBeganAt: Date?
    private var lastMovementPoint: MileageTripPoint?
    private var lastDrivingPoint: MileageTripPoint?
    private var lastObservedTimestamp: Date?

    init(
        context: MileageTrackingContext,
        configuration: MileageDetectionConfiguration = .init()
    ) {
        self.context = context
        self.configuration = configuration
    }

    mutating func process(
        _ point: MileageTripPoint
    ) -> [MileageDetectionEvent] {
        guard isValid(point) else {
            rejectedPointCount += 1
            return []
        }

        lastObservedTimestamp = point.timestamp

        switch state {
        case .idle, .arming:
            return processPotentialStart(point)
        case .tracking, .stopping:
            return processActiveTrip(point)
        }
    }

    mutating func cancelActiveTrip() {
        reset(anchor: activeRoute.last ?? anchor)
    }

    private mutating func processPotentialStart(
        _ point: MileageTripPoint
    ) -> [MileageDetectionEvent] {
        guard let anchor else {
            self.anchor = point
            return []
        }

        let displacedEnough = anchor.distance(to: point) >=
            configuration.startDisplacementMeters
        let movingFastEnough = point.speedMetersPerSecond >=
            configuration.startSpeedMetersPerSecond

        guard displacedEnough && movingFastEnough else {
            startCandidates.removeAll(keepingCapacity: true)
            if point.speedMetersPerSecond <
                configuration.stopSpeedMetersPerSecond {
                self.anchor = point
            }
            return changeState(to: .idle)
        }

        startCandidates.append(point)
        var events = changeState(to: .arming)

        guard startCandidates.count >=
            configuration.requiredConsecutiveStartSamples else {
            return events
        }

        let tripID = UUID()
        activeTripID = tripID
        activeRoute = [anchor] + startCandidates
        lastMovementPoint = activeRoute.last
        lastDrivingPoint = activeRoute.last
        stoppingBeganAt = nil
        startCandidates.removeAll(keepingCapacity: true)

        events.append(contentsOf: changeState(to: .tracking))
        events.append(
            .tripStarted(
                id: tripID,
                at: activeRoute.first?.timestamp ?? point.timestamp
            )
        )
        return events
    }

    private mutating func processActiveTrip(
        _ point: MileageTripPoint
    ) -> [MileageDetectionEvent] {
        var events: [MileageDetectionEvent] = []
        appendToRouteIfPlausible(point)

        let isDriving = point.speedMetersPerSecond >=
            configuration.startSpeedMetersPerSecond

        if isDriving {
            lastMovementPoint = point
            lastDrivingPoint = point
            stoppingBeganAt = nil
            events.append(contentsOf: changeState(to: .tracking))
            return events
        }

        if stoppingBeganAt == nil {
            stoppingBeganAt = point.timestamp
            events.append(contentsOf: changeState(to: .stopping))
            return events
        }

        guard let stoppingBeganAt,
              point.timestamp.timeIntervalSince(stoppingBeganAt) >=
                configuration.stopDwellDuration else {
            return events
        }

        guard let tripID = activeTripID,
              let firstPoint = activeRoute.first,
              let endingPoint = lastDrivingPoint ?? lastMovementPoint ?? activeRoute.last else {
            let events = changeState(to: .idle)
            reset(anchor: point)
            return events
        }

        let completedRoute = routeEnding(at: endingPoint)
        let completedDistanceMeters = routeDistance(completedRoute)

        let averageAccuracy = completedRoute.isEmpty
            ? 0
            : completedRoute.reduce(0) {
                $0 + $1.horizontalAccuracyMeters
            } / Double(completedRoute.count)
        let trip = MileageTrip(
            id: tripID,
            accountID: context.accountID,
            userID: context.userID,
            originatingDeviceID: context.deviceID,
            entrySource: .automatic,
            startedAt: firstPoint.timestamp,
            endedAt: endingPoint.timestamp,
            timeZoneIdentifier: context.timeZoneIdentifier,
            route: completedRoute,
            distanceMeters: completedDistanceMeters,
            classification: .unclassified,
            businessPurpose: "",
            note: "",
            createdAt: point.timestamp,
            classifiedAt: nil,
            updatedAt: point.timestamp,
            detectionVersion: configuration.detectionVersion,
            accuracy: MileageTripAccuracySummary(
                acceptedPointCount: completedRoute.count,
                rejectedPointCount: rejectedPointCount,
                averageHorizontalAccuracyMeters: averageAccuracy
            )
        )

        events.append(contentsOf: changeState(to: .idle))
        reset(anchor: point)
        events.append(.tripCompleted(trip))
        return events
    }

    private mutating func appendToRouteIfPlausible(
        _ point: MileageTripPoint
    ) {
        guard let previous = activeRoute.last else {
            activeRoute.append(point)
            return
        }

        let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            rejectedPointCount += 1
            return
        }

        let segmentDistance = previous.distance(to: point)
        let impliedSpeed = segmentDistance / elapsed
        let plausibleSpeed = max(
            configuration.maximumUnexplainedSpeedMetersPerSecond,
            max(previous.speedMetersPerSecond, point.speedMetersPerSecond) + 15
        )
        guard impliedSpeed <= plausibleSpeed else {
            rejectedPointCount += 1
            return
        }

        guard segmentDistance >=
            configuration.minimumRecordedSegmentMeters else {
            return
        }

        activeRoute.append(point)
    }

    private func isValid(_ point: MileageTripPoint) -> Bool {
        guard point.latitude >= -90, point.latitude <= 90,
              point.longitude >= -180, point.longitude <= 180,
              point.horizontalAccuracyMeters >= 0,
              point.horizontalAccuracyMeters <=
                configuration.maximumHorizontalAccuracyMeters,
              point.speedMetersPerSecond >= 0 else {
            return false
        }

        if let lastObservedTimestamp,
           point.timestamp <= lastObservedTimestamp {
            return false
        }
        return true
    }

    private func routeDistance(_ route: [MileageTripPoint]) -> Double {
        guard route.count > 1 else {
            return 0
        }
        return zip(route, route.dropFirst()).reduce(0) {
            $0 + $1.0.distance(to: $1.1)
        }
    }

    private func routeEnding(
        at endingPoint: MileageTripPoint
    ) -> [MileageTripPoint] {
        guard let index = activeRoute.lastIndex(where: {
            $0.timestamp <= endingPoint.timestamp
        }) else {
            return activeRoute
        }
        return Array(activeRoute[...index])
    }

    private mutating func changeState(
        to newState: MileageTrackingState
    ) -> [MileageDetectionEvent] {
        guard state != newState else {
            return []
        }
        state = newState
        return [.stateChanged(newState)]
    }

    private mutating func reset(anchor: MileageTripPoint?) {
        state = .idle
        self.anchor = anchor
        startCandidates.removeAll(keepingCapacity: true)
        activeTripID = nil
        activeRoute.removeAll(keepingCapacity: true)
        stoppingBeganAt = nil
        lastMovementPoint = nil
        lastDrivingPoint = nil
    }
}
