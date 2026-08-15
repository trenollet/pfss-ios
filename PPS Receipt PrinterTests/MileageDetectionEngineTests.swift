import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct MileageDetectionEngineTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func requiresSustainedDrivingBeforeStartingTrip() {
        var engine = makeEngine()

        #expect(engine.process(point(0, metersEast: 0, mph: 0)).isEmpty)
        #expect(engine.process(point(10, metersEast: 40, mph: 12)).contains {
            $0 == .stateChanged(.arming)
        })
        #expect(engine.process(point(20, metersEast: 80, mph: 12)).allSatisfy {
            if case .tripStarted = $0 { return false }
            return true
        })

        let events = engine.process(point(30, metersEast: 120, mph: 12))
        #expect(events.contains { if case .tripStarted = $0 { return true }; return false })
        #expect(engine.state == .tracking)
    }

    @Test func walkingDoesNotCreateTrip() {
        var engine = makeEngine()
        _ = engine.process(point(0, metersEast: 0, mph: 0))

        for index in 1...12 {
            let events = engine.process(
                point(
                    TimeInterval(index * 10),
                    metersEast: Double(index * 15),
                    mph: 3
                )
            )
            #expect(events.allSatisfy {
                if case .tripStarted = $0 { return false }
                return true
            })
        }
        #expect(engine.state == .idle)
    }

    @Test func oneGpsSpikeDoesNotCreateTrip() {
        var engine = makeEngine()
        _ = engine.process(point(0, metersEast: 0, mph: 0))
        _ = engine.process(point(10, metersEast: 2_000, mph: 65))
        let events = engine.process(point(20, metersEast: 5, mph: 0))

        #expect(events.allSatisfy {
            if case .tripStarted = $0 { return false }
            return true
        })
        #expect(engine.state == .idle)
    }

    @Test func completesAfterThreeStationaryMinutes() throws {
        var engine = makeEngine()
        startTrip(&engine)

        _ = engine.process(point(40, metersEast: 170, mph: 15))
        _ = engine.process(point(50, metersEast: 171, mph: 0))
        #expect(engine.state == .stopping)
        _ = engine.process(point(170, metersEast: 172, mph: 0))
        #expect(engine.state == .stopping)

        let events = engine.process(point(231, metersEast: 173, mph: 0))
        let completed = try #require(events.compactMap { event in
            if case let .tripCompleted(trip) = event { return trip }
            return nil
        }.first)

        #expect(completed.classification == .unclassified)
        #expect(completed.entrySource == .automatic)
        #expect(completed.distanceMeters > 130)
        #expect(engine.state == .idle)
    }

    @Test func briefStopDoesNotSplitTrip() {
        var engine = makeEngine()
        startTrip(&engine)
        _ = engine.process(point(40, metersEast: 170, mph: 15))
        _ = engine.process(point(50, metersEast: 171, mph: 0))
        #expect(engine.state == .stopping)

        let resumed = engine.process(point(100, metersEast: 300, mph: 20))
        #expect(resumed.contains(.stateChanged(.tracking)))
        #expect(resumed.allSatisfy {
            if case .tripCompleted = $0 { return false }
            return true
        })
    }

    @Test func walkingAfterParkingIsTrimmedFromCompletedTrip() throws {
        var engine = makeEngine()
        startTrip(&engine)
        let lastDrivingPoint = point(40, metersEast: 170, mph: 15)
        _ = engine.process(lastDrivingPoint)
        _ = engine.process(point(50, metersEast: 180, mph: 3))
        _ = engine.process(point(140, metersEast: 220, mph: 3))

        let events = engine.process(point(231, metersEast: 260, mph: 3))
        let completed = try #require(events.compactMap { event in
            if case let .tripCompleted(trip) = event { return trip }
            return nil
        }.first)

        #expect(completed.endedAt == lastDrivingPoint.timestamp)
        #expect(completed.route.last == lastDrivingPoint)
        #expect(completed.distanceMeters < 190)
    }

    @Test func rejectsPoorAccuracy() {
        var engine = makeEngine()
        let events = engine.process(
            point(0, metersEast: 0, mph: 20, accuracy: 200)
        )

        #expect(events.isEmpty)
        #expect(engine.rejectedPointCount == 1)
    }

    private func makeEngine() -> MileageDetectionEngine {
        MileageDetectionEngine(
            context: MileageTrackingContext(
                accountID: UUID(),
                userID: UUID(),
                deviceID: UUID(),
                timeZoneIdentifier: "America/Chicago"
            )
        )
    }

    private func startTrip(_ engine: inout MileageDetectionEngine) {
        _ = engine.process(point(0, metersEast: 0, mph: 0))
        _ = engine.process(point(10, metersEast: 40, mph: 12))
        _ = engine.process(point(20, metersEast: 80, mph: 12))
        _ = engine.process(point(30, metersEast: 120, mph: 12))
    }

    private func point(
        _ seconds: TimeInterval,
        metersEast: Double,
        mph: Double,
        accuracy: Double = 5
    ) -> MileageTripPoint {
        let metersPerLongitudeDegree = 111_320.0
        return MileageTripPoint(
            latitude: 35.4676,
            longitude: -97.5164 + metersEast / metersPerLongitudeDegree,
            timestamp: start.addingTimeInterval(seconds),
            horizontalAccuracyMeters: accuracy,
            speedMetersPerSecond: mph * 0.44704
        )
    }
}
