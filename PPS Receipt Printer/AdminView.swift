//
//  AdminView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var cloudManager = PFSSCloudflareBetaManager()
    @State private var isConfirmingLogout = false
    @State private var logoutError = ""
    @State private var isShowingLogoutError = false

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
    }

    private var syncPresentationState: OfflineSyncPresentationState {
        OfflineSyncStatusResolver.resolve(
            mode: store.offlineSynchronizationMode,
            queue: store.offlineOperationQueue,
            connectivity: store.offlineConnectivityMonitor.status,
            cloudAccessStatus: store.cloudSynchronizationAccessStatus
        )
    }

    var body: some View {
        List {
                if store.shouldPresentAuthenticatedUserInfo {
                    Section("User Info") {
                        if let employee = store.authenticatedCloudEmployee {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(employee.displayName)
                                    .font(.headline)
                                Text(employee.roleDisplayText)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            Label(
                                "No Linked Employee Profile",
                                systemImage: "person.crop.circle.badge.exclamationmark"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if store.canManageCompany {
                    Section("Business") {
                    if cloudManager.currentSession?.member.role == .owner {
                        NavigationLink {
                            PFSSOwnerWorkProfileView(manager: cloudManager)
                        } label: {
                            Label(
                                "My Work Roles",
                                systemImage: "person.badge.key"
                            )
                        }
                    }
                    NavigationLink {
                        BusinessProfileView()
                    } label: {
                        Label(
                            "Business Profile",
                            systemImage: "building.2"
                        )
                    }
                    NavigationLink {
                        EmployeesView()
                    } label: {
                        Label(
                            "Employees & Capacity",
                            systemImage: "person.3"
                        )
                    }
                    }
                }

                Section("Reports") {
                    NavigationLink {
                        SitesView()
                    } label: {
                        Label(
                            "Sites",
                            systemImage: "house"
                        )
                    }

                    NavigationLink {
                        JobHistoryReportView()
                    } label: {
                        Label(
                            "Job History Report",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }

                if store.canManageCompany {
                    Section("Configuration") {
                    NavigationLink {
                        RecommendationRuleEditorView()
                    } label: {
                        Label(
                            "Recommendation Rules",
                            systemImage: "sparkles"
                        )
                    }
                    }
                }

                Section("Printing") {
                    if store.canManageCompany {
                        NavigationLink {
                            ServiceCatalogView()
                        } label: {
                            Label("Catalog Items", systemImage: "square.grid.2x2")
                        }
                    }

                    NavigationLink {
                        PrintView()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                }

                if store.canManageCompany {
                    Section("Data") {
                        NavigationLink {
                            DataManagementView()
                        } label: {
                            Label(
                                "Data Management",
                                systemImage: "externaldrive"
                            )
                        }
                    }
                }

                Section("App Information") {
                    if store.shouldPresentAuthenticatedUserInfo {
                        NavigationLink {
                            OfflineSyncDetailsView(
                                queue: store.offlineOperationQueue,
                                connectivity: store.offlineConnectivityMonitor,
                                mode: store.offlineSynchronizationMode,
                                cloudAccessStatus: store.cloudSynchronizationAccessStatus,
                                canOverrideConflicts: store.canOverrideSynchronizationConflicts,
                                onSyncNow: store.offlineSynchronizationService.map { service in
                                    { service.syncNow() }
                                },
                                onResolveConflict: { operationID, resolution in
                                    try store.resolveRecordConflict(
                                        operationID: operationID,
                                        resolution: resolution
                                    )
                                }
                            )
                        } label: {
                            HStack {
                                Text("Sync Status")
                                Spacer()
                                Label(
                                    syncPresentationState.title,
                                    systemImage: syncPresentationState.systemImage
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(syncPresentationState.color)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "Synchronization status: \(syncPresentationState.title)"
                            )
                            .accessibilityHint(syncPresentationState.detail)
                        }
                    }
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }

                if let member = cloudManager.currentSession?.member,
                   member.role == .owner {
                    Section("Account Security") {
                        NavigationLink {
                            PFSSOwnerAccountSecurityView(
                                manager: cloudManager
                            )
                        } label: {
                            Label(
                                "Recovery & Owner Devices",
                                systemImage: "lock.shield"
                            )
                        }
                    }

                    Section("Logged In Owner") {
                        LabeledContent("Name", value: member.displayName)
                        LabeledContent(
                            "Email Address",
                            value: member.email ?? "Unavailable"
                        )
                    }
                }

                if cloudManager.isEnrolled {
                    Section {
                        Button("Log Out of PFSS", role: .destructive) {
                            isConfirmingLogout = true
                        }
                    } footer: {
                        Text(
                            "Logging out removes company information and secure access from this device. It does not delete the company account."
                        )
                    }
                }
        }
        .task {
            if cloudManager.isEnrolled {
                try? await cloudManager.refreshSession()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Log Out of PFSS?",
            isPresented: $isConfirmingLogout,
            titleVisibility: .visible
        ) {
            Button("Log Out and Clear This Device", role: .destructive) {
                do {
                    try cloudManager.logOut()
                } catch {
                    logoutError = error.localizedDescription
                    isShowingLogoutError = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "This device will return to the PFSS activation and new-company setup screen. The server account remains active."
            )
        }
        .alert("Unable to Log Out", isPresented: $isShowingLogoutError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logoutError)
        }
    }
}

private struct PFSSOwnerAccountSecurityView: View {
    @ObservedObject var manager: PFSSCloudflareBetaManager
    @State private var recoveryStatus: PFSSOwnerRecoveryCodeStatus?
    @State private var generatedCodes: [String] = []
    @State private var isShowingOwnerInvitationForm = false
    @State private var ownerInvitation: PFSSOwnerAccountInvitation?
    @State private var ownerMemberToRevoke: PFSSTenantMember?
    @State private var isConfirmingReplacement = false
    @State private var deviceToRevoke: PFSSTenantDevice?
    @State private var isWorking = false
    @State private var errorMessage = ""
    @State private var isShowingError = false

    private var ownerDevices: [PFSSTenantDevice] {
        manager.devices.filter { $0.role == .owner }
    }

    private var ownerMembers: [PFSSTenantMember] {
        manager.members.filter {
            $0.role == .owner && $0.status != .revoked
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(ownerMembers) { member in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(member.displayName)
                            Spacer()
                            Text(member.status.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    member.status == .active
                                        ? Color.green : Color.orange
                                )
                        }
                        if member.id == manager.currentSession?.member.id {
                            Text("Current Owner")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(
                                member.status == .invited
                                    ? "Cancel Owner Invitation"
                                    : "Revoke Owner Access",
                                role: .destructive
                            ) {
                                ownerMemberToRevoke = member
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }

                Button {
                    isShowingOwnerInvitationForm = true
                } label: {
                    Label("Invite Another Owner", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Company Owners")
            } footer: {
                Text(
                    "Each Owner verifies a separately invited email and receives independent sign-in, recovery, and device access. PFSS always protects the final active Owner."
                )
            }

            Section {
                if let recoveryStatus {
                    LabeledContent(
                        "Unused Codes",
                        value: recoveryStatus.availableCodes.formatted()
                    )
                    if let createdAt = recoveryStatus.createdAt {
                        LabeledContent("Last Created") {
                            Text(createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            ))
                        }
                    }
                } else {
                    ProgressView("Checking recovery protection")
                }

                Button {
                    isConfirmingReplacement = true
                } label: {
                    Label(
                        "Create New Recovery Codes",
                        systemImage: "key.horizontal"
                    )
                }
                .disabled(isWorking)
            } header: {
                Text("Recovery Codes")
            } footer: {
                Text(
                    "Store these codes somewhere safe outside PFSS. Creating a new set permanently disables every unused code from the previous set."
                )
            }

            Section {
                if ownerDevices.isEmpty {
                    Text("No Owner devices are available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ownerDevices) { device in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(device.displayName)
                                Spacer()
                                if device.id == manager.currentSession?.device.id {
                                    Text("This Device")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                } else if device.revokedAt != nil {
                                    Text("Revoked")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                            }
                            Text("Last active \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if device.id != manager.currentSession?.device.id,
                               device.revokedAt == nil {
                                Button("Revoke Lost Device", role: .destructive) {
                                    deviceToRevoke = device
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Owner Devices")
            } footer: {
                Text(
                    "A revoked device is denied immediately and receives a company-data removal command when it next contacts PFSS."
                )
            }
        }
        .navigationTitle("Account Security")
        .task { await refresh() }
        .confirmationDialog(
            "Replace Recovery Codes?",
            isPresented: $isConfirmingReplacement,
            titleVisibility: .visible
        ) {
            Button("Create and Replace Codes", role: .destructive) {
                replaceCodes()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every unused recovery code from the current set will stop working immediately.")
        }
        .confirmationDialog(
            "Revoke This Owner Device?",
            isPresented: Binding(
                get: { deviceToRevoke != nil },
                set: { if !$0 { deviceToRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke Lost Device", role: .destructive) {
                revokeSelectedDevice()
            }
            Button("Cancel", role: .cancel) { deviceToRevoke = nil }
        } message: {
            Text("The device will lose company access and remove PFSS company data the next time it connects.")
        }
        .confirmationDialog(
            ownerMemberToRevoke?.status == .invited
                ? "Cancel This Owner Invitation?"
                : "Revoke This Owner?",
            isPresented: Binding(
                get: { ownerMemberToRevoke != nil },
                set: { if !$0 { ownerMemberToRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                ownerMemberToRevoke?.status == .invited
                    ? "Cancel Invitation" : "Revoke Owner Access",
                role: .destructive
            ) {
                revokeSelectedOwner()
            }
            Button("Cancel", role: .cancel) { ownerMemberToRevoke = nil }
        } message: {
            Text(
                "Revoking an active Owner also revokes all of that Owner's devices. This cannot remove the current or final active Owner."
            )
        }
        .sheet(isPresented: $isShowingOwnerInvitationForm) {
            PFSSOwnerInvitationForm { displayName, email in
                isShowingOwnerInvitationForm = false
                createOwnerInvitation(displayName: displayName, email: email)
            }
        }
        .sheet(item: $ownerInvitation) { invitation in
            PFSSOwnerInvitationResultView(invitation: invitation)
        }
        .sheet(isPresented: Binding(
            get: { !generatedCodes.isEmpty },
            set: { if !$0 { generatedCodes = [] } }
        )) {
            NavigationStack {
                List {
                    Section {
                        Text("Save these codes now. PFSS will not display this set again.")
                            .font(.headline)
                        ForEach(generatedCodes, id: \.self) { code in
                            Text(code)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    Section {
                        ShareLink(
                            item: generatedCodes.joined(separator: "\n"),
                            subject: Text("PFSS Owner Recovery Codes")
                        ) {
                            Label("Save or Share Codes", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .navigationTitle("Recovery Codes")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { generatedCodes = [] }
                    }
                }
            }
        }
        .alert("Unable to Update Security", isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func refresh() async {
        do {
            async let status = manager.ownerRecoveryCodeStatus()
            async let administration: Void = manager.refreshAdministration()
            recoveryStatus = try await status
            try await administration
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func replaceCodes() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let receipt = try await manager.replaceOwnerRecoveryCodes()
                generatedCodes = receipt.recoveryCodes
                recoveryStatus = PFSSOwnerRecoveryCodeStatus(
                    availableCodes: receipt.recoveryCodes.count,
                    createdAt: receipt.createdAt
                )
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
    }

    private func revokeSelectedDevice() {
        guard let device = deviceToRevoke else { return }
        deviceToRevoke = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await manager.revokeDevice(device)
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
    }

    private func createOwnerInvitation(displayName: String, email: String) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                ownerInvitation = try await manager.createOwnerInvitation(
                    displayName: displayName,
                    email: email
                )
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
    }

    private func revokeSelectedOwner() {
        guard let member = ownerMemberToRevoke else { return }
        ownerMemberToRevoke = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await manager.revokeOwnerMember(member)
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
    }
}

private struct PFSSOwnerInvitationForm: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String) -> Void
    @State private var displayName = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full name", text: $displayName)
                        .textContentType(.name)
                    TextField("owner@company.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                } header: {
                    Text("New Company Owner")
                } footer: {
                    Text(
                        "The invited person must verify this exact email address before PFSS activates Owner authority."
                    )
                }
            }
            .navigationTitle("Invite Owner")
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
                            email.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).lowercased()
                        )
                    }
                    .disabled(
                        displayName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        !email.contains("@")
                    )
                }
            }
        }
    }
}

private struct PFSSOwnerInvitationResultView: View {
    @Environment(\.dismiss) private var dismiss
    let invitation: PFSSOwnerAccountInvitation

    var body: some View {
        NavigationStack {
            List {
                Section("Invited Owner") {
                    LabeledContent("Name", value: invitation.displayName)
                    LabeledContent("Email", value: invitation.email)
                }
                Section("Single-Use Owner Invitation") {
                    Text(invitation.invitationCode)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    ShareLink(
                        item: invitation.invitationCode,
                        subject: Text("PFSS Owner Invitation")
                    ) {
                        Label("Share Invitation Code", systemImage: "square.and.arrow.up")
                    }
                }
                Section("Expires") {
                    Text(invitation.expiresAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ))
                }
                Section {
                    Text(
                        "The invited Owner selects Accept Owner Invitation on Get Started, enters this code, and verifies \(invitation.email) through WorkOS."
                    )
                }
            }
            .navigationTitle("Owner Invitation")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PFSSOwnerWorkProfileView: View {
    @ObservedObject var manager: PFSSCloudflareBetaManager
    @State private var isSalesperson = true
    @State private var isTechnician = true
    @State private var isSaving = false
    @State private var message = ""
    @State private var isShowingMessage = false

    var body: some View {
        Form {
            Section {
                Toggle("Sales", isOn: $isSalesperson)
                Toggle("Technician", isOn: $isTechnician)
            } header: {
                Text("Operational Roles")
            } footer: {
                Text(
                    "Your Owner authority remains unchanged. These choices let PFSS assign sales and service work to you."
                )
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(
                        isSaving ? "Saving Work Roles" : "Save Work Roles",
                        systemImage: "checkmark.circle"
                    )
                }
                .disabled(
                    isSaving || (!isSalesperson && !isTechnician)
                )
            }
        }
        .navigationTitle("My Work Roles")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Owner Work Profile", isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                var roles = Set<PFSSOwnerOperationalRole>()
                if isSalesperson { roles.insert(.salesperson) }
                if isTechnician { roles.insert(.technician) }
                _ = try await manager.configureOwnerWorkProfile(roles: roles)
                message = "Your employee profile is ready. Synchronization will add or update you in the employee list."
            } catch {
                message = error.localizedDescription
            }
            isShowingMessage = true
        }
    }
}
