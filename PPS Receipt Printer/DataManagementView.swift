//
//  DataManagementView.swift
//  PPS Receipt Printer
//
//  Phase 16 Step 2 – Local backup export, inspection, and guarded restore.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct PFSSArchiveCandidate: Identifiable {
    let id = UUID()
    var sourceName: String
    var data: Data
    var archive: PFSSValidatedArchive
}

struct DataManagementView: View {
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var iCloudManager = PFSSICloudArchiveManager()
    @StateObject private var googleDriveManager = PFSSGoogleDriveManager()
    @StateObject private var cloudflareManager = PFSSCloudflareBetaManager()

    @State private var backups: [PFSSLocalBackup] = []
    @State private var exportDocument: PFSSArchiveDocument?
    @State private var exportFileName = "PFSS-Backup"
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var candidate: PFSSArchiveCandidate?
    @State private var messageTitle = ""
    @State private var message = ""
    @State private var isShowingMessage = false
    @State private var isShowingClearConfirmation = false
    @State private var isShowingFinalClearConfirmation = false
    @State private var cloudflareEnrollmentCode = ""
    @State private var isRecoveryExpanded = false

    private let backupService = PFSSLocalBackupService()

    var body: some View {
        List {
            companyDataSection
            companyAccessSection

            if isOwner {
                ownerRecoverySection
            }
        }
        .navigationTitle("Data Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadBackups()
            iCloudManager.refresh()
            if googleDriveManager.state == .connected {
                refreshGoogleDrive()
            }
            if cloudflareManager.isEnrolled {
                refreshCloudflare()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .pfssCompanyDataWasRemoved
            )
        ) { _ in
            exportDocument = nil
            candidate = nil
            isExporting = false
            isImporting = false
            googleDriveManager.disconnect()
            cloudflareManager.disconnect()
            reloadBackups()
            showMessage(
                "Company Access Removed",
                "This device no longer has access. Company-owned data and stored recovery credentials were removed."
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .pfssOwnerRecoveryAuthorizationWasRevoked
            )
        ) { _ in
            discardOwnerRecoveryState()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .pfssArchive,
            defaultFilename: exportFileName
        ) { result in
            if case let .failure(error) = result {
                showMessage("Export Failed", error.localizedDescription)
            } else {
                Task {
                    do {
                        try await recordRecoveryAudit(
                            .externalBackup,
                            provider: .localFile
                        )
                    } catch {
                        showMessage(
                            "Export Audit Failed",
                            error.localizedDescription
                        )
                    }
                }
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pfssArchive, .json],
            allowsMultipleSelection: false
        ) { result in
            importSelection(result)
        }
        .sheet(item: $candidate) { candidate in
            NavigationStack {
                PFSSArchiveInspectionView(candidate: candidate) {
                    restore(candidate)
                }
            }
        }
        .alert(messageTitle, isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
        }
        .confirmationDialog(
            "Clear the Local Database?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                isShowingFinalClearConfirmation = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "This will remove all customers, sites, leads, estimates, jobs, invoices, employees, assignments, catalog data, and pending sync actions from this device."
            )
        }
        .alert(
            "Final Warning — This Cannot Be Undone",
            isPresented: $isShowingFinalClearConfirmation
        ) {
            Button("Clear All Local Data", role: .destructive) {
                clearLocalDatabase()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "Continuing will permanently clear the local PFSS database. Make sure you have a backup if you may need this data again."
            )
        }
    }

    private func discardOwnerRecoveryState() {
        exportDocument = nil
        candidate = nil
        isExporting = false
        isImporting = false
        isRecoveryExpanded = false
        googleDriveManager.disconnect()
    }

    private var isOwner: Bool {
        cloudflareManager.currentSession?.member.role == .owner
    }

    private var companyDataSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: cloudflareStatusImage)
                    .font(.title2)
                    .foregroundStyle(cloudflareStatusColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("PFSS Cloud")
                        .fontWeight(.semibold)
                    Text(companyDataStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let session = cloudflareManager.currentSession {
                LabeledContent("Company", value: session.tenant.displayName)
                LabeledContent("This Device", value: session.device.displayName)
            } else if !cloudflareManager.isEnrolled {
                companyEnrollmentControls
            }
        } header: {
            Text("Company Data")
        } footer: {
            Text(
                "PFSS keeps company data protected and synchronized automatically. No manual backup action is needed for everyday use."
            )
        }
    }

    @ViewBuilder
    private var companyEnrollmentControls: some View {
        SecureField(
            "One-time device enrollment code",
            text: $cloudflareEnrollmentCode
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

        Button {
            enrollCloudflareBeta()
        } label: {
            Label("Activate Company Access", systemImage: "lock.shield")
        }
        .disabled(
            cloudflareEnrollmentCode.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty ||
            cloudflareIsBusy
        )
    }

    private var companyAccessSection: some View {
        Section {
            if let session = cloudflareManager.currentSession {
                LabeledContent(
                    "Signed In As",
                    value: session.member.displayName
                )
                LabeledContent("Access Role", value: session.member.role.title)
            }

            if cloudflareManager.currentSession?.member.role.canManageAccess == true {
                LabeledContent(
                    "Team Access",
                    value: "\(cloudflareManager.members.count) member\(cloudflareManager.members.count == 1 ? "" : "s")"
                )
                LabeledContent(
                    "Enrolled Devices",
                    value: cloudflareManager.devices.filter {
                        $0.revokedAt == nil
                    }.count.formatted()
                )
            }

            NavigationLink {
                EmployeesView()
            } label: {
                Label("Manage Access by Employee", systemImage: "person.2")
            }

            if isOwner {
                NavigationLink {
                    PFSSCloudflareAccessManagementView(
                        manager: cloudflareManager,
                        navigationTitle: "Access Overview"
                    )
                } label: {
                    Label(
                        "Company Access Overview",
                        systemImage: "person.3.sequence"
                    )
                }

                NavigationLink {
                    PFSSConflictAuditView()
                } label: {
                    Label(
                        "Conflict Decision Audit",
                        systemImage: "checkmark.shield"
                    )
                }
            }
        } header: {
            Text("People & Devices")
        } footer: {
            Text(
                "Invitations, licenses, and device access are managed from each employee's record."
            )
        }
    }

    private var ownerRecoverySection: some View {
        Section {
            DisclosureGroup(isExpanded: $isRecoveryExpanded) {
                recoveryActions
                pfssRecovery
                iCloudRecovery
                googleDriveRecovery
                localBackupHistory
                restoreSafeguards

                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Label("Clear Local Database", systemImage: "trash.slash")
                }
            } label: {
                Label(
                    "Recovery Tools",
                    systemImage: "externaldrive.badge.timemachine"
                )
                .fontWeight(.semibold)
            }
        } header: {
            Text("Recovery")
        } footer: {
            Text(
                "Only the company owner can export, connect personal backup services, restore, or clear company data."
            )
        }
    }

    private var recoveryActions: some View {
        Group {
            Button {
                createBackup()
            } label: {
                Label("Export Recovery Archive", systemImage: "square.and.arrow.up")
            }

            Button {
                isImporting = true
            } label: {
                Label("Inspect Archive for Restore", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private var pfssRecovery: some View {
        if cloudflareManager.latestBackup != nil {
            Button {
                inspectLatestCloudflareBackup()
            } label: {
                Label("Inspect Latest PFSS Recovery Point", systemImage: "cloud.fill")
            }
            .disabled(cloudflareIsBusy)
        }
    }

    private var iCloudRecovery: some View {
        DisclosureGroup {
            Text(iCloudManager.availability.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                syncToICloud()
            } label: {
                Label("Back Up Now", systemImage: "icloud.and.arrow.up")
            }
            .disabled(
                iCloudManager.availability != .available ||
                iCloudManager.isWorking
            )

            Button {
                inspectLatestICloudBackup()
            } label: {
                Label("Inspect Latest Backup", systemImage: "icloud.and.arrow.down")
            }
            .disabled(
                iCloudManager.latestArchive == nil ||
                iCloudManager.isWorking
            )
        } label: {
            providerDisclosureLabel(
                title: "iCloud",
                detail: iCloudManager.availability.title,
                image: iCloudStatusImage,
                color: iCloudStatusColor
            )
        }
    }

    private var googleDriveRecovery: some View {
        DisclosureGroup {
            if googleDriveManager.state == .disconnected {
                Button {
                    connectGoogleDrive()
                } label: {
                    Label("Connect Google Drive", systemImage: "person.crop.circle.badge.plus")
                }
            } else {
                Button {
                    backUpToGoogleDrive()
                } label: {
                    Label("Back Up Now", systemImage: "arrow.up.doc")
                }
                .disabled(googleDriveIsBusy)

                Button {
                    inspectLatestGoogleDriveBackup()
                } label: {
                    Label("Inspect Latest Backup", systemImage: "arrow.down.doc")
                }
                .disabled(
                    googleDriveManager.latestArchive == nil ||
                    googleDriveIsBusy
                )

                Button(role: .destructive) {
                    googleDriveManager.disconnect()
                } label: {
                    Label("Disconnect Google Drive", systemImage: "link.slash")
                }
                .disabled(googleDriveIsBusy)
            }
        } label: {
            providerDisclosureLabel(
                title: "Google Drive",
                detail: googleDriveManager.state.title,
                image: googleDriveStatusImage,
                color: googleDriveStatusColor
            )
        }
    }

    private var localBackupHistory: some View {
        DisclosureGroup {
            if backups.isEmpty {
                Text("No local recovery archives are available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups) { backup in
                    Button {
                        inspect(backup)
                    } label: {
                        LabeledContent(
                            backup.kind.title,
                            value: backup.createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            Label(
                "Local Recovery History (\(backups.count))",
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    private var restoreSafeguards: some View {
        DisclosureGroup {
            Label("Archive integrity is verified", systemImage: "checkmark.shield")
            Label("Restore requires confirmation", systemImage: "hand.raised")
            Label("Current data is preserved first", systemImage: "arrow.counterclockwise.circle")
        } label: {
            Label("Restore Safeguards", systemImage: "checkmark.shield.fill")
        }
    }

    private var companyDataStatus: String {
        switch cloudflareManager.state {
        case .notConfigured, .notEnrolled:
            return "Company access needs activation"
        case .enrolling:
            return "Activating company access"
        case .connected:
            return "Protected and synchronized"
        case .working:
            return "Synchronizing changes"
        case .failed:
            return "Unable to synchronize"
        }
    }

    private func createBackup() {
        Task {
            do {
                let now = Date()
                let data = try store.createOwnerRecoveryArchive(createdAt: now)
                try await recordRecoveryAudit(.archiveCreated, provider: .localFile)
                _ = try backupService.save(data, kind: .manual, createdAt: now)
                exportDocument = PFSSArchiveDocument(data: data)
                exportFileName = "PFSS-Backup-\(Self.exportDateFormatter.string(from: now))"
                reloadBackups()
                isExporting = true
            } catch {
                showMessage("Backup Failed", error.localizedDescription)
            }
        }
    }

    private func clearLocalDatabase() {
        Task {
            do {
                try store.clearOwnerLocalData()
                try await recordRecoveryAudit(.localDataCleared)
                showMessage(
                    "Local Recovery Started",
                    "Local business and operational data was removed. PFSS will now rebuild this device from the protected company data before synchronization resumes. Existing backup files were preserved."
                )
            } catch {
                showMessage(
                    "Unable to Clear Local Database",
                    error.localizedDescription
                )
            }
        }
    }

    private func syncToICloud() {
        Task {
            do {
                let now = Date()
                let data = try store.createOwnerRecoveryArchive(createdAt: now)
                try await recordRecoveryAudit(.archiveCreated, provider: .iCloud)
                _ = try iCloudManager.upload(data, createdAt: now)
                try await recordRecoveryAudit(.externalBackup, provider: .iCloud)
                showMessage(
                    "iCloud Backup Complete",
                    "The validated PFSS archive was saved to iCloud Drive."
                )
            } catch {
                iCloudManager.refresh()
                showMessage("iCloud Backup Failed", error.localizedDescription)
            }
        }
    }

    private func inspectLatestICloudBackup() {
        do {
            try store.requireOwnerRecoveryAuthorization()
            let (archive, data) = try iCloudManager.latestData()
            try presentCandidate(
                data: data,
                sourceName: archive.fileURL.lastPathComponent
            )
        } catch {
            showMessage("Unable to Read iCloud Backup", error.localizedDescription)
        }
    }

    private func connectGoogleDrive() {
        Task {
            do {
                try store.requireOwnerRecoveryAuthorization()
                try await googleDriveManager.connect()
            } catch {
                showMessage("Google Drive Connection Failed", error.localizedDescription)
            }
        }
    }

    private func refreshGoogleDrive() {
        Task {
            do {
                try store.requireOwnerRecoveryAuthorization()
                try await googleDriveManager.refresh()
            } catch {
                showMessage("Google Drive Refresh Failed", error.localizedDescription)
            }
        }
    }

    private func backUpToGoogleDrive() {
        Task {
            do {
                let now = Date()
                let data = try store.createOwnerRecoveryArchive(createdAt: now)
                try await recordRecoveryAudit(
                    .archiveCreated,
                    provider: .googleDrive
                )
                try await googleDriveManager.upload(data, createdAt: now)
                try await recordRecoveryAudit(
                    .externalBackup,
                    provider: .googleDrive
                )
                showMessage(
                    "Google Drive Backup Complete",
                    "The validated PFSS archive was saved to Google Drive."
                )
            } catch {
                showMessage("Google Drive Backup Failed", error.localizedDescription)
            }
        }
    }

    private func inspectLatestGoogleDriveBackup() {
        Task {
            do {
                try store.requireOwnerRecoveryAuthorization()
                let (archive, data) = try await googleDriveManager.latestData()
                try presentCandidate(data: data, sourceName: archive.name)
            } catch {
                showMessage("Unable to Read Google Drive Backup", error.localizedDescription)
            }
        }
    }

    private func enrollCloudflareBeta() {
        Task {
            do {
                try await cloudflareManager.enroll(
                    code: cloudflareEnrollmentCode,
                    deviceName: UIDevice.current.name
                )
            } catch {
                showMessage("PFSS Cloud Activation Failed", error.localizedDescription)
                return
            }

            cloudflareEnrollmentCode = ""
            do {
                let didBootstrap: Bool
                if store.hasLocalCompanyData {
                    didBootstrap = false
                } else {
                    let data = try await cloudflareManager
                        .synchronizationBootstrapData()
                    didBootstrap = try store.applySynchronizationBootstrap(data)
                }
                showMessage(
                    "PFSS Cloud Connected",
                    didBootstrap
                        ? "Company data is ready. Close and reopen PFSS once to enable ongoing queued synchronization."
                        : "Company access is active on this device."
                )
            } catch {
                showMessage(
                    "PFSS Cloud Connected",
                    "Company access is active. Initial company data will be downloaded automatically when a synchronization snapshot becomes available."
                )
            }
        }
    }

    private func refreshCloudflare() {
        Task {
            do {
                try await cloudflareManager.refresh()
            } catch {
                showMessage("PFSS Cloud Refresh Failed", error.localizedDescription)
            }
        }
    }

    private func backUpToCloudflare() {
        Task {
            do {
                let data = try store.createOwnerRecoveryArchive()
                try await recordRecoveryAudit(
                    .archiveCreated,
                    provider: .pfssCloud
                )
                try await cloudflareManager.uploadBackup(data)
                try await recordRecoveryAudit(
                    .externalBackup,
                    provider: .pfssCloud
                )
                showMessage(
                    "PFSS Cloud Backup Complete",
                    "The recovery archive was stored securely for this company."
                )
            } catch {
                showMessage("PFSS Cloud Backup Failed", error.localizedDescription)
            }
        }
    }

    private func inspectLatestCloudflareBackup() {
        Task {
            do {
                try store.requireOwnerRecoveryAuthorization()
                let data = try await cloudflareManager.latestData()
                try presentCandidate(
                    data: data,
                    sourceName: "PFSS Cloud Recovery Point"
                )
            } catch {
                showMessage(
                    "Unable to Read PFSS Cloud Recovery Point",
                    error.localizedDescription
                )
            }
        }
    }

    private func inspect(_ backup: PFSSLocalBackup) {
        do {
            try presentCandidate(
                data: backupService.data(for: backup),
                sourceName: backup.fileURL.lastPathComponent
            )
        } catch {
            showMessage("Unable to Inspect Backup", error.localizedDescription)
        }
    }

    private func importSelection(_ result: Result<[URL], Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                let accessGranted = url.startAccessingSecurityScopedResource()
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    if accessGranted { url.stopAccessingSecurityScopedResource() }
                    throw error
                }
                if accessGranted { url.stopAccessingSecurityScopedResource() }
                try presentCandidate(data: data, sourceName: url.lastPathComponent)
                try await recordRecoveryAudit(.archiveImported, provider: .localFile)
            } catch {
                showMessage("Unable to Inspect Backup", error.localizedDescription)
            }
        }
    }

    private func presentCandidate(data: Data, sourceName: String) throws {
        let archive = try store.inspectOwnerRecoveryArchive(data)
        candidate = PFSSArchiveCandidate(
            sourceName: sourceName,
            data: data,
            archive: archive
        )
    }

    private func restore(_ candidate: PFSSArchiveCandidate) {
        Task {
            do {
                let result = try store.restoreOwnerRecoveryArchive(
                    candidate.data,
                    backupService: backupService
                )
                try await recordRecoveryAudit(.archiveRestored)
                self.candidate = nil
                reloadBackups()
                showMessage(
                    "Restore Complete",
                    "PFSS restored the selected backup. Your previous data was preserved in \(result.safetyBackup.kind.title)."
                )
            } catch {
                self.candidate = nil
                reloadBackups()
                showMessage("Restore Failed", error.localizedDescription)
            }
        }
    }

    private func recordRecoveryAudit(
        _ event: PFSSRecoveryAuditEvent,
        provider: PFSSRecoveryAuditProvider? = nil
    ) async throws {
        try store.requireOwnerRecoveryAuthorization()
        try await cloudflareManager.recordRecoveryAudit(event, provider: provider)
    }

    private func reloadBackups() {
        backups = backupService.availableBackups()
    }

    private func showMessage(_ title: String, _ body: String) {
        messageTitle = title
        message = body
        isShowingMessage = true
    }

    private func providerDisclosureLabel(
        title: String,
        detail: String,
        image: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iCloudStatusImage: String {
        switch iCloudManager.availability {
        case .checking: return "icloud"
        case .available: return "checkmark.icloud.fill"
        case .signedOut: return "person.crop.circle.badge.exclamationmark"
        case .containerUnavailable: return "icloud.slash"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private var iCloudStatusColor: Color {
        switch iCloudManager.availability {
        case .available: return .green
        case .checking: return .secondary
        case .signedOut, .containerUnavailable: return .orange
        case .failed: return .red
        }
    }

    private var googleDriveIsBusy: Bool {
        googleDriveManager.state == .connecting ||
        googleDriveManager.state == .working
    }

    private var googleDriveStatusImage: String {
        switch googleDriveManager.state {
        case .disconnected: return "externaldrive.badge.questionmark"
        case .connecting, .working: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var googleDriveStatusColor: Color {
        switch googleDriveManager.state {
        case .disconnected: return .secondary
        case .connecting, .working: return .blue
        case .connected: return .green
        case .failed: return .red
        }
    }

    private var cloudflareIsBusy: Bool {
        cloudflareManager.state == .enrolling ||
        cloudflareManager.state == .working
    }

    private var cloudflareStatusImage: String {
        switch cloudflareManager.state {
        case .notConfigured, .notEnrolled: return "cloud"
        case .enrolling, .working: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.shield.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var cloudflareStatusColor: Color {
        switch cloudflareManager.state {
        case .notConfigured, .notEnrolled: return .secondary
        case .enrolling, .working: return .blue
        case .connected: return .green
        case .failed: return .red
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct PFSSMemberActionRequest: Identifiable {
    let id = UUID()
    var member: PFSSTenantMember
    var action: PFSSTenantMemberAction
}

private struct PFSSMemberAccessRow: View {
    let member: PFSSTenantMember
    let canManage: Bool
    let onCancelInvitation: () -> Void
    let onAction: (PFSSTenantMemberAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.displayName)
                        .fontWeight(.semibold)
                    Text(member.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(member.role.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }

            if canManage {
                controls
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var controls: some View {
        switch member.status {
        case .invited:
            Button(
                "Cancel Pending Invitation",
                role: .destructive,
                action: onCancelInvitation
            )
            .font(.subheadline.weight(.semibold))
        case .active:
            actionButtons(primary: .suspend)
        case .suspended:
            actionButtons(primary: .reactivate)
        case .revoked:
            EmptyView()
        }
    }

    private func actionButtons(
        primary: PFSSTenantMemberAction
    ) -> some View {
        HStack {
            Button(primary.title) {
                onAction(primary)
            }
            Button("Revoke", role: .destructive) {
                onAction(.revoke)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}

private struct PFSSMemberAccessSection: View {
    let members: [PFSSTenantMember]
    let currentRole: PFSSTenantRole
    let currentMemberID: String?
    let onCancelInvitation: (PFSSTenantMember) -> Void
    let onAction: (PFSSTenantMember, PFSSTenantMemberAction) -> Void

    var body: some View {
        Section {
            if members.isEmpty {
                Text("No members are available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members) { member in
                    PFSSMemberAccessRow(
                        member: member,
                        canManage: canManage(member),
                        onCancelInvitation: {
                            onCancelInvitation(member)
                        },
                        onAction: { action in
                            onAction(member, action)
                        }
                    )
                }
            }
        } header: {
            Text("Company Members")
        }
    }

    private func canManage(_ member: PFSSTenantMember) -> Bool {
        guard member.id != currentMemberID,
              member.role != .owner else {
            return false
        }

        switch currentRole {
        case .owner:
            return true
        case .manager:
            return member.role == .member
        case .member:
            return false
        }
    }
}

private struct PFSSDeviceAccessRow: View {
    let device: PFSSTenantDevice
    let canRevoke: Bool
    let onRevoke: () -> Void

    private var isActive: Bool {
        device.revokedAt == nil
    }

    private var statusTitle: String {
        isActive ? "Active" : "Revoked"
    }

    private var statusColor: Color {
        isActive ? .green : .red
    }

    private var lastSeenText: String {
        device.lastSeenAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .fontWeight(.semibold)
                    Text(device.memberName + " · " + device.role.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text("Last seen " + lastSeenText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isActive && canRevoke {
                Button(
                    "Revoke Device Access",
                    role: .destructive,
                    action: onRevoke
                )
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PFSSDeviceAccessSection: View {
    let devices: [PFSSTenantDevice]
    let currentRole: PFSSTenantRole
    let currentDeviceID: String?
    let onRevoke: (PFSSTenantDevice) -> Void

    var body: some View {
        Section {
            if devices.isEmpty {
                Text("No devices are available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    PFSSDeviceAccessRow(
                        device: device,
                        canRevoke: canRevoke(device)
                    ) {
                        onRevoke(device)
                    }
                }
            }
        } header: {
            Text("Enrolled Devices")
        }
    }

    private func canRevoke(_ device: PFSSTenantDevice) -> Bool {
        guard device.id != currentDeviceID else {
            return false
        }

        switch currentRole {
        case .owner:
            return true
        case .manager:
            return device.role == .member
        case .member:
            return false
        }
    }
}

private struct PFSSCloudflareAccessManagementView: View {
    @ObservedObject var manager: PFSSCloudflareBetaManager
    var navigationTitle = "Company Access"

    @State private var isShowingInvitationForm = false
    @State private var invitation: PFSSTenantInvitation?
    @State private var deviceToRevoke: PFSSTenantDevice?
    @State private var invitationToCancel: PFSSTenantMember?
    @State private var memberAction: PFSSMemberActionRequest?
    @State private var isConfirmingCleanup = false
    @State private var showInactiveAccess = false
    @State private var alertTitle = "Access Management Error"
    @State private var errorMessage = ""
    @State private var isShowingError = false

    private var currentRole: PFSSTenantRole {
        manager.currentSession?.member.role ?? .member
    }

    private var visibleMembers: [PFSSTenantMember] {
        showInactiveAccess
            ? manager.members
            : manager.members.filter {
                $0.status == .active || $0.status == .invited
            }
    }

    private var visibleDevices: [PFSSTenantDevice] {
        showInactiveAccess
            ? manager.devices
            : manager.devices.filter { $0.revokedAt == nil }
    }

    var body: some View {
        AnyView(List {
            Section {
                LabeledContent("Role", value: currentRole.title)
                Text(authorityDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Your Authority")
            }

            PFSSMemberAccessSection(
                members: visibleMembers,
                currentRole: currentRole,
                currentMemberID: manager.currentSession?.member.id,
                onCancelInvitation: { member in
                    invitationToCancel = member
                },
                onAction: { member, action in
                    memberAction = PFSSMemberActionRequest(
                        member: member,
                        action: action
                    )
                }
            )

            PFSSDeviceAccessSection(
                devices: visibleDevices,
                currentRole: currentRole,
                currentDeviceID: manager.currentSession?.device.id
            ) { device in
                deviceToRevoke = device
            }

            Section {
                Toggle("Show Inactive and Revoked", isOn: $showInactiveAccess)

                if currentRole == .owner {
                    Button {
                        isConfirmingCleanup = true
                    } label: {
                        Label(
                            "Clear Old Access Credentials",
                            systemImage: "clock.badge.xmark"
                        )
                    }
                }
            } header: {
                Text("Access History")
            } footer: {
                Text(
                    "Expired invitation secrets are removed after 30 days. Revoked device credentials are scrubbed after 90 days. Minimal audit history is retained."
                )
            }
        })
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingInvitationForm = true
                } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                }
            }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $isShowingInvitationForm) {
            PFSSCloudflareInvitationForm(
                inviterRole: currentRole
            ) { displayName, role in
                isShowingInvitationForm = false
                Task {
                    do {
                        invitation = try await manager.createInvitation(
                            displayName: displayName,
                            role: role
                        )
                    } catch {
                        showError(error)
                    }
                }
            }
        }
        .sheet(item: $invitation) { invitation in
            PFSSCloudflareInvitationResultView(invitation: invitation)
        }
        .confirmationDialog(
            "Revoke This Device?",
            isPresented: Binding(
                get: { deviceToRevoke != nil },
                set: { if !$0 { deviceToRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke Device Access", role: .destructive) {
                guard let device = deviceToRevoke else { return }
                deviceToRevoke = nil
                Task {
                    do {
                        try await manager.revokeDevice(device)
                    } catch {
                        showError(error)
                    }
                }
            }
            Button("Cancel", role: .cancel) { deviceToRevoke = nil }
        } message: {
            Text(
                "The device will be rejected on its next request. Data already stored on that device is not remotely erased."
            )
        }
        .confirmationDialog(
            "Cancel This Invitation?",
            isPresented: Binding(
                get: { invitationToCancel != nil },
                set: { if !$0 { invitationToCancel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel Invitation", role: .destructive) {
                guard let member = invitationToCancel else { return }
                invitationToCancel = nil
                Task {
                    do {
                        try await manager.cancelInvitation(for: member)
                    } catch {
                        showError(error)
                    }
                }
            }
            Button("Keep Invitation", role: .cancel) {
                invitationToCancel = nil
            }
        } message: {
            Text("The single-use code will stop working immediately.")
        }
        .confirmationDialog(
            memberActionTitle,
            isPresented: Binding(
                get: { memberAction != nil },
                set: { if !$0 { memberAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(memberAction?.action.title ?? "Continue", role: .destructive) {
                guard let request = memberAction else { return }
                memberAction = nil
                Task {
                    do {
                        try await manager.updateMember(
                            request.member,
                            action: request.action
                        )
                    } catch {
                        showError(error)
                    }
                }
            }
            Button("Cancel", role: .cancel) { memberAction = nil }
        } message: {
            Text(memberActionMessage)
        }
        .confirmationDialog(
            "Clear Old Access Credentials?",
            isPresented: $isConfirmingCleanup,
            titleVisibility: .visible
        ) {
            Button("Run Safe Cleanup", role: .destructive) {
                Task {
                    do {
                        let result = try await manager.cleanAccessHistory()
                        showMessage(
                            "Access Cleanup Complete",
                            "Removed \(result.invitationSecretsPurged) old invitation secret(s) and scrubbed \(result.deviceCredentialsPurged) revoked device credential(s)."
                        )
                    } catch {
                        showError(error)
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "PFSS will remove only expired secret material that has passed its retention period. Member and access audit history remains available."
            )
        }
        .alert(alertTitle, isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var authorityDescription: String {
        switch currentRole {
        case .owner:
            return "Owners can invite Managers or Members and revoke any company device."
        case .manager:
            return "Managers can invite Members and revoke Member devices. Owner and Manager access remains protected."
        case .member:
            return "Members cannot administer company membership or devices."
        }
    }

    private var memberActionTitle: String {
        guard let request = memberAction else { return "Update Member?" }
        return "\(request.action.title) \(request.member.displayName)?"
    }

    private var memberActionMessage: String {
        guard let request = memberAction else { return "" }
        switch request.action {
        case .suspend:
            return "All devices for this member will be denied until the membership is reactivated."
        case .reactivate:
            return "This member's existing non-revoked devices will regain company access."
        case .revoke:
            return "The membership and every enrolled device will lose access immediately. Audit history will be retained."
        }
    }

    private func refresh() async {
        do {
            try await manager.refreshAdministration()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        alertTitle = "Access Management Error"
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func showMessage(_ title: String, _ message: String) {
        alertTitle = title
        errorMessage = message
        isShowingError = true
    }
}

private struct PFSSCloudflareInvitationForm: View {
    @Environment(\.dismiss) private var dismiss

    let inviterRole: PFSSTenantRole
    let onCreate: (String, PFSSTenantRole) -> Void

    @State private var displayName = ""
    @State private var role: PFSSTenantRole = .member

    var body: some View {
        NavigationStack {
            Form {
                Section("New Company User") {
                    TextField("Full name", text: $displayName)
                        .textContentType(.name)
                    if inviterRole == .owner {
                        Picker("Access Role", selection: $role) {
                            Text("Member").tag(PFSSTenantRole.member)
                            Text("Manager").tag(PFSSTenantRole.manager)
                        }
                    } else {
                        LabeledContent("Access Role", value: "Member")
                    }
                }
                Section {
                    Text(
                        "PFSS creates a seven-day, single-use enrollment code. The invited user receives no company access until the code is redeemed on their device."
                    )
                }
            }
            .navigationTitle("Invite User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(
                            displayName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            inviterRole == .owner ? role : .member
                        )
                    }
                    .disabled(
                        displayName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }
}

private struct PFSSCloudflareInvitationResultView: View {
    @Environment(\.dismiss) private var dismiss

    let invitation: PFSSTenantInvitation

    var body: some View {
        NavigationStack {
            List {
                Section("Single-Use Enrollment Code") {
                    Text(invitation.enrollmentCode)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = invitation.enrollmentCode
                    } label: {
                        Label("Copy Enrollment Code", systemImage: "doc.on.doc")
                    }
                }
                Section("Expiration") {
                    Text(invitation.expiresAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ))
                }
                Section {
                    Text(
                        "Share this code securely with the invited user. PFSS does not store the clear-text code and cannot display it again."
                    )
                }
            }
            .navigationTitle("Invitation Created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PFSSArchiveInspectionView: View {
    @Environment(\.dismiss) private var dismiss

    let candidate: PFSSArchiveCandidate
    let onRestore: () -> Void

    @State private var isConfirmingRestore = false

    var body: some View {
        List {
            Section("Validated Backup") {
                Label("Integrity Check Passed", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                LabeledContent("Source", value: candidate.sourceName)
                LabeledContent(
                    "Created",
                    value: candidate.archive.manifest.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                LabeledContent(
                    "Business",
                    value: candidate.archive.manifest.businessName.isEmpty
                        ? "Not named"
                        : candidate.archive.manifest.businessName
                )
                LabeledContent(
                    "App Version",
                    value: "\(candidate.archive.manifest.appVersion) (\(candidate.archive.manifest.appBuild))"
                )
                LabeledContent(
                    "Data Schema",
                    value: String(candidate.archive.manifest.dataSchemaVersion)
                )
            }

            Section("Contents") {
                countRow("Customers", candidate.archive.manifest.recordCounts.customers)
                countRow("Sites", candidate.archive.manifest.recordCounts.sites)
                countRow("Leads", candidate.archive.manifest.recordCounts.leads)
                countRow("Estimates", candidate.archive.manifest.recordCounts.estimates)
                countRow("Jobs", candidate.archive.manifest.recordCounts.jobs)
                countRow("Invoices", candidate.archive.manifest.recordCounts.invoices)
                countRow("Employees", candidate.archive.manifest.recordCounts.employees)
                countRow("Assignments", candidate.archive.manifest.recordCounts.assignments)
                countRow("Catalog Items", candidate.archive.manifest.recordCounts.catalogItems)
                countRow("Pending Sync Actions", candidate.archive.manifest.recordCounts.pendingOperations)
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingRestore = true
                } label: {
                    Label("Restore This Backup", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(
                    "Restore replaces current PFSS data. A complete safety backup of the current state will be created automatically first."
                )
            }
        }
        .navigationTitle("Inspect Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .confirmationDialog(
            "Replace Current PFSS Data?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Restore and Create Safety Backup", role: .destructive) {
                onRestore()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "PFSS will first preserve the current data locally, then restore the validated backup."
            )
        }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        LabeledContent(title, value: count.formatted())
    }
}
