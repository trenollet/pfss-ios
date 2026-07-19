//
//  DispatchDecisionEngine.swift
//  PPS Receipt Printer
//
//  Brick 12 — Sprint 2
//  Policy-aware, explainable technician dispatch recommendations.
//

import Foundation

struct DispatchDecisionEngine {

    // MARK: - Public API

    static func evaluate(
        job: JobRecord,
        employees: [EmployeeRecord],
        jobs: [JobRecord],
        policy: DecisionPolicy = .balancedWorkload,
        onOrAfter date: Date? = nil,
        calendar: Calendar = .current
    ) -> DispatchDecisionResult {
        let targetDate = date ?? job.scheduledDate

        let candidates = SchedulingEngine.availableEmployeeRecommendations(
            for: job,
            employees: employees,
            onOrAfter: targetDate,
            from: jobs,
            calendar: calendar
        )

        let availableCandidates = candidates.filter(\.isAvailable)
        let unavailableCandidates = candidates.filter { !$0.isAvailable }

        guard !availableCandidates.isEmpty else {
            return DispatchDecisionResult(
                job: job,
                policy: policy,
                decisions: [],
                unavailableEmployees: unavailableCandidates
            )
        }

        let context = ScoringContext(
            earliestStart: availableCandidates
                .compactMap { $0.earliestAvailableOpening?.start }
                .min(),
            maximumRemainingMinutes: availableCandidates
                .map(\.remainingMinutes)
                .max() ?? 0,
            minimumUtilization: availableCandidates
                .map { $0.capacitySummary.utilizationFraction }
                .min() ?? 0
        )

        let scoredCandidates = availableCandidates
            .compactMap { candidate -> ScoredCandidate? in
                guard let opening = candidate.earliestAvailableOpening else {
                    return nil
                }

                let evaluation = evaluateCandidate(
                    candidate,
                    opening: opening,
                    job: job,
                    policy: policy,
                    context: context,
                    calendar: calendar
                )

                return ScoredCandidate(
                    candidate: candidate,
                    opening: opening,
                    score: evaluation.score,
                    reasons: evaluation.reasons
                )
            }
            .sorted { first, second in
                if first.score != second.score {
                    return first.score > second.score
                }

                if first.opening.start != second.opening.start {
                    return first.opening.start < second.opening.start
                }

                return first.candidate.employee.displayName
                    .localizedCaseInsensitiveCompare(
                        second.candidate.employee.displayName
                    ) == .orderedAscending
            }

        let topScore = scoredCandidates.first?.score ?? 0
        let secondScore = scoredCandidates.dropFirst().first?.score

        let decisions = scoredCandidates.enumerated().map { index, item in
            DispatchDecision(
                job: job,
                employee: item.candidate.employee,
                opening: item.opening,
                policy: policy,
                score: item.score,
                confidencePercentage: confidencePercentage(
                    score: item.score,
                    topScore: topScore,
                    secondScore: index == 0 ? secondScore : nil,
                    isTopChoice: index == 0
                ),
                reasons: item.reasons
            )
        }

        return DispatchDecisionResult(
            job: job,
            policy: policy,
            decisions: decisions,
            unavailableEmployees: unavailableCandidates
        )
    }

    static func bestDecision(
        for job: JobRecord,
        employees: [EmployeeRecord],
        jobs: [JobRecord],
        policy: DecisionPolicy = .balancedWorkload,
        onOrAfter date: Date? = nil,
        calendar: Calendar = .current
    ) -> DispatchDecision? {
        evaluate(
            job: job,
            employees: employees,
            jobs: jobs,
            policy: policy,
            onOrAfter: date,
            calendar: calendar
        ).bestDecision
    }

    static func rankedDecisions(
        for job: JobRecord,
        employees: [EmployeeRecord],
        jobs: [JobRecord],
        policy: DecisionPolicy = .balancedWorkload,
        onOrAfter date: Date? = nil,
        limit: Int? = nil,
        calendar: Calendar = .current
    ) -> [DispatchDecision] {
        let decisions = evaluate(
            job: job,
            employees: employees,
            jobs: jobs,
            policy: policy,
            onOrAfter: date,
            calendar: calendar
        ).decisions

        guard let limit else {
            return decisions
        }

        return Array(decisions.prefix(max(limit, 0)))
    }

    // MARK: - Candidate Evaluation

    private static func evaluateCandidate(
        _ candidate: AvailableEmployee,
        opening: AvailableOpening,
        job: JobRecord,
        policy: DecisionPolicy,
        context: ScoringContext,
        calendar: Calendar
    ) -> CandidateEvaluation {
        var score = 0.0
        var reasons: [DecisionReason] = []

        addNoConflictEvidence(
            to: &score,
            reasons: &reasons
        )

        addRequestedDateEvidence(
            opening: opening,
            job: job,
            calendar: calendar,
            score: &score,
            reasons: &reasons
        )

        addEarliestOpeningEvidence(
            opening: opening,
            earliestStart: context.earliestStart,
            policy: policy,
            score: &score,
            reasons: &reasons
        )

        addRemainingCapacityEvidence(
            candidate: candidate,
            maximumRemainingMinutes: context.maximumRemainingMinutes,
            policy: policy,
            score: &score,
            reasons: &reasons
        )

        addUtilizationEvidence(
            candidate: candidate,
            minimumUtilization: context.minimumUtilization,
            policy: policy,
            score: &score,
            reasons: &reasons
        )

        addExactFitEvidence(
            opening: opening,
            job: job,
            score: &score,
            reasons: &reasons
        )

        addPolicySpecificEvidence(
            policy: policy,
            job: job,
            score: &score,
            reasons: &reasons
        )

        return CandidateEvaluation(
            score: max(score, 0),
            reasons: reasons.sorted { first, second in
                if first.weight != second.weight {
                    return first.weight > second.weight
                }

                return first.title.localizedCaseInsensitiveCompare(second.title)
                    == .orderedAscending
            }
        )
    }

    // MARK: - Evidence Rules

    private static func addNoConflictEvidence(
        to score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        let weight = 40.0
        score += weight

        reasons.append(
            DecisionReason(
                type: .noConflicts,
                message: "No scheduling conflicts were found for this assignment.",
                weight: weight
            )
        )
    }

    private static func addRequestedDateEvidence(
        opening: AvailableOpening,
        job: JobRecord,
        calendar: Calendar,
        score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        guard calendar.isDate(opening.start, inSameDayAs: job.scheduledDate) else {
            return
        }

        let weight = 8.0
        score += weight

        reasons.append(
            DecisionReason(
                type: .availableToday,
                message: "An opening is available on the requested service date.",
                weight: weight
            )
        )
    }

    private static func addEarliestOpeningEvidence(
        opening: AvailableOpening,
        earliestStart: Date?,
        policy: DecisionPolicy,
        score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        guard let earliestStart,
              opening.start == earliestStart else {
            return
        }

        let weight = earliestOpeningWeight(for: policy)
        score += weight

        reasons.append(
            DecisionReason(
                type: .earliestOpening,
                message: "This is the earliest valid opening among the eligible technicians.",
                weight: weight
            )
        )
    }

    private static func addRemainingCapacityEvidence(
        candidate: AvailableEmployee,
        maximumRemainingMinutes: Int,
        policy: DecisionPolicy,
        score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        let maximumWeight = remainingCapacityWeight(for: policy)
        let ratio: Double

        if maximumRemainingMinutes > 0 {
            ratio = Double(max(candidate.remainingMinutes, 0))
                / Double(maximumRemainingMinutes)
        } else {
            ratio = 0
        }

        let weight = min(max(ratio, 0), 1) * maximumWeight
        score += weight

        reasons.append(
            DecisionReason(
                type: .remainingCapacity,
                message: "\(formattedMinutes(candidate.remainingMinutes)) remain in the technician's daily capacity.",
                weight: weight
            )
        )
    }

    private static func addUtilizationEvidence(
        candidate: AvailableEmployee,
        minimumUtilization: Double,
        policy: DecisionPolicy,
        score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        let maximumWeight = lowUtilizationWeight(for: policy)
        let utilization = min(
            max(candidate.capacitySummary.utilizationFraction, 0),
            1
        )
        let availableFraction = 1 - utilization
        var weight = availableFraction * maximumWeight

        if policy == .balancedWorkload,
           abs(utilization - minimumUtilization) < 0.0001 {
            weight += 4
        }

        score += weight

        reasons.append(
            DecisionReason(
                type: policy == .balancedWorkload
                    ? .balancedWorkload
                    : .lowUtilization,
                message: "Current utilization is \(candidate.capacitySummary.utilizationPercentage)%.",
                weight: weight
            )
        )
    }

    private static func addExactFitEvidence(
        opening: AvailableOpening,
        job: JobRecord,
        score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        let requiredMinutes = SchedulingEngine.scheduledMinutes(for: job)

        guard requiredMinutes > 0,
              opening.durationMinutes == requiredMinutes else {
            return
        }

        let weight = 4.0
        score += weight

        reasons.append(
            DecisionReason(
                type: .exactFit,
                message: "The opening exactly matches the job's scheduled duration.",
                weight: weight
            )
        )
    }

    private static func addPolicySpecificEvidence(
        policy: DecisionPolicy,
        job: JobRecord,
        score: inout Double,
        reasons: inout [DecisionReason]
    ) {
        switch policy {
        case .emergency:
            let weight = 20.0
            score += weight

            reasons.append(
                DecisionReason(
                    type: .emergencyPriority,
                    message: "Emergency dispatch strongly prioritizes the first valid opening.",
                    weight: weight
                )
            )

        case .highestRevenue:
            let weight = min(max(job.total, 0) / 100, 10)
            score += weight

            reasons.append(
                DecisionReason(
                    type: .highValueJob,
                    message: "This policy preserves technician capacity while prioritizing higher-value work.",
                    weight: weight
                )
            )

        case .closestTechnician,
             .preferredTechnician,
             .highestSkill,
             .custom:
            reasons.append(
                DecisionReason(
                    type: .fallbackPolicy,
                    message: "The data required for \(policy.displayName.lowercased()) is not available yet, so balanced workload scoring was used.",
                    weight: 0,
                    isPositive: false
                )
            )

        case .balancedWorkload,
             .earliestAvailable:
            break
        }
    }

    // MARK: - Policy Weights

    private static func earliestOpeningWeight(
        for policy: DecisionPolicy
    ) -> Double {
        switch policy {
        case .earliestAvailable:
            return 40
        case .emergency:
            return 50
        default:
            return 20
        }
    }

    private static func remainingCapacityWeight(
        for policy: DecisionPolicy
    ) -> Double {
        switch policy {
        case .balancedWorkload:
            return 25
        case .highestRevenue:
            return 20
        case .earliestAvailable,
             .emergency:
            return 10
        default:
            return 25
        }
    }

    private static func lowUtilizationWeight(
        for policy: DecisionPolicy
    ) -> Double {
        switch policy {
        case .balancedWorkload:
            return 20
        case .highestRevenue:
            return 15
        case .earliestAvailable,
             .emergency:
            return 5
        default:
            return 20
        }
    }

    // MARK: - Ranking and Confidence

    private static func confidencePercentage(
        score: Double,
        topScore: Double,
        secondScore: Double?,
        isTopChoice: Bool
    ) -> Int {
        guard topScore > 0 else {
            return 0
        }

        let relativeScore = min(max(score / topScore, 0), 1)
        var percentage = Int((relativeScore * 82).rounded())

        if isTopChoice {
            percentage += 8

            if let secondScore {
                let separation = max(topScore - secondScore, 0)
                let separationRatio = min(separation / topScore, 1)
                percentage += Int((separationRatio * 10).rounded())
            } else {
                percentage += 10
            }
        }

        return min(max(percentage, 0), 100)
    }

    // MARK: - Formatting

    private static func formattedMinutes(_ minutes: Int) -> String {
        let safeMinutes = max(minutes, 0)
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60

        switch (hours, remainder) {
        case (0, _):
            return "\(remainder) minutes"
        case (_, 0):
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        default:
            return "\(hours) hour\(hours == 1 ? "" : "s") \(remainder) minutes"
        }
    }

    // MARK: - Private Models

    private struct ScoringContext {
        let earliestStart: Date?
        let maximumRemainingMinutes: Int
        let minimumUtilization: Double
    }

    private struct CandidateEvaluation {
        let score: Double
        let reasons: [DecisionReason]
    }

    private struct ScoredCandidate {
        let candidate: AvailableEmployee
        let opening: AvailableOpening
        let score: Double
        let reasons: [DecisionReason]
    }
}
