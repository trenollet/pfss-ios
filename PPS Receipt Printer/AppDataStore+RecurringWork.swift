//
//  AppDataStore+RecurringWork.swift
//  PPS Receipt Printer
//
//  Phase 18 – Recurring-work template lifecycle and bounded materialization.
//

import Foundation

@MainActor
extension AppDataStore {
    /// Converts the pre-Phase 18 recurring-job representation into durable
    /// templates. Existing jobs keep their identifiers and history.
    func migrateLegacyRecurringWorkIfNeeded() {
        let engine = RecurringWorkEngine()
        var migratedJobs = jobs
        var migratedTemplates = recurringWorkTemplates
        var didChangeJobs = false

        let legacyRoots = migratedJobs.filter {
            $0.lifecycleStatus == .active &&
            $0.isRecurring &&
            $0.recurrenceFrequency != nil &&
            $0.recurrenceSequence == 0
        }

        for root in legacyRoots {
            guard let frequency = root.recurrenceFrequency else { continue }
            let templateID = root.recurringWorkTemplateID
                ?? root.recurrenceSeriesID
                ?? root.id

            if migratedTemplates.contains(where: { $0.id == templateID }) == false {
                var prototype = root
                prototype.recurrenceSeriesID = templateID
                prototype.recurringWorkTemplateID = templateID
                prototype.recurringWorkOccurrenceKey = engine.occurrenceKey(
                    templateID: templateID,
                    occurrenceIndex: 0
                )
                migratedTemplates.append(
                    RecurringWorkTemplate(
                        id: templateID,
                        rule: frequency.recurringWorkRule,
                        endCondition: recurrenceEndCondition(for: root),
                        anchorDate: root.scheduledDate,
                        prototype: prototype,
                        createdAt: root.createdDate,
                        updatedAt: Date()
                    )
                )
            }

            for index in migratedJobs.indices where
                migratedJobs[index].recurrenceSeriesID == templateID ||
                migratedJobs[index].id == root.id {
                migratedJobs[index].recurrenceSeriesID = templateID
                migratedJobs[index].recurringWorkTemplateID = templateID
                migratedJobs[index].recurringWorkOccurrenceKey = engine.occurrenceKey(
                    templateID: templateID,
                    occurrenceIndex: migratedJobs[index].recurrenceSequence
                )
                didChangeJobs = true
            }
        }

        if didChangeJobs { jobs = migratedJobs }
        if migratedTemplates.map(\.id) != recurringWorkTemplates.map(\.id) {
            recurringWorkTemplates = migratedTemplates
        }
    }

    /// Creates or updates the template represented by the first job in a
    /// recurring series. Editing a generated occurrence does not silently
    /// rewrite the series.
    func upsertRecurringWorkTemplate(from job: JobRecord) {
        guard job.lifecycleStatus == .active,
              job.isRecurring,
              let frequency = job.recurrenceFrequency,
              job.recurrenceSequence == 0 else {
            if let templateID = job.recurringWorkTemplateID,
               let index = recurringWorkTemplates.firstIndex(where: {
                   $0.id == templateID
               }),
               job.isRecurring == false {
                recurringWorkTemplates[index].status = .terminated
                recurringWorkTemplates[index].revision += 1
                recurringWorkTemplates[index].updatedAt = Date()
            }
            return
        }

        let templateID = job.recurringWorkTemplateID
            ?? job.recurrenceSeriesID
            ?? job.id
        var prototype = job
        prototype.recurrenceSeriesID = templateID
        prototype.recurringWorkTemplateID = templateID
        prototype.recurringWorkOccurrenceKey = RecurringWorkEngine().occurrenceKey(
            templateID: templateID,
            occurrenceIndex: 0
        )

        if let index = recurringWorkTemplates.firstIndex(where: {
            $0.id == templateID
        }) {
            recurringWorkTemplates[index].revision += 1
            recurringWorkTemplates[index].rule = frequency.recurringWorkRule
            recurringWorkTemplates[index].endCondition = recurrenceEndCondition(for: job)
            recurringWorkTemplates[index].anchorDate = job.scheduledDate
            recurringWorkTemplates[index].prototype = prototype
            recurringWorkTemplates[index].updatedAt = Date()
        } else {
            recurringWorkTemplates.append(
                RecurringWorkTemplate(
                    id: templateID,
                    rule: frequency.recurringWorkRule,
                    endCondition: recurrenceEndCondition(for: job),
                    anchorDate: job.scheduledDate,
                    prototype: prototype,
                    createdAt: job.createdDate,
                    updatedAt: Date()
                )
            )
        }

        if let jobIndex = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[jobIndex].recurrenceSeriesID = templateID
            jobs[jobIndex].recurringWorkTemplateID = templateID
            jobs[jobIndex].recurringWorkOccurrenceKey = prototype.recurringWorkOccurrenceKey
        }
    }

    /// Maintains a finite rolling window of real Job records. Re-running this
    /// method is safe because every occurrence has a stable key and UUID.
    func materializeRecurringWorkHorizon(generatedAt: Date = Date()) {
        let engine = RecurringWorkEngine()
        var materializedJobs = jobs
        var didChangeJobs = false

        for template in recurringWorkTemplates where template.status == .active {
            // Skip decisions live on the synchronized template, while Job
            // occurrences are materialized locally on every device. A device
            // that generated an occurrence before receiving the exception
            // must remove its stale, unstarted copy when it reconciles the
            // template. Without this pass, the initiating device removes the
            // Job but another device can continue showing it indefinitely.
            let skippedIndices = Set(template.exceptions.compactMap { exception in
                exception.kind == .skipped ? exception.occurrenceIndex : nil
            })
            if !skippedIndices.isEmpty {
                let originalCount = materializedJobs.count
                materializedJobs.removeAll { job in
                    job.recurringWorkTemplateID == template.id &&
                    skippedIndices.contains(job.recurrenceSequence) &&
                    job.workflowState == .notStarted &&
                    (job.status == .toBeScheduled ||
                     job.status == .scheduled ||
                     job.status == .assigned)
                }
                didChangeJobs = didChangeJobs ||
                    materializedJobs.count != originalCount
            }

            guard let planned = try? engine.plan(
                template: template,
                generatedAt: generatedAt
            ) else { continue }

            for occurrence in planned {
                if occurrence.occurrenceIndex == 0,
                   let rootIndex = materializedJobs.firstIndex(where: {
                       $0.id == template.prototype.id ||
                       ($0.recurringWorkTemplateID == template.id &&
                        $0.recurrenceSequence == 0)
                   }) {
                    materializedJobs[rootIndex].recurrenceSeriesID = template.id
                    materializedJobs[rootIndex].recurringWorkTemplateID = template.id
                    materializedJobs[rootIndex].recurringWorkOccurrenceKey = occurrence.occurrenceKey
                    didChangeJobs = true
                    continue
                }

                if let existingIndex = materializedJobs.firstIndex(where: {
                    $0.recurringWorkOccurrenceKey == occurrence.occurrenceKey ||
                    $0.id == occurrence.jobID
                }) {
                    materializedJobs[existingIndex].recurrenceSeriesID = template.id
                    materializedJobs[existingIndex].recurringWorkTemplateID = template.id
                    materializedJobs[existingIndex].recurringWorkOccurrenceKey = occurrence.occurrenceKey
                    didChangeJobs = true
                    continue
                }

                var job = template.prototype
                job.id = occurrence.jobID
                job.jobNumber = recurringJobNumber(
                    template: template,
                    occurrenceIndex: occurrence.occurrenceIndex
                )
                job.scheduledDate = occurrence.scheduledDate
                job.arrivalWindowEnd = recurringShiftedDate(
                    template.prototype.arrivalWindowEnd,
                    toDayContaining: occurrence.scheduledDate
                )
                job.completionDeadline = recurringShiftedDate(
                    template.prototype.completionDeadline,
                    toDayContaining: occurrence.scheduledDate
                )
                job.setupStartDate = nil
                job.completedDate = nil
                job.status = .toBeScheduled
                job.workflowState = .notStarted
                job.timelineEvents = []
                job.createdDate = template.createdAt
                job.lifecycleStatus = .active
                job.recurrenceSeriesID = template.id
                job.recurrenceSequence = occurrence.occurrenceIndex
                job.recurringWorkTemplateID = template.id
                job.recurringWorkOccurrenceKey = occurrence.occurrenceKey
                materializedJobs.append(job)
                didChangeJobs = true
            }
        }

        if didChangeJobs {
            jobs = materializedJobs
            synchronizeAssignmentsFromJobs()
        }
    }

    func pauseRecurringWork(templateID: UUID) {
        updateRecurringWorkStatus(templateID: templateID, status: .paused)
    }

    func resumeRecurringWork(templateID: UUID) {
        updateRecurringWorkStatus(templateID: templateID, status: .active)
        materializeRecurringWorkHorizon()
    }

    func updateRecurringWorkSeries(
        templateID: UUID,
        frequency: JobRecurrenceFrequency,
        endMode: JobRecurrenceEndMode,
        endDate: Date?,
        occurrenceCount: Int?,
        siteID: UUID?
    ) {
        guard let templateIndex = recurringWorkTemplates.firstIndex(where: {
            $0.id == templateID
        }) else { return }

        let previousRule = recurringWorkTemplates[templateIndex].rule

        let updatedEndCondition: RecurringWorkEndCondition
        switch endMode {
        case .noEnd:
            updatedEndCondition = .noEnd
        case .endDate:
            updatedEndCondition = .endDate(
                endDate ?? recurringWorkTemplates[templateIndex].anchorDate
            )
        case .occurrenceCount:
            updatedEndCondition = .occurrenceCount(
                max(occurrenceCount ?? 1, 1)
            )
        }

        recurringWorkTemplates[templateIndex].rule = frequency.recurringWorkRule
        recurringWorkTemplates[templateIndex].endCondition = updatedEndCondition
        recurringWorkTemplates[templateIndex].prototype.recurrenceFrequency = frequency
        recurringWorkTemplates[templateIndex].prototype.recurrenceEndMode = endMode
        recurringWorkTemplates[templateIndex].prototype.recurrenceEndDate = endDate
        recurringWorkTemplates[templateIndex].prototype.recurrenceOccurrenceCount = occurrenceCount
        recurringWorkTemplates[templateIndex].prototype.siteID = siteID
        if previousRule != frequency.recurringWorkRule {
            // A skip belongs to a position in the old schedule. Retaining it
            // after a frequency change could silently skip a different date in
            // the newly rebuilt routine.
            recurringWorkTemplates[templateIndex].exceptions = []
        }
        recurringWorkTemplates[templateIndex].revision += 1
        recurringWorkTemplates[templateIndex].updatedAt = Date()

        let jobsToReplace = jobs.filter {
            isReplaceableRecurringOccurrence($0, templateID: templateID)
        }
        let replacedJobIDs = Set(jobsToReplace.map(\.id))

        // The rule is authoritative. Remove the complete unstarted schedule,
        // including occurrence zero, then materialize a fresh routine from the
        // updated template. In-progress and completed Jobs are never selected.
        jobs.removeAll { replacedJobIDs.contains($0.id) }
        removeAssignments(forJobIDs: replacedJobIDs)

        materializeRecurringWorkHorizon()
        synchronizeAssignmentsFromJobs()
    }

    private func isReplaceableRecurringOccurrence(
        _ job: JobRecord,
        templateID: UUID
    ) -> Bool {
        job.recurringWorkTemplateID == templateID &&
            job.workflowState == .notStarted &&
            (job.status == .toBeScheduled ||
             job.status == .scheduled ||
             job.status == .assigned)
    }

    private func removeAssignments(forJobIDs jobIDs: Set<UUID>) {
        guard !jobIDs.isEmpty else { return }

        let assignmentIDs = assignmentStore.assignments.compactMap { assignment in
            jobIDs.contains(assignment.jobID) ? assignment.id : nil
        }
        for assignmentID in assignmentIDs {
            _ = try? assignmentStore.delete(id: assignmentID)
        }
    }

    /// Stops future generation and removes only unstarted future occurrences.
    /// Completed and in-progress history is never rewritten.
    func terminateRecurringWork(templateID: UUID, asOf date: Date = Date()) {
        updateRecurringWorkStatus(templateID: templateID, status: .terminated)
        jobs.removeAll {
            $0.recurringWorkTemplateID == templateID &&
            $0.scheduledDate > date &&
            $0.workflowState == .notStarted &&
            ($0.status == .toBeScheduled ||
             $0.status == .scheduled ||
             $0.status == .assigned)
        }
        synchronizeAssignmentsFromJobs()
    }

    func skipRecurringOccurrence(
        jobID: UUID,
        reason: String,
        addReplacementToSeriesEnd: Bool = false,
        at date: Date = Date()
    ) {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let templateID = job.recurringWorkTemplateID,
              let templateIndex = recurringWorkTemplates.firstIndex(where: {
                  $0.id == templateID
              }),
              job.workflowState == .notStarted,
              job.status == .toBeScheduled ||
              job.status == .scheduled ||
              job.status == .assigned else {
            return
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if addReplacementToSeriesEnd {
            recurringWorkTemplates[templateIndex].endCondition =
                extendedRecurringWorkEndCondition(
                    recurringWorkTemplates[templateIndex].endCondition,
                    rule: recurringWorkTemplates[templateIndex].rule
                )
        }
        recurringWorkTemplates[templateIndex].exceptions.append(
            RecurringWorkOccurrenceException(
                occurrenceIndex: job.recurrenceSequence,
                kind: .skipped,
                reason: trimmedReason.isEmpty ? "Skipped by an authorized user." : trimmedReason,
                createdAt: date
            )
        )
        recurringWorkTemplates[templateIndex].revision += 1
        recurringWorkTemplates[templateIndex].updatedAt = date
        jobs.removeAll { $0.id == jobID }
        materializeRecurringWorkHorizon()
        synchronizeAssignmentsFromJobs()
    }

    private func extendedRecurringWorkEndCondition(
        _ endCondition: RecurringWorkEndCondition,
        rule: RecurringWorkRule,
        calendar: Calendar = .current
    ) -> RecurringWorkEndCondition {
        switch endCondition {
        case .noEnd:
            // The next occurrence already exists conceptually in an open-ended
            // series, so no boundary needs to move.
            return .noEnd
        case let .occurrenceCount(count):
            return .occurrenceCount(count + 1)
        case let .endDate(endDate):
            let component: Calendar.Component
            switch rule.unit {
            case .day: component = .day
            case .week: component = .weekOfYear
            case .month: component = .month
            case .year: component = .year
            }
            let extended = calendar.date(
                byAdding: component,
                value: rule.interval,
                to: endDate
            ) ?? endDate
            return .endDate(extended)
        }
    }

    private func updateRecurringWorkStatus(
        templateID: UUID,
        status: RecurringWorkTemplateStatus
    ) {
        guard let index = recurringWorkTemplates.firstIndex(where: {
            $0.id == templateID
        }) else { return }
        recurringWorkTemplates[index].status = status
        recurringWorkTemplates[index].revision += 1
        recurringWorkTemplates[index].updatedAt = Date()
    }

    private func recurringShiftedDate(
        _ source: Date?,
        toDayContaining target: Date
    ) -> Date? {
        guard let source else { return nil }
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: target
        )
    }

    private func recurrenceEndCondition(
        for job: JobRecord
    ) -> RecurringWorkEndCondition {
        switch job.recurrenceEndMode {
        case .noEnd:
            return .noEnd
        case .endDate:
            return .endDate(job.recurrenceEndDate ?? job.scheduledDate)
        case .occurrenceCount:
            return .occurrenceCount(max(job.recurrenceOccurrenceCount ?? 1, 1))
        }
    }

    private func recurringJobNumber(
        template: RecurringWorkTemplate,
        occurrenceIndex: Int
    ) -> String {
        "\(template.prototype.jobNumber)-R\(String(format: "%03d", occurrenceIndex))"
    }
}
