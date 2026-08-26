import Foundation
import Testing
@testable import PPS_Receipt_Printer

struct RecurringWorkEngineTests {
    private let engine = RecurringWorkEngine()

    @Test func repeatedPlanningProducesStableOccurrenceKeysAndJobIDs() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        let generatedAt = try testDate(year: 2026, month: 8, day: 7)
        let template = makeTemplate(anchor: anchor, rule: .weekly)

        let first = try engine.plan(
            template: template,
            generatedAt: generatedAt,
            calendar: testCalendar
        )
        let retry = try engine.plan(
            template: template,
            generatedAt: generatedAt,
            calendar: testCalendar
        )

        #expect(first.map(\.occurrenceKey) == retry.map(\.occurrenceKey))
        #expect(first.map(\.jobID) == retry.map(\.jobID))
        #expect(Set(first.map(\.jobID)).count == first.count)
    }

    @Test func occurrenceCountEndsSeriesExactly() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.endCondition = .occurrenceCount(3)
        template.generationHorizonDays = 365

        let result = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )

        #expect(result.map(\.occurrenceIndex) == [0, 1, 2])
    }

    @Test func skippedOccurrenceIsNotRegenerated() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.exceptions = [
            RecurringWorkOccurrenceException(
                occurrenceIndex: 1,
                kind: .skipped,
                reason: "Customer requested a skip."
            )
        ]

        let result = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )

        #expect(result.contains(where: { $0.occurrenceIndex == 1 }) == false)
        #expect(result.contains(where: { $0.occurrenceIndex == 2 }))
    }

    @Test func pausedTemplateGeneratesNothing() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.status = .paused

        let result = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )

        #expect(result.isEmpty)
    }

    @Test func heldTemplateGeneratesNothing() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.status = .held

        let result = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )

        #expect(result.isEmpty)
    }

    @Test func resumedScheduleStartsAtHeldOccurrenceIndex() throws {
        let anchor = try testDate(year: 2026, month: 9, day: 1)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.scheduleStartIndex = 3
        template.endCondition = .occurrenceCount(6)

        let result = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 9, day: 1),
            calendar: testCalendar
        )

        #expect(result.map(\.occurrenceIndex) == [3, 4, 5])
        #expect(result.first?.scheduledDate == anchor)
    }

    @MainActor
    @Test func synchronizedSkipPrunesStaleUnstartedOccurrence() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.endCondition = .occurrenceCount(3)
        template.exceptions = [
            RecurringWorkOccurrenceException(
                occurrenceIndex: 1,
                kind: .skipped,
                reason: "Skipped on another device."
            )
        ]
        let planned = try engine.plan(
            template: makeTemplate(anchor: anchor, rule: .weekly),
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )
        let staleOccurrence = try #require(
            planned.first(where: { $0.occurrenceIndex == 1 })
        )
        var staleJob = template.prototype
        staleJob.id = staleOccurrence.jobID
        staleJob.recurrenceSeriesID = template.id
        staleJob.recurringWorkTemplateID = template.id
        staleJob.recurringWorkOccurrenceKey = staleOccurrence.occurrenceKey
        staleJob.recurrenceSequence = staleOccurrence.occurrenceIndex
        staleJob.scheduledDate = staleOccurrence.scheduledDate
        staleJob.status = .assigned
        staleJob.workflowState = .notStarted

        let store = AppDataStore(persistenceEnabled: false)
        store.recurringWorkTemplates = [template]
        store.jobs = [staleJob]

        store.materializeRecurringWorkHorizon(
            generatedAt: try testDate(year: 2026, month: 8, day: 7)
        )

        #expect(store.jobs.contains(where: { $0.id == staleJob.id }) == false)
        #expect(store.jobs.contains(where: {
            $0.recurringWorkTemplateID == template.id &&
            $0.recurrenceSequence == 2
        }))
    }

    @MainActor
    @Test func synchronizedHoldPrunesRemoteUnstartedCopies() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.status = .held
        template.heldOccurrenceIndex = 1

        var completed = template.prototype
        completed.recurringWorkTemplateID = template.id
        completed.recurrenceSequence = 0
        completed.workflowState = .completed
        completed.status = .completed

        var stale = template.prototype
        stale.id = UUID()
        stale.recurringWorkTemplateID = template.id
        stale.recurrenceSequence = 1
        stale.workflowState = .notStarted
        stale.status = .assigned

        let store = AppDataStore(persistenceEnabled: false)
        store.recurringWorkTemplates = [template]
        store.jobs = [completed, stale]

        store.materializeRecurringWorkHorizon(
            generatedAt: try testDate(year: 2026, month: 8, day: 7)
        )

        #expect(store.jobs.contains(where: { $0.id == completed.id }))
        #expect(store.jobs.contains(where: { $0.id == stale.id }) == false)
    }

    @Test func monthlySeriesClampsToShorterMonth() throws {
        let anchor = try testDate(year: 2027, month: 1, day: 29)
        var template = makeTemplate(anchor: anchor, rule: .monthly)
        template.endCondition = .occurrenceCount(2)

        let result = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2027, month: 1, day: 28),
            calendar: testCalendar
        )
        let second = try #require(result.first(where: { $0.occurrenceIndex == 1 }))
        let parts = testCalendar.dateComponents([.year, .month, .day], from: second.scheduledDate)

        #expect(parts.year == 2027)
        #expect(parts.month == 3)
        #expect(parts.day == 1) // Feb 28 is Sunday, so PFSS moves it to Monday.
    }

    @Test func seriesEditorFirstPresentationUsesStoredSeriesValues() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        let siteID = UUID()
        var template = makeTemplate(anchor: anchor, rule: .monthly)
        template.prototype.siteID = siteID
        template.endCondition = .occurrenceCount(9)

        let state = RecurringWorkSeriesEditorState(template: template)

        #expect(state.frequency == .monthly)
        #expect(state.endMode == .occurrenceCount)
        #expect(state.occurrenceCount == 9)
        #expect(state.endDate == nil)
        #expect(state.siteID == siteID)
    }

    @MainActor
    @Test func seriesSiteUpdateChangesOnlyUnstartedOccurrences() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.endCondition = .occurrenceCount(3)
        let originalSiteID = UUID()
        let replacementSiteID = UUID()
        template.prototype.siteID = originalSiteID

        var root = template.prototype
        root.recurringWorkTemplateID = template.id
        root.recurrenceSeriesID = template.id
        root.recurrenceSequence = 0
        root.workflowState = .notStarted
        root.status = .scheduled

        var completed = template.prototype
        completed.id = UUID()
        completed.recurringWorkTemplateID = template.id
        completed.recurrenceSeriesID = template.id
        completed.recurrenceSequence = 1
        completed.workflowState = .completed
        completed.status = .completed

        let store = AppDataStore(persistenceEnabled: false)
        store.recurringWorkTemplates = [template]
        store.jobs = [root, completed]

        store.updateRecurringWorkSeries(
            templateID: template.id,
            frequency: .weekly,
            endMode: .occurrenceCount,
            endDate: nil,
            occurrenceCount: 3,
            siteID: replacementSiteID
        )

        #expect(store.recurringWorkTemplates.first?.prototype.siteID == replacementSiteID)
        #expect(store.jobs.contains(where: { $0.id == root.id }) == false)
        #expect(store.jobs.first(where: { $0.id == completed.id })?.siteID == originalSiteID)
        #expect(store.jobs.filter {
            $0.recurringWorkTemplateID == template.id &&
            $0.workflowState == .notStarted
        }.allSatisfy { $0.siteID == replacementSiteID })
    }

    @MainActor
    @Test func frequencyChangeRebuildsEveryUnstartedOccurrence() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.endCondition = .occurrenceCount(4)

        let oldPlan = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )
        var oldJobs = oldPlan.map { occurrence in
            var job = template.prototype
            job.id = occurrence.jobID
            job.recurringWorkTemplateID = template.id
            job.recurrenceSeriesID = template.id
            job.recurringWorkOccurrenceKey = occurrence.occurrenceKey
            job.recurrenceSequence = occurrence.occurrenceIndex
            job.scheduledDate = occurrence.scheduledDate
            job.workflowState = .notStarted
            job.status = .scheduled
            return job
        }
        var completed = oldJobs.removeFirst()
        completed.id = UUID()
        completed.workflowState = .completed
        completed.status = .completed
        let oldFutureDates = Set(oldJobs.map(\.scheduledDate))

        let store = AppDataStore(persistenceEnabled: false)
        store.recurringWorkTemplates = [template]
        store.jobs = [completed] + oldJobs

        store.updateRecurringWorkSeries(
            templateID: template.id,
            frequency: .monthly,
            endMode: .occurrenceCount,
            endDate: nil,
            occurrenceCount: 4,
            siteID: nil
        )

        #expect(store.jobs.contains(where: { $0.id == completed.id }))
        #expect(store.recurringWorkTemplates.first?.rule == .monthly)
        let rebuiltJobs = store.jobs.filter {
            $0.recurringWorkTemplateID == template.id &&
            $0.workflowState == .notStarted
        }
        #expect(rebuiltJobs.allSatisfy { $0.recurrenceFrequency == .monthly })
        #expect(rebuiltJobs.contains(where: {
            oldFutureDates.contains($0.scheduledDate)
        }) == false)
    }

    @MainActor
    @Test func holdAndReleaseRebuildsOnlyRemainingUnstartedWork() throws {
        let anchor = try testDate(year: 2026, month: 8, day: 10)
        var template = makeTemplate(anchor: anchor, rule: .weekly)
        template.endCondition = .occurrenceCount(4)
        template.generationHorizonDays = 365

        let oldPlan = try engine.plan(
            template: template,
            generatedAt: try testDate(year: 2026, month: 8, day: 7),
            calendar: testCalendar
        )
        var oldJobs = oldPlan.map { occurrence in
            var job = template.prototype
            job.id = occurrence.jobID
            job.recurringWorkTemplateID = template.id
            job.recurrenceSeriesID = template.id
            job.recurringWorkOccurrenceKey = occurrence.occurrenceKey
            job.recurrenceSequence = occurrence.occurrenceIndex
            job.scheduledDate = occurrence.scheduledDate
            job.workflowState = .notStarted
            job.status = .scheduled
            return job
        }
        oldJobs[0].workflowState = .completed
        oldJobs[0].status = .completed
        let completedID = oldJobs[0].id
        let selectedID = oldJobs[1].id

        let store = AppDataStore(persistenceEnabled: false)
        store.recurringWorkTemplates = [template]
        store.jobs = oldJobs

        store.holdRecurringWork(
            templateID: template.id,
            fromJobID: selectedID,
            at: try testDate(year: 2026, month: 8, day: 12)
        )

        #expect(store.recurringWorkTemplates.first?.status == .held)
        #expect(store.jobs.map(\.id) == [completedID])

        let releaseDate = try testDate(year: 2026, month: 9, day: 1)
        store.releaseRecurringWork(templateID: template.id, at: releaseDate)

        #expect(store.recurringWorkTemplates.first?.status == .active)
        #expect(store.jobs.contains(where: { $0.id == completedID }))
        let rebuilt = store.jobs.filter { $0.workflowState == .notStarted }
            .sorted { $0.recurrenceSequence < $1.recurrenceSequence }
        #expect(rebuilt.map(\.recurrenceSequence) == [1, 2, 3])
        #expect(rebuilt.first?.scheduledDate == releaseDate)
    }

    @MainActor
    @Test func movingOneOccurrenceDoesNotChangeTemplateOrFutureJobs() throws {
        let originalDate = try testDate(year: 2026, month: 8, day: 10)
        let futureDate = try testDate(year: 2026, month: 8, day: 17)
        let movedDate = try testDate(year: 2026, month: 8, day: 11)
        let template = makeTemplate(anchor: originalDate, rule: .weekly)

        var selected = template.prototype
        selected.recurringWorkTemplateID = template.id
        selected.recurrenceSeriesID = template.id
        selected.recurrenceSequence = 0

        var future = template.prototype
        future.id = UUID()
        future.recurringWorkTemplateID = template.id
        future.recurrenceSeriesID = template.id
        future.recurrenceSequence = 1
        future.scheduledDate = futureDate

        let store = AppDataStore(persistenceEnabled: false)
        store.recurringWorkTemplates = [template]
        store.jobs = [selected, future]

        var moved = selected
        moved.assignmentSchedulingMode = .fixedTime
        moved.scheduledDate = movedDate

        #expect(store.updateSingleJobOccurrenceSchedule(moved))
        #expect(store.jobs.first(where: { $0.id == selected.id })?.scheduledDate == movedDate)
        #expect(store.jobs.first(where: { $0.id == future.id })?.scheduledDate == futureDate)
        #expect(store.recurringWorkTemplates.first?.anchorDate == originalDate)
        #expect(store.recurringWorkTemplates.first?.prototype.scheduledDate == originalDate)
        #expect(store.assignment(forJobID: selected.id)?.scheduling.fixedStartDate == movedDate)
    }

    private func makeTemplate(
        anchor: Date,
        rule: RecurringWorkRule
    ) -> RecurringWorkTemplate {
        RecurringWorkTemplate(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            rule: rule,
            anchorDate: anchor,
            generationHorizonDays: 120,
            prototype: JobRecord(
                jobNumber: "JOB-TEST-001",
                customerNumber: "CUSTOMER-001",
                siteID: nil,
                estimateNumber: "",
                serviceType: .other,
                otherService: "Routine Service",
                subtotal: 100,
                discount: 0,
                total: 100,
                primaryTechnicianID: nil,
                secondaryTechnicianID: nil,
                scheduledDate: anchor,
                completedDate: nil,
                status: .scheduled,
                workNotes: "",
                isRecurring: true,
                recurrenceFrequency: .weekly,
                createdDate: anchor
            )
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDate(
        year: Int,
        month: Int,
        day: Int
    ) throws -> Date {
        try #require(testCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 9
        )))
    }
}
