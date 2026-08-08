import Foundation

enum JobRecurrenceEndMode: String, Codable, CaseIterable, Identifiable {
    case noEnd = "No End Date"
    case endDate = "End On Date"
    case occurrenceCount = "After Number of Jobs"

    var id: String { rawValue }
}

enum JobRecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case biannual = "Bi-Annual"
    case annual = "Annual"

    var id: String { rawValue }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        occurrenceDate(from: date, occurrence: 1, calendar: calendar)
    }

    /// Calculates an occurrence from the series' original anchor date, then
    /// applies PFSS's weekend operating rule. Calculating from the anchor keeps
    /// monthly and annual series from drifting after a weekend adjustment.
    func occurrenceDate(
        from anchorDate: Date,
        occurrence: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard occurrence > 0 else {
            return adjustedToBusinessDay(anchorDate, calendar: calendar)
        }

        let proposedDate: Date?

        switch self {
        case .weekly:
            proposedDate = calendar.date(
                byAdding: .weekOfYear,
                value: occurrence,
                to: anchorDate
            )
        case .biweekly:
            proposedDate = calendar.date(
                byAdding: .weekOfYear,
                value: 2 * occurrence,
                to: anchorDate
            )
        case .monthly:
            proposedDate = calendar.date(
                byAdding: .month,
                value: occurrence,
                to: anchorDate
            )
        case .quarterly:
            proposedDate = calendar.date(
                byAdding: .month,
                value: 3 * occurrence,
                to: anchorDate
            )
        case .biannual:
            proposedDate = calendar.date(
                byAdding: .month,
                value: 6 * occurrence,
                to: anchorDate
            )
        case .annual:
            proposedDate = calendar.date(
                byAdding: .year,
                value: occurrence,
                to: anchorDate
            )
        }

        guard let proposedDate else { return nil }
        return adjustedToBusinessDay(proposedDate, calendar: calendar)
    }

    /// Saturday occurrences move to the preceding Friday. Sunday occurrences
    /// move to the following Monday. The time of day is preserved.
    private func adjustedToBusinessDay(
        _ date: Date,
        calendar: Calendar
    ) -> Date? {
        switch calendar.component(.weekday, from: date) {
        case 7:
            return calendar.date(byAdding: .day, value: -1, to: date)
        case 1:
            return calendar.date(byAdding: .day, value: 1, to: date)
        default:
            return date
        }
    }
}
