//
//  DecisionPolicy.swift
//  PPS Receipt Printer
//
//  Brick 12 — Dispatch decision policies.
//

import Foundation

enum DecisionPolicy: String, CaseIterable, Identifiable, Codable {
    case balancedWorkload
    case earliestAvailable
    case closestTechnician
    case preferredTechnician
    case highestSkill
    case highestRevenue
    case emergency
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balancedWorkload:
            return "Balanced Workload"
        case .earliestAvailable:
            return "Earliest Available"
        case .closestTechnician:
            return "Closest Technician"
        case .preferredTechnician:
            return "Preferred Technician"
        case .highestSkill:
            return "Highest Skill"
        case .highestRevenue:
            return "Highest Revenue"
        case .emergency:
            return "Emergency Dispatch"
        case .custom:
            return "Custom"
        }
    }

    var summary: String {
        switch self {
        case .balancedWorkload:
            return "Favors available technicians with more remaining capacity and lower utilization."
        case .earliestAvailable:
            return "Favors the technician who can begin the job soonest."
        case .closestTechnician:
            return "Reserved for future routing and drive-time data. Uses balanced workload until routing is available."
        case .preferredTechnician:
            return "Reserved for future customer preference data. Uses balanced workload until preferences are available."
        case .highestSkill:
            return "Reserved for future skill and certification data. Uses balanced workload until skills are available."
        case .highestRevenue:
            return "Favors decisions that preserve capacity while prioritizing higher-value work."
        case .emergency:
            return "Strongly favors the first valid opening, regardless of workload balance."
        case .custom:
            return "Reserved for user-defined decision weights. Uses balanced workload until custom weights are configured."
        }
    }
}
