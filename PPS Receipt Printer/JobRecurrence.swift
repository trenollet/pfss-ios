import Foundation

enum JobRecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case biannual = "Bi-Annual"
    case annual = "Annual"

    var id: String { rawValue }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly: return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date)
        case .biannual: return calendar.date(byAdding: .month, value: 6, to: date)
        case .annual: return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}
