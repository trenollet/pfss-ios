//
//  DecisionReason.swift
//  PPS Receipt Printer
//
//  Brick 12 — Explainable evidence attached to a decision.
//

import Foundation

struct DecisionReason: Identifiable {
    let id: UUID
    let type: DecisionReasonType
    let title: String
    let message: String
    let weight: Double
    let isPositive: Bool

    init(
        id: UUID = UUID(),
        type: DecisionReasonType,
        title: String? = nil,
        message: String,
        weight: Double,
        isPositive: Bool = true
    ) {
        self.id = id
        self.type = type
        self.title = title ?? type.displayName
        self.message = message
        self.weight = weight
        self.isPositive = isPositive
    }
}
