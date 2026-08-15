//
//  RecurringWorkEngine.swift
//  PPS Receipt Printer
//
//  Phase 18 – Deterministic, UI-independent recurring-work planning.
//

import CryptoKit
import Foundation

enum RecurringWorkIntervalUnit: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
}

struct RecurringWorkRule: Codable, Hashable {
    var interval: Int
    var unit: RecurringWorkIntervalUnit

    init(interval: Int, unit: RecurringWorkIntervalUnit) {
        self.interval = max(interval, 1)
        self.unit = unit
    }

    static let weekly = Self(interval: 1, unit: .week)
    static let biweekly = Self(interval: 2, unit: .week)
    static let monthly = Self(interval: 1, unit: .month)
}

enum RecurringWorkEndCondition: Codable, Hashable {
    case noEnd
    case endDate(Date)
    case occurrenceCount(Int)
}

enum RecurringWorkTemplateStatus: String, Codable, CaseIterable {
    case active
    case paused
    case held
    case terminated
    case archived
}

enum RecurringWorkExceptionKind: String, Codable {
    case skipped
    case cancelled
    case detached
}

struct RecurringWorkOccurrenceException: Identifiable, Codable {
    var id: UUID = UUID()
    var occurrenceIndex: Int
    var kind: RecurringWorkExceptionKind
    var reason: String
    var createdAt: Date = Date()
}

struct RecurringWorkTemplate: Identifiable, Codable {
    var id: UUID
    var revision: Int
    var status: RecurringWorkTemplateStatus
    var rule: RecurringWorkRule
    var endCondition: RecurringWorkEndCondition
    var anchorDate: Date
    var generationHorizonDays: Int
    var prototype: JobRecord
    var exceptions: [RecurringWorkOccurrenceException]
    var scheduleStartIndex: Int?
    var heldOccurrenceIndex: Int?
    var heldScheduledDate: Date?
    var holdStartedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        status: RecurringWorkTemplateStatus = .active,
        rule: RecurringWorkRule,
        endCondition: RecurringWorkEndCondition = .noEnd,
        anchorDate: Date,
        generationHorizonDays: Int = 120,
        prototype: JobRecord,
        exceptions: [RecurringWorkOccurrenceException] = [],
        scheduleStartIndex: Int? = nil,
        heldOccurrenceIndex: Int? = nil,
        heldScheduledDate: Date? = nil,
        holdStartedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.revision = max(revision, 1)
        self.status = status
        self.rule = rule
        self.endCondition = endCondition
        self.anchorDate = anchorDate
        self.generationHorizonDays = min(max(generationHorizonDays, 7), 730)
        self.prototype = prototype
        self.exceptions = exceptions
        self.scheduleStartIndex = scheduleStartIndex
        self.heldOccurrenceIndex = heldOccurrenceIndex
        self.heldScheduledDate = heldScheduledDate
        self.holdStartedAt = holdStartedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct RecurringWorkPlannedOccurrence: Identifiable, Hashable {
    var id: String { occurrenceKey }
    let templateID: UUID
    let templateRevision: Int
    let occurrenceIndex: Int
    let occurrenceKey: String
    let jobID: UUID
    let scheduledDate: Date
}

enum RecurringWorkEngineError: LocalizedError, Equatable {
    case invalidHorizon
    case invalidOccurrenceCount
    case occurrenceLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidHorizon:
            return "The recurring-work generation horizon is invalid."
        case .invalidOccurrenceCount:
            return "The recurring-work occurrence count must be greater than zero."
        case .occurrenceLimitExceeded:
            return "The recurring-work rule produced too many occurrences for one planning pass."
        }
    }
}

struct RecurringWorkEngine {
    static let maximumOccurrencesPerPlan = 1_000

    func plan(
        template: RecurringWorkTemplate,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [RecurringWorkPlannedOccurrence] {
        guard template.generationHorizonDays > 0,
              let horizon = calendar.date(
                byAdding: .day,
                value: template.generationHorizonDays,
                to: generatedAt
              ) else {
            throw RecurringWorkEngineError.invalidHorizon
        }

        if case let .occurrenceCount(count) = template.endCondition,
           count <= 0 {
            throw RecurringWorkEngineError.invalidOccurrenceCount
        }

        guard template.status == .active else { return [] }

        let excluded = Set(template.exceptions.map(\.occurrenceIndex))
        var result: [RecurringWorkPlannedOccurrence] = []
        let scheduleStartIndex = max(template.scheduleStartIndex ?? 0, 0)
        var index = scheduleStartIndex

        while index < Self.maximumOccurrencesPerPlan {
            if case let .occurrenceCount(count) = template.endCondition,
               index >= count {
                break
            }

            guard let date = occurrenceDate(
                anchor: template.anchorDate,
                rule: template.rule,
                index: index - scheduleStartIndex,
                calendar: calendar
            ) else { break }

            if case let .endDate(endDate) = template.endCondition,
               date > endDate {
                break
            }
            if date > horizon { break }

            let planningStart = calendar.startOfDay(for: generatedAt)
            if !excluded.contains(index),
               index == 0 || date >= planningStart {
                let key = occurrenceKey(
                    templateID: template.id,
                    occurrenceIndex: index
                )
                result.append(
                    RecurringWorkPlannedOccurrence(
                        templateID: template.id,
                        templateRevision: template.revision,
                        occurrenceIndex: index,
                        occurrenceKey: key,
                        jobID: deterministicUUID(for: key),
                        scheduledDate: date
                    )
                )
            }
            index += 1
        }

        if index == Self.maximumOccurrencesPerPlan {
            throw RecurringWorkEngineError.occurrenceLimitExceeded
        }
        return result
    }

    func occurrenceKey(
        templateID: UUID,
        occurrenceIndex: Int
    ) -> String {
        "\(templateID.uuidString.lowercased()):\(occurrenceIndex)"
    }

    func deterministicUUID(for value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func occurrenceDate(
        anchor: Date,
        rule: RecurringWorkRule,
        index: Int,
        calendar: Calendar
    ) -> Date? {
        guard index >= 0 else { return nil }
        if index == 0 { return adjustedToBusinessDay(anchor, calendar: calendar) }
        let amount = rule.interval * index
        let date: Date?
        switch rule.unit {
        case .day:
            date = calendar.date(byAdding: .day, value: amount, to: anchor)
        case .week:
            date = calendar.date(byAdding: .weekOfYear, value: amount, to: anchor)
        case .month:
            date = monthDate(anchor: anchor, months: amount, calendar: calendar)
        case .year:
            date = monthDate(anchor: anchor, months: amount * 12, calendar: calendar)
        }
        guard let date else { return nil }
        return adjustedToBusinessDay(date, calendar: calendar)
    }

    private func monthDate(
        anchor: Date,
        months: Int,
        calendar: Calendar
    ) -> Date? {
        let anchorParts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: anchor
        )
        guard let monthStart = calendar.date(from: DateComponents(
            year: anchorParts.year,
            month: anchorParts.month,
            day: 1,
            hour: anchorParts.hour,
            minute: anchorParts.minute,
            second: anchorParts.second
        )),
        let targetMonth = calendar.date(byAdding: .month, value: months, to: monthStart),
        let dayRange = calendar.range(of: .day, in: .month, for: targetMonth) else {
            return nil
        }
        return calendar.date(
            bySetting: .day,
            value: min(anchorParts.day ?? 1, dayRange.count),
            of: targetMonth
        )
    }

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

extension JobRecurrenceFrequency {
    var recurringWorkRule: RecurringWorkRule {
        switch self {
        case .weekly: return .weekly
        case .biweekly: return .biweekly
        case .monthly: return .monthly
        case .quarterly: return .init(interval: 3, unit: .month)
        case .biannual: return .init(interval: 6, unit: .month)
        case .annual: return .init(interval: 1, unit: .year)
        }
    }
}

extension RecurringWorkRule {
    var jobRecurrenceFrequency: JobRecurrenceFrequency {
        switch (interval, unit) {
        case (1, .week): return .weekly
        case (2, .week): return .biweekly
        case (1, .month): return .monthly
        case (3, .month): return .quarterly
        case (6, .month): return .biannual
        case (1, .year): return .annual
        default: return .monthly
        }
    }
}
