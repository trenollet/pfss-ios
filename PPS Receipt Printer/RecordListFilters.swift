import Foundation

enum RecordDateFilter: String, CaseIterable, Identifiable {
    case all = "All Dates"
    case today = "Today"
    case upcoming = "Upcoming"
    case past = "Past"

    var id: String { rawValue }

    func includes(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .today: return calendar.isDateInToday(date)
        case .upcoming: return date >= calendar.startOfDay(for: Date())
        case .past: return date < calendar.startOfDay(for: Date())
        }
    }
}

enum RecordListSortOrder: String, CaseIterable, Identifiable {
    case dateAscending = "Date — Earliest First"
    case dateDescending = "Date — Latest First"
    case nameAscending = "Name — A to Z"

    var id: String { rawValue }
}
