//
//  PFSSConflictInboxView.swift
//  PPS Receipt Printer
//
//  Phase 16 – Centralized Manager and Owner synchronization conflict inbox.
//

import CoreFoundation
import SwiftUI

struct PFSSConflictInboxItem: Identifiable, Equatable {
    let operation: PendingOfflineOperation
    let conflictingFields: [String]

    var id: UUID { operation.id }
    var detectedAt: Date { operation.conflict?.detectedAt ?? operation.updatedAt }
    var recordTitle: String {
        operation.entityType.conflictDisplayName
    }
    var recordIdentifier: String {
        operation.entityID?.uuidString.lowercased() ?? "Unknown record"
    }
    var fieldComparisons: [PFSSConflictFieldComparison] {
        PFSSConflictComparisonEngine.comparisons(for: operation)
    }
    var displayFields: [String] {
        conflictingFields.isEmpty
            ? fieldComparisons.map(\.fieldPath)
            : conflictingFields
    }
}

struct PFSSConflictFieldComparison: Identifiable, Equatable {
    var fieldPath: String
    var baseValue: String
    var deviceValue: String
    var cloudValue: String
    var operationalImpact: String

    var id: String { fieldPath }
}

enum PFSSConflictComparisonEngine {
    static func comparisons(
        for operation: PendingOfflineOperation
    ) -> [PFSSConflictFieldComparison] {
        guard let conflict = operation.conflict,
              let remote = conflict.remoteVersion,
              let deviceRecord = recordObject(from: conflict.localVersion.payload),
              let cloudRecord = recordObject(from: remote.payload) else {
            return []
        }
        let baseRecord = baseRecordObject(from: conflict.localVersion.payload)
        var results: [PFSSConflictFieldComparison] = []
        compare(
            base: baseRecord,
            device: deviceRecord,
            cloud: cloudRecord,
            path: "",
            entityType: operation.entityType,
            serverImpact: operation.metadata["conflictOperationalImpact"],
            results: &results
        )
        let serverFields = Set(operation.metadata["conflictingPaths"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? [])
        let focused = serverFields.isEmpty ? results : results.filter { comparison in
            serverFields.contains(comparison.fieldPath) || serverFields.contains {
                comparison.fieldPath.hasPrefix("\($0).")
            }
        }
        return focused.sorted {
            $0.fieldPath.localizedCaseInsensitiveCompare($1.fieldPath)
                == .orderedAscending
        }
    }

    private static func recordObject(
        from payload: OfflineOperationPayload
    ) -> Any? {
        guard let mutation = try? OfflineRecordMutationCodec.decode(
            payload,
            decoder: AppDataStore.recordSynchronizationDecoder
        ) else { return nil }
        return try? JSONSerialization.jsonObject(with: mutation.recordData)
    }

    private static func baseRecordObject(
        from payload: OfflineOperationPayload
    ) -> Any? {
        guard let envelope = try? payload.decode(
            SynchronizationMutationEnvelope.self,
            decoder: AppDataStore.recordSynchronizationDecoder
        ), let baseRecordData = envelope.baseRecordData else { return nil }
        return try? JSONSerialization.jsonObject(with: baseRecordData)
    }

    private static func compare(
        base: Any?,
        device: Any,
        cloud: Any,
        path: String,
        entityType: OfflineEntityType,
        serverImpact: String?,
        results: inout [PFSSConflictFieldComparison]
    ) {
        if valuesEqual(device, cloud) { return }
        if let base,
           valuesEqual(device, base) || valuesEqual(cloud, base) {
            return
        }
        if let deviceObject = device as? [String: Any],
           let cloudObject = cloud as? [String: Any] {
            let baseObject = base as? [String: Any]
            let keys = Set(deviceObject.keys).union(cloudObject.keys)
            for key in keys {
                compare(
                    base: baseObject?[key] ?? (baseObject == nil ? nil : MissingValue.shared),
                    device: deviceObject[key] ?? MissingValue.shared,
                    cloud: cloudObject[key] ?? MissingValue.shared,
                    path: path.isEmpty ? key : "\(path).\(key)",
                    entityType: entityType,
                    serverImpact: serverImpact,
                    results: &results
                )
            }
            return
        }
        let renderedBaseValue: String
        if let base {
            renderedBaseValue = displayValue(base)
        } else {
            renderedBaseValue = "Unavailable for older change"
        }
        results.append(PFSSConflictFieldComparison(
            fieldPath: path.isEmpty ? "record" : path,
            baseValue: renderedBaseValue,
            deviceValue: displayValue(device),
            cloudValue: displayValue(cloud),
            operationalImpact: serverImpact ?? operationalImpact(
                entityType: entityType,
                fieldPath: path
            )
        ))
    }

    private static func operationalImpact(
        entityType: OfflineEntityType,
        fieldPath: String
    ) -> String {
        let field = fieldPath.split(separator: ".").first.map(String.init) ?? fieldPath
        if entityType == .employee,
           ["roles", "role", "isActive", "accessRole", "lifecycleStatus"].contains(field) {
            return "Can change employee access or active workforce status."
        }
        if ["amountPaid", "balanceDue", "paidDate", "receipts", "total", "tax"]
            .contains(field) {
            return "Can change billing, payment, or receipt records."
        }
        if ["scheduledDate", "scheduledStart", "scheduledEnd", "scheduling",
            "arrivalWindowEnd", "completionDeadline", "routeSequence"].contains(field) {
            return "Can change when work is scheduled or routed."
        }
        if ["primaryTechnicianID", "secondaryTechnicianID", "crew",
            "assignmentPriority"].contains(field) {
            return "Can change who is responsible for the work."
        }
        if ["status", "workflowState", "lifecycleStatus", "completedDate"]
            .contains(field) {
            return "Can change the record's workflow or lifecycle state."
        }
        return "Changes shared company information on every synchronized device."
    }

    private static func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if lhs is MissingValue || rhs is MissingValue {
            return lhs is MissingValue && rhs is MissingValue
        }
        return (lhs as AnyObject).isEqual(rhs)
    }

    private static func displayValue(_ value: Any) -> String {
        if value is MissingValue || value is NSNull { return "Not set" }
        if let text = value as? String {
            if text.isEmpty { return "Empty" }
            if text.count > 240 {
                return "\(text.prefix(237))…"
            }
            return text
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "Yes" : "No"
            }
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(
               withJSONObject: value,
               options: [.sortedKeys]
           ),
           let text = String(data: data, encoding: .utf8) {
            return text.count > 240 ? "\(text.prefix(237))…" : text
        }
        return String(describing: value)
    }

    private final class MissingValue {
        static let shared = MissingValue()
        private init() {}
    }
}

enum PFSSConflictInbox {
    static func unresolvedItems(
        in operations: [PendingOfflineOperation]
    ) -> [PFSSConflictInboxItem] {
        operations.compactMap { operation in
            guard operation.status == .conflicted,
                  operation.conflict?.requiresHumanReview == true else {
                return nil
            }
            let fields = operation.metadata["conflictingPaths"]?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            return PFSSConflictInboxItem(
                operation: operation,
                conflictingFields: fields
            )
        }
        .sorted {
            if $0.detectedAt != $1.detectedAt {
                return $0.detectedAt < $1.detectedAt
            }
            return $0.operation.sequenceNumber < $1.operation.sequenceNumber
        }
    }
}

private struct PFSSRevokedDeviceConflictGroup: Identifiable {
    var sourceDeviceID: String
    var count: Int
    var id: String { sourceDeviceID }
}

struct PFSSConflictInboxView: View {
    @ObservedObject var queue: OfflineOperationQueue
    let canOverrideConflicts: Bool
    let onResolveConflict:
        (UUID, OfflineConflictResolution, String, [String]) async throws -> Void
    let onDiscardRevokedDeviceConflicts: (String, Int) async throws -> Void

    @State private var selectedItem: PFSSConflictInboxItem?
    @State private var resolutionError = ""
    @State private var isShowingResolutionError = false
    @State private var isResolving = false
    @State private var resolutionReason = ""
    @State private var cleanupGroup: PFSSRevokedDeviceConflictGroup?

    private var items: [PFSSConflictInboxItem] {
        PFSSConflictInbox.unresolvedItems(in: queue.orderedOperations)
    }

    private var deviceGroups: [PFSSRevokedDeviceConflictGroup] {
        Dictionary(grouping: items) {
            $0.operation.metadata["sourceDeviceID"] ?? ""
        }
        .compactMap { sourceDeviceID, groupedItems in
            guard !sourceDeviceID.isEmpty, groupedItems.count > 1 else { return nil }
            return PFSSRevokedDeviceConflictGroup(
                sourceDeviceID: sourceDeviceID,
                count: groupedItems.count
            )
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label(
                        items.isEmpty ? "Inbox Clear" : "Review Required",
                        systemImage: items.isEmpty
                            ? "checkmark.circle.fill"
                            : "tray.full.fill"
                    )
                    .foregroundStyle(
                        items.isEmpty ? Color.green : Color.purple
                    )
                    Spacer()
                    Text(items.count.formatted())
                        .font(.title3.weight(.semibold))
                }
            } footer: {
                Text(
                    "PFSS keeps both versions until an authorized reviewer chooses the company record to retain. Oldest conflicts appear first."
                )
            }
            .disabled(isResolving)

            Section("Unresolved Conflicts") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Conflicts Need Review",
                        systemImage: "checkmark.circle",
                        description: Text(
                            "New synchronization conflicts will appear here automatically."
                        )
                    )
                } else {
                    ForEach(items) { item in
                        Button {
                            resolutionReason = ""
                            selectedItem = item
                        } label: {
                            conflictRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }


            if canOverrideConflicts, !deviceGroups.isEmpty {
                Section {
                    ForEach(deviceGroups) { group in
                        Button(role: .destructive) {
                            cleanupGroup = group
                        } label: {
                            Label(
                                "Discard Retained Changes From Removed Device",
                                systemImage: "iphone.slash"
                            )
                        }
                        .disabled(isResolving)
                    }
                } header: {
                    Text("Disconnected Device Cleanup")
                } footer: {
                    Text(
                        "Use this only for a device that has already been removed from Account Security. PFSS keeps the accepted cloud records and clears only that revoked device's rejected copies."
                    )
                }
            }
        }
        .navigationTitle("Conflict Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                conflictReview(item)
            }
        }
        .alert("Unable to Resolve Conflict", isPresented: $isShowingResolutionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resolutionError)
        }
        .confirmationDialog(
            "Discard all retained changes from this removed device?",
            isPresented: Binding(
                get: { cleanupGroup != nil },
                set: { if !$0 { cleanupGroup = nil } }
            ),
            presenting: cleanupGroup
        ) { group in
            Button(
                "Keep Cloud Records and Discard Device Changes",
                role: .destructive
            ) {
                discardRevokedDeviceGroup(group)
            }
            Button("Cancel", role: .cancel) { cleanupGroup = nil }
        } message: { group in
            Text(
                "PFSS will retrieve the complete server list, then proceed only if the device is revoked and that exact list is still current. The decision will be recorded in the audit history."
            )
        }
    }

    private func conflictRow(_ item: PFSSConflictInboxItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.recordTitle)
                    .font(.headline)
                Spacer()
                Text(item.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if item.displayFields.isEmpty {
                Text("Entire record requires comparison")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.displayFields.map(Self.fieldLabel).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Label("Review conflict", systemImage: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .padding(.vertical, 4)
    }

    private func conflictReview(_ item: PFSSConflictInboxItem) -> some View {
        List {
            Section("Record") {
                LabeledContent("Type", value: item.recordTitle)
                LabeledContent("Detected") {
                    Text(item.detectedAt.formatted(date: .long, time: .shortened))
                }
                LabeledContent("Record ID") {
                    Text(item.recordIdentifier)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Field Comparison") {
                if item.fieldComparisons.isEmpty {
                    Text("PFSS could not decode this older conflict into individual field values. Review this as a whole-record conflict.")
                } else {
                    ForEach(item.fieldComparisons) { comparison in
                        fieldComparison(comparison)
                    }
                }
            }

            Section {
                TextField(
                    "Decision note (Optional)",
                    text: $resolutionReason,
                    axis: .vertical
                )
                .lineLimit(2...4)

                Button {
                    resolve(item, as: .keptRemote)
                } label: {
                    Label("Keep Cloud Version", systemImage: "icloud.and.arrow.down")
                }
                .disabled(isResolving)

                if canOverrideConflicts {
                    Button {
                        resolve(item, as: .keptLocal)
                    } label: {
                        Label(
                            "Keep Device Version",
                            systemImage: "arrow.up.doc"
                        )
                    }
                    .disabled(isResolving)
                }
            } header: {
                Text("Decision")
            } footer: {
                Text(
                    canOverrideConflicts
                        ? "Add a note if it will help your team understand the decision. If left blank, PFSS records the selected decision automatically. Keeping the device's version submits it again as an authorized reviewed replacement."
                        : "Add a note if it will help your team understand the decision. If left blank, PFSS records the selected decision automatically. Only a Manager or Owner may replace the accepted cloud version."
                )
            }
        }
        .navigationTitle("Review Conflict")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { selectedItem = nil }
            }
        }
    }

    private func fieldComparison(
        _ comparison: PFSSConflictFieldComparison
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                Self.fieldLabel(comparison.fieldPath),
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.purple)

            comparisonValue(
                "Common Base",
                value: comparison.baseValue,
                color: .gray
            )
            comparisonValue(
                "Employee Device",
                value: comparison.deviceValue,
                color: .orange
            )
            comparisonValue(
                "PFSS Cloud",
                value: comparison.cloudValue,
                color: .blue
            )
            Label(comparison.operationalImpact, systemImage: "arrow.triangle.branch")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func comparisonValue(
        _ title: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func resolve(
        _ item: PFSSConflictInboxItem,
        as resolution: OfflineConflictResolution
    ) {
        isResolving = true
        Task {
            do {
                try await onResolveConflict(
                    item.id,
                    resolution,
                    resolutionReason,
                    item.fieldComparisons.map(\.fieldPath)
                )
                selectedItem = nil
                resolutionReason = ""
            } catch {
                resolutionError = error.localizedDescription
                isShowingResolutionError = true
            }
            isResolving = false
        }
    }

    private func discardRevokedDeviceGroup(
        _ group: PFSSRevokedDeviceConflictGroup
    ) {
        isResolving = true
        Task {
            do {
                try await onDiscardRevokedDeviceConflicts(
                    group.sourceDeviceID,
                    group.count
                )
                cleanupGroup = nil
            } catch {
                cleanupGroup = nil
                resolutionError = error.localizedDescription
                isShowingResolutionError = true
            }
            isResolving = false
        }
    }

    nonisolated private static func fieldLabel(_ path: String) -> String {
        let leaf = path.split(separator: ".").last.map(String.init) ?? path
        return leaf
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }
}

struct PFSSQuarantineInboxItem: Identifiable {
    let operation: PendingOfflineOperation
    var id: UUID { operation.id }
    var detectedAt: Date {
        operation.metadata["quarantinedAt"].flatMap(
            ISO8601DateFormatter().date(from:)
        ) ?? operation.updatedAt
    }
    var fields: [String] {
        operation.metadata["quarantineAffectedFields"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
    var comparisons: [PFSSConflictFieldComparison] {
        PFSSConflictComparisonEngine.comparisons(for: operation)
    }
    var explanation: SynchronizationIssueExplanation {
        SynchronizationIssueExplanation.explain(
            failure: operation.failure,
            entityType: operation.entityType
        )
    }
}

enum PFSSQuarantineInbox {
    static func unresolvedItems(
        in operations: [PendingOfflineOperation]
    ) -> [PFSSQuarantineInboxItem] {
        operations.filter {
            $0.metadata["serverQuarantineID"] != nil &&
            $0.metadata["serverQuarantineStatus"] == "unresolved"
        }
        .map(PFSSQuarantineInboxItem.init)
        .sorted { $0.detectedAt < $1.detectedAt }
    }
}

struct PFSSQuarantineInboxView: View {
    @ObservedObject var queue: OfflineOperationQueue
    let employees: [EmployeeRecord]
    let onResolve:
        (UUID, OfflineQuarantineResolution, String) async throws -> Void
    let onRepairAssignment: (UUID, Assignment, String) async throws -> Void

    @State private var selectedItem: PFSSQuarantineInboxItem?
    @State private var reason = ""
    @State private var isResolving = false
    @State private var errorMessage = ""
    @State private var isShowingError = false

    private var items: [PFSSQuarantineInboxItem] {
        PFSSQuarantineInbox.unresolvedItems(in: queue.orderedOperations)
    }

    var body: some View {
        List {
            Section {
                Label(
                    items.isEmpty ? "Inbox Clear" : "Review Required",
                    systemImage: items.isEmpty
                        ? "checkmark.circle.fill"
                        : "shippingbox.fill"
                )
                .foregroundStyle(items.isEmpty ? Color.green : Color.orange)
            } footer: {
                Text(
                    "Quarantined changes remain preserved on their originating device until a Manager or Owner records a decision."
                )
            }

            Section("Quarantined Changes") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Quarantined Changes",
                        systemImage: "checkmark.circle",
                        description: Text(
                            "Changes that cannot synchronize safely will appear here automatically."
                        )
                    )
                } else {
                    ForEach(items) { item in
                        Button {
                            reason = ""
                            selectedItem = item
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.operation.entityType.conflictDisplayName)
                                        .font(.headline)
                                    Spacer()
                                    Text(item.detectedAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Text(item.explanation.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Quarantine Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            NavigationStack { review(item) }
        }
        .alert("Unable to Resolve Quarantine", isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
    }

    private func review(_ item: PFSSQuarantineInboxItem) -> some View {
        List {
            Section("Record") {
                LabeledContent(
                    "Type",
                    value: item.operation.entityType.conflictDisplayName
                )
                LabeledContent("Employee Device") {
                    Text(item.operation.metadata["sourceDeviceID"] ?? "Unknown")
                        .font(.caption.monospaced())
                }
                if let entityID = item.operation.entityID {
                    LabeledContent("Record ID") {
                        Text(entityID.uuidString.lowercased())
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Why It Was Quarantined") {
                Text(item.explanation.title)
                    .font(.headline)
                Text(item.explanation.summary)
                Label(item.explanation.impact, systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(.secondary)
                Text(item.explanation.recommendedAction)
                    .font(.subheadline.weight(.semibold))
                if let impact = item.operation.metadata[
                    "quarantineOperationalImpact"
                ] {
                    Label(impact, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                DisclosureGroup("Technical Details") {
                    if let code = item.explanation.technicalCode {
                        LabeledContent("Code") {
                            Text(code).font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    LabeledContent("Operation") {
                        Text(item.operation.metadata["sourceOperationID"]
                            ?? item.operation.id.uuidString.lowercased())
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if let raw = item.operation.metadata["quarantineReason"] {
                        Text(raw).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Exact Record Change") {
                if item.comparisons.isEmpty {
                    Text(
                        "This operation does not contain a comparable current cloud record. The attempted operation remains preserved for support review."
                    )
                } else {
                    ForEach(item.comparisons) { comparison in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.fieldLabel(comparison.fieldPath))
                                .font(.headline)
                            LabeledContent("Before", value: comparison.baseValue)
                            LabeledContent("Device Intended", value: comparison.deviceValue)
                            LabeledContent("Current Cloud", value: comparison.cloudValue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                TextField("Decision note (Optional)", text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                Button(role: .destructive) {
                    resolve(item, as: .discard)
                } label: {
                    Label("Discard Device Change", systemImage: "trash")
                }
                .disabled(isResolving)

                Button {
                    resolve(item, as: .retry)
                } label: {
                    Label("Retry Device Change", systemImage: "arrow.clockwise")
                }
                .disabled(isResolving)

                if item.operation.entityType == .assignment {
                    NavigationLink {
                        PFSSAssignmentQuarantineRepairView(
                            item: item,
                            employees: employees,
                            onSubmit: onRepairAssignment
                        )
                    } label: {
                        Label(
                            "Edit and Approve Assignment",
                            systemImage: "person.2.badge.gearshape"
                        )
                    }
                }
            } header: {
                Text("Manager Decision")
            } footer: {
                Text(
                    "Add a note if it will help your team understand the decision. If left blank, PFSS records the selected decision automatically. Discard cancels only the unaccepted device change; it does not delete the cloud record. Retry returns the preserved operation to the originating device's synchronization queue."
                )
            }
        }
        .navigationTitle("Review Quarantine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { selectedItem = nil }
            }
        }
    }

    private func resolve(
        _ item: PFSSQuarantineInboxItem,
        as resolution: OfflineQuarantineResolution
    ) {
        isResolving = true
        Task {
            do {
                try await onResolve(item.id, resolution, reason.trimmed)
                await MainActor.run {
                    isResolving = false
                    selectedItem = nil
                    reason = ""
                }
            } catch {
                await MainActor.run {
                    isResolving = false
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
        }
    }

    private static func fieldLabel(_ field: String) -> String {
        field.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        ).replacingOccurrences(of: ".", with: " › ").capitalized
    }
}

private struct PFSSAssignmentQuarantineRepairView: View {
    let item: PFSSQuarantineInboxItem
    let employees: [EmployeeRecord]
    let onSubmit: (UUID, Assignment, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var primaryID: UUID?
    @State private var supportingID: UUID?
    @State private var priority: AssignmentPriority
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private let cloudAssignment: Assignment
    private let employeeIntendedAssignment: Assignment

    init(
        item: PFSSQuarantineInboxItem,
        employees: [EmployeeRecord],
        onSubmit: @escaping (UUID, Assignment, String) async throws -> Void
    ) {
        self.item = item
        self.employees = employees
        self.onSubmit = onSubmit
        let intended = Self.decodeAssignment(item.operation.payload)
        let cloud = item.operation.conflict?.remoteVersion.flatMap {
            Self.decodeAssignment($0.payload)
        }
        let fallback = intended ?? cloud ?? Assignment(
            assignmentNumber: "Unavailable",
            jobID: UUID(),
            jobNumber: "Unavailable",
            customerNumber: "Unavailable",
            scheduling: AssignmentScheduling(
                mode: .flexibleDay,
                estimatedDurationMinutes: 60
            )
        )
        self.employeeIntendedAssignment = intended ?? fallback
        self.cloudAssignment = cloud ?? fallback
        _primaryID = State(initialValue: intended?.primaryTechnicianID
            ?? cloud?.primaryTechnicianID)
        _supportingID = State(initialValue: intended?.supportingTechnicianIDs.first
            ?? cloud?.supportingTechnicianIDs.first)
        _priority = State(initialValue: intended?.priority ?? cloud?.priority ?? .normal)
    }

    var body: some View {
        Form {
            Section("What Happened") {
                Text(item.explanation.summary)
                Text(item.explanation.impact).foregroundStyle(.secondary)
            }
            Section("Employee Intended") {
                LabeledContent("Primary Technician", value: employeeName(
                    employeeIntendedAssignment.primaryTechnicianID
                ))
                LabeledContent("Supporting Technician", value: employeeName(
                    employeeIntendedAssignment.supportingTechnicianIDs.first
                ))
                LabeledContent("Priority", value: employeeIntendedAssignment.priority.rawValue)
            }
            Section("Current Company Assignment") {
                LabeledContent("Primary Technician", value: employeeName(
                    cloudAssignment.primaryTechnicianID
                ))
                LabeledContent("Supporting Technician", value: employeeName(
                    cloudAssignment.supportingTechnicianIDs.first
                ))
                LabeledContent("Priority", value: cloudAssignment.priority.rawValue)
            }
            Section("Corrected Assignment") {
                Picker("Primary Technician", selection: $primaryID) {
                    Text("Not Assigned").tag(UUID?.none)
                    ForEach(eligibleEmployees) { employee in
                        Text(employee.displayName).tag(Optional(employee.id))
                    }
                }
                Picker("Supporting Technician", selection: $supportingID) {
                    Text("None").tag(UUID?.none)
                    ForEach(eligibleEmployees.filter { $0.id != primaryID }) { employee in
                        Text(employee.displayName).tag(Optional(employee.id))
                    }
                }
                Picker("Priority", selection: $priority) {
                    ForEach(AssignmentPriority.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            Section {
                TextField(
                    "Example: Corrected the crew to match today's schedule.",
                    text: $reason,
                    axis: .vertical
                )
                .lineLimit(2...4)
            } header: {
                Text("Approval Reason")
            } footer: {
                Text("PFSS will create a new Manager-approved assignment change and keep the original failed employee change in audit history.")
            }
        }
        .navigationTitle("Repair Assignment")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Approve Repair") { submit() }
                    .disabled(primaryID == nil || reason.trimmed.count < 10 || isSubmitting)
            }
        }
        .alert("Unable to Approve Repair", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
    }

    private var eligibleEmployees: [EmployeeRecord] {
        employees.filter { $0.isActive && $0.hasRole(.technician) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var repairedAssignment: Assignment {
        var repaired = cloudAssignment
        repaired.priority = priority
        repaired.updatedDate = Date()
        let retained = repaired.crew.members.map { member -> AssignmentCrewMember in
            var copy = member
            if copy.isActive { copy.removedDate = Date() }
            return copy
        }
        var members = retained
        if let primaryID {
            members.append(AssignmentCrewMember(
                employeeID: primaryID,
                role: .primary
            ))
        }
        if let supportingID, supportingID != primaryID {
            members.append(AssignmentCrewMember(
                employeeID: supportingID,
                role: .supporting
            ))
        }
        repaired.crew = AssignmentCrew(members: members)
        return repaired
    }

    private func submit() {
        isSubmitting = true
        Task {
            do {
                try await onSubmit(item.id, repairedAssignment, reason.trimmed)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func employeeName(_ id: UUID?) -> String {
        guard let id else { return "Not assigned" }
        return employees.first { $0.id == id }?.displayName ?? "Unknown employee"
    }

    private static func decodeAssignment(
        _ payload: OfflineOperationPayload
    ) -> Assignment? {
        guard let mutation = try? OfflineRecordMutationCodec.decode(
            payload,
            decoder: AppDataStore.recordSynchronizationDecoder
        ) else { return nil }
        return try? AppDataStore.recordSynchronizationDecoder.decode(
            Assignment.self,
            from: mutation.recordData
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension OfflineEntityType {
    var conflictDisplayName: String {
        switch self {
        case .job: return "Job"
        case .assignment: return "Assignment"
        case .invoice: return "Invoice"
        case .payment: return "Payment"
        case .route: return "Route"
        case .customer: return "Customer"
        case .site: return "Site"
        case .lead: return "Lead"
        case .estimate: return "Estimate"
        case .employee: return "Employee"
        case .catalog: return "Catalog Item"
        case .recurringWork: return "Recurring Work"
        case .custom: return "Company Record"
        }
    }
}
