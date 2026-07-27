//
//  AppDataStore+OperationalRecommendations.swift
//  PPS Receipt Printer
//
//  Phase 14.6 — Recommendation Engine live integration boundary
//

import Foundation

/// Errors raised while turning an advisory recommendation into an authorized
/// Dispatch operation.
enum OperationalRecommendationIntegrationError: LocalizedError {
    case assignmentUnavailable
    case candidateUnavailable
    case overrideReasonRequired

    var errorDescription: String? {
        switch self {
        case .assignmentUnavailable:
            return "The operational Assignment is unavailable for this Job."
        case .candidateUnavailable:
            return "The selected technician is not part of the current recommendation."
        case .overrideReasonRequired:
            return "Enter a short reason for selecting a technician other than PFSS's recommendation."
        }
    }
}

@MainActor
extension AppDataStore {
    /// Produces a deterministic, non-mutating technician recommendation using
    /// the live Assignment, Workforce Intelligence, and Scheduling evidence.
    ///
    /// Route evidence remains optional until a candidate has a resolvable live
    /// origin. The engine reports that limitation instead of fabricating a
    /// distance or silently excluding the technician.
    func operationalRecommendation(
        for job: JobRecord,
        purpose: OperationalRecommendationPurpose = .technicianAssignment,
        policy: OperationalRecommendationPolicy = .balanced,
        onOrAfter requestedDate: Date? = nil,
        calendar: Calendar = .current,
        generatedAt: Date = Date()
    ) -> OperationalRecommendationResult? {
        guard let assignment = assignment(forJobID: job.id) else {
            return nil
        }

        let evaluationDate = requestedDate ?? job.scheduledDate
        let requirements = WorkforceCapabilityRequirements(
            requiredServiceType: job.serviceType
        )
        let technicians = activeEmployees
            .filter { $0.hasRole(.technician) }
        let legacyDecisions = DispatchDecisionEngine.rankedDecisions(
            for: job,
            employees: technicians,
            jobs: activeJobs,
            policy: legacyPolicy(for: policy),
            onOrAfter: evaluationDate,
            calendar: calendar
        )
        let decisionByEmployeeID = Dictionary(
            uniqueKeysWithValues: legacyDecisions.map {
                ($0.employee.id, $0)
            }
        )

        let request = OperationalRecommendationRequest(
            assignmentID: assignment.id,
            jobID: job.id,
            purpose: purpose,
            evaluationDate: evaluationDate,
            priority: assignment.priority,
            capabilityRequirements: requirements,
            preferredTechnicianID: job.primaryTechnicianID,
            incumbentTechnicianID: assignment.primaryTechnicianID,
            requestedCrewSize: max(assignment.crew.activeMembers.count, 1),
            requestedStartDate: job.scheduledDate,
            notes: assignment.dispatchNotes
        )

        let candidates = technicians.map { technician in
            let workforce = workforceSnapshot(
                for: technician,
                on: evaluationDate,
                requirements: requirements
            )
            let decision = decisionByEmployeeID[technician.id]
            let conflictMessages: [String]

            if decision != nil {
                conflictMessages = []
            } else {
                conflictMessages = [
                    workforce.availability.reason.isEmpty
                        ? "No conflict-free opening was found."
                        : workforce.availability.reason
                ]
            }

            return OperationalRecommendationCandidateInput(
                employeeID: technician.id,
                employeeName: technician.displayName,
                workforce: workforce,
                schedule: OperationalScheduleEvidence(
                    hasConflictFreeOpening: decision != nil,
                    proposedStartDate: decision?.opening.start,
                    proposedEndDate: decision?.opening.end,
                    availableMinutes: workforce.workload.remainingCapacityMinutes,
                    conflictMessages: conflictMessages
                ),
                travel: nil,
                isPreferredTechnician: technician.id == request.preferredTechnicianID,
                isIncumbentTechnician: technician.id == request.incumbentTechnicianID
            )
        }

        return OperationalRecommendationEngine(
            configuration: OperationalRecommendationConfiguration(
                policy: policy
            )
        ).evaluate(
            request: request,
            candidates: candidates,
            generatedAt: generatedAt
        )
    }

    /// Applies the human's final selection through Dispatch Engine and writes
    /// an explainable audit note to the Assignment. The recommendation itself
    /// never mutates operational data.
    @discardableResult
    func assignTechnicianUsingRecommendation(
        _ technicianID: UUID,
        toJobID jobID: UUID,
        recommendation: OperationalRecommendationResult,
        overrideReason: String = "",
        actorEmployeeID: UUID? = nil,
        decidedAt: Date = Date()
    ) throws -> OperationalRecommendationDecision {
        guard let candidate = recommendation.candidates.first(where: {
            $0.employeeID == technicianID
        }) else {
            throw OperationalRecommendationIntegrationError.candidateUnavailable
        }

        let recommendedID = recommendation.bestCandidate?.employeeID
        let isOverride = recommendedID != technicianID
        let cleanReason = overrideReason.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if isOverride && cleanReason.isEmpty {
            throw OperationalRecommendationIntegrationError.overrideReasonRequired
        }

        let disposition: OperationalRecommendationDisposition = isOverride
            ? .selectedAlternative
            : .acceptedRecommended
        let decision = OperationalRecommendationDecision(
            recommendationResultID: recommendation.id,
            assignmentID: recommendation.request.assignmentID,
            disposition: disposition,
            recommendedTechnicianID: recommendedID,
            selectedTechnicianID: technicianID,
            actorEmployeeID: actorEmployeeID,
            decidedAt: decidedAt,
            reason: cleanReason
        )

        let assignment = try assignTechnician(
            technicianID,
            toJobID: jobID,
            scheduledStart: candidate.proposedStartDate,
            isHumanOverride: decision.wasHumanOverride
        )

        let recommendationName = recommendation.bestCandidate?.employeeName
            ?? "No eligible technician"
        let decisionNote = decision.wasHumanOverride
            ? "PFSS recommended \(recommendationName). A human selected \(candidate.employeeName). Reason: \(cleanReason)"
            : "PFSS recommendation accepted: \(candidate.employeeName) at \(candidate.scorePercentage)% confidence."
        let auditLine = "Recommendation \(recommendation.id.uuidString): \(decisionNote)"
        let existingNotes = assignment.dispatchNotes.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let combinedNotes = existingNotes.isEmpty
            ? auditLine
            : existingNotes + "\n\n" + auditLine

        _ = try assignmentEngine.updateDispatchNotes(
            assignmentID: assignment.id,
            notes: combinedNotes,
            actorEmployeeID: actorEmployeeID,
            at: decidedAt
        )

        return decision
    }

    private func legacyPolicy(
        for policy: OperationalRecommendationPolicy
    ) -> DecisionPolicy {
        switch policy {
        case .balanced:
            return .balancedWorkload
        case .fastestResponse:
            return .earliestAvailable
        case .capabilityFirst:
            return .highestSkill
        case .workloadBalance:
            return .balancedWorkload
        case .closestQualified:
            return .closestTechnician
        case .emergency:
            return .emergency
        }
    }
}
