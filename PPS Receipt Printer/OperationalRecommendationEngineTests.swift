//
//  OperationalRecommendationEngineTests.swift
//  PPS Receipt PrinterTests
//
//  Phase 14.6 — Recommendation Engine
//

import Foundation
import XCTest
@testable import PPS_Receipt_Printer

@MainActor
final class OperationalRecommendationEngineTests: XCTestCase {
    func testQualifiedCandidateRanksAheadOfWarningCandidate() {
        let request = makeRequest()
        let qualified = makeCandidate(
            id: technicianID(1),
            name: "Avery Qualified",
            capability: .qualified,
            utilization: 0.35,
            distance: 8
        )
        let warning = makeCandidate(
            id: technicianID(2),
            name: "Blake Warning",
            capability: .qualifiedWithWarnings,
            capabilityEvidence: [
                WorkforceEvidence(
                    severity: .warning,
                    category: .skill,
                    message: "Skill verification is pending."
                )
            ],
            utilization: 0.35,
            distance: 8
        )

        let result = makeEngine().evaluate(
            request: request,
            candidates: [warning, qualified],
            generatedAt: fixedDate
        )

        XCTAssertEqual(result.bestCandidate?.employeeID, qualified.employeeID)
        XCTAssertEqual(result.rankedCandidates.map(\.rank), [1, 2])
        XCTAssertEqual(
            result.rankedCandidates[1].eligibility,
            .eligibleWithWarnings
        )
    }

    func testExpiredRequiredCredentialIsExcludedButRemainsVisible() {
        let expired = makeCandidate(
            id: technicianID(1),
            name: "Expired Credential",
            capability: .notQualified,
            capabilityEvidence: [
                WorkforceEvidence(
                    severity: .blocking,
                    category: .certification,
                    message: "Required certification OSHA 10 is expired."
                )
            ]
        )
        let eligible = makeCandidate(
            id: technicianID(2),
            name: "Eligible Technician"
        )

        let result = makeEngine().evaluate(
            request: makeRequest(),
            candidates: [expired, eligible],
            generatedAt: fixedDate
        )

        XCTAssertEqual(result.bestCandidate?.employeeID, eligible.employeeID)
        XCTAssertEqual(result.excludedCandidates.count, 1)
        XCTAssertEqual(result.excludedCandidates[0].employeeID, expired.employeeID)
        XCTAssertTrue(
            result.excludedCandidates[0].blockers.contains {
                $0.detail.localizedCaseInsensitiveContains("expired")
            }
        )
    }

    func testUnavailableEmployeeIsExcluded() {
        let unavailable = makeCandidate(
            id: technicianID(1),
            name: "Unavailable",
            availability: .unavailable
        )

        let result = makeEngine().evaluate(
            request: makeRequest(),
            candidates: [unavailable],
            generatedAt: fixedDate
        )

        XCTAssertFalse(result.hasRecommendation)
        XCTAssertEqual(result.excludedCandidates.count, 1)
        XCTAssertEqual(result.excludedCandidates[0].eligibility, .ineligible)
    }

    func testClosestQualifiedPolicyPrefersShorterTravel() {
        let near = makeCandidate(
            id: technicianID(1),
            name: "Near",
            distance: 2,
            travelMinutes: 5
        )
        let far = makeCandidate(
            id: technicianID(2),
            name: "Far",
            distance: 28,
            travelMinutes: 40
        )
        let engine = makeEngine(policy: .closestQualified)

        let result = engine.evaluate(
            request: makeRequest(),
            candidates: [far, near],
            generatedAt: fixedDate
        )

        XCTAssertEqual(result.bestCandidate?.employeeID, near.employeeID)
        XCTAssertGreaterThan(
            result.rankedCandidates[0].scorePercentage,
            result.rankedCandidates[1].scorePercentage
        )
    }

    func testWorkloadPolicyPrefersTechnicianWithMoreCapacity() {
        let open = makeCandidate(
            id: technicianID(1),
            name: "Open Capacity",
            utilization: 0.2
        )
        let busy = makeCandidate(
            id: technicianID(2),
            name: "Busy Technician",
            utilization: 0.9
        )

        let result = makeEngine(policy: .workloadBalance).evaluate(
            request: makeRequest(),
            candidates: [busy, open],
            generatedAt: fixedDate
        )

        XCTAssertEqual(result.bestCandidate?.employeeID, open.employeeID)
        XCTAssertTrue(
            result.candidates.first(where: { $0.employeeID == busy.employeeID })?
                .warnings.contains { $0.category == .workload } == true
        )
    }

    func testEmergencyPolicyPrefersFasterResponse() {
        let request = makeRequest(
            priority: .emergency,
            requestedStart: fixedDate
        )
        let fast = makeCandidate(
            id: technicianID(1),
            name: "Fast Response",
            proposedStart: fixedDate.addingTimeInterval(15 * 60),
            distance: 3,
            travelMinutes: 7
        )
        let slow = makeCandidate(
            id: technicianID(2),
            name: "Slow Response",
            proposedStart: fixedDate.addingTimeInterval(120 * 60),
            distance: 20,
            travelMinutes: 35
        )

        let result = makeEngine(policy: .emergency).evaluate(
            request: request,
            candidates: [slow, fast],
            generatedAt: fixedDate
        )

        XCTAssertEqual(result.bestCandidate?.employeeID, fast.employeeID)
        XCTAssertTrue(
            result.bestCandidate?.evidence.contains {
                $0.category == .priority
            } == true
        )
    }

    func testMissingTravelDataProducesWarningButRemainsEligible() {
        let candidate = makeCandidate(
            id: technicianID(1),
            name: "No GPS",
            hasTravel: false
        )

        let result = makeEngine().evaluate(
            request: makeRequest(),
            candidates: [candidate],
            generatedAt: fixedDate
        )

        XCTAssertTrue(result.hasRecommendation)
        XCTAssertEqual(result.bestCandidate?.eligibility, .eligibleWithWarnings)
        XCTAssertTrue(
            result.bestCandidate?.warnings.contains {
                $0.category == .dataQuality
            } == true
        )
    }

    func testIdenticalInputsProduceStableRankingRegardlessOfInputOrder() {
        let alpha = makeCandidate(
            id: technicianID(1),
            name: "Alpha Technician"
        )
        let beta = makeCandidate(
            id: technicianID(2),
            name: "Beta Technician"
        )
        let engine = makeEngine()
        let request = makeRequest()

        let first = engine.evaluate(
            request: request,
            candidates: [beta, alpha],
            generatedAt: fixedDate
        )
        let second = engine.evaluate(
            request: request,
            candidates: [alpha, beta],
            generatedAt: fixedDate
        )

        XCTAssertEqual(
            first.rankedCandidates.map(\.employeeID),
            second.rankedCandidates.map(\.employeeID)
        )
        XCTAssertEqual(first.bestCandidate?.employeeID, alpha.employeeID)
    }

    func testDuplicateTechnicianInputIsEvaluatedOnce() {
        let candidate = makeCandidate(
            id: technicianID(1),
            name: "Duplicate Technician"
        )

        let result = makeEngine().evaluate(
            request: makeRequest(),
            candidates: [candidate, candidate],
            generatedAt: fixedDate
        )

        XCTAssertEqual(result.candidates.count, 1)
    }

    func testHumanAlternativeSelectionIsRecordedAsOverride() {
        let decision = OperationalRecommendationDecision(
            recommendationResultID: UUID(),
            assignmentID: UUID(),
            disposition: .selectedAlternative,
            recommendedTechnicianID: technicianID(1),
            selectedTechnicianID: technicianID(2),
            actorEmployeeID: technicianID(9),
            decidedAt: fixedDate,
            reason: "The dispatcher knows the customer requested this technician."
        )

        XCTAssertTrue(decision.wasHumanOverride)
        XCTAssertEqual(decision.selectedTechnicianID, technicianID(2))
        XCTAssertFalse(decision.reason.isEmpty)
    }

    // MARK: - Fixtures

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_785_264_000)
    }

    private func makeEngine(
        policy: OperationalRecommendationPolicy = .balanced
    ) -> OperationalRecommendationEngine {
        OperationalRecommendationEngine(
            configuration: OperationalRecommendationConfiguration(
                policy: policy
            )
        )
    }

    private func makeRequest(
        priority: AssignmentPriority = .normal,
        requestedStart: Date? = nil
    ) -> OperationalRecommendationRequest {
        OperationalRecommendationRequest(
            assignmentID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            jobID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            evaluationDate: fixedDate,
            priority: priority,
            capabilityRequirements: WorkforceCapabilityRequirements(),
            requestedStartDate: requestedStart
        )
    }

    private func makeCandidate(
        id: UUID,
        name: String,
        capability: WorkforceCapabilityState = .qualified,
        capabilityEvidence: [WorkforceEvidence] = [],
        availability: WorkforceAvailabilityState = .available,
        utilization: Double = 0.4,
        proposedStart: Date? = nil,
        distance: Double = 8,
        travelMinutes: Int = 15,
        hasTravel: Bool = true
    ) -> OperationalRecommendationCandidateInput {
        let capacity = 480
        let assigned = Int((Double(capacity) * utilization).rounded())
        let proposed = proposedStart ?? fixedDate.addingTimeInterval(30 * 60)

        let snapshot = WorkforceTechnicianSnapshot(
            employeeID: id,
            employeeName: name,
            generatedAt: fixedDate,
            capability: WorkforceCapabilityEvaluation(
                state: capability,
                evidence: capabilityEvidence
            ),
            availability: WorkforceAvailabilityEvaluation(
                state: availability,
                availableInterval: availability.isAvailable
                    ? DateInterval(
                        start: fixedDate,
                        end: fixedDate.addingTimeInterval(8 * 60 * 60)
                    )
                    : nil,
                reason: availability.rawValue
            ),
            workload: WorkforceWorkloadSnapshot(
                employeeID: id,
                date: fixedDate,
                activeAssignmentIDs: [],
                assignmentCount: utilization >= 0.85 ? 5 : 2,
                assignedMinutes: assigned,
                capacityMinutes: capacity,
                remainingCapacityMinutes: max(capacity - assigned, 0),
                utilizationFraction: utilization,
                exceedsMaximumDailyAssignments: false
            ),
            history: WorkforceHistoricalMetrics(
                completedAssignmentCount: 20,
                onTimeArrivalRate: 0.9,
                firstTimeCompletionRate: 0.9,
                averageCustomerRating: 4.5,
                calculatedDate: fixedDate
            )
        )

        return OperationalRecommendationCandidateInput(
            employeeID: id,
            employeeName: name,
            workforce: snapshot,
            schedule: OperationalScheduleEvidence(
                hasConflictFreeOpening: true,
                proposedStartDate: proposed,
                proposedEndDate: proposed.addingTimeInterval(60 * 60),
                availableMinutes: 120
            ),
            travel: hasTravel
                ? OperationalTravelEvidence(
                    distanceMiles: distance,
                    travelMinutes: travelMinutes,
                    proposedRouteSequence: 1,
                    source: .roadNetwork,
                    isLocationResolved: true
                )
                : nil
        )
    }

    private func technicianID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "10000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
