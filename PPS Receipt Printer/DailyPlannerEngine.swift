//
//  DailyPlannerEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.3 – Daily Planner Engine
//

import Foundation

/// Builds a deterministic, non-mutating technician-day proposal from existing
/// Assignment constraints.
///
/// Planning order is intentionally stable:
/// 1. Preserve fixed commitments.
/// 2. Place lunch around fixed work.
/// 3. Place arrival-window and deadline work by earliest constraint.
/// 4. Fill remaining capacity with flexible-day work.
///
/// Route geography and traffic are intentionally deferred to Step 4.
struct DailyPlannerEngine {
    let configuration: DailyPlannerConfiguration
    let calendar: Calendar

    init(
        configuration: DailyPlannerConfiguration = DailyPlannerConfiguration(),
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.calendar = calendar
    }

    func plan(
        for technician: EmployeeRecord,
        on date: Date,
        assignments: [Assignment]
    ) -> DailyPlan {
        let planningDate = calendar.startOfDay(for: date)

        guard technician.isActive,
              technician.lifecycleStatus == .active else {
            return unavailablePlan(
                technician: technician,
                date: planningDate,
                kind: .inactiveTechnician,
                message: "\(technician.displayName) is inactive and cannot receive a daily plan."
            )
        }

        guard SchedulingCalculator.isWorkingDay(
            planningDate,
            for: technician,
            calendar: calendar
        ) else {
            return unavailablePlan(
                technician: technician,
                date: planningDate,
                kind: .nonWorkingDay,
                message: "\(technician.displayName) is not scheduled to work on this day."
            )
        }

        guard let workdayStart = dateAtMinutesAfterMidnight(
            atMinutesAfterMidnight: technician.defaultStartMinutes,
            on: planningDate
        ),
        let workdayEnd = dateAtMinutesAfterMidnight(
            atMinutesAfterMidnight: technician.defaultEndMinutes,
            on: planningDate
        ),
        workdayStart < workdayEnd else {
            return unavailablePlan(
                technician: technician,
                date: planningDate,
                kind: .nonWorkingDay,
                message: "The technician's configured workday has no usable time."
            )
        }

        let relevantAssignments = assignments
            .filter { isPlannable($0, for: technician) }
            .filter { occurs($0, on: planningDate) }

        var state = PlanningState()

        let invalidAssignments = relevantAssignments.filter {
            !$0.scheduling.isValid
        }

        for assignment in invalidAssignments.sorted(by: stableAssignmentOrder) {
            state.unplaced.insert(assignment.id)
            state.conflicts.append(
                PlanningConflict(
                    kind: .invalidScheduling,
                    severity: .error,
                    message: "\(assignment.assignmentNumber) has incomplete or invalid scheduling constraints.",
                    assignmentID: assignment.id,
                    conflictingAssignmentID: nil
                )
            )
        }

        let validAssignments = relevantAssignments.filter {
            $0.scheduling.isValid
        }

        let fixedAssignments = validAssignments
            .filter { $0.scheduling.mode == .fixedTime }
            .sorted(by: fixedCommitmentOrder)

        for assignment in fixedAssignments {
            placeFixedCommitment(
                assignment,
                technician: technician,
                workdayStart: workdayStart,
                workdayEnd: workdayEnd,
                state: &state
            )
        }

        placeLunch(
            for: technician,
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            state: &state
        )

        let constrainedAssignments = validAssignments
            .filter {
                $0.scheduling.mode == .arrivalWindow ||
                $0.scheduling.mode == .deadline
            }
            .sorted(by: constrainedAssignmentOrder)

        for assignment in constrainedAssignments {
            placeConstrainedAssignment(
                assignment,
                technician: technician,
                planningDate: planningDate,
                workdayStart: workdayStart,
                workdayEnd: workdayEnd,
                state: &state
            )
        }

        let flexibleAssignments = validAssignments
            .filter { $0.scheduling.mode == .flexibleDay }
            .sorted(by: flexibleAssignmentOrder)

        for assignment in flexibleAssignments {
            placeFlexibleAssignment(
                assignment,
                technician: technician,
                workdayStart: workdayStart,
                workdayEnd: workdayEnd,
                state: &state
            )
        }

        appendCapacityConflictIfNeeded(
            technician: technician,
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            state: &state
        )

        let orderedItems = state.items.sorted(by: planItemOrder)
        let openWindows = calculateOpenWindows(
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            occupied: state.busy
        )

        return DailyPlan(
            technicianID: technician.id,
            date: planningDate,
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            items: orderedItems,
            openWindows: openWindows,
            conflicts: deduplicatedConflicts(state.conflicts.sorted(by: conflictOrder)),
            recommendations: state.recommendations,
            unplacedAssignmentIDs: state.unplaced.sorted {
                $0.uuidString < $1.uuidString
            },
            dailyReserveMinutes: configuration.effectiveDailyReserveMinutes
        )
    }

    // MARK: - Fixed Commitments

    private func placeFixedCommitment(
        _ assignment: Assignment,
        technician: EmployeeRecord,
        workdayStart: Date,
        workdayEnd: Date,
        state: inout PlanningState
    ) {
        guard let serviceStart = assignment.scheduling.fixedStartDate else {
            markUnplaced(
                assignment,
                kind: .invalidScheduling,
                message: "The fixed start is missing.",
                state: &state
            )
            return
        }

        let item = makeAssignmentItem(
            assignment,
            technicianID: technician.id,
            serviceStart: serviceStart,
            fixed: true,
            explanation: "Preserved the customer-confirmed fixed start."
        )

        if item.occupiedStart < workdayStart || item.occupiedEnd > workdayEnd {
            state.conflicts.append(
                PlanningConflict(
                    kind: .fixedCommitmentOutsideWorkday,
                    severity: .error,
                    message: "\(assignment.assignmentNumber) falls outside the technician's configured workday.",
                    assignmentID: assignment.id,
                    conflictingAssignmentID: nil
                )
            )
        }

        if let overlap = firstOverlap(with: item, in: state.busy) {
            state.conflicts.append(
                PlanningConflict(
                    kind: .fixedCommitmentOverlap,
                    severity: .error,
                    message: "\(assignment.assignmentNumber) overlaps another fixed commitment.",
                    assignmentID: assignment.id,
                    conflictingAssignmentID: overlap.assignmentID
                )
            )
        }

        append(item, to: &state)
        state.recommendations.append(
            PlanningRecommendation(
                kind: .preserveFixedCommitment,
                assignmentID: assignment.id,
                message: "Keep \(assignment.assignmentNumber) at \(shortTime(serviceStart))."
            )
        )
    }

    // MARK: - Lunch

    private func placeLunch(
        for technician: EmployeeRecord,
        workdayStart: Date,
        workdayEnd: Date,
        state: inout PlanningState
    ) {
        let duration = max(technician.lunchDurationMinutes, 0)
        guard duration > 0 else { return }

        let configuredWindowStart = dateAtMinutesAfterMidnight(
            atMinutesAfterMidnight: configuration.lunchWindowStartMinutes,
            on: workdayStart
        ) ?? workdayStart
        let configuredWindowEnd = dateAtMinutesAfterMidnight(
            atMinutesAfterMidnight: configuration.lunchWindowEndMinutes,
            on: workdayStart
        ) ?? workdayEnd
        let earliestStart = max(workdayStart, configuredWindowStart)
        let latestEnd = min(workdayEnd, configuredWindowEnd)

        guard let latestStart = calendar.date(
            byAdding: .minute,
            value: -duration,
            to: latestEnd
        ), earliestStart <= latestStart else {
            state.conflicts.append(
                PlanningConflict(
                    kind: .lunchUnavailable,
                    severity: .warning,
                    message: "The configured lunch duration does not fit inside the lunch window.",
                    assignmentID: nil,
                    conflictingAssignmentID: nil
                )
            )
            return
        }

        let preferred = dateAtMinutesAfterMidnight(
            atMinutesAfterMidnight: configuration.preferredLunchStartMinutes,
            on: workdayStart
        ) ?? earliestStart

        let candidates = candidateStarts(
            earliest: earliestStart,
            latest: latestStart
        )
        .sorted { first, second in
            let firstDistance = abs(first.timeIntervalSince(preferred))
            let secondDistance = abs(second.timeIntervalSince(preferred))
            if firstDistance != secondDistance {
                return firstDistance < secondDistance
            }
            return first < second
        }

        for start in candidates {
            guard let end = calendar.date(
                byAdding: .minute,
                value: duration,
                to: start
            ) else { continue }

            let interval = BusyInterval(
                start: start,
                end: end,
                assignmentID: nil,
                kind: .lunch
            )

            guard !overlaps(interval, any: state.busy) else { continue }

            let item = DailyPlanItem(
                kind: .lunch,
                assignmentID: nil,
                jobID: nil,
                technicianID: technician.id,
                title: "Lunch",
                schedulingMode: nil,
                serviceStart: start,
                serviceEnd: end,
                occupiedStart: start,
                occupiedEnd: end,
                isFixedCommitment: false,
                explanation: "Placed near the preferred lunch time without moving fixed work."
            )
            state.items.append(item)
            state.busy.append(interval)
            return
        }

        state.conflicts.append(
            PlanningConflict(
                kind: .lunchUnavailable,
                severity: .warning,
                message: "No conflict-free lunch opening was available between \(shortTime(earliestStart)) and \(shortTime(latestEnd)).",
                assignmentID: nil,
                conflictingAssignmentID: nil
            )
        )
    }

    // MARK: - Constrained Work

    private func placeConstrainedAssignment(
        _ assignment: Assignment,
        technician: EmployeeRecord,
        planningDate: Date,
        workdayStart: Date,
        workdayEnd: Date,
        state: inout PlanningState
    ) {
        let earliestServiceStart: Date
        let latestServiceStart: Date
        let conflictKind: PlanningConflictKind
        let recommendationKind: PlanningRecommendationKind
        let explanation: String

        switch assignment.scheduling.mode {
        case .arrivalWindow:
            guard let windowStart = assignment.scheduling.arrivalWindowStart,
                  let windowEnd = assignment.scheduling.arrivalWindowEnd else {
                markUnplaced(
                    assignment,
                    kind: .invalidScheduling,
                    message: "The arrival window is incomplete.",
                    state: &state
                )
                return
            }
            earliestServiceStart = max(windowStart, workdayStart)
            latestServiceStart = min(windowEnd, workdayEnd)
            conflictKind = .arrivalWindowUnavailable
            recommendationKind = .placeWithinArrivalWindow
            explanation = "Placed at the earliest available start inside the arrival window."

        case .deadline:
            guard let deadline = assignment.scheduling.completionDeadline,
                  let latestStart = calendar.date(
                    byAdding: .minute,
                    value: -assignment.scheduling.estimatedDurationMinutes,
                    to: deadline
                  ) else {
                markUnplaced(
                    assignment,
                    kind: .invalidScheduling,
                    message: "The completion deadline is missing.",
                    state: &state
                )
                return
            }
            earliestServiceStart = workdayStart
            latestServiceStart = min(latestStart, workdayEnd)
            conflictKind = .deadlineUnavailable
            recommendationKind = .placeBeforeDeadline
            explanation = "Placed in the earliest opening that completes before the deadline."

        default:
            return
        }

        guard let item = earliestAvailableItem(
            for: assignment,
            technicianID: technician.id,
            earliestServiceStart: earliestServiceStart,
            latestServiceStart: latestServiceStart,
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            explanation: explanation,
            state: state
        ) else {
            markUnplaced(
                assignment,
                kind: conflictKind,
                message: "No valid opening satisfies \(assignment.assignmentNumber)'s \(assignment.scheduling.mode.rawValue.lowercased()) constraint.",
                state: &state
            )
            return
        }

        append(item, to: &state)
        state.recommendations.append(
            PlanningRecommendation(
                kind: recommendationKind,
                assignmentID: assignment.id,
                message: "Place \(assignment.assignmentNumber) at \(shortTime(item.serviceStart))."
            )
        )
    }

    // MARK: - Flexible Work

    private func placeFlexibleAssignment(
        _ assignment: Assignment,
        technician: EmployeeRecord,
        workdayStart: Date,
        workdayEnd: Date,
        state: inout PlanningState
    ) {
        guard let item = earliestAvailableItem(
            for: assignment,
            technicianID: technician.id,
            earliestServiceStart: workdayStart,
            latestServiceStart: workdayEnd,
            workdayStart: workdayStart,
            workdayEnd: workdayEnd,
            explanation: "Filled the earliest open capacity on the flexible service day.",
            state: state
        ) else {
            markUnplaced(
                assignment,
                kind: .assignmentNotPlaced,
                message: "No remaining opening can hold \(assignment.assignmentNumber).",
                state: &state
            )
            return
        }

        append(item, to: &state)
        state.recommendations.append(
            PlanningRecommendation(
                kind: .fillOpenCapacity,
                assignmentID: assignment.id,
                message: "Use the \(shortTime(item.serviceStart)) opening for \(assignment.assignmentNumber)."
            )
        )
    }

    // MARK: - Placement Helpers

    private func earliestAvailableItem(
        for assignment: Assignment,
        technicianID: UUID,
        earliestServiceStart: Date,
        latestServiceStart: Date,
        workdayStart: Date,
        workdayEnd: Date,
        explanation: String,
        state: PlanningState
    ) -> DailyPlanItem? {
        let preBuffer = assignment.scheduling.preServiceBufferMinutes
        let earliestForBuffer = calendar.date(
            byAdding: .minute,
            value: preBuffer,
            to: workdayStart
        ) ?? workdayStart
        let lowerBound = max(earliestServiceStart, earliestForBuffer)
        let alignedLowerBound = roundedUpToSlot(lowerBound)

        guard alignedLowerBound <= latestServiceStart else { return nil }

        for candidateStart in candidateStarts(
            earliest: alignedLowerBound,
            latest: latestServiceStart
        ) {
            let item = makeAssignmentItem(
                assignment,
                technicianID: technicianID,
                serviceStart: candidateStart,
                fixed: false,
                explanation: explanation
            )

            guard item.occupiedStart >= workdayStart,
                  item.occupiedEnd <= workdayEnd,
                  firstOverlap(with: item, in: state.busy) == nil,
                  fitsCapacityBudget(
                    adding: item,
                    workdayStart: workdayStart,
                    workdayEnd: workdayEnd,
                    state: state
                  ) else {
                continue
            }

            if assignment.scheduling.mode == .deadline,
               let deadline = assignment.scheduling.completionDeadline,
               item.serviceEnd > deadline {
                continue
            }

            return item
        }

        return nil
    }

    private func makeAssignmentItem(
        _ assignment: Assignment,
        technicianID: UUID,
        serviceStart: Date,
        fixed: Bool,
        explanation: String
    ) -> DailyPlanItem {
        let scheduling = assignment.scheduling
        let serviceEnd = calendar.date(
            byAdding: .minute,
            value: scheduling.estimatedDurationMinutes,
            to: serviceStart
        ) ?? serviceStart
        let occupiedStart = calendar.date(
            byAdding: .minute,
            value: -scheduling.preServiceBufferMinutes,
            to: serviceStart
        ) ?? serviceStart
        let postAndTransition = scheduling.postServiceBufferMinutes +
            configuration.effectiveTransitionBufferMinutes
        let occupiedEnd = calendar.date(
            byAdding: .minute,
            value: postAndTransition,
            to: serviceEnd
        ) ?? serviceEnd

        return DailyPlanItem(
            kind: .assignment,
            assignmentID: assignment.id,
            jobID: assignment.jobID,
            technicianID: technicianID,
            title: assignment.jobNumber,
            schedulingMode: scheduling.mode,
            serviceStart: serviceStart,
            serviceEnd: serviceEnd,
            occupiedStart: occupiedStart,
            occupiedEnd: occupiedEnd,
            isFixedCommitment: fixed,
            explanation: explanation
        )
    }

    private func append(
        _ item: DailyPlanItem,
        to state: inout PlanningState
    ) {
        state.items.append(item)
        state.busy.append(
            BusyInterval(
                start: item.occupiedStart,
                end: item.occupiedEnd,
                assignmentID: item.assignmentID,
                kind: item.kind == .lunch ? .lunch : .assignment
            )
        )
    }

    private func markUnplaced(
        _ assignment: Assignment,
        kind: PlanningConflictKind,
        message: String,
        state: inout PlanningState
    ) {
        state.unplaced.insert(assignment.id)
        state.conflicts.append(
            PlanningConflict(
                kind: kind,
                severity: .error,
                message: message,
                assignmentID: assignment.id,
                conflictingAssignmentID: nil
            )
        )
        state.recommendations.append(
            PlanningRecommendation(
                kind: .reviewConflict,
                assignmentID: assignment.id,
                message: "Review \(assignment.assignmentNumber) manually before accepting this plan."
            )
        )
    }

    // MARK: - Capacity and Windows

    private func fitsCapacityBudget(
        adding item: DailyPlanItem,
        workdayStart: Date,
        workdayEnd: Date,
        state: PlanningState
    ) -> Bool {
        let workdayMinutes = max(
            Int(workdayEnd.timeIntervalSince(workdayStart) / 60),
            0
        )
        let usedMinutes = state.items.reduce(0) {
            $0 + $1.occupiedMinutes
        }
        return usedMinutes + item.occupiedMinutes +
            configuration.effectiveDailyReserveMinutes <= workdayMinutes
    }

    private func appendCapacityConflictIfNeeded(
        technician: EmployeeRecord,
        workdayStart: Date,
        workdayEnd: Date,
        state: inout PlanningState
    ) {
        let workdayMinutes = max(
            Int(workdayEnd.timeIntervalSince(workdayStart) / 60),
            0
        )
        let occupiedMinutes = state.items.reduce(0) {
            $0 + $1.occupiedMinutes
        }
        let requiredMinutes = occupiedMinutes +
            configuration.effectiveDailyReserveMinutes

        guard requiredMinutes > workdayMinutes else { return }

        state.conflicts.append(
            PlanningConflict(
                kind: .insufficientCapacity,
                severity: .error,
                message: "The proposed day exceeds \(technician.displayName)'s workday by \(requiredMinutes - workdayMinutes) minutes.",
                assignmentID: nil,
                conflictingAssignmentID: nil
            )
        )
    }

    private func calculateOpenWindows(
        workdayStart: Date,
        workdayEnd: Date,
        occupied: [BusyInterval]
    ) -> [PlanningWindow] {
        let clipped = occupied.compactMap { interval -> BusyInterval? in
            let start = max(interval.start, workdayStart)
            let end = min(interval.end, workdayEnd)
            guard start < end else { return nil }
            return BusyInterval(
                start: start,
                end: end,
                assignmentID: interval.assignmentID,
                kind: interval.kind
            )
        }
        .sorted { first, second in
            if first.start != second.start { return first.start < second.start }
            return first.end < second.end
        }

        var merged: [BusyInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = BusyInterval(
                    start: last.start,
                    end: max(last.end, interval.end),
                    assignmentID: last.assignmentID,
                    kind: last.kind
                )
            } else {
                merged.append(interval)
            }
        }

        var cursor = workdayStart
        var windows: [PlanningWindow] = []

        for interval in merged {
            if cursor < interval.start {
                windows.append(
                    PlanningWindow(
                        kind: .open,
                        start: cursor,
                        end: interval.start
                    )
                )
            }
            cursor = max(cursor, interval.end)
        }

        if cursor < workdayEnd {
            windows.append(
                PlanningWindow(
                    kind: .open,
                    start: cursor,
                    end: workdayEnd
                )
            )
        }

        return windows
    }

    // MARK: - Eligibility

    private func isPlannable(
        _ assignment: Assignment,
        for technician: EmployeeRecord
    ) -> Bool {
        guard assignment.lifecycleStatus == .active,
              assignment.status == .scheduled ||
              assignment.status == .dispatched ||
              assignment.status == .enRoute ||
              assignment.status == .onSite else {
            return false
        }

        return assignment.primaryTechnicianID == technician.id ||
            assignment.supportingTechnicianIDs.contains(technician.id)
    }

    private func occurs(
        _ assignment: Assignment,
        on planningDate: Date
    ) -> Bool {
        let scheduling = assignment.scheduling

        switch scheduling.mode {
        case .fixedTime:
            guard let date = scheduling.fixedStartDate ?? scheduling.serviceDate else {
                return false
            }
            return calendar.isDate(date, inSameDayAs: planningDate)

        case .arrivalWindow:
            guard let start = scheduling.arrivalWindowStart,
                  let end = scheduling.arrivalWindowEnd,
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: planningDate) else {
                return false
            }
            return start < dayEnd && end >= planningDate

        case .flexibleDay:
            guard let serviceDate = scheduling.serviceDate else { return false }
            return calendar.isDate(serviceDate, inSameDayAs: planningDate)

        case .deadline:
            if let serviceDate = scheduling.serviceDate {
                return calendar.isDate(serviceDate, inSameDayAs: planningDate)
            }
            guard let deadline = scheduling.completionDeadline else { return false }
            return calendar.isDate(deadline, inSameDayAs: planningDate)
        }
    }

    // MARK: - Stable Ordering

    private func fixedCommitmentOrder(
        _ first: Assignment,
        _ second: Assignment
    ) -> Bool {
        let firstDate = first.scheduling.fixedStartDate ?? .distantFuture
        let secondDate = second.scheduling.fixedStartDate ?? .distantFuture
        if firstDate != secondDate { return firstDate < secondDate }
        return stableAssignmentOrder(first, second)
    }

    private func constrainedAssignmentOrder(
        _ first: Assignment,
        _ second: Assignment
    ) -> Bool {
        let firstLimit = latestConstraint(for: first)
        let secondLimit = latestConstraint(for: second)
        if firstLimit != secondLimit { return firstLimit < secondLimit }
        return stableAssignmentOrder(first, second)
    }

    private func flexibleAssignmentOrder(
        _ first: Assignment,
        _ second: Assignment
    ) -> Bool {
        if first.priority != second.priority {
            return priorityRank(first.priority) > priorityRank(second.priority)
        }

        switch (first.routeSequence, second.routeSequence) {
        case let (.some(lhs), .some(rhs)) where lhs != rhs:
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return stableAssignmentOrder(first, second)
        }
    }

    private func stableAssignmentOrder(
        _ first: Assignment,
        _ second: Assignment
    ) -> Bool {
        if first.priority != second.priority {
            return priorityRank(first.priority) > priorityRank(second.priority)
        }
        if first.assignmentNumber != second.assignmentNumber {
            return first.assignmentNumber.localizedStandardCompare(second.assignmentNumber) == .orderedAscending
        }
        return first.id.uuidString < second.id.uuidString
    }

    private func latestConstraint(for assignment: Assignment) -> Date {
        switch assignment.scheduling.mode {
        case .arrivalWindow:
            return assignment.scheduling.arrivalWindowEnd ?? .distantFuture
        case .deadline:
            guard let deadline = assignment.scheduling.completionDeadline else {
                return .distantFuture
            }
            return calendar.date(
                byAdding: .minute,
                value: -assignment.scheduling.estimatedDurationMinutes,
                to: deadline
            ) ?? deadline
        default:
            return .distantFuture
        }
    }

    private func priorityRank(_ priority: AssignmentPriority) -> Int {
        switch priority {
        case .emergency: return 3
        case .high: return 2
        case .normal: return 1
        case .low: return 0
        }
    }

    private func planItemOrder(
        _ first: DailyPlanItem,
        _ second: DailyPlanItem
    ) -> Bool {
        if first.occupiedStart != second.occupiedStart {
            return first.occupiedStart < second.occupiedStart
        }
        return first.id < second.id
    }

    private func conflictOrder(
        _ first: PlanningConflict,
        _ second: PlanningConflict
    ) -> Bool {
        if first.severity != second.severity {
            return first.severity == .error
        }
        return first.id < second.id
    }

    private func deduplicatedConflicts(
        _ conflicts: [PlanningConflict]
    ) -> [PlanningConflict] {
        var seen = Set<String>()
        return conflicts.filter { conflict in
            seen.insert(conflict.id).inserted
        }
    }

    // MARK: - Date and Interval Helpers

    private func dateAtMinutesAfterMidnight(
        atMinutesAfterMidnight minutes: Int,
        on date: Date
    ) -> Date? {
        let start = calendar.startOfDay(for: date)
        return calendar.date(
            byAdding: .minute,
            value: minutes,
            to: start
        )
    }

    private func roundedUpToSlot(_ date: Date) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let minutes = max(Int(date.timeIntervalSince(dayStart) / 60), 0)
        let interval = configuration.slotIntervalMinutes
        let roundedMinutes = ((minutes + interval - 1) / interval) * interval
        return calendar.date(
            byAdding: .minute,
            value: roundedMinutes,
            to: dayStart
        ) ?? date
    }

    private func candidateStarts(
        earliest: Date,
        latest: Date
    ) -> [Date] {
        guard earliest <= latest else { return [] }
        var starts: [Date] = []
        var candidate = roundedUpToSlot(earliest)

        while candidate <= latest {
            starts.append(candidate)
            guard let next = calendar.date(
                byAdding: .minute,
                value: configuration.slotIntervalMinutes,
                to: candidate
            ), next > candidate else {
                break
            }
            candidate = next
        }

        return starts
    }

    private func firstOverlap(
        with item: DailyPlanItem,
        in busy: [BusyInterval]
    ) -> BusyInterval? {
        busy.first {
            item.occupiedStart < $0.end && $0.start < item.occupiedEnd
        }
    }

    private func overlaps(
        _ interval: BusyInterval,
        any busy: [BusyInterval]
    ) -> Bool {
        busy.contains {
            interval.start < $0.end && $0.start < interval.end
        }
    }

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func unavailablePlan(
        technician: EmployeeRecord,
        date: Date,
        kind: PlanningConflictKind,
        message: String
    ) -> DailyPlan {
        DailyPlan(
            technicianID: technician.id,
            date: date,
            workdayStart: nil,
            workdayEnd: nil,
            items: [],
            openWindows: [],
            conflicts: [
                PlanningConflict(
                    kind: kind,
                    severity: .error,
                    message: message,
                    assignmentID: nil,
                    conflictingAssignmentID: nil
                )
            ],
            recommendations: [],
            unplacedAssignmentIDs: [],
            dailyReserveMinutes: configuration.effectiveDailyReserveMinutes
        )
    }
}

// MARK: - Private Planning State

private extension DailyPlannerEngine {
    struct PlanningState {
        var items: [DailyPlanItem] = []
        var busy: [BusyInterval] = []
        var conflicts: [PlanningConflict] = []
        var recommendations: [PlanningRecommendation] = []
        var unplaced: Set<UUID> = []
    }

    struct BusyInterval {
        enum Kind {
            case assignment
            case lunch
        }

        let start: Date
        let end: Date
        let assignmentID: UUID?
        let kind: Kind
    }
}
