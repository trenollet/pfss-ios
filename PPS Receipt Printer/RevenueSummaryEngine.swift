import Foundation

enum RevenueForecastPeriod: CaseIterable, Hashable, Identifiable {
    case weekly, monthly, quarterly, annual

    var id: Self { self }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .annual: "Annually"
        }
    }

    var numberOfPeriods: Int {
        switch self {
        case .weekly: 5 // This week and the next four.
        case .monthly: 3
        case .quarterly: 4
        case .annual: 3
        }
    }

    func label(offset: Int, now: Date, calendar: Calendar) -> String {
        switch (self, offset) {
        case (.weekly, 0): return "This Week"
        case (.weekly, 1): return "Next Week"
        case (.monthly, 0): return "This Month"
        case (.monthly, 1): return "Next Month"
        case (.quarterly, 0): return "This Quarter"
        case (.quarterly, 1): return "Next Quarter"
        case (.annual, 0): return "This Year"
        case (.annual, 1): return "Next Year"
        case (.weekly, _): return "Week \(offset + 1)"
        case (.monthly, _): return "Month \(offset + 1)"
        case (.quarterly, _):
            let start = dateInterval(now: now, calendar: calendar, offset: offset).start
            return "Q\((calendar.component(.month, from: start) - 1) / 3 + 1) \(calendar.component(.year, from: start))"
        case (.annual, _):
            let start = dateInterval(now: now, calendar: calendar, offset: offset).start
            return String(calendar.component(.year, from: start))
        }
    }

    func dateInterval(now: Date, calendar: Calendar, offset: Int = 0) -> DateInterval {
        precondition(offset >= 0)
        let current: DateInterval
        let component: Calendar.Component
        let step: Int
        switch self {
        case .weekly:
            // Match the existing Revenue calendar: Sunday through Saturday.
            current = RevenueSummaryPeriod.weekly.dateInterval(now: now, calendar: calendar)
            component = .weekOfYear
            step = 1
        case .monthly:
            current = calendar.dateInterval(of: .month, for: now)!
            component = .month
            step = 1
        case .quarterly:
            let year = calendar.component(.year, from: now)
            let month = calendar.component(.month, from: now)
            let firstMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1))!
            let end = calendar.date(byAdding: .month, value: 3, to: start)!
            current = DateInterval(start: start, end: end)
            component = .month
            step = 3
        case .annual:
            current = calendar.dateInterval(of: .year, for: now)!
            component = .year
            step = 1
        }
        guard offset > 0 else { return current }
        let start = calendar.date(byAdding: component, value: step * offset, to: current.start)!
        let end = calendar.date(byAdding: component, value: step, to: start)!
        return DateInterval(start: start, end: end)
    }

    func subtitle(now: Date, calendar: Calendar, offset: Int = 0) -> String {
        let interval = dateInterval(now: now, calendar: calendar, offset: offset)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let range = "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted))"
        if self == .quarterly {
            return "Q\((calendar.component(.month, from: interval.start) - 1) / 3 + 1) · \(range)"
        }
        return range
    }
}

struct RevenueForecast {
    let amount: Double
    let jobs: [JobRecord]
}

enum RevenueForecastEngine {
    static func includes(
        _ job: JobRecord,
        in period: RevenueForecastPeriod,
        now: Date,
        calendar: Calendar,
        offset: Int = 0
    ) -> Bool {
        let interval = period.dateInterval(now: now, calendar: calendar, offset: offset)
        let today = calendar.startOfDay(for: now)
        return job.lifecycleStatus == .active
            && (job.status == .scheduled || job.status == .assigned)
            && job.workflowState == .notStarted
            && job.scheduledDate >= today
            && interval.contains(job.scheduledDate)
    }

    static func forecast(
        for period: RevenueForecastPeriod,
        jobs: [JobRecord],
        now: Date = Date(),
        calendar: Calendar = .current,
        offset: Int = 0
    ) -> RevenueForecast {
        var seen = Set<UUID>()
        let included = jobs.filter {
            includes($0, in: period, now: now, calendar: calendar, offset: offset)
                && seen.insert($0.id).inserted
        }.sorted { $0.scheduledDate < $1.scheduledDate }
        let amount = included.reduce(0) { $0 + max($1.total, 0) }
        return RevenueForecast(amount: amount, jobs: included)
    }
}

enum RevenueSummaryPeriod: CaseIterable, Hashable, Identifiable {
    case daily
    case weekly
    case monthly
    case annual

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: "Daily Summary"
        case .weekly: "Weekly Summary"
        case .monthly: "Monthly Summary"
        case .annual: "Annual Summary"
        }
    }

    func subtitle(now: Date, calendar: Calendar) -> String {
        let interval = dateInterval(now: now, calendar: calendar)
        switch self {
        case .daily:
            return now.formatted(date: .complete, time: .omitted)
        case .weekly:
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)
                ?? interval.end
            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted))"
        case .monthly:
            return "Month to date · \(now.formatted(.dateTime.month(.wide).year()))"
        case .annual:
            return "Year to date · \(calendar.component(.year, from: now))"
        }
    }

    func dateInterval(now: Date, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now

        switch self {
        case .daily:
            return DateInterval(start: startOfToday, end: endOfToday)
        case .weekly:
            let weekday = calendar.component(.weekday, from: startOfToday)
            let sunday = calendar.date(
                byAdding: .day,
                value: -(weekday - 1),
                to: startOfToday
            ) ?? startOfToday
            let nextSunday = calendar.date(byAdding: .day, value: 7, to: sunday)
                ?? endOfToday
            return DateInterval(start: sunday, end: nextSunday)
        case .monthly:
            let start = calendar.dateInterval(of: .month, for: now)?.start
                ?? startOfToday
            return DateInterval(start: start, end: endOfToday)
        case .annual:
            let start = calendar.dateInterval(of: .year, for: now)?.start
                ?? startOfToday
            return DateInterval(start: start, end: endOfToday)
        }
    }
}

enum RevenueSummaryEngine {
    static func summary(
        for period: RevenueSummaryPeriod,
        jobs: [JobRecord],
        invoices: [InvoiceRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RevenueSummary {
        let interval = period.dateInterval(now: now, calendar: calendar)

        let scheduled = jobs
            .filter {
                interval.contains($0.scheduledDate)
                    && $0.status != .cancelled
                    && $0.status != .completed
            }
            .reduce(0) { $0 + max($1.total, 0) }

        let completed = jobs
            .filter { job in
                guard job.status == .completed else { return false }
                return interval.contains(job.completedDate ?? job.scheduledDate)
            }
            .reduce(0) { $0 + max($1.total, 0) }

        let periodInvoices = invoices.filter {
            interval.contains($0.issueDate) && $0.status != .void && $0.lifecycleStatus == .active
        }

        let invoiced = periodInvoices
            .reduce(0) { $0 + max($1.total, 0) }

        var countedGroups = Set<UUID>()
        let correctedCollection = invoices.reduce(0.0) { sum, invoice in
            guard let correction = invoice.paymentCorrection,
                  let latest = correction.history.last,
                  countedGroups.insert(correction.rootInvoiceID).inserted else { return sum }
            let members = invoices.filter { $0.paymentCorrection?.rootInvoiceID == correction.rootInvoiceID }
            let evidence = correction.originalInvoices + members
            return sum + collection(pool: latest.pool, evidence: evidence, interval: interval)
                + unpooledReceipts(pool: latest.pool, invoices: members, interval: interval)
        }
        let collected = correctedCollection + invoices.filter { $0.status != .void && $0.paymentCorrection == nil }.reduce(0.0) { sum, invoice in
            guard let combination = invoice.combination else {
                return sum + ((invoice.paidDate.map(interval.contains) ?? false) ? max(invoice.amountPaid, 0) : 0)
            }
            let carried = collection(pool: combination.paymentRedistribution.pool,
                evidence: combination.sourceInvoices + [invoice], interval: interval)
            let later = unpooledReceipts(pool: combination.paymentRedistribution.pool, invoices: [invoice], interval: interval)
            return sum + carried + later
        }

        let outstanding = periodInvoices
            .reduce(0) { $0 + max($1.balanceDue, 0) }

        return RevenueSummary(
            scheduled: scheduled,
            completed: completed,
            invoiced: invoiced,
            collected: collected,
            outstanding: outstanding
        )
    }

    private static func collection(pool: InvoicePaymentPool, evidence: [InvoiceRecord], interval: DateInterval) -> Double {
        pool.verifications.reduce(0.0) { sum, check in
            let effective = check.collectedAmount + pool.adjustments.filter { $0.verificationID == check.id }.reduce(0) { $0 + $1.amountChange }
            var remaining = max(NSDecimalNumber(decimal: effective).doubleValue, 0)
            if check.receiptIDs.isEmpty {
                // Prefer the original paid date, never a redistribution date.
                let original = evidence.first { $0.id == check.sourceInvoiceID }
                return sum + ((original?.paidDate.map(interval.contains) ?? false) ? remaining : 0)
            }
            let ids = Set(check.receiptIDs)
            var seen = Set<UUID>()
            let receipts = evidence.filter { $0.id == check.sourceInvoiceID }.flatMap { $0.receipts ?? [] }
                .filter { ids.contains($0.id) && seen.insert($0.id).inserted }.sorted { $0.issuedAt < $1.issuedAt }
            return sum + receipts.reduce(0.0) { amount, receipt in
                let verified = min(remaining, max(receipt.paymentAmount, 0))
                remaining -= verified
                return amount + (interval.contains(receipt.issuedAt) ? verified : 0)
            }
        }
    }

    private static func unpooledReceipts(pool: InvoicePaymentPool, invoices: [InvoiceRecord], interval: DateInterval) -> Double {
        var events = Set(pool.verifications.flatMap(\.paymentEventIDs))
        return invoices.flatMap { $0.receipts ?? [] }.reduce(0.0) { amount, receipt in
            guard events.insert(receipt.paymentEventID).inserted, interval.contains(receipt.issuedAt) else { return amount }
            return amount + max(receipt.paymentAmount, 0)
        }
    }
}
