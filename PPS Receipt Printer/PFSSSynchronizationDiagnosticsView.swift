//
//  PFSSSynchronizationDiagnosticsView.swift
//  PPS Receipt Printer
//
//  Phase 20 Step 7 – consent-based sync support submission.
//

import SwiftUI

struct PFSSSynchronizationDiagnosticsView: View {
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var manager = PFSSCloudflareBetaManager()

    @State private var description = ""
    @State private var consented = false
    @State private var isSending = false
    @State private var submission: PFSSSynchronizationDiagnosticSubmission?
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section("What PFSS Sends") {
                diagnosticRow(
                    "Included",
                    "Account and device identifiers, app build, sync cursor, operation and record IDs, failure codes, quarantine or conflict IDs, timestamps, and retry results.",
                    systemImage: "checkmark.shield"
                )
                diagnosticRow(
                    "Not Included",
                    "Customer names or contact details, addresses, job notes, invoices, photos, attachments, record contents, passwords, or access tokens.",
                    systemImage: "hand.raised"
                )
            }

            Section("What Were You Doing?") {
                TextEditor(text: $description)
                    .frame(minHeight: 100)
                    .onChange(of: description) { _, value in
                        if value.count > 500 {
                            description = String(value.prefix(500))
                        }
                    }
                Text("Optional • \(description.count)/500 characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $consented) {
                    Text("I agree to send these limited diagnostics")
                }

                Button {
                    sendDiagnostics()
                } label: {
                    HStack {
                        Label(
                            isSending ? "Sending Diagnostics…" : "Send Sync Diagnostics",
                            systemImage: "wave.3.right.circle"
                        )
                        Spacer()
                        if isSending { ProgressView() }
                    }
                }
                .disabled(!consented || isSending || submission != nil)
            } footer: {
                Text(
                    "The encrypted connection sends this package to PFSS company-scoped support storage. It is automatically deleted after 30 days. PFSS never sends diagnostics silently."
                )
            }

            if let submission {
                Section("Support Case Created") {
                    LabeledContent("Case Number") {
                        Text(submission.caseCode)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                    }
                    LabeledContent(
                        "Submitted",
                        value: submission.submittedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    LabeledContent(
                        "Automatic Deletion",
                        value: submission.expiresAt.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    Text(
                        "Give this case number to PFSS support so the exact device failure can be located without connecting to your device."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            if !errorMessage.isEmpty {
                Section("Unable to Send") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Send Sync Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diagnosticRow(
        _ title: String,
        _ detail: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private func sendDiagnostics() {
        isSending = true
        errorMessage = ""
        Task {
            do {
                try await manager.refreshSession()
                guard let session = manager.currentSession else {
                    throw PFSSCloudflareBetaError.notEnrolled
                }
                let bundle = PFSSSynchronizationDiagnosticCollector.make(
                    store: store,
                    session: session,
                    description: description
                )
                submission = try await manager.submitSynchronizationDiagnostics(
                    bundle
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
