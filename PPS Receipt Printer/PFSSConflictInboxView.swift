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
    var deviceValue: String
    var cloudValue: String

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
        var results: [PFSSConflictFieldComparison] = []
        compare(
            device: deviceRecord,
            cloud: cloudRecord,
            path: "",
            results: &results
        )
        return results.sorted {
            $0.fieldPath.localizedCaseInsensitiveCompare($1.fieldPath)
                == .orderedAscending
        }
    }

    private static func recordObject(
        from payload: OfflineOperationPayload
    ) -> Any? {
        guard let mutation = try? payload.decode(
            OfflineRecordMutationPayload.self,
            decoder: AppDataStore.recordSynchronizationDecoder
        ) else { return nil }
        return try? JSONSerialization.jsonObject(with: mutation.recordData)
    }

    private static func compare(
        device: Any,
        cloud: Any,
        path: String,
        results: inout [PFSSConflictFieldComparison]
    ) {
        if valuesEqual(device, cloud) { return }
        if let deviceObject = device as? [String: Any],
           let cloudObject = cloud as? [String: Any] {
            let keys = Set(deviceObject.keys).union(cloudObject.keys)
            for key in keys {
                compare(
                    device: deviceObject[key] ?? MissingValue.shared,
                    cloud: cloudObject[key] ?? MissingValue.shared,
                    path: path.isEmpty ? key : "\(path).\(key)",
                    results: &results
                )
            }
            return
        }
        results.append(PFSSConflictFieldComparison(
            fieldPath: path.isEmpty ? "record" : path,
            deviceValue: displayValue(device),
            cloudValue: displayValue(cloud)
        ))
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

struct PFSSConflictInboxView: View {
    @ObservedObject var queue: OfflineOperationQueue
    let canOverrideConflicts: Bool
    let onResolveConflict:
        (UUID, OfflineConflictResolution, String, [String]) async throws -> Void

    @State private var selectedItem: PFSSConflictInboxItem?
    @State private var resolutionError = ""
    @State private var isShowingResolutionError = false
    @State private var isResolving = false
    @State private var resolutionReason = ""

    private var items: [PFSSConflictInboxItem] {
        PFSSConflictInbox.unresolvedItems(in: queue.orderedOperations)
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
                            selectedItem = item
                        } label: {
                            conflictRow(item)
                        }
                        .buttonStyle(.plain)
                    }
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
                    "Reason (Optional)",
                    text: $resolutionReason,
                    axis: .vertical
                )
                .lineLimit(2...4)

                Button {
                    resolve(item, as: .keptRemote)
                } label: {
                    Label("Keep Cloud Version", systemImage: "icloud.and.arrow.down")
                }

                if canOverrideConflicts {
                    Button {
                        resolve(item, as: .keptLocal)
                    } label: {
                        Label(
                            "Keep Device Version",
                            systemImage: "arrow.up.doc"
                        )
                    }
                }
            } header: {
                Text("Decision")
            } footer: {
                Text(
                    canOverrideConflicts
                        ? "Keeping the device's version submits it again as an authorized reviewed replacement."
                        : "Only a Manager or Owner may replace the accepted cloud version."
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
                "Employee Device",
                value: comparison.deviceValue,
                color: .orange
            )
            comparisonValue(
                "PFSS Cloud",
                value: comparison.cloudValue,
                color: .blue
            )
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
            } catch {
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
