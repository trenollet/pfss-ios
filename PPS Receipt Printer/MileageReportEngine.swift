//
//  MileageReportEngine.swift
//  PPS Receipt Printer
//
//  Phase 19 – Deterministic mileage filtering, totals, and CSV export.
//

import Foundation

enum MileageReportClassification: String, CaseIterable, Identifiable {
    case business = "Business"
    case personal = "Personal"
    case all = "All"

    var id: String { rawValue }
}

struct MileageReportSummary {
    let trips: [MileageTrip]
    let businessMiles: Double
    let personalMiles: Double

    var totalMiles: Double { businessMiles + personalMiles }
}

enum MileageReportEngine {
    static func summary(
        trips: [MileageTrip],
        startDate: Date,
        endDate: Date,
        classification: MileageReportClassification,
        calendar: Calendar = .current
    ) -> MileageReportSummary {
        let lowerBound = calendar.startOfDay(for: min(startDate, endDate))
        let upperDay = calendar.startOfDay(for: max(startDate, endDate))
        let upperBound = calendar.date(byAdding: .day, value: 1, to: upperDay)
            ?? upperDay.addingTimeInterval(86_400)

        let filtered = trips.filter { trip in
            guard trip.startedAt >= lowerBound, trip.startedAt < upperBound else {
                return false
            }
            switch classification {
            case .business:
                return trip.classification == .business
            case .personal:
                return trip.classification == .personal
            case .all:
                return trip.classification == .business ||
                    trip.classification == .personal
            }
        }
        .sorted { $0.startedAt < $1.startedAt }

        return MileageReportSummary(
            trips: filtered,
            businessMiles: filtered
                .filter { $0.classification == .business }
                .reduce(0) { $0 + $1.distanceMiles },
            personalMiles: filtered
                .filter { $0.classification == .personal }
                .reduce(0) { $0 + $1.distanceMiles }
        )
    }

    static func csv(
        for summary: MileageReportSummary,
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = timeZone
        let tripDateFormatter = DateFormatter()
        tripDateFormatter.calendar = Calendar(identifier: .gregorian)
        tripDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        tripDateFormatter.timeZone = timeZone
        tripDateFormatter.dateFormat = "yyyy-MM-dd"
        var rows = [
            [
                "Trip Date",
                "Start Time",
                "End Time",
                "Starting Location",
                "Ending Location",
                "Classification",
                "Business Purpose",
                "Distance Miles",
                "Entry Source",
                "Trip Type",
                "Notes"
            ].map(escape).joined(separator: ",")
        ]

        for trip in summary.trips {
            let date = tripDateFormatter.string(from: trip.startedAt)
            let startTime = dateFormatter.string(from: trip.startedAt)
            let endTime = trip.entrySource == .automatic
                ? dateFormatter.string(from: trip.endedAt)
                : ""
            rows.append(
                [
                    date,
                    startTime,
                    endTime,
                    trip.startAddress ?? "",
                    trip.endAddress ?? "",
                    trip.classification.rawValue.capitalized,
                    trip.businessPurpose,
                    trip.distanceMiles.formatted(
                        .number.precision(.fractionLength(2))
                    ),
                    trip.entrySource == .automatic ? "Automatic" : "Manual",
                    trip.isRoundTrip == true ? "Round Trip" : "One Way",
                    trip.note
                ].map(escape).joined(separator: ",")
            )
        }

        rows.append("")
        rows.append(["Business Miles", format(summary.businessMiles)].map(escape).joined(separator: ","))
        rows.append(["Personal Miles", format(summary.personalMiles)].map(escape).joined(separator: ","))
        rows.append(["Total Miles", format(summary.totalMiles)].map(escape).joined(separator: ","))
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    nonisolated private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    nonisolated private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
