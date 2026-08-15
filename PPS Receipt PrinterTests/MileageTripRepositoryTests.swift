import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct MileageTripRepositoryTests {
    @Test func tripSurvivesRepositoryReload() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let repository = MileageTripRepository(baseDirectory: fixture.directory)
        try repository.configure(context: fixture.context)
        try repository.save(fixture.trip)

        let reloaded = MileageTripRepository(baseDirectory: fixture.directory)
        try reloaded.configure(context: fixture.context)

        #expect(reloaded.trips == [fixture.trip])
        #expect(reloaded.unclassifiedTrips.map(\.id) == [fixture.trip.id])
    }

    @Test func activeTripCheckpointSurvivesRepositoryReload() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        var engine = MileageDetectionEngine(context: fixture.context)
        _ = engine.process(fixture.trip.route[0])

        let repository = MileageTripRepository(baseDirectory: fixture.directory)
        try repository.configure(context: fixture.context)
        try repository.checkpoint(engine: engine)

        let reloaded = MileageTripRepository(baseDirectory: fixture.directory)
        try reloaded.configure(context: fixture.context)

        let restored = try #require(reloaded.restoredEngine())
        #expect(restored.context == fixture.context)
        #expect(restored.state == engine.state)
    }

    @Test func classificationCanBeReversedWithHistoryPreserved() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let businessDate = fixture.trip.endedAt.addingTimeInterval(60)
        let undoDate = businessDate.addingTimeInterval(60)

        let repository = MileageTripRepository(baseDirectory: fixture.directory)
        try repository.configure(context: fixture.context)
        try repository.save(fixture.trip)
        try repository.classify(
            tripID: fixture.trip.id,
            as: .business,
            at: businessDate
        )
        try repository.classify(
            tripID: fixture.trip.id,
            as: .unclassified,
            at: undoDate
        )

        let trip = try #require(repository.trips.first)
        #expect(trip.classification == .unclassified)
        #expect(trip.classifiedAt == nil)
        #expect(trip.classificationHistory.count == 2)
        #expect(trip.classificationHistory[0].newValue == .business)
        #expect(trip.classificationHistory[1].newValue == .unclassified)
    }

    @Test func monthToDateMileageIncludesCurrentMonthTrips() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let repository = MileageTripRepository(baseDirectory: fixture.directory)
        try repository.configure(context: fixture.context)
        try repository.save(fixture.trip)

        let total = repository.monthToDateMileageMiles(
            asOf: fixture.trip.endedAt,
            calendar: calendar
        )
        #expect(abs(total - fixture.trip.distanceMiles) < 0.000_001)
    }

    private func makeFixture() throws -> (
        directory: URL,
        context: MileageTrackingContext,
        trip: MileageTrip
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let context = MileageTrackingContext(
            accountID: UUID(),
            userID: UUID(),
            deviceID: UUID(),
            timeZoneIdentifier: "America/Chicago"
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let route = [
            MileageTripPoint(
                latitude: 35.4676,
                longitude: -97.5164,
                timestamp: startedAt,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 8
            ),
            MileageTripPoint(
                latitude: 35.4686,
                longitude: -97.5154,
                timestamp: startedAt.addingTimeInterval(60),
                horizontalAccuracyMeters: 6,
                speedMetersPerSecond: 8
            )
        ]
        let trip = MileageTrip(
            id: UUID(),
            accountID: context.accountID,
            userID: context.userID,
            originatingDeviceID: context.deviceID,
            entrySource: .automatic,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            timeZoneIdentifier: context.timeZoneIdentifier,
            route: route,
            distanceMeters: route[0].distance(to: route[1]),
            classification: .unclassified,
            businessPurpose: "",
            note: "",
            createdAt: startedAt.addingTimeInterval(60),
            classifiedAt: nil,
            updatedAt: startedAt.addingTimeInterval(60),
            detectionVersion: 1,
            accuracy: MileageTripAccuracySummary(
                acceptedPointCount: 2,
                rejectedPointCount: 0,
                averageHorizontalAccuracyMeters: 5.5
            )
        )
        return (directory, context, trip)
    }
}
