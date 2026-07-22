//
//  DispatchEngine+RoutePlan.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Human-reviewed route application
//

import Foundation

@MainActor
extension DispatchEngine {
    /// Applies a fully reviewed RoutePlan through the existing audited Dispatch
    /// API. The complete plan is preflighted before the first Assignment is
    /// changed so authorization or stale-data failures cannot create a partial
    /// route merely because they were discovered halfway through the loop.
    @discardableResult
    func applyRoutePlan(
        _ routePlan: RoutePlan,
        actor: DispatchActor,
        allowConstraintOverride: Bool = false,
        reason: String? = nil,
        at timestamp: Date = Date()
    ) throws -> [DispatchResult] {
        guard routePlan.unrouteableAssignmentIDs.isEmpty else {
            throw RoutePlanApplicationError.unrouteableAssignments(
                routePlan.unrouteableAssignmentIDs.count
            )
        }

        if routePlan.hasBlockingConflicts && !allowConstraintOverride {
            throw RoutePlanApplicationError.blockingConflicts
        }

        let cleanReason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if routePlan.hasBlockingConflicts && cleanReason.isEmpty {
            throw RoutePlanApplicationError.overrideReasonRequired
        }

        let orderedStops = routePlan.stops.sorted {
            $0.sequence < $1.sequence
        }
        let uniqueAssignmentIDs = Set(orderedStops.map(\.assignmentID))

        guard uniqueAssignmentIDs.count == orderedStops.count else {
            throw RoutePlanApplicationError.duplicateAssignment
        }

        // Preflight every record and permission before performing mutations.
        for stop in orderedStops {
            guard let assignment = assignment(id: stop.assignmentID) else {
                throw RoutePlanApplicationError.assignmentUnavailable(
                    stop.assignmentID
                )
            }

            guard assignment.isOperationallyActive else {
                throw RoutePlanApplicationError.assignmentInactive(
                    assignment.assignmentNumber
                )
            }

            guard assignment.crew.containsActiveEmployee(
                routePlan.technicianID
            ) else {
                throw RoutePlanApplicationError.technicianMismatch(
                    assignment.assignmentNumber
                )
            }

            let authorization = authorization(
                for: .reorderRoute,
                actor: actor,
                assignmentID: assignment.id,
                affectedTechnicianID: assignment.primaryTechnicianID
            )
            guard authorization.isAllowed else {
                throw RoutePlanApplicationError.notAuthorized(
                    authorization.reason
                )
            }
        }

        let applicationNote: String
        if routePlan.hasBlockingConflicts {
            applicationNote = "Route applied after reviewed constraint override: \(cleanReason)"
        } else if cleanReason.isEmpty {
            applicationNote = "Human-reviewed PFSS route recommendation applied."
        } else {
            applicationNote = cleanReason
        }

        var results: [DispatchResult] = []

        for stop in orderedStops {
            guard let current = assignment(id: stop.assignmentID) else {
                // The preflight above makes this unreachable unless another
                // operation changes the store during this synchronous command.
                throw RoutePlanApplicationError.assignmentUnavailable(
                    stop.assignmentID
                )
            }

            guard current.routeSequence != stop.sequence else { continue }

            let result = try reorderRoute(
                assignmentID: stop.assignmentID,
                routeSequence: stop.sequence,
                actor: actor,
                reason: applicationNote,
                at: timestamp
            )
            results.append(result)
        }

        return results
    }
}

enum RoutePlanApplicationError: LocalizedError {
    case unrouteableAssignments(Int)
    case blockingConflicts
    case overrideReasonRequired
    case duplicateAssignment
    case assignmentUnavailable(UUID)
    case assignmentInactive(String)
    case technicianMismatch(String)
    case notAuthorized(String)

    var errorDescription: String? {
        switch self {
        case .unrouteableAssignments(let count):
            return "This route has \(count) unrouteable assignment\(count == 1 ? "" : "s"). Resolve every missing or invalid address before applying it."
        case .blockingConflicts:
            return "This route violates one or more scheduling constraints. Review the conflicts before applying an override."
        case .overrideReasonRequired:
            return "Enter a reason before applying a route with scheduling conflicts."
        case .duplicateAssignment:
            return "The route contains the same assignment more than once."
        case .assignmentUnavailable:
            return "An assignment changed or became unavailable. Refresh the route before applying it."
        case .assignmentInactive(let number):
            return "\(number) is no longer active. Refresh the route before applying it."
        case .technicianMismatch(let number):
            return "\(number) is no longer assigned to this route's technician."
        case .notAuthorized(let reason):
            return reason
        }
    }
}

