//
//  SynchronizationRecoverySummary.swift
//  PPS Receipt Printer
//
//  Phase 20 Step 4 – one durable, understandable stale-device recovery result.
//

import Foundation
import Combine

struct SynchronizationRecoverySummary: Codable, Equatable {
    var startedAt: Date
    var completedAt: Date
    var startingCursor: Int
    var endingCursor: Int
    var pulledChanges: Int
    var alreadyReflected: Int
    var supersededDeviceChanges: Int
    var requiringReview: Int

    var detail: String {
        var parts = ["Downloaded \(pulledChanges) cloud change\(pulledChanges == 1 ? "" : "s")"]
        if alreadyReflected > 0 {
            parts.append("\(alreadyReflected) already reflected")
        }
        if supersededDeviceChanges > 0 {
            parts.append("\(supersededDeviceChanges) older device change\(supersededDeviceChanges == 1 ? "" : "s") safely superseded")
        }
        if requiringReview > 0 {
            parts.append("\(requiringReview) need review")
        }
        return parts.joined(separator: " • ")
    }
}

@MainActor
final class PFSSSynchronizationRecoveryStatus: ObservableObject {
    static let shared = PFSSSynchronizationRecoveryStatus()

    @Published private(set) var latest: SynchronizationRecoverySummary?

    private let defaults: UserDefaults
    private let key = "PFSSSynchronizationRecoverySummary"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            latest = try? JSONDecoder().decode(
                SynchronizationRecoverySummary.self,
                from: data
            )
        }
    }

    func record(_ summary: SynchronizationRecoverySummary) {
        latest = summary
        if let data = try? JSONEncoder().encode(summary) {
            defaults.set(data, forKey: key)
        }
    }

    func clear() {
        latest = nil
        defaults.removeObject(forKey: key)
    }
}
