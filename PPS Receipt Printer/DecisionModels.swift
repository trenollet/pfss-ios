//
//  DecisionModels.swift
//  PPS Receipt Printer
//
//  Brick 12 — Shared dispatch decision models.
//

import Foundation

struct DispatchDecision: Identifiable {
    let id: UUID
    let job: JobRecord
    let employee: EmployeeRecord
    let opening: AvailableOpening
    let policy: DecisionPolicy
    let score: Double
    let confidencePercentage: Int
    let confidence: DecisionConfidence
    let reasons: [DecisionReason]

    init(
        id: UUID = UUID(),
        job: JobRecord,
        employee: EmployeeRecord,
        opening: AvailableOpening,
        policy: DecisionPolicy,
        score: Double,
        confidencePercentage: Int,
        reasons: [DecisionReason]
    ) {
        let safeConfidence = min(max(confidencePercentage, 0), 100)

        self.id = id
        self.job = job
        self.employee = employee
        self.opening = opening
        self.policy = policy
        self.score = score
        self.confidencePercentage = safeConfidence
        self.confidence = DecisionConfidence.from(
            percentage: safeConfidence
        )
        self.reasons = reasons
    }
}

struct DispatchDecisionResult {
    let job: JobRecord
    let policy: DecisionPolicy
    let decisions: [DispatchDecision]
    let unavailableEmployees: [AvailableEmployee]

    var bestDecision: DispatchDecision? {
        decisions.first
    }

    var hasRecommendation: Bool {
        bestDecision != nil
    }
}
