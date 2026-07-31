//
//  PFSSConflictAuditView.swift
//  PPS Receipt Printer
//
//  Phase 16 – Owner conflict-resolution audit history.
//

import SwiftUI

struct PFSSConflictAuditView: View {
    @StateObject private var manager = PFSSCloudflareBetaManager()
    @State private var events: [PFSSConflictAuditEvent] = []
    @State private var selectedEvent: PFSSConflictAuditEvent?
    @State private var errorMessage = ""
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading Audit History")
                    Spacer()
                }
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No Conflict Decisions",
                    systemImage: "checkmark.shield",
                    description: Text(
                        "Resolved synchronization conflicts will appear here."
                    )
                )
            } else {
                ForEach(events) { event in
                    Button {
                        selectedEvent = event
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Conflict Audit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                eventDetail(event)
            }
        }
        .alert("Unable to Load Audit History", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func eventRow(_ event: PFSSConflictAuditEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(event.entityType.conflictDisplayName)
                    .font(.headline)
                Spacer()
                Text(event.resolvedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(decisionTitle(event.resolution))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            Text("\(event.resolverName) • \(event.resolverRole?.title ?? "Unknown Role")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func eventDetail(_ event: PFSSConflictAuditEvent) -> some View {
        List {
            Section("Decision") {
                LabeledContent("Record", value: event.entityType.conflictDisplayName)
                LabeledContent("Result", value: decisionTitle(event.resolution))
                LabeledContent("Resolved By", value: event.resolverName)
                LabeledContent(
                    "Role",
                    value: event.resolverRole?.title ?? "Unknown Role"
                )
                LabeledContent("Resolved") {
                    Text(event.resolvedAt.formatted(date: .long, time: .shortened))
                }
                if let reason = event.reason, !reason.isEmpty {
                    LabeledContent("Reason", value: reason)
                }
            }

            Section("Affected Fields") {
                if event.affectedFields.isEmpty {
                    Text("Whole record")
                } else {
                    ForEach(event.affectedFields, id: \.self) { field in
                        Text(field)
                    }
                }
            }

            Section("Revision Evidence") {
                LabeledContent("Original Cloud Revision") {
                    revisionText(event.originalCloudRevision)
                }
                LabeledContent("Final Revision") {
                    revisionText(event.finalRevision)
                }
            }

            let comparisons = comparisons(for: event)
            Section("Original Versions") {
                if comparisons.isEmpty {
                    Text("The original complete record versions remain stored in the audit event.")
                } else {
                    ForEach(comparisons) { comparison in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(comparison.fieldPath)
                                .font(.headline)
                            Text("Device: \(comparison.deviceValue)")
                            Text("Cloud: \(comparison.cloudValue)")
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Conflict Decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { selectedEvent = nil }
            }
        }
    }

    private func comparisons(
        for event: PFSSConflictAuditEvent
    ) -> [PFSSConflictFieldComparison] {
        var operation = event.localOperation
        operation.conflict = OfflineConflictInformation(
            kind: .concurrentModification,
            detectedAt: event.detectedAt,
            localVersion: OfflineRecordVersion(
                modifiedAt: event.localOperation.createdAt,
                source: .local,
                payload: event.localOperation.payload
            ),
            remoteVersion: OfflineRecordVersion(
                revision: event.originalCloudRevision,
                modifiedAt: event.cloudOperation.createdAt,
                source: .remote,
                payload: event.cloudOperation.payload
            )
        )
        return PFSSConflictComparisonEngine.comparisons(for: operation)
    }

    private func revisionText(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .textSelection(.enabled)
    }

    private func decisionTitle(_ value: String) -> String {
        value == "keptDevice" ? "Kept Device Version" : "Kept Cloud Version"
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await manager.refreshSession()
            events = try await manager.conflictAuditEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
