//
//  DecisionReasonType.swift
//  PPS Receipt Printer
//
//  Brick 12 — Typed evidence used by decision engines.
//

import Foundation

enum DecisionReasonType: String, CaseIterable, Identifiable, Codable {
    case noConflicts
    case earliestOpening
    case availableToday
    case remainingCapacity
    case lowUtilization
    case balancedWorkload
    case exactFit
    case emergencyPriority
    case highValueJob
    case fallbackPolicy
    case schedulingConflict
    case noOpening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noConflicts:
            return "No Conflicts"
        case .earliestOpening:
            return "Earliest Opening"
        case .availableToday:
            return "Available Today"
        case .remainingCapacity:
            return "Remaining Capacity"
        case .lowUtilization:
            return "Low Utilization"
        case .balancedWorkload:
            return "Balanced Workload"
        case .exactFit:
            return "Exact Fit"
        case .emergencyPriority:
            return "Emergency Priority"
        case .highValueJob:
            return "High-Value Job"
        case .fallbackPolicy:
            return "Policy Fallback"
        case .schedulingConflict:
            return "Scheduling Conflict"
        case .noOpening:
            return "No Opening"
        }
    }
}
