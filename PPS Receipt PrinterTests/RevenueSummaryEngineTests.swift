import XCTest
@testable import PPS_Receipt_Printer

final class RevenueSummaryEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testForecastQuarterBoundariesAreFixedCalendarQuarters() throws {
        for (month, firstMonth, lastMonth, quarter) in [
            (1, 1, 3, "Q1"), (3, 1, 3, "Q1"),
            (4, 4, 6, "Q2"), (6, 4, 6, "Q2"),
            (7, 7, 9, "Q3"), (9, 7, 9, "Q3"),
            (10, 10, 12, "Q4"), (12, 10, 12, "Q4")
        ] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: 15)))
            let interval = RevenueForecastPeriod.quarterly.dateInterval(now: now, calendar: calendar)
            XCTAssertEqual(interval.start, calendar.date(from: DateComponents(year: 2026, month: firstMonth, day: 1)))
            let expectedEnd = calendar.date(from: DateComponents(year: lastMonth == 12 ? 2027 : 2026,
                month: lastMonth == 12 ? 1 : lastMonth + 1, day: 1))
            XCTAssertEqual(interval.end, expectedEnd)
            XCTAssertTrue(RevenueForecastPeriod.quarterly.subtitle(now: now, calendar: calendar).hasPrefix(quarter))
        }
    }

    func testForecastUsesFutureScheduledJobValuesOnceAndExcludesStartedOrUnscheduledWork() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12)))
        func at(_ day: Int, _ month: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
        }
        let today = forecastJob("TODAY", amount: 100, date: at(16), status: .scheduled)
        let upcoming = forecastJob("UPCOMING", amount: 250, date: at(30), status: .assigned)
        var started = forecastJob("STARTED", amount: 300, date: at(20), status: .inProgress)
        started.workflowState = .working
        var inconsistentStarted = forecastJob("STARTED-STATUS", amount: 310, date: at(20), status: .scheduled)
        inconsistentStarted.workflowState = .settingUp
        var archived = forecastJob("ARCHIVED", amount: 400, date: at(20), status: .scheduled)
        archived.lifecycleStatus = .archived
        var duplicate = today
        duplicate.total = 999
        let jobs = [today, upcoming, started, inconsistentStarted, archived, duplicate,
            forecastJob("OVERDUE", amount: 500, date: at(15), status: .scheduled),
            forecastJob("UNSCHEDULED", amount: 600, date: at(18), status: .toBeScheduled),
            forecastJob("COMPLETED", amount: 700, date: at(18), status: .completed),
            forecastJob("CANCELLED", amount: 800, date: at(18), status: .cancelled),
            forecastJob("NEXT-QUARTER", amount: 900, date: at(1, 10), status: .scheduled)]
        let month = RevenueForecastEngine.forecast(for: .monthly, jobs: jobs, now: now, calendar: calendar)
        XCTAssertEqual(month.amount, 350)
        XCTAssertEqual(month.jobs.map(\.jobNumber), ["TODAY", "UPCOMING"])
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .quarterly, jobs: jobs, now: now, calendar: calendar).amount, 350)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .annual, jobs: jobs, now: now, calendar: calendar).amount, 1250)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .weekly, jobs: jobs, now: now, calendar: calendar).amount, 100)
    }

    func testForecastDetailPeriodsRollAcrossYearWithoutOverlapping() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12)))
        let expectations: [(RevenueForecastPeriod, Int, [DateComponents])] = [
            (.weekly, 5, [
                DateComponents(year: 2026, month: 12, day: 27),
                DateComponents(year: 2027, month: 1, day: 3),
                DateComponents(year: 2027, month: 1, day: 10),
                DateComponents(year: 2027, month: 1, day: 17),
                DateComponents(year: 2027, month: 1, day: 24)
            ]),
            (.monthly, 3, [
                DateComponents(year: 2026, month: 12, day: 1),
                DateComponents(year: 2027, month: 1, day: 1),
                DateComponents(year: 2027, month: 2, day: 1)
            ]),
            (.quarterly, 4, [
                DateComponents(year: 2026, month: 10, day: 1),
                DateComponents(year: 2027, month: 1, day: 1),
                DateComponents(year: 2027, month: 4, day: 1),
                DateComponents(year: 2027, month: 7, day: 1)
            ]),
            (.annual, 3, [
                DateComponents(year: 2026, month: 1, day: 1),
                DateComponents(year: 2027, month: 1, day: 1),
                DateComponents(year: 2028, month: 1, day: 1)
            ])
        ]
        for (period, count, starts) in expectations {
            XCTAssertEqual(period.numberOfPeriods, count)
            let intervals = (0..<count).map { period.dateInterval(now: now, calendar: calendar, offset: $0) }
            for index in intervals.indices {
                XCTAssertEqual(intervals[index].start, calendar.date(from: starts[index]))
                if index > 0 { XCTAssertEqual(intervals[index - 1].end, intervals[index].start) }
            }
        }
    }

    func testFuturePeriodForecastsUseTheirOwnFullDates() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12)))
        func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
        }
        let jobs = [
            forecastJob("CURRENT", amount: 100, date: at(2026, 12, 31), status: .scheduled),
            forecastJob("NEXT", amount: 200, date: at(2027, 1, 1), status: .assigned),
            forecastJob("THIRD", amount: 300, date: at(2027, 2, 1), status: .scheduled),
            forecastJob("FOURTH-QUARTER", amount: 400, date: at(2027, 7, 1), status: .scheduled)
        ]
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .monthly, jobs: jobs, now: now, calendar: calendar).amount, 100)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .monthly, jobs: jobs, now: now, calendar: calendar, offset: 1).amount, 200)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .monthly, jobs: jobs, now: now, calendar: calendar, offset: 2).amount, 300)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .quarterly, jobs: jobs, now: now, calendar: calendar, offset: 1).amount, 500)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .quarterly, jobs: jobs, now: now, calendar: calendar, offset: 3).amount, 400)
        XCTAssertEqual(RevenueForecastEngine.forecast(for: .annual, jobs: jobs, now: now, calendar: calendar, offset: 1).amount, 900)
        XCTAssertEqual(RevenueForecastPeriod.quarterly.label(offset: 1, now: now, calendar: calendar), "Next Quarter")
        XCTAssertEqual(RevenueForecastPeriod.quarterly.label(offset: 2, now: now, calendar: calendar), "Q2 2027")
    }

    func testWeeklyPeriodRunsSundayThroughSaturday() throws {
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))
        )
        let interval = RevenueSummaryPeriod.weekly.dateInterval(
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            interval.start,
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))
        )
        XCTAssertEqual(
            interval.end,
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))
        )
    }

    func testMonthToDateExcludesFutureAndPriorMonthRevenue() throws {
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))
        )
        let july = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))
        )
        let august = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))
        )
        let future = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 12))
        )

        let invoices = [
            invoice(number: "JULY", amount: 100, date: july),
            invoice(number: "AUGUST", amount: 250, date: august),
            invoice(number: "FUTURE", amount: 400, date: future),
        ]

        let summary = RevenueSummaryEngine.summary(
            for: .monthly,
            jobs: [],
            invoices: invoices,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.invoiced, 250)
        XCTAssertEqual(summary.collected, 250)
        XCTAssertEqual(summary.outstanding, 0)
    }

    func testOutstandingUsesCurrentInvoiceBalance() throws {
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))
        )
        var partiallyPaid = invoice(number: "PARTIAL", amount: 500, date: now)
        partiallyPaid.amountPaid = 325
        partiallyPaid.balanceDue = 175
        partiallyPaid.status = .partiallyPaid

        let summary = RevenueSummaryEngine.summary(
            for: .daily,
            jobs: [],
            invoices: [partiallyPaid],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.invoiced, 500)
        XCTAssertEqual(summary.outstanding, 175)
    }

    @MainActor
    func testCombiningDoesNotRedateOrDoubleCountVerifiedCollection() throws {
        let oldDate = Date(timeIntervalSince1970: 1_780_000_000)
        let today = oldDate.addingTimeInterval(10 * 86400)
        var a = invoice(number: "A", amount: 100, date: oldDate)
        var b = invoice(number: "B", amount: 200, date: oldDate)
        b.amountPaid = 0; b.paidDate = nil; b.status = .draft; b.balanceDue = 200
        let check = InvoiceCollectionVerification(id: UUID(), sourceInvoiceID: a.id,
            recordedAmount: 100, collectedAmount: 100, receiptIDs: [], paymentEventIDs: [],
            verifiedBy: "Member", verifiedAt: today, note: "Collected")
        let proposal = try InvoiceCombinationEngine.propose(invoiceNumber: "NEW-C",
            billingCustomerNumber: "CUS-1", sources: [a, b], verifications: [check], preparedBy: "Member")
        var combined = invoice(number: "NEW-C", amount: 300, date: today)
        combined.id = proposal.id; combined.combination = proposal
        combined.amountPaid = 100; combined.balanceDue = 200; combined.status = .partiallyPaid
        a.status = .void; a.combinedIntoInvoiceID = combined.id
        b.status = .void; b.combinedIntoInvoiceID = combined.id
        let bills = [a, b, combined]
        XCTAssertEqual(RevenueSummaryEngine.summary(for: .daily, jobs: [], invoices: bills,
            now: today, calendar: calendar).collected, 0)
        XCTAssertEqual(RevenueSummaryEngine.summary(for: .daily, jobs: [], invoices: bills,
            now: oldDate, calendar: calendar).collected, 100)
        XCTAssertEqual(RevenueSummaryEngine.summary(for: .daily, jobs: [], invoices: bills,
            now: today, calendar: calendar).invoiced, 300)
    }

    private func invoice(number: String, amount: Double, date: Date) -> InvoiceRecord {
        InvoiceRecord(
            invoiceNumber: number,
            customerNumber: "CUS-1",
            siteID: nil,
            jobNumber: "JOB-1",
            lineItems: [],
            subtotal: amount,
            discount: 0,
            total: amount,
            amountPaid: amount,
            balanceDue: 0,
            status: .paid,
            issueDate: date,
            dueDate: date,
            paidDate: date,
            notes: ""
        )
    }

    private func forecastJob(_ number: String, amount: Double, date: Date, status: JobStatus) -> JobRecord {
        JobRecord(jobNumber: number, customerNumber: "CUS-1", siteID: nil,
            estimateNumber: "", serviceType: .other, otherService: "Test", lineItems: [],
            subtotal: amount, discount: 0, total: amount, primaryTechnicianID: nil,
            secondaryTechnicianID: nil, scheduledDate: date, completedDate: nil,
            status: status, workNotes: "", isRecurring: false, createdDate: date)
    }
}
