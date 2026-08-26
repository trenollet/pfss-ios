//
//  PFSSSynchronizationHealthView.swift
//  PPS Receipt Printer
//
//  Phase 20 Step 7 – Owner/Manager synchronization health monitoring.
//

import SwiftUI

struct PFSSSynchronizationHealthView: View {
    @StateObject private var manager = PFSSCloudflareBetaManager()
    @State private var health: PFSSSynchronizationHealth?
    @State private var isLoading = true
    @State private var errorMessage = ""

    var body: some View {
        List {
            if let health {
                overallSection(health)
                alertSection(health)
                attentionSection(health)
                deviceSection(health)
                deliverySection(health.summary.pushLast24Hours)
                trendSection(health)
                Section {
                    Text(
                        "Last checked \(health.generatedAt.formatted(date: .abbreviated, time: .shortened)). Pull down to check again."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } else if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Checking company synchronization…")
                    }
                }
            } else {
                Section("Unable to Check Health") {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.red)
                    Button("Try Again") { Task { await refresh() } }
                }
            }
        }
        .navigationTitle("Synchronization Health")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    @ViewBuilder
    private func alertSection(_ health: PFSSSynchronizationHealth) -> some View {
        if !health.alerts.isEmpty {
            Section("Alerts") {
                ForEach(health.alerts) { alert in
                    VStack(alignment: .leading, spacing: 7) {
                        Label {
                            Text(alert.title).fontWeight(.semibold)
                        } icon: {
                            Image(systemName: alert.severity == "critical"
                                ? "exclamationmark.octagon.fill"
                                : "exclamationmark.triangle.fill")
                                .foregroundStyle(alert.severity == "critical"
                                    ? Color.red : Color.orange)
                        }
                        Text(alert.detail)
                            .font(.subheadline)
                        Text("Recommended: \(alert.recommendation)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(
                            "First noticed \(alert.openedAt.formatted(date: .abbreviated, time: .shortened))."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func overallSection(
        _ health: PFSSSynchronizationHealth
    ) -> some View {
        Section("Company Status") {
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text(health.status.title)
                        .font(.headline)
                    Text(overallExplanation(health))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: statusImage(health.status))
                    .foregroundStyle(statusColor(health.status))
            }
            .accessibilityElement(children: .combine)

            LabeledContent("Active Devices", value: "\(health.summary.activeDevices)")
            LabeledContent("Up to Date", value: "\(health.summary.healthyDevices)")
            if health.summary.delayedDevices > 0 {
                LabeledContent("Delayed", value: "\(health.summary.delayedDevices)")
            }
            if health.summary.actionRequiredDevices > 0 {
                LabeledContent(
                    "Devices Needing Attention",
                    value: "\(health.summary.actionRequiredDevices)"
                )
            }
            if health.summary.activeAlerts > 0 {
                LabeledContent(
                    "Active Alerts",
                    value: "\(health.summary.activeAlerts)"
                )
            }
        }
    }

    @ViewBuilder
    private func attentionSection(
        _ health: PFSSSynchronizationHealth
    ) -> some View {
        if health.summary.unresolvedConflicts > 0 ||
            health.summary.quarantinedChanges > 0 {
            Section("Manager Review") {
                if health.summary.unresolvedConflicts > 0 {
                    attentionRow(
                        "Conflicting Changes",
                        count: health.summary.unresolvedConflicts,
                        age: health.summary.oldestConflictAgeSeconds,
                        detail: "Compare the two versions and choose the correct company record."
                    )
                }
                if health.summary.quarantinedChanges > 0 {
                    attentionRow(
                        "Changes Held for Review",
                        count: health.summary.quarantinedChanges,
                        age: health.summary.oldestQuarantineAgeSeconds,
                        detail: "Repair, retry, or disregard changes that the server could not safely accept."
                    )
                }
            }
        }
    }

    private func deviceSection(
        _ health: PFSSSynchronizationHealth
    ) -> some View {
        Section("Devices") {
            ForEach(health.devices) { device in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(device.displayName)
                            .fontWeight(.semibold)
                        Spacer()
                        Label(
                            device.status.title,
                            systemImage: statusImage(device.status)
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(device.status))
                    }
                    Text("\(device.role.title) • Build \(device.appBuild ?? "Unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(device.reasons, id: \.self) { reason in
                        Text(reason)
                            .font(.subheadline)
                    }
                    if device.behindBy > 0 {
                        Text(recommendation(for: device))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "Last contacted PFSS \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func deliverySection(
        _ push: PFSSSynchronizationHealth.Summary.PushSummary
    ) -> some View {
        Section("Background Delivery • Last 24 Hours") {
            LabeledContent("Signals Sent", value: "\(push.sent)")
            LabeledContent("Accepted by Apple", value: "\(push.accepted)")
            LabeledContent("Received by Devices", value: "\(push.received)")
            LabeledContent("Syncs Completed", value: "\(push.completed)")
            if push.deferred > 0 {
                LabeledContent("Waiting on a Device", value: "\(push.deferred)")
            }
            if push.failed > 0 {
                LabeledContent("Failed", value: "\(push.failed)")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func trendSection(
        _ health: PFSSSynchronizationHealth
    ) -> some View {
        let trends = health.trendsLast7Days
        if !trends.byEntity.isEmpty || !trends.byField.isEmpty ||
            !trends.quarantineReasons.isEmpty {
            Section("Problems Seen • Last 7 Days") {
                ForEach(trends.byEntity.prefix(5)) { item in
                    LabeledContent(
                        plainName(item.entityType),
                        value: "\(item.count)"
                    )
                }
                ForEach(trends.quarantineReasons.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plainReason(item.reason))
                        Text("\(item.count) occurrence\(item.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func attentionRow(
        _ title: String,
        count: Int,
        age: Int?,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text("\(count)")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            Text(detail)
                .font(.subheadline)
            if let age {
                Text("Oldest item has waited \(plainDuration(age)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() async {
        guard !isLoading || health == nil else { return }
        isLoading = true
        errorMessage = ""
        do {
            try await manager.refreshSession()
            guard manager.currentSession?.member.role.canManageAccess == true else {
                throw PFSSCloudflareBetaError.server("manager_access_required")
            }
            let refreshedHealth = try await manager.synchronizationHealth()
            health = refreshedHealth
            NotificationCenter.default.post(
                name: .pfssSynchronizationHealthDidRefresh,
                object: refreshedHealth
            )
        } catch {
            errorMessage = friendlyError(error)
        }
        isLoading = false
    }

    private func overallExplanation(_ health: PFSSSynchronizationHealth) -> String {
        switch health.status {
        case .healthy:
            return "All active devices match the company change feed."
        case .delayed:
            return "At least one device is waiting to receive company changes."
        case .actionRequired:
            return "A device or held change needs attention from an Owner or Manager."
        }
    }

    private func recommendation(
        for device: PFSSSynchronizationHealth.Device
    ) -> String {
        if device.status == .actionRequired {
            return "Recommended: connect this device to the internet, open PFSS, and check Sync Status."
        }
        return "PFSS will retry automatically. Open the app if the change is needed immediately."
    }

    private func statusImage(_ status: PFSSSynchronizationHealthLevel) -> String {
        switch status {
        case .healthy: return "checkmark.circle.fill"
        case .delayed: return "clock.badge.exclamationmark"
        case .actionRequired: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: PFSSSynchronizationHealthLevel) -> Color {
        switch status {
        case .healthy: return .green
        case .delayed: return .orange
        case .actionRequired: return .red
        }
    }

    private func plainDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "less than a minute" }
        if seconds < 3_600 { return "\(seconds / 60) minutes" }
        if seconds < 86_400 { return "\(seconds / 3_600) hours" }
        return "\(seconds / 86_400) days"
    }

    private func plainName(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func plainReason(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized.contains("schema") {
            return "The change did not match the current record format"
        }
        if normalized.contains("requires_manager") {
            return "The change required Manager approval"
        }
        if normalized.contains("revision") || normalized.contains("conflict") {
            return "The record changed on another device first"
        }
        return plainName(value)
    }

    private func friendlyError(_ error: Error) -> String {
        if case let PFSSCloudflareBetaError.server(message) = error,
           message == "manager_access_required" || message == "forbidden" {
            return "Only an Owner or Manager can view company synchronization health."
        }
        return "PFSS could not check company synchronization health. Check the internet connection and try again."
    }
}
