import Foundation
import Testing
@testable import PPS_Receipt_Printer

@MainActor
struct MileageReportEngineTests {
    @Test func filtersInclusiveDatesAndClassification() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let business = trip(
            date: date(2026, 8, 10),
            miles: 12.5,
            classification: .business
        )
        let personal = trip(
            date: date(2026, 8, 11),
            miles: 4.25,
            classification: .personal
        )
        let outside = trip(
            date: date(2026, 7, 31),
            miles: 50,
            classification: .business
        )

        let summary = MileageReportEngine.summary(
            trips: [outside, personal, business],
            startDate: date(2026, 8, 10),
            endDate: date(2026, 8, 11),
            classification: .all,
            calendar: calendar
        )

        #expect(summary.trips.map(\.id) == [business.id, personal.id])
        #expect(summary.businessMiles == 12.5)
        #expect(summary.personalMiles == 4.25)
        #expect(summary.totalMiles == 16.75)
    }

    @Test func csvEscapesUserTextAndIncludesTotals() {
        var example = trip(
            date: date(2026, 8, 10),
            miles: 10,
            classification: .business
        )
        example.businessPurpose = "Customer visit, downtown"
        example.note = "Said \"use rear entrance\""
        let summary = MileageReportSummary(
            trips: [example],
            businessMiles: 10,
            personalMiles: 0
        )

        let csv = MileageReportEngine.csv(
            for: summary,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(csv.contains("\"Customer visit, downtown\""))
        #expect(csv.contains("\"Said \"\"use rear entrance\"\"\""))
        #expect(csv.contains("\"Total Miles\",\"10.00\""))
    }

    private func trip(
        date: Date,
        miles: Double,
        classification: MileageTripClassification
    ) -> MileageTrip {
        MileageTrip(
            id: UUID(),
            accountID: UUID(),
            userID: UUID(),
            originatingDeviceID: UUID(),
            entrySource: .manual,
            startedAt: date,
            endedAt: date,
            timeZoneIdentifier: "UTC",
            route: [],
            distanceMeters: miles * 1_609.344,
            classification: classification,
            businessPurpose: "",
            note: "",
            createdAt: date,
            classifiedAt: date,
            updatedAt: date,
            detectionVersion: 1,
            accuracy: MileageTripAccuracySummary(
                acceptedPointCount: 0,
                rejectedPointCount: 0,
                averageHorizontalAccuracyMeters: 0
            )
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }
}
