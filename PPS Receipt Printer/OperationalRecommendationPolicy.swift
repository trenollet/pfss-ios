//
//  OperationalRecommendationPolicy.swift
//  PPS Receipt Printer
//
//  Phase 14.6 — Recommendation Engine
//

import Foundation

/// The human-selected objective used to rank otherwise eligible technicians.
enum OperationalRecommendationPolicy: String, CaseIterable, Identifiable, Codable {
    case balanced = "Balanced"
    case fastestResponse = "Fastest Response"
    case capabilityFirst = "Capability First"
    case workloadBalance = "Workload Balance"
    case closestQualified = "Closest Qualified"
    case emergency = "Emergency"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .balanced:
            return "Balances capability, schedule, workload, travel, and history."
        case .fastestResponse:
            return "Prioritizes the earliest conflict-free arrival."
        case .capabilityFirst:
            return "Prioritizes skill, certification, and equipment strength."
        case .workloadBalance:
            return "Prioritizes remaining capacity and balanced utilization."
        case .closestQualified:
            return "Prioritizes qualified technicians with the shortest travel."
        case .emergency:
            return "Prioritizes qualified, available technicians who can respond fastest."
        }
    }

    var defaultWeights: OperationalRecommendationWeights {
        switch self {
        case .balanced:
            return OperationalRecommendationWeights(
                capability: 24,
                availability: 16,
                scheduleFit: 18,
                workload: 12,
                travel: 14,
                history: 7,
                preference: 4,
                crewContinuity: 5
            )

        case .fastestResponse:
            return OperationalRecommendationWeights(
                capability: 20,
                availability: 18,
                scheduleFit: 25,
                workload: 7,
                travel: 22,
                history: 3,
                preference: 2,
                crewContinuity: 3
            )

        case .capabilityFirst:
            return OperationalRecommendationWeights(
                capability: 42,
                availability: 14,
                scheduleFit: 14,
                workload: 8,
                travel: 7,
                history: 8,
                preference: 3,
                crewContinuity: 4
            )

        case .workloadBalance:
            return OperationalRecommendationWeights(
                capability: 20,
                availability: 15,
                scheduleFit: 18,
                workload: 28,
                travel: 8,
                history: 4,
                preference: 3,
                crewContinuity: 4
            )

        case .closestQualified:
            return OperationalRecommendationWeights(
                capability: 24,
                availability: 14,
                scheduleFit: 14,
                workload: 7,
                travel: 30,
                history: 4,
                preference: 3,
                crewContinuity: 4
            )

        case .emergency:
            return OperationalRecommendationWeights(
                capability: 26,
                availability: 22,
                scheduleFit: 22,
                workload: 4,
                travel: 22,
                history: 1,
                preference: 1,
                crewContinuity: 2
            )
        }
    }
}

/// Explainable scoring weights. Values are relative and normalized by the
/// engine, allowing future Admin configuration without changing its API.
struct OperationalRecommendationWeights: Codable, Hashable {
    var capability: Double
    var availability: Double
    var scheduleFit: Double
    var workload: Double
    var travel: Double
    var history: Double
    var preference: Double
    var crewContinuity: Double

    init(
        capability: Double,
        availability: Double,
        scheduleFit: Double,
        workload: Double,
        travel: Double,
        history: Double,
        preference: Double,
        crewContinuity: Double
    ) {
        self.capability = Self.safe(capability)
        self.availability = Self.safe(availability)
        self.scheduleFit = Self.safe(scheduleFit)
        self.workload = Self.safe(workload)
        self.travel = Self.safe(travel)
        self.history = Self.safe(history)
        self.preference = Self.safe(preference)
        self.crewContinuity = Self.safe(crewContinuity)
    }

    var total: Double {
        capability + availability + scheduleFit + workload + travel +
        history + preference + crewContinuity
    }

    func weight(
        for category: OperationalRecommendationEvidenceCategory
    ) -> Double {
        switch category {
        case .employee, .skill, .certification, .equipment, .vehicle:
            return capability
        case .availability:
            return availability
        case .schedule, .priority:
            return scheduleFit
        case .workload:
            return workload
        case .travel, .dataQuality:
            return travel
        case .history:
            return history
        case .preference:
            return preference
        case .crewContinuity:
            return crewContinuity
        }
    }

    private static func safe(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

/// Business rules that determine when a candidate must be excluded rather than
/// merely ranked lower. These defaults protect customer commitments and safety.
struct OperationalRecommendationExclusionPolicy: Codable, Hashable {
    var excludeInactiveEmployee: Bool
    var excludeUnavailableEmployee: Bool
    var excludeUnqualifiedEmployee: Bool
    var excludeScheduleConflict: Bool
    var excludeExpiredRequiredCredential: Bool
    var allowMissingTravelData: Bool

    init(
        excludeInactiveEmployee: Bool = true,
        excludeUnavailableEmployee: Bool = true,
        excludeUnqualifiedEmployee: Bool = true,
        excludeScheduleConflict: Bool = true,
        excludeExpiredRequiredCredential: Bool = true,
        allowMissingTravelData: Bool = true
    ) {
        self.excludeInactiveEmployee = excludeInactiveEmployee
        self.excludeUnavailableEmployee = excludeUnavailableEmployee
        self.excludeUnqualifiedEmployee = excludeUnqualifiedEmployee
        self.excludeScheduleConflict = excludeScheduleConflict
        self.excludeExpiredRequiredCredential = excludeExpiredRequiredCredential
        self.allowMissingTravelData = allowMissingTravelData
    }
}

/// Complete, serializable configuration for one deterministic engine run.
struct OperationalRecommendationConfiguration: Codable, Hashable {
    var policy: OperationalRecommendationPolicy
    var weights: OperationalRecommendationWeights
    var exclusions: OperationalRecommendationExclusionPolicy
    var maximumPreferredTravelMiles: Double
    var workloadWarningUtilization: Double
    var historyMinimumSampleSize: Int

    init(
        policy: OperationalRecommendationPolicy = .balanced,
        weights: OperationalRecommendationWeights? = nil,
        exclusions: OperationalRecommendationExclusionPolicy =
            OperationalRecommendationExclusionPolicy(),
        maximumPreferredTravelMiles: Double = 35,
        workloadWarningUtilization: Double = 0.85,
        historyMinimumSampleSize: Int = 5
    ) {
        self.policy = policy
        self.weights = weights ?? policy.defaultWeights
        self.exclusions = exclusions
        self.maximumPreferredTravelMiles = Self.safeMiles(
            maximumPreferredTravelMiles
        )
        self.workloadWarningUtilization = min(
            max(
                workloadWarningUtilization.isFinite
                    ? workloadWarningUtilization
                    : 0.85,
                0
            ),
            1
        )
        self.historyMinimumSampleSize = max(historyMinimumSampleSize, 0)
    }

    private static func safeMiles(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 35
    }
}

// MARK: - Legacy Policy Bridge

extension OperationalRecommendationPolicy {
    /// Temporary compatibility bridge used while the old scheduling-only
    /// DispatchDecisionEngine is replaced during Step 6 integration.
    init(legacyPolicy: DecisionPolicy) {
        switch legacyPolicy {
        case .balancedWorkload, .custom:
            self = .balanced
        case .earliestAvailable:
            self = .fastestResponse
        case .closestTechnician:
            self = .closestQualified
        case .preferredTechnician:
            self = .balanced
        case .highestSkill:
            self = .capabilityFirst
        case .highestRevenue:
            self = .workloadBalance
        case .emergency:
            self = .emergency
        }
    }
}
