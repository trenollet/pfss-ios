//
//  MileageTripModels.swift
//  PPS Receipt Printer
//
//  Phase 19 – Durable, provider-neutral mileage trip facts.
//

import Foundation

enum MileageTripClassification: String, Codable, CaseIterable, Hashable {
    case unclassified
    case business
    case personal
}

enum MileageTripEntrySource: String, Codable, Hashable {
    case automatic
    case manual
}

struct MileageTripClassificationChange: Codable, Hashable {
    let previousValue: MileageTripClassification
    let newValue: MileageTripClassification
    let changedAt: Date
}

struct MileageTripPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double

    func distance(to other: MileageTripPoint) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let latitude1 = latitude * .pi / 180
        let latitude2 = other.latitude * .pi / 180
        let latitudeDelta = (other.latitude - latitude) * .pi / 180
        let longitudeDelta = (other.longitude - longitude) * .pi / 180

        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(latitude1) * cos(latitude2) *
            sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let angularDistance = 2 * atan2(
            sqrt(haversine),
            sqrt(max(0, 1 - haversine))
        )
        return earthRadiusMeters * angularDistance
    }
}

struct MileageTripAccuracySummary: Codable, Hashable {
    let acceptedPointCount: Int
    let rejectedPointCount: Int
    let averageHorizontalAccuracyMeters: Double
}

struct MileageTripCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

struct MileageTrip: Identifiable, Codable, Hashable {
    let id: UUID
    let accountID: UUID
    let userID: UUID
    let originatingDeviceID: UUID
    let entrySource: MileageTripEntrySource
    var startedAt: Date
    var endedAt: Date
    let timeZoneIdentifier: String
    let route: [MileageTripPoint]
    var distanceMeters: Double
    var startAddress: String? = nil
    var endAddress: String? = nil
    var startCoordinate: MileageTripCoordinate? = nil
    var endCoordinate: MileageTripCoordinate? = nil
    // Optional for backward-compatible decoding of trips saved before Build 19.2.4.
    var isRoundTrip: Bool? = nil
    var classification: MileageTripClassification
    var businessPurpose: String
    var note: String
    let createdAt: Date
    var classifiedAt: Date?
    var exportedAt: Date? = nil
    var updatedAt: Date
    let detectionVersion: Int
    let accuracy: MileageTripAccuracySummary
    var classificationHistory: [MileageTripClassificationChange] = []

    var distanceMiles: Double {
        distanceMeters / 1_609.344
    }
}

struct MileageTrackingContext: Codable, Hashable {
    let accountID: UUID
    let userID: UUID
    let deviceID: UUID
    let timeZoneIdentifier: String

    init(
        accountID: UUID,
        userID: UUID,
        deviceID: UUID,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.accountID = accountID
        self.userID = userID
        self.deviceID = deviceID
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

struct MileageDetectionConfiguration: Codable, Hashable {
    var startDisplacementMeters = 30.48
    var startSpeedMetersPerSecond = 4.4704
    var requiredConsecutiveStartSamples = 3
    var stopSpeedMetersPerSecond = 1.34112
    var stopMovementToleranceMeters = 15.0
    var stopDwellDuration: TimeInterval = 180
    var maximumHorizontalAccuracyMeters = 65.0
    var minimumRecordedSegmentMeters = 2.0
    var maximumUnexplainedSpeedMetersPerSecond = 75.0
    var detectionVersion = 1
}

enum MileageTrackingState: String, Codable, Hashable {
    case idle
    case arming
    case tracking
    case stopping
}

enum MileageDetectionEvent: Equatable {
    case stateChanged(MileageTrackingState)
    case tripStarted(id: UUID, at: Date)
    case tripCompleted(MileageTrip)
}
