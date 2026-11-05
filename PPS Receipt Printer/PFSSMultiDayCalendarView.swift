import SwiftUI

private enum PFSSCalendarDisplayMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case multiDay = "Multi Day"
    case month = "Month"

    var id: Self { self }
    var systemImage: String {
        switch self {
        case .day: "rectangle.portrait"
        case .multiDay: "rectangle.split.3x1"
        case .month: "calendar"
        }
    }
}

enum PFSSCalendarRecordKind: Hashable {
    case job
    case lead
}

struct PFSSCalendarEntry: Identifiable, Hashable {
    let id: String
    let recordID: UUID
    let kind: PFSSCalendarRecordKind
    let employeeID: UUID
    let title: String
    let subtitle: String
    let startDate: Date
    let endDate: Date
    let color: Color

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct PFSSPositionedCalendarEntry: Identifiable {
    let entry: PFSSCalendarEntry
    let lane: Int
    let laneCount: Int
    var id: String { entry.id }
}

struct PFSSMultiDayCalendarView: View {
    let entries: [PFSSCalendarEntry]
    let calendarTitle: String
    let showsCalendarsButton: Bool
    let onSelectEntry: (PFSSCalendarEntry) -> Void
    let onShowCalendars: () -> Void
    private let displayModeStorageKey: String

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 72
    private let dayRange = -730...730
    @State private var visibleDate: Date? = Calendar.current.startOfDay(for: Date())
    @State private var lastVisibleDate = Calendar.current.startOfDay(for: Date())
    @State private var visibleMonth: Date? = Calendar.current.dateInterval(
        of: .month,
        for: Date()
    )?.start
    @State private var lastVisibleMonth = Calendar.current.dateInterval(
        of: .month,
        for: Date()
    )?.start ?? Calendar.current.startOfDay(for: Date())
    @State private var displayMode: PFSSCalendarDisplayMode
    @State private var lastTimelineMode: PFSSCalendarDisplayMode
    @State private var timelineRevision = 0

    init(
        entries: [PFSSCalendarEntry],
        calendarTitle: String,
        displayModeStorageKey: String,
        showsCalendarsButton: Bool,
        onSelectEntry: @escaping (PFSSCalendarEntry) -> Void,
        onShowCalendars: @escaping () -> Void
    ) {
        self.entries = entries
        self.calendarTitle = calendarTitle
        self.displayModeStorageKey = displayModeStorageKey
        self.showsCalendarsButton = showsCalendarsButton
        self.onSelectEntry = onSelectEntry
        self.onShowCalendars = onShowCalendars

        let savedMode = UserDefaults.standard
            .string(forKey: displayModeStorageKey)
            .flatMap(PFSSCalendarDisplayMode.init(rawValue:))
        let initialMode = savedMode ?? .day
        _displayMode = State(initialValue: initialMode)
        _lastTimelineMode = State(
            initialValue: initialMode == .month ? .day : initialMode
        )
    }

    private var today: Date { calendar.startOfDay(for: Date()) }

    private var dates: [Date] {
        dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                calendarHeader
                Divider()

                if displayMode != .month {
                    multiDayCalendar(width: geometry.size.width)
                        .id("\(displayMode.rawValue)-\(timelineRevision)")
                } else {
                    monthPager(width: geometry.size.width)
                }
            }
            .background(Color(.systemBackground))
        }
        .safeAreaInset(edge: .bottom) {
            if showsCalendarsButton {
                HStack {
                    Spacer()
                    Button(action: onShowCalendars) {
                        Image(systemName: "calendar")
                            .font(.headline)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Calendars")
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
        .onChange(of: visibleDate) { _, date in
            if let date { lastVisibleDate = calendar.startOfDay(for: date) }
        }
        .onChange(of: visibleMonth) { _, month in
            if let month { lastVisibleMonth = startOfMonth(month) }
        }
        .onChange(of: displayMode) { _, mode in
            UserDefaults.standard.set(mode.rawValue, forKey: displayModeStorageKey)
        }
        .onDisappear {
            if visibleDate == nil { visibleDate = lastVisibleDate }
            if visibleMonth == nil { visibleMonth = lastVisibleMonth }
        }
    }

    private func multiDayCalendar(width: CGFloat) -> some View {
        let dayWidth = displayMode == .day ? width : max(172, width / 2)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(visibleHeaderDates, id: \.self) { date in
                    dayHeader(date)
                        .frame(width: dayWidth, height: 58)
                }
            }
            .frame(width: width, height: 58, alignment: .leading)
            .clipped()

            Divider()

            ScrollViewReader { verticalProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        ScrollViewReader { horizontalProxy in
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 0) {
                                    ForEach(dates, id: \.self) { date in
                                        dayTimeline(date, width: dayWidth)
                                            .id(date)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollIndicators(.hidden)
                            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                            .scrollPosition(id: $visibleDate, anchor: .leading)
                            .onAppear {
                                scrollTimeline(
                                    horizontalProxy,
                                    to: visibleDate ?? lastVisibleDate
                                )
                            }
                        }

                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: hourHeight * 7)
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("calendar-hour-7")
                            Spacer(minLength: 0)
                        }
                        .frame(width: 1, height: hourHeight * 24)
                        .allowsHitTesting(false)
                    }
                }
                .onAppear {
                    if visibleDate == nil { visibleDate = lastVisibleDate }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        verticalProxy.scrollTo("calendar-hour-7", anchor: .top)
                    }
                }
            }
        }
    }

    private func scrollTimeline(
        _ proxy: ScrollViewProxy,
        to date: Date
    ) {
        let target = calendar.startOfDay(for: date)
        visibleDate = target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(target, anchor: .leading)
        }
    }

    private var visibleHeaderDates: [Date] {
        let firstDate = calendar.startOfDay(
            for: visibleDate ?? lastVisibleDate
        )
        let count = displayMode == .day ? 1 : 2
        return (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDate)
        }
    }

    private var calendarHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(calendarTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    switchMode(to: .month)
                } label: {
                    Text(headerDate.formatted(.dateTime.month(.wide).year()))
                        .font(.title2.bold())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Month view")
            }

            Spacer()

            Menu {
                ForEach(PFSSCalendarDisplayMode.allCases) { mode in
                    Button {
                        switchMode(to: mode)
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                    }
                }
            } label: {
                Image(systemName: displayMode.systemImage)
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Calendar View")

            Button("Today") {
                withAnimation(.snappy) {
                    visibleDate = today
                    visibleMonth = startOfMonth(today)
                }
            }
            .fontWeight(.semibold)
            .disabled(isShowingToday)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var headerDate: Date {
        displayMode == .month
            ? (visibleMonth ?? startOfMonth(today))
            : (visibleDate ?? today)
    }

    private var isShowingToday: Bool {
        switch displayMode {
        case .day, .multiDay:
            calendar.isDateInToday(visibleDate ?? today)
        case .month:
            calendar.isDate(
                visibleMonth ?? startOfMonth(today),
                equalTo: today,
                toGranularity: .month
            )
        }
    }

    private var months: [Date] {
        (-120...120).compactMap {
            calendar.date(byAdding: .month, value: $0, to: startOfMonth(today))
        }
    }

    private func monthPager(width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(months, id: \.self) { month in
                    monthGrid(month)
                        .frame(width: width)
                        .id(month)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleMonth, anchor: .center)
        .onAppear {
            if visibleMonth == nil { visibleMonth = lastVisibleMonth }
        }
    }

    private func monthGrid(_ month: Date) -> some View {
        let dates = monthGridDates(month)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 0
            ) {
                ForEach(dates, id: \.self) { date in
                    monthDay(date, displayedMonth: month)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private func monthDay(_ date: Date, displayedMonth: Date) -> some View {
        let dayEntries = entries(on: date)
        let belongsToMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return Button {
            let selectedDate = calendar.startOfDay(for: date)
            visibleDate = selectedDate
            lastVisibleDate = selectedDate
            timelineRevision += 1
            displayMode = lastTimelineMode
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(calendar.isDateInToday(date) ? .bold : .regular))
                    .foregroundStyle(
                        calendar.isDateInToday(date)
                            ? Color.white
                            : (belongsToMonth ? Color.primary : Color.secondary.opacity(0.55))
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        calendar.isDateInToday(date) ? Color.red : Color.clear,
                        in: Circle()
                    )

                HStack(spacing: 2) {
                    ForEach(Array(dayEntries.prefix(3).enumerated()), id: \.offset) { _, entry in
                        Circle()
                            .fill(entry.color)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(date.formatted(date: .complete, time: .omitted)), \(dayEntries.count) events"
        )
    }

    private func monthGridDates(_ month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingDays = firstWeekday - calendar.firstWeekday >= 0
            ? firstWeekday - calendar.firstWeekday
            : firstWeekday - calendar.firstWeekday + 7
        let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: monthInterval.start
        ) ?? monthInterval.start
        let cellCount = Int(ceil(Double(leadingDays + dayRange.count) / 7.0)) * 7
        return (0..<cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    private func switchMode(to mode: PFSSCalendarDisplayMode) {
        guard mode != displayMode else { return }
        if mode == .month {
            if displayMode != .month { lastTimelineMode = displayMode }
            visibleMonth = startOfMonth(visibleDate ?? lastVisibleDate)
        } else {
            visibleDate = visibleMonth ?? lastVisibleMonth
            lastTimelineMode = mode
            timelineRevision += 1
        }
        displayMode = mode
    }

    private func dayHeader(_ date: Date) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.bold())
                    .foregroundStyle(calendar.isDateInToday(date) ? .white : .primary)
                    .frame(width: 34, height: 34)
                    .background(
                        calendar.isDateInToday(date) ? Color.red : Color.clear,
                        in: Circle()
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color(.systemBackground))
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 0.5)
        }
    }

    private func dayTimeline(_ date: Date, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            hourGrid(width: width)

            ForEach(positionedEntries(on: date)) { positioned in
                eventBlock(positioned, dayWidth: width)
            }

            if calendar.isDateInToday(date) {
                currentTimeLine(width: width)
            }
        }
        .frame(width: width, height: hourHeight * 24)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 0.5)
        }
    }

    private func legacyDayColumn(_ date: Date, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            dayHeader(date)
            ZStack(alignment: .topLeading) {
                hourGrid(width: width)

                ForEach(positionedEntries(on: date)) { positioned in
                    eventBlock(positioned, dayWidth: width)
                }

                if calendar.isDateInToday(date) {
                    currentTimeLine(width: width)
                }
            }
            .frame(width: width, height: hourHeight * 24)
        }
        .frame(width: width)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 0.5)
        }
    }

    private func hourGrid(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 4) {
                    Text(hourLabel(hour))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                        .offset(y: -6)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 0.5)
                }
                .frame(width: width, height: hourHeight, alignment: .top)
            }
        }
    }

    private func eventBlock(
        _ positioned: PFSSPositionedCalendarEntry,
        dayWidth: CGFloat
    ) -> some View {
        let entry = positioned.entry
        let startMinutes = minutesSinceStartOfDay(entry.startDate)
        let durationMinutes = max(
            entry.endDate.timeIntervalSince(entry.startDate) / 60,
            30
        )
        let y = CGFloat(startMinutes) / 60 * hourHeight
        let height = max(CGFloat(durationMinutes) / 60 * hourHeight, 38)
        let availableWidth = max(dayWidth - 48, 112)
        let laneWidth = availableWidth / CGFloat(max(positioned.laneCount, 1))

        return Button {
            onSelectEntry(entry)
        } label: {
            HStack(spacing: 5) {
                Capsule()
                    .fill(entry.color)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.subtitle)
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(5)
            .frame(
                width: max(laneWidth - 2, 28),
                height: height,
                alignment: .topLeading
            )
            .background(entry.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(entry.color.opacity(0.42), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .offset(
            x: 43 + CGFloat(positioned.lane) * laneWidth,
            y: y + 1
        )
    }

    private func currentTimeLine(width: CGFloat) -> some View {
        let y = CGFloat(minutesSinceStartOfDay(Date())) / 60 * hourHeight
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1)
        }
        .frame(width: width - 39)
        .offset(x: 39, y: y)
        .accessibilityHidden(true)
    }

    private func entries(on date: Date) -> [PFSSCalendarEntry] {
        entries
            .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func positionedEntries(on date: Date) -> [PFSSPositionedCalendarEntry] {
        let sorted = entries(on: date)
        guard !sorted.isEmpty else { return [] }

        var result: [PFSSPositionedCalendarEntry] = []
        var cluster: [PFSSCalendarEntry] = []
        var clusterEnd = Date.distantPast

        func appendCluster(_ entries: [PFSSCalendarEntry]) {
            guard !entries.isEmpty else { return }
            var laneEndDates: [Date] = []
            var assignments: [(PFSSCalendarEntry, Int)] = []

            for entry in entries {
                if let availableLane = laneEndDates.firstIndex(where: {
                    $0 <= entry.startDate
                }) {
                    laneEndDates[availableLane] = entry.endDate
                    assignments.append((entry, availableLane))
                } else {
                    laneEndDates.append(entry.endDate)
                    assignments.append((entry, laneEndDates.count - 1))
                }
            }

            let laneCount = laneEndDates.count
            result.append(contentsOf: assignments.map {
                PFSSPositionedCalendarEntry(
                    entry: $0.0,
                    lane: $0.1,
                    laneCount: laneCount
                )
            })
        }

        for entry in sorted {
            if !cluster.isEmpty && entry.startDate >= clusterEnd {
                appendCluster(cluster)
                cluster = []
                clusterEnd = .distantPast
            }
            cluster.append(entry)
            clusterEnd = max(clusterEnd, entry.endDate)
        }
        appendCluster(cluster)
        return result
    }

    private func minutesSinceStartOfDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        guard let date = calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: today
        ) else { return "" }
        return date.formatted(.dateTime.hour())
    }
}

struct PFSSCalendarEmployeeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let employees: [EmployeeRecord]
    @Binding var selectedEmployeeIDs: Set<UUID>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(employees) { employee in
                        Button {
                            toggle(employee.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(pfssCalendarColor(named: employee.colorName))
                                    .frame(width: 12, height: 12)
                                Text(employee.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedEmployeeIDs.contains(employee.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Select one or more employees to display together.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedEmployeeIDs.contains(id) {
            selectedEmployeeIDs.remove(id)
        } else {
            selectedEmployeeIDs.insert(id)
        }
    }
}

func pfssCalendarColor(named name: String) -> Color {
    switch name.lowercased() {
    case "red": .red
    case "orange": .orange
    case "yellow": .yellow
    case "green": .green
    case "mint": .mint
    case "teal": .teal
    case "cyan": .cyan
    case "blue": .blue
    case "indigo": .indigo
    case "purple": .purple
    case "pink": .pink
    default: .blue
    }
}
