//
//  DecisionConfidence.swift
//  PPS Receipt Printer
//
//  Brick 12 — Human-readable decision confidence.
//

import Foundation

enum DecisionConfidence: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high
    case veryHigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .veryHigh:
            return "Very High"
        }
    }

    var starCount: Int {
        switch self {
        case .low:
            return 2
        case .medium:
            return 3
        case .high:
            return 4
        case .veryHigh:
            return 5
        }
    }

    static func from(percentage: Int) -> DecisionConfidence {
        switch min(max(percentage, 0), 100) {
        case 90...:
            return .veryHigh
        case 75..<90:
            return .high
        case 55..<75:
            return .medium
        default:
            return .low
        }
    }
}
