//
//  OperationalRecommendationModels.swift
//  PPS Receipt Printer
//
//  Phase 14.6 — Recommendation Engine
//

import Foundation

// MARK: - Recommendation Request

/// The operational decision PFSS is helping a human make.
enum OperationalRecommendationPurpose: String, Codable, Hashable {
    case technicianAssignment = "Technician Assignment"
    case emergencyInsertion = "Emergency Insertion"
    case supportingTechnician = "Supporting Technician"
    case routePosition = "Route Position"
}

/// Immutable input describing the Assignment and the decision being evaluated.
///
/// The Recommendation Engine receives employees, Workforce snapshots, scheduling
/// evidence, and route evidence separately. Keeping this request identifier-based
/// prevents the recommendation domain from owning or mutating application records.
struct OperationalRecommendationRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let assignmentID: UUID
    let jobID: UUID
    let purpose: OperationalRecommendationPurpose
    let evaluationDate: Date
    let priority: AssignmentPriority
    let capabilityRequirements: WorkforceCapabilityRequirements
    let preferredTechnicianID: UUID?
    let incumbentTechnicianID: UUID?
    let requestedCrewSize: Int
    let requestedStartDate: Date?
    let latestAcceptableStartDate: Date?
    let notes: String

    init(
        id: UUID = UUID(),
        assignmentID: UUID,
        jobID: UUID,
        purpose: OperationalRecommendationPurpose = .technicianAssignment,
        evaluationDate: Date,
        priority: AssignmentPriority = .normal,
        capabilityRequirements: WorkforceCapabilityRequirements,
        preferredTechnicianID: UUID? = nil,
        incumbentTechnicianID: UUID? = nil,
        requestedCrewSize: Int = 1,
        requestedStartDate: Date? = nil,
        latestAcceptableStartDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.jobID = jobID
        self.purpose = purpose
        self.evaluationDate = evaluationDate
        self.priority = priority
        self.capabilityRequirements = capabilityRequirements
        self.preferredTechnicianID = preferredTechnicianID
        self.incumbentTechnicianID = incumbentTechnicianID
        self.requestedCrewSize = max(requestedCrewSize, 1)
        self.requestedStartDate = requestedStartDate
        self.latestAcceptableStartDate = latestAcceptableStartDate
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Candidate Input Evidence

/// Scheduling evidence prepared by Scheduling or Daily Planner for one technician.
struct OperationalScheduleEvidence: Codable, Hashable {
    let hasConflictFreeOpening: Bool
    let proposedStartDate: Date?
    let proposedEndDate: Date?
    let availableMinutes: Int
    let conflictMessages: [String]

    init(
        hasConflictFreeOpening: Bool,
        proposedStartDate: Date? = nil,
        proposedEndDate: Date? = nil,
        availableMinutes: Int = 0,
        conflictMessages: [String] = []
    ) {
        self.hasConflictFreeOpening = hasConflictFreeOpening
        self.proposedStartDate = proposedStartDate
        self.proposedEndDate = proposedEndDate
        self.availableMinutes = max(availableMinutes, 0)
        self.conflictMessages = conflictMessages
    }
}

/// Route evidence prepared by Route Engine for one technician.
struct OperationalTravelEvidence: Codable, Hashable {
    let distanceMiles: Double?
    let travelMinutes: Int?
    let proposedRouteSequence: Int?
    let source: RouteTravelEstimateSource?
    let isLocationResolved: Bool
    let warningMessages: [String]

    init(
        distanceMiles: Double? = nil,
        travelMinutes: Int? = nil,
        proposedRouteSequence: Int? = nil,
        source: RouteTravelEstimateSource? = nil,
        isLocationResolved: Bool,
        warningMessages: [String] = []
    ) {
        if let distanceMiles, distanceMiles.isFinite {
            self.distanceMiles = max(distanceMiles, 0)
        } else {
            self.distanceMiles = nil
        }

        if let travelMinutes {
            self.travelMinutes = max(travelMinutes, 0)
        } else {
            self.travelMinutes = nil
        }

        if let proposedRouteSequence {
            self.proposedRouteSequence = max(proposedRouteSequence, 0)
        } else {
            self.proposedRouteSequence = nil
        }

        self.source = source
        self.isLocationResolved = isLocationResolved
        self.warningMessages = warningMessages
    }
}

/// All explainable input for a single technician candidate.
struct OperationalRecommendationCandidateInput: Identifiable, Codable, Hashable {
    let employeeID: UUID
    let employeeName: String
    let workforce: WorkforceTechnicianSnapshot
    let schedule: OperationalScheduleEvidence
    let travel: OperationalTravelEvidence?
    let isPreferredTechnician: Bool
    let isIncumbentTechnician: Bool

    var id: UUID { employeeID }

    init(
        employeeID: UUID,
        employeeName: String,
        workforce: WorkforceTechnicianSnapshot,
        schedule: OperationalScheduleEvidence,
        travel: OperationalTravelEvidence? = nil,
        isPreferredTechnician: Bool = false,
        isIncumbentTechnician: Bool = false
    ) {
        self.employeeID = employeeID
        self.employeeName = employeeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.workforce = workforce
        self.schedule = schedule
        self.travel = travel
        self.isPreferredTechnician = isPreferredTechnician
        self.isIncumbentTechnician = isIncumbentTechnician
    }
}

// MARK: - Explainable Evidence

enum OperationalRecommendationEvidenceCategory: String, Codable, Hashable {
    case employee = "Employee"
    case skill = "Skill"
    case certification = "Certification"
    case equipment = "Equipment"
    case vehicle = "Vehicle"
    case availability = "Availability"
    case schedule = "Schedule"
    case workload = "Workload"
    case travel = "Travel"
    case history = "History"
    case preference = "Preference"
    case crewContinuity = "Crew Continuity"
    case priority = "Priority"
    case dataQuality = "Data Quality"
}

enum OperationalRecommendationEvidenceImpact: String, Codable, Hashable {
    case blocking = "Blocking"
    case warning = "Warning"
    case supporting = "Supporting"
    case informational = "Informational"
}

/// One human-readable fact used by the engine.
///
/// `scoreContribution` is retained with the result so a recommendation can be
/// audited without rerunning the engine under a later policy configuration.
struct OperationalRecommendationEvidence: Identifiable, Codable, Hashable {
    let id: UUID
    let category: OperationalRecommendationEvidenceCategory
    let impact: OperationalRecommendationEvidenceImpact
    let title: String
    let detail: String
    let scoreContribution: Double

    init(
        id: UUID = UUID(),
        category: OperationalRecommendationEvidenceCategory,
        impact: OperationalRecommendationEvidenceImpact,
        title: String,
        detail: String,
        scoreContribution: Double = 0
    ) {
        self.id = id
        self.category = category
        self.impact = impact
        self.title = title
        self.detail = detail
        self.scoreContribution = scoreContribution.isFinite
            ? scoreContribution
            : 0
    }
}

// MARK: - Ranked Results

enum OperationalRecommendationEligibility: String, Codable, Hashable {
    case eligible = "Eligible"
    case eligibleWithWarnings = "Eligible with Warnings"
    case ineligible = "Ineligible"
}

enum OperationalRecommendationConfidence: String, CaseIterable, Codable, Hashable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very High"

    static func from(percentage: Int) -> OperationalRecommendationConfidence {
        switch min(max(percentage, 0), 100) {
        case 90...: return .veryHigh
        case 75..<90: return .high
        case 55..<75: return .medium
        default: return .low
        }
    }
}

/// One ranked technician option. Ineligible candidates remain visible and
/// explain why they were excluded instead of silently disappearing.
struct OperationalRecommendationCandidate: Identifiable, Codable, Hashable {
    let employeeID: UUID
    let employeeName: String
    let rank: Int?
    let eligibility: OperationalRecommendationEligibility
    let score: Double
    let scorePercentage: Int
    let confidence: OperationalRecommendationConfidence
    let proposedStartDate: Date?
    let proposedEndDate: Date?
    let proposedRouteSequence: Int?
    let distanceMiles: Double?
    let travelMinutes: Int?
    let evidence: [OperationalRecommendationEvidence]

    var id: UUID { employeeID }

    var blockers: [OperationalRecommendationEvidence] {
        evidence.filter { $0.impact == .blocking }
    }

    var warnings: [OperationalRecommendationEvidence] {
        evidence.filter { $0.impact == .warning }
    }

    var strengths: [OperationalRecommendationEvidence] {
        evidence.filter { $0.impact == .supporting }
    }

    var isSelectable: Bool {
        eligibility != .ineligible
    }

    init(
        employeeID: UUID,
        employeeName: String,
        rank: Int? = nil,
        eligibility: OperationalRecommendationEligibility,
        score: Double,
        scorePercentage: Int,
        proposedStartDate: Date? = nil,
        proposedEndDate: Date? = nil,
        proposedRouteSequence: Int? = nil,
        distanceMiles: Double? = nil,
        travelMinutes: Int? = nil,
        evidence: [OperationalRecommendationEvidence]
    ) {
        self.employeeID = employeeID
        self.employeeName = employeeName
        self.rank = rank.map { max($0, 1) }
        self.eligibility = eligibility
        self.score = score.isFinite ? score : 0
        self.scorePercentage = min(max(scorePercentage, 0), 100)
        self.confidence = .from(percentage: self.scorePercentage)
        self.proposedStartDate = proposedStartDate
        self.proposedEndDate = proposedEndDate
        self.proposedRouteSequence = proposedRouteSequence
        self.distanceMiles = distanceMiles
        self.travelMinutes = travelMinutes
        self.evidence = evidence
    }
}

/// Immutable output returned by the Recommendation Engine.
struct OperationalRecommendationResult: Identifiable, Codable, Hashable {
    let id: UUID
    let request: OperationalRecommendationRequest
    let policy: OperationalRecommendationPolicy
    let candidates: [OperationalRecommendationCandidate]
    let generatedAt: Date
    let engineVersion: String

    var rankedCandidates: [OperationalRecommendationCandidate] {
        candidates.filter(\.isSelectable).sorted {
            ($0.rank ?? Int.max) < ($1.rank ?? Int.max)
        }
    }

    var excludedCandidates: [OperationalRecommendationCandidate] {
        candidates.filter { !$0.isSelectable }
    }

    var bestCandidate: OperationalRecommendationCandidate? {
        hasTopScoreTie ? nil : rankedCandidates.first
    }

    /// Candidates whose operational scores are effectively equal at the top.
    /// PFSS deliberately does not convert an alphabetical ordering into a
    /// recommendation when the underlying evidence cannot distinguish them.
    var leadingCandidates: [OperationalRecommendationCandidate] {
        guard let leader = rankedCandidates.first else { return [] }
        return rankedCandidates.filter {
            abs($0.score - leader.score) <= 0.5
        }
    }

    var hasTopScoreTie: Bool {
        leadingCandidates.count > 1
    }

    var hasRecommendation: Bool {
        bestCandidate != nil
    }

    init(
        id: UUID = UUID(),
        request: OperationalRecommendationRequest,
        policy: OperationalRecommendationPolicy,
        candidates: [OperationalRecommendationCandidate],
        generatedAt: Date = Date(),
        engineVersion: String = "14.6.2"
    ) {
        self.id = id
        self.request = request
        self.policy = policy
        self.candidates = candidates
        self.generatedAt = generatedAt
        self.engineVersion = engineVersion
    }
}

// MARK: - Human Decision Record

enum OperationalRecommendationDisposition: String, Codable, Hashable {
    case acceptedRecommended = "Accepted Recommendation"
    case selectedAlternative = "Selected Alternative"
    case rejected = "Rejected"
    case deferred = "Deferred"
}

/// Durable audit record of the human decision made from a recommendation.
/// Creating this value does not itself assign or dispatch a technician.
struct OperationalRecommendationDecision: Identifiable, Codable, Hashable {
    let id: UUID
    let recommendationResultID: UUID
    let assignmentID: UUID
    let disposition: OperationalRecommendationDisposition
    let recommendedTechnicianID: UUID?
    let selectedTechnicianID: UUID?
    let actorEmployeeID: UUID?
    let decidedAt: Date
    let reason: String

    var wasHumanOverride: Bool {
        disposition == .selectedAlternative ||
        (selectedTechnicianID != nil &&
            selectedTechnicianID != recommendedTechnicianID)
    }

    init(
        id: UUID = UUID(),
        recommendationResultID: UUID,
        assignmentID: UUID,
        disposition: OperationalRecommendationDisposition,
        recommendedTechnicianID: UUID?,
        selectedTechnicianID: UUID? = nil,
        actorEmployeeID: UUID? = nil,
        decidedAt: Date = Date(),
        reason: String = ""
    ) {
        self.id = id
        self.recommendationResultID = recommendationResultID
        self.assignmentID = assignmentID
        self.disposition = disposition
        self.recommendedTechnicianID = recommendedTechnicianID
        self.selectedTechnicianID = selectedTechnicianID
        self.actorEmployeeID = actorEmployeeID
        self.decidedAt = decidedAt
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
