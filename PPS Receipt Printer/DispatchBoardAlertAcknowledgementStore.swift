//
//  DispatchBoardAlertAcknowledgementStore.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Dispatcher-reviewed operational alerts
//

import Foundation
import Combine

/// Remembers alerts that an authorized dispatcher accepted for a particular
/// operating day. Acknowledgement only changes Dispatch Board presentation;
/// it never alters the underlying Assignment, Daily Plan, or business rules.
@MainActor
final class DispatchBoardAlertAcknowledgementStore: ObservableObject {
    @Published private(set) var acknowledgedKeys: Set<String>

    private let defaults: UserDefaults
    private let storageKey = "PFSS.DispatchBoard.AcknowledgedAlerts.v1"
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.acknowledgedKeys = Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    func visibleAlerts(
        in snapshot: DispatchBoardSnapshot,
        technicianID: UUID? = nil
    ) -> [DispatchBoardAlert] {
        var encountered = Set<String>()

        return snapshot.alerts.filter { alert in
            guard isExcludedBoardNotice(alert) == false else {
                return false
            }
            if let technicianID, alert.technicianID != technicianID {
                return false
            }
            guard isAcknowledged(alert, on: snapshot.date) == false else {
                return false
            }
            return encountered.insert(alert.id).inserted
        }
    }

    func acknowledge(_ alert: DispatchBoardAlert, on date: Date) {
        acknowledgedKeys.insert(key(for: alert, on: date))
        persist()
    }

    func isAcknowledged(_ alert: DispatchBoardAlert, on date: Date) -> Bool {
        acknowledgedKeys.contains(key(for: alert, on: date))
    }

    func acknowledgedCount(on date: Date) -> Int {
        let prefix = dayPrefix(for: date)
        return acknowledgedKeys.filter { $0.hasPrefix(prefix) }.count
    }

    func restoreAcknowledgedAlerts(on date: Date) {
        let prefix = dayPrefix(for: date)
        acknowledgedKeys = acknowledgedKeys.filter { $0.hasPrefix(prefix) == false }
        persist()
    }

    private func isExcludedBoardNotice(
        _ alert: DispatchBoardAlert
    ) -> Bool {
        alert.title.localizedCaseInsensitiveCompare("Unassigned work") == .orderedSame ||
        alert.message.localizedCaseInsensitiveContains(
            "Primary Technician has not been assigned"
        ) ||
        alert.title.localizedCaseInsensitiveCompare("Non-Working Day") == .orderedSame ||
        alert.message.localizedCaseInsensitiveContains(
            "not scheduled to work on this day"
        )
    }

    private func key(for alert: DispatchBoardAlert, on date: Date) -> String {
        dayPrefix(for: date) + alert.id
    }

    private func dayPrefix(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d|",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func persist() {
        defaults.set(Array(acknowledgedKeys).sorted(), forKey: storageKey)
    }
}
