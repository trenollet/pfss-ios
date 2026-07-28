//
//  AssignmentHistory.swift
//  PPS Receipt Printer
//
//  Phase 14 – Dispatch and Field Intelligence
//

import Foundation

struct AssignmentHistoryEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var type: AssignmentHistoryEventType
    var title: String
    var timestamp: Date

    /// Employee responsible for the action, when known.
    var actorEmployeeID: UUID?

    var previousStatus: AssignmentStatus?
    var resultingStatus: AssignmentStatus?

    /// Optional employee affected by a crew or ownership change.
    var affectedEmployeeID: UUID?

    var note: String?

    /// Small, durable key/value details for future analytics and diagnostics.
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        type: AssignmentHistoryEventType,
        title: String,
        timestamp: Date = Date(),
        actorEmployeeID: UUID? = nil,
        previousStatus: AssignmentStatus? = nil,
        resultingStatus: AssignmentStatus? = nil,
        affectedEmployeeID: UUID? = nil,
        note: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.timestamp = timestamp
        self.actorEmployeeID = actorEmployeeID
        self.previousStatus = previousStatus
        self.resultingStatus = resultingStatus
        self.affectedEmployeeID = affectedEmployeeID
        self.note = note
        self.metadata = metadata
    }
}

struct AssignmentHistory: Codable, Hashable {
    private(set) var events: [AssignmentHistoryEvent]

    init(events: [AssignmentHistoryEvent] = []) {
        self.events = events.sorted { $0.timestamp < $1.timestamp }
    }

    var chronologicalEvents: [AssignmentHistoryEvent] {
        events.sorted { $0.timestamp < $1.timestamp }
    }

    var reverseChronologicalEvents: [AssignmentHistoryEvent] {
        events.sorted { $0.timestamp > $1.timestamp }
    }

    var latestEvent: AssignmentHistoryEvent? {
        reverseChronologicalEvents.first
    }

    mutating func append(_ event: AssignmentHistoryEvent) {
        events.append(event)
        events.sort { $0.timestamp < $1.timestamp }
    }

    mutating func append(contentsOf newEvents: [AssignmentHistoryEvent]) {
        events.append(contentsOf: newEvents)
        events.sort { $0.timestamp < $1.timestamp }
    }
}
