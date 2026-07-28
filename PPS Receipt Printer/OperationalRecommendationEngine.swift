//
//  OperationalRecommendationEngine.swift
//  PPS Receipt Printer
//
//  Phase 14.6 — Recommendation Engine
//

import Foundation

/// Deterministic, explainable operational recommendation engine.
///
/// This engine ranks evidence that has already been prepared by Workforce
/// Intelligence, Scheduling/Daily Planner, and Route Engine. It never mutates an
/// Assignment, selects a technician, or dispatches work. A human must accept or
/// override its output through Dispatch Engine.
struct OperationalRecommendationEngine {
    let configuration: OperationalRecommendationConfiguration

    init(
        configuration: OperationalRecommendationConfiguration =
            OperationalRecommendationConfiguration()
    ) {
        self.configuration = configuration
    }

    // MARK: - Public API

    func evaluate(
        request: OperationalRecommendationRequest,
        candidates: [OperationalRecommendationCandidateInput],
        generatedAt: Date = Date()
    ) -> OperationalRecommendationResult {
        let uniqueCandidates = deduplicated(candidates)
        let evaluated = uniqueCandidates.map {
            evaluateCandidate($0, request: request)
        }

        let selectable = evaluated
            .filter(\.isSelectable)
            .sorted(by: candidateOrder)

        var rankedByEmployeeID: [UUID: Int] = [:]
        var previous: OperationalRecommendationCandidate?
        var currentRank = 0
        for (index, candidate) in selectable.enumerated() {
            if let previous,
               abs(candidate.score - previous.score) <= 0.5 {
                // Keep the same rank when evidence cannot meaningfully
                // distinguish two candidates.
            } else {
                currentRank = index + 1
            }
            rankedByEmployeeID[candidate.employeeID] = currentRank
            previous = candidate
        }

        let ranked = evaluated
            .map { candidate in
                copy(
                    candidate,
                    rank: rankedByEmployeeID[candidate.employeeID]
                )
            }
            .sorted { first, second in
                switch (first.rank, second.rank) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return stableNameOrder(first, second)
                }
            }

        return OperationalRecommendationResult(
            request: request,
            policy: configuration.policy,
            candidates: ranked,
            generatedAt: generatedAt
        )
    }

    func bestCandidate(
        for request: OperationalRecommendationRequest,
        candidates: [OperationalRecommendationCandidateInput],
        generatedAt: Date = Date()
    ) -> OperationalRecommendationCandidate? {
        evaluate(
            request: request,
            candidates: candidates,
            generatedAt: generatedAt
        ).bestCandidate
    }

    // MARK: - Candidate Evaluation

    private func evaluateCandidate(
        _ input: OperationalRecommendationCandidateInput,
        request: OperationalRecommendationRequest
    ) -> OperationalRecommendationCandidate {
        var evidence: [OperationalRecommendationEvidence] = []
        var score = 0.0

        score += capabilityEvidence(for: input, into: &evidence)
        score += availabilityEvidence(for: input, into: &evidence)
        score += scheduleEvidence(
            for: input,
            request: request,
            into: &evidence
        )
        score += workloadEvidence(for: input, into: &evidence)
        score += travelEvidence(for: input, into: &evidence)
        score += historyEvidence(for: input, into: &evidence)
        score += preferenceEvidence(for: input, into: &evidence)
        score += continuityEvidence(for: input, into: &evidence)

        addPriorityContext(request.priority, to: &evidence)

        let blockers = evidence.filter { $0.impact == .blocking }
        let warnings = evidence.filter { $0.impact == .warning }

        let eligibility: OperationalRecommendationEligibility
        if !blockers.isEmpty {
            eligibility = .ineligible
        } else if !warnings.isEmpty {
            eligibility = .eligibleWithWarnings
        } else {
            eligibility = .eligible
        }

        let totalWeight = max(configuration.weights.total, 1)
        let percentage = Int(
            (min(max(score / totalWeight, 0), 1) * 100).rounded()
        )

        return OperationalRecommendationCandidate(
            employeeID: input.employeeID,
            employeeName: input.employeeName,
            eligibility: eligibility,
            score: score,
            scorePercentage: percentage,
            proposedStartDate: input.schedule.proposedStartDate,
            proposedEndDate: input.schedule.proposedEndDate,
            proposedRouteSequence: input.travel?.proposedRouteSequence,
            distanceMiles: input.travel?.distanceMiles,
            travelMinutes: input.travel?.travelMinutes,
            evidence: sortedEvidence(evidence)
        )
    }

    // MARK: - Capability

    private func capabilityEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        let evaluation = input.workforce.capability
        let weight = configuration.weights.capability
        let factor: Double
        let impact: OperationalRecommendationEvidenceImpact
        let title: String

        switch evaluation.state {
        case .qualified:
            factor = 1
            impact = .supporting
            title = "Capability requirements satisfied"

        case .qualifiedWithWarnings:
            factor = 0.78
            impact = .warning
            title = "Capability requirements satisfied with warnings"

        case .notQualified:
            factor = 0
            impact = configuration.exclusions.excludeUnqualifiedEmployee
                ? .blocking
                : .warning
            title = "Capability requirements not satisfied"
        }

        let contribution = weight * factor
        evidence.append(
            OperationalRecommendationEvidence(
                category: .skill,
                impact: impact,
                title: title,
                detail: capabilitySummary(evaluation),
                scoreContribution: contribution
            )
        )

        evaluation.evidence.forEach { workforceEvidence in
            var mappedImpact = mapImpact(workforceEvidence.severity)

            if workforceEvidence.category == .certification,
               workforceEvidence.severity == .blocking,
               configuration.exclusions.excludeExpiredRequiredCredential {
                mappedImpact = .blocking
            } else if mappedImpact == .blocking,
                      !configuration.exclusions.excludeUnqualifiedEmployee {
                mappedImpact = .warning
            }

            evidence.append(
                OperationalRecommendationEvidence(
                    category: mapCategory(workforceEvidence.category),
                    impact: mappedImpact,
                    title: workforceEvidence.category.rawValue,
                    detail: workforceEvidence.message
                )
            )
        }

        return contribution
    }

    // MARK: - Availability

    private func availabilityEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        let availability = input.workforce.availability
        let weight = configuration.weights.availability
        let factor: Double
        let impact: OperationalRecommendationEvidenceImpact

        switch availability.state {
        case .available:
            factor = 1
            impact = .supporting
        case .availableOverride:
            factor = 0.95
            impact = .supporting
        case .limited:
            factor = 0.58
            impact = .warning
        case .inactive:
            factor = 0
            impact = configuration.exclusions.excludeInactiveEmployee
                ? .blocking
                : .warning
        case .unavailable, .offSchedule:
            factor = 0
            impact = configuration.exclusions.excludeUnavailableEmployee
                ? .blocking
                : .warning
        }

        let contribution = weight * factor
        evidence.append(
            OperationalRecommendationEvidence(
                category: .availability,
                impact: impact,
                title: availability.state.rawValue,
                detail: availability.reason,
                scoreContribution: contribution
            )
        )

        return contribution
    }

    // MARK: - Schedule

    private func scheduleEvidence(
        for input: OperationalRecommendationCandidateInput,
        request: OperationalRecommendationRequest,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        let schedule = input.schedule
        let weight = configuration.weights.scheduleFit
        var factor = schedule.hasConflictFreeOpening ? 1.0 : 0.0
        var impact: OperationalRecommendationEvidenceImpact =
            schedule.hasConflictFreeOpening ? .supporting : .warning
        var detail = schedule.hasConflictFreeOpening
            ? "A conflict-free opening is available."
            : schedule.conflictMessages.joined(separator: " ")

        if !schedule.hasConflictFreeOpening,
           configuration.exclusions.excludeScheduleConflict {
            impact = .blocking
        }

        if let latest = request.latestAcceptableStartDate,
           let proposed = schedule.proposedStartDate,
           proposed > latest {
            factor = 0
            impact = configuration.exclusions.excludeScheduleConflict
                ? .blocking
                : .warning
            detail = "The proposed start is later than the latest acceptable start."
        } else if let requested = request.requestedStartDate,
                  let proposed = schedule.proposedStartDate,
                  proposed > requested {
            let delayMinutes = proposed.timeIntervalSince(requested) / 60
            factor = max(1 - min(delayMinutes / 240, 0.8), 0.2)
            detail = "The proposed opening begins \(Int(delayMinutes.rounded())) minutes after the requested start."
        }

        if detail.isEmpty {
            detail = "No conflict-free opening was found."
        }

        let contribution = weight * factor
        evidence.append(
            OperationalRecommendationEvidence(
                category: .schedule,
                impact: impact,
                title: schedule.hasConflictFreeOpening
                    ? "Schedule fit"
                    : "Schedule conflict",
                detail: detail,
                scoreContribution: contribution
            )
        )

        return contribution
    }

    // MARK: - Workload

    private func workloadEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        let workload = input.workforce.workload
        let weight = configuration.weights.workload
        let factor: Double

        if workload.capacityMinutes > 0 {
            factor = min(
                max(
                    Double(workload.remainingCapacityMinutes) /
                        Double(workload.capacityMinutes),
                    0
                ),
                1
            )
        } else {
            factor = 0
        }

        let isWarning = workload.exceedsMaximumDailyAssignments ||
            workload.utilizationFraction >=
                configuration.workloadWarningUtilization
        let contribution = weight * factor

        evidence.append(
            OperationalRecommendationEvidence(
                category: .workload,
                impact: isWarning ? .warning : .supporting,
                title: isWarning ? "High workload" : "Available capacity",
                detail: "\(workload.assignmentCount) assignments, \(workload.utilizationPercentage)% utilized, \(workload.remainingCapacityMinutes) minutes remaining.",
                scoreContribution: contribution
            )
        )

        return contribution
    }

    // MARK: - Travel

    private func travelEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        let weight = configuration.weights.travel

        guard let travel = input.travel,
              travel.isLocationResolved,
              let distance = travel.distanceMiles else {
            let impact: OperationalRecommendationEvidenceImpact =
                configuration.exclusions.allowMissingTravelData
                    ? .warning
                    : .blocking
            let factor = configuration.exclusions.allowMissingTravelData
                ? 0.5
                : 0
            let contribution = weight * factor

            evidence.append(
                OperationalRecommendationEvidence(
                    category: .dataQuality,
                    impact: impact,
                    title: "Travel data unavailable",
                    detail: "The technician remains visible, but distance and response time could not be evaluated.",
                    scoreContribution: contribution
                )
            )
            return contribution
        }

        let preferredMaximum = max(
            configuration.maximumPreferredTravelMiles,
            1
        )
        let factor: Double
        let impact: OperationalRecommendationEvidenceImpact

        if distance <= preferredMaximum {
            factor = 1 - (0.8 * (distance / preferredMaximum))
            impact = .supporting
        } else {
            factor = max(
                0.1 - ((distance - preferredMaximum) / preferredMaximum),
                0
            )
            impact = .warning
        }

        let contribution = weight * factor
        let travelDescription = travel.travelMinutes.map {
            String(format: "%.1f miles, %d minutes.", distance, $0)
        } ?? String(format: "%.1f miles.", distance)

        evidence.append(
            OperationalRecommendationEvidence(
                category: .travel,
                impact: impact,
                title: impact == .supporting
                    ? "Travel is within the preferred range"
                    : "Travel exceeds the preferred range",
                detail: travelDescription,
                scoreContribution: contribution
            )
        )

        travel.warningMessages.forEach {
            evidence.append(
                OperationalRecommendationEvidence(
                    category: .travel,
                    impact: .warning,
                    title: "Route warning",
                    detail: $0
                )
            )
        }

        return contribution
    }

    // MARK: - History

    private func historyEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        let history = input.workforce.history
        let weight = configuration.weights.history
        let values = [
            history.onTimeArrivalRate,
            history.firstTimeCompletionRate,
            history.averageCustomerRating.map { $0 / 5 }
        ].compactMap { $0 }

        guard history.completedAssignmentCount >=
                configuration.historyMinimumSampleSize,
              !values.isEmpty else {
            let contribution = weight * 0.5
            evidence.append(
                OperationalRecommendationEvidence(
                    category: .history,
                    impact: .informational,
                    title: "Limited performance history",
                    detail: "There is not yet enough history to strongly affect this recommendation.",
                    scoreContribution: contribution
                )
            )
            return contribution
        }

        let factor = values.reduce(0, +) / Double(values.count)
        let contribution = weight * factor
        evidence.append(
            OperationalRecommendationEvidence(
                category: .history,
                impact: factor >= 0.75 ? .supporting : .warning,
                title: "Historical performance",
                detail: "Based on \(history.completedAssignmentCount) completed assignments.",
                scoreContribution: contribution
            )
        )
        return contribution
    }

    // MARK: - Preference and Continuity

    private func preferenceEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        guard input.isPreferredTechnician else { return 0 }
        let contribution = configuration.weights.preference
        evidence.append(
            OperationalRecommendationEvidence(
                category: .preference,
                impact: .supporting,
                title: "Preferred technician",
                detail: "This technician matches the recorded preference for the assignment.",
                scoreContribution: contribution
            )
        )
        return contribution
    }

    private func continuityEvidence(
        for input: OperationalRecommendationCandidateInput,
        into evidence: inout [OperationalRecommendationEvidence]
    ) -> Double {
        guard input.isIncumbentTechnician else { return 0 }
        let contribution = configuration.weights.crewContinuity
        evidence.append(
            OperationalRecommendationEvidence(
                category: .crewContinuity,
                impact: .supporting,
                title: "Assignment continuity",
                detail: "This technician already owns or participates in the assignment.",
                scoreContribution: contribution
            )
        )
        return contribution
    }

    private func addPriorityContext(
        _ priority: AssignmentPriority,
        to evidence: inout [OperationalRecommendationEvidence]
    ) {
        guard priority == .high || priority == .emergency else { return }
        evidence.append(
            OperationalRecommendationEvidence(
                category: .priority,
                impact: .informational,
                title: "\(priority.rawValue) priority",
                detail: priority == .emergency
                    ? "Response time should be reviewed before accepting the recommendation."
                    : "The assignment has elevated operational priority."
            )
        )
    }

    // MARK: - Mapping

    private func mapImpact(
        _ severity: WorkforceEvidenceSeverity
    ) -> OperationalRecommendationEvidenceImpact {
        switch severity {
        case .information: return .informational
        case .satisfied: return .supporting
        case .warning: return .warning
        case .blocking: return .blocking
        }
    }

    private func mapCategory(
        _ category: WorkforceEvidenceCategory
    ) -> OperationalRecommendationEvidenceCategory {
        switch category {
        case .employee: return .employee
        case .skill: return .skill
        case .certification: return .certification
        case .resource: return .equipment
        case .availability: return .availability
        case .workload: return .workload
        }
    }

    private func capabilitySummary(
        _ evaluation: WorkforceCapabilityEvaluation
    ) -> String {
        let blockers = evaluation.blockers.count
        let warnings = evaluation.warnings.count

        if blockers > 0 {
            return "\(blockers) blocking capability requirement\(blockers == 1 ? "" : "s") must be resolved."
        }

        if warnings > 0 {
            return "Requirements are satisfied with \(warnings) warning\(warnings == 1 ? "" : "s")."
        }

        return "Required skills, credentials, and resources are satisfied."
    }

    // MARK: - Deterministic Ordering

    private func deduplicated(
        _ candidates: [OperationalRecommendationCandidateInput]
    ) -> [OperationalRecommendationCandidateInput] {
        var seen = Set<UUID>()
        return candidates
            .sorted { first, second in
                if first.employeeName != second.employeeName {
                    return first.employeeName.localizedCaseInsensitiveCompare(
                        second.employeeName
                    ) == .orderedAscending
                }
                return first.employeeID.uuidString < second.employeeID.uuidString
            }
            .filter { seen.insert($0.employeeID).inserted }
    }

    private func candidateOrder(
        _ first: OperationalRecommendationCandidate,
        _ second: OperationalRecommendationCandidate
    ) -> Bool {
        if first.scorePercentage != second.scorePercentage {
            return first.scorePercentage > second.scorePercentage
        }
        if first.score != second.score {
            return first.score > second.score
        }
        if first.proposedStartDate != second.proposedStartDate {
            return (first.proposedStartDate ?? .distantFuture) <
                (second.proposedStartDate ?? .distantFuture)
        }
        return stableNameOrder(first, second)
    }

    private func stableNameOrder(
        _ first: OperationalRecommendationCandidate,
        _ second: OperationalRecommendationCandidate
    ) -> Bool {
        let comparison = first.employeeName.localizedCaseInsensitiveCompare(
            second.employeeName
        )
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return first.employeeID.uuidString < second.employeeID.uuidString
    }

    private func sortedEvidence(
        _ evidence: [OperationalRecommendationEvidence]
    ) -> [OperationalRecommendationEvidence] {
        evidence.sorted { first, second in
            let firstRank = impactRank(first.impact)
            let secondRank = impactRank(second.impact)
            if firstRank != secondRank { return firstRank < secondRank }
            if first.scoreContribution != second.scoreContribution {
                return first.scoreContribution > second.scoreContribution
            }
            return first.title.localizedCaseInsensitiveCompare(second.title)
                == .orderedAscending
        }
    }

    private func impactRank(
        _ impact: OperationalRecommendationEvidenceImpact
    ) -> Int {
        switch impact {
        case .blocking: return 0
        case .warning: return 1
        case .supporting: return 2
        case .informational: return 3
        }
    }

    private func copy(
        _ candidate: OperationalRecommendationCandidate,
        rank: Int?
    ) -> OperationalRecommendationCandidate {
        OperationalRecommendationCandidate(
            employeeID: candidate.employeeID,
            employeeName: candidate.employeeName,
            rank: rank,
            eligibility: candidate.eligibility,
            score: candidate.score,
            scorePercentage: candidate.scorePercentage,
            proposedStartDate: candidate.proposedStartDate,
            proposedEndDate: candidate.proposedEndDate,
            proposedRouteSequence: candidate.proposedRouteSequence,
            distanceMiles: candidate.distanceMiles,
            travelMinutes: candidate.travelMinutes,
            evidence: candidate.evidence
        )
    }
}
