//
//  EmployeeDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/14/26.
//

import SwiftUI

struct EmployeeDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cloudManager = PFSSCloudflareBetaManager()

    @State var employee: EmployeeRecord
    private let originalEmployee: EmployeeRecord

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var showingRoleSelection = false
    @State private var showingUnsavedChangesAlert = false
    @State private var showingArchiveConfirmation = false
    @State private var isArchivingEmployee = false
    @State private var lifecycleErrorMessage = ""
    @State private var showingLifecycleError = false

    @FocusState private var isInputFocused: Bool

    private let colorOptions = [
        "blue",
        "green",
        "orange",
        "purple",
        "red",
        "yellow",
        "gray"
    ]

    private let lunchOptions = [
        0,
        15,
        30,
        45,
        60
    ]

    init(employee: EmployeeRecord) {
        originalEmployee = employee
        _employee = State(initialValue: employee)

        _startTime = State(
            initialValue: Self.dateFromMinutes(
                employee.defaultStartMinutes
            )
        )

        _endTime = State(
            initialValue: Self.dateFromMinutes(
                employee.defaultEndMinutes
            )
        )
    }

    private var dailyCapacityMinutes: Int {
        let startMinutes = minutesFromDate(startTime)
        let endMinutes = minutesFromDate(endTime)

        return max(
            endMinutes
            - startMinutes
            - employee.lunchDurationMinutes,
            0
        )
    }

    var body: some View {
        Form {
            Section("Employee Setup") {
                employeeSectionLink(
                    title: "Employee",
                    subtitle: employee.roleDisplayText,
                    symbol: "person.crop.circle.fill"
                ) {
                    EmployeeIdentityEditorView(
                        employee: $employee,
                        allowsRoleEditing: store.canManageCompany
                    )
                }

                employeeSectionLink(
                    title: "Home / Base Address",
                    subtitle: employee.normalizedBaseAddress ?? "Not set",
                    symbol: "house.fill"
                ) {
                    EmployeeBaseAddressEditorView(baseAddress: $employee.baseAddress)
                }

                employeeSectionLink(
                    title: "Working Days",
                    subtitle: "\(employee.workingDays.count) days selected",
                    symbol: "calendar"
                ) {
                    EmployeeWorkingDaysEditorView(workingDays: $employee.workingDays)
                }

                employeeSectionLink(
                    title: "Normal Work Day",
                    subtitle: SchedulingCalculator.formattedDuration(minutes: dailyCapacityMinutes),
                    symbol: "clock.fill"
                ) {
                    EmployeeNormalWorkdayEditorView(
                        startTime: $startTime,
                        endTime: $endTime,
                        lunchMinutes: $employee.lunchDurationMinutes
                    )
                }

                employeeSectionLink(
                    title: "Time Off",
                    subtitle: "\(employee.workforceProfile.availabilityExceptions.filter { $0.kind == .unavailable }.count) scheduled",
                    symbol: "calendar.badge.minus"
                ) {
                    EmployeeTimeOffView(
                        exceptions: $employee.workforceProfile.availabilityExceptions,
                        employeeName: employee.displayName
                    )
                }

                NavigationLink {
                    WorkforceProfileEditorView(
                        profile: $employee.workforceProfile,
                        employeeName: employee.displayName
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            "Workforce Profile",
                            systemImage: "person.text.rectangle"
                        )
                        .fontWeight(.semibold)

                        Text(workforceProfileSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }

            if cloudManager.currentSession?.member.role.canManageAccess == true {
                Section("Company Access") {
                    NavigationLink {
                        EmployeeCompanyAccessView(
                            employee: employee,
                            manager: cloudManager
                        )
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PFSS Access & Devices")
                                    .fontWeight(.semibold)
                                Text(companyAccessSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.badge.key.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }

            if store.canManageCompany {
                Section {
                    if employee.lifecycleStatus == .archived {
                        Button {
                            store.restoreEmployee(employee)
                            dismiss()
                        } label: {
                            Label("Restore Employee", systemImage: "arrow.uturn.backward.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(role: .destructive) {
                            showingArchiveConfirmation = true
                        } label: {
                            Label("Archive Employee", systemImage: "archivebox.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isArchivingEmployee)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(employee.displayName)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingRoleSelection) {
            EmployeeRoleSelectionView(selectedRoles: $employee.roles)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(
                    employee.firstName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
        .alert(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert
        ) {
            Button("Save Changes") {
                saveChanges()
            }

            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This employee has changes that have not been saved.")
        }
        .confirmationDialog(
            "Archive \(employee.displayName)?",
            isPresented: $showingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Secure Access and Archive", role: .destructive) {
                archiveEmployeeSecurely()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "PFSS will cancel any pending invitation or suspend active company access before archiving this employee. Restoring the employee record will not automatically reactivate login access."
            )
        }
        .alert(
            "Unable to Archive Employee",
            isPresented: $showingLifecycleError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lifecycleErrorMessage)
        }
        .task {
            guard cloudManager.isEnrolled else { return }
            try? await cloudManager.refresh()
        }
    }

    private var companyAccessSummary: String {
        guard let member = employeeCloudMember else {
            return cloudManager.currentSession?.member.role.canManageAccess == true
                ? "No company login assigned"
                : "Managed by a company administrator"
        }

        let deviceCount = cloudManager.devices.filter {
            $0.memberID == member.id && $0.revokedAt == nil
        }.count
        return "\(member.status.title) · \(deviceCount) active device\(deviceCount == 1 ? "" : "s")"
    }

    private func archiveEmployeeSecurely() {
        isArchivingEmployee = true
        Task {
            defer { isArchivingEmployee = false }
            do {
                if cloudManager.isEnrolled {
                    try await cloudManager.refresh()
                    guard cloudManager.currentSession?.member.role.canManageAccess == true else {
                        throw PFSSCloudflareBetaError.server(
                            "Only an Owner or Manager can archive an employee with company access."
                        )
                    }

                    _ = try await cloudManager.secureEmployeeAccessForArchive(
                        employeeID: employee.id
                    )
                }

                store.archiveEmployee(employee)
                dismiss()
            } catch {
                lifecycleErrorMessage = error.localizedDescription
                showingLifecycleError = true
            }
        }
    }

    private var employeeCloudMember: PFSSTenantMember? {
        let employeeID = employee.id.uuidString.lowercased()
        let matches = cloudManager.members.filter {
            $0.employeeID?.lowercased() == employeeID
        }
        return matches.last(where: { $0.status != .revoked }) ?? matches.last
    }

    private func employeeSectionLink<Destination: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
            }
            .padding(.vertical, 5)
        }
    }

    private var hasUnsavedChanges: Bool {
        encodedEmployee(employeeForComparison) !=
            encodedEmployee(originalEmployee)
    }

    private var employeeForComparison: EmployeeRecord {
        var candidate = employee
        candidate.defaultStartMinutes = minutesFromDate(startTime)
        candidate.defaultEndMinutes = minutesFromDate(endTime)
        candidate.normalizeRoles()
        return candidate
    }

    private var workforceProfileSummary: String {
        let profile = employee.workforceProfile

        guard profile.hasIntelligenceData else {
            return "No operational profile information entered"
        }

        return "\(profile.skills.count) skills · \(profile.certifications.count) certifications · \(profile.resourceAccess.count) resources"
    }

    private func saveChanges() {
        isInputFocused = false

        if !store.canManageCompany {
            employee.role = originalEmployee.role
            employee.roles = originalEmployee.roles
        }

        employee.firstName =
            employee.firstName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.lastName =
            employee.lastName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.phone =
            employee.phone.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.email =
            employee.email.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.baseAddress =
            employee.baseAddress.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        employee.defaultStartMinutes =
            minutesFromDate(startTime)

        employee.defaultEndMinutes =
            minutesFromDate(endTime)

        employee.normalizeRoles()

        store.updateEmployee(employee)
        dismiss()
    }

    private func requestDismissal() {
        isInputFocused = false
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func encodedEmployee(
        _ employee: EmployeeRecord
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(employee)
    }

    private func workingDayBinding(
        for day: Workday
    ) -> Binding<Bool> {
        Binding(
            get: {
                employee.workingDays.contains(day)
            },
            set: { isWorking in
                if isWorking {
                    employee.workingDays.insert(day)
                } else {
                    employee.workingDays.remove(day)
                }
            }
        )
    }

    private func lunchLabel(
        for minutes: Int
    ) -> String {
        guard minutes > 0 else {
            return "No Lunch"
        }

        return SchedulingCalculator.formattedDuration(
            minutes: minutes
        )
    }

    private func minutesFromDate(
        _ date: Date
    ) -> Int {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )

        return
            (components.hour ?? 0) * 60
            + (components.minute ?? 0)
    }

    private static func dateFromMinutes(
        _ minutes: Int
    ) -> Date {
        let safeMinutes = max(minutes, 0)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60

        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func displayColor(
        for colorName: String
    ) -> Color {
        switch colorName.lowercased() {
        case "green":
            return .green

        case "orange":
            return .orange

        case "purple":
            return .purple

        case "red":
            return .red

        case "yellow":
            return .yellow

        case "gray":
            return .gray

        default:
            return .blue
        }
    }
}

private struct EmployeeCompanyAccessView: View {
    let employee: EmployeeRecord
    @ObservedObject var manager: PFSSCloudflareBetaManager

    @State private var invitation: PFSSTenantInvitation?
    @State private var deviceToRevoke: PFSSTenantDevice?
    @State private var isShowingMemberRevocation = false
    @State private var alertTitle = "Company Access"
    @State private var alertMessage = ""
    @State private var isShowingAlert = false

    private var employeeMember: PFSSTenantMember? {
        let employeeID = employee.id.uuidString.lowercased()
        let matches = manager.members.filter {
            $0.employeeID?.lowercased() == employeeID
        }
        return matches.last(where: { $0.status != .revoked }) ?? matches.last
    }

    private var employeeDevices: [PFSSTenantDevice] {
        guard let memberID = employeeMember?.id else { return [] }
        return manager.devices
            .filter { $0.memberID == memberID }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    private var currentRole: PFSSTenantRole {
        manager.currentSession?.member.role ?? .member
    }

    private var approvedInvitationRole: PFSSTenantRole? {
        PFSSEmployeeAccessRolePolicy.invitationRole(for: employee)
    }

    private var canManageEmployee: Bool {
        guard currentRole.canManageAccess else { return false }
        guard employeeMember?.role != .owner else { return false }
        if currentRole == .manager {
            return approvedInvitationRole == .member &&
                (employeeMember == nil || employeeMember?.role == .member)
        }
        return true
    }

    var body: some View {
        List {
            employeeIdentitySection

            if manager.isEnrolled {
                membershipSection
                deviceSection
            } else {
                Section {
                    ContentUnavailableView(
                        "Company Access Unavailable",
                        systemImage: "person.badge.key",
                        description: Text(
                            "Activate this device's company access before managing employee licenses."
                        )
                    )
                }
            }
        }
        .navigationTitle("Company Access")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .sheet(item: $invitation) { invitation in
            EmployeeInvitationResultView(
                employeeName: employee.displayName,
                invitation: invitation
            )
        }
        .confirmationDialog(
            "Revoke This Device?",
            isPresented: Binding(
                get: { deviceToRevoke != nil },
                set: { if !$0 { deviceToRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke and Remove Company Data", role: .destructive) {
                revokeSelectedDevice()
            }
            Button("Cancel", role: .cancel) {
                deviceToRevoke = nil
            }
        } message: {
            Text(
                "The next time this device contacts PFSS, it will remove all company-owned data and stored recovery access."
            )
        }
        .confirmationDialog(
            "Revoke Employee Access?",
            isPresented: $isShowingMemberRevocation,
            titleVisibility: .visible
        ) {
            Button("Revoke All Access", role: .destructive) {
                updateMember(.revoke)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "Every device assigned to this employee will lose access and remove company-owned data on its next PFSS connection."
            )
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private var employeeIdentitySection: some View {
        Section("Employee") {
            LabeledContent("Name", value: employee.displayName)
            if !employee.email.isEmpty {
                LabeledContent("Email", value: employee.email)
            }
            Text(
                "The employee record and security membership remain separate, securely linked records."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var membershipSection: some View {
        Section("License & Membership") {
            if let member = employeeMember {
                LabeledContent("Status", value: member.status.title)
                LabeledContent("Access Role", value: member.role.title)
                if let approvedInvitationRole,
                   member.role != approvedInvitationRole {
                    Label(
                        "Access does not match the employee's approved PFSS role.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if canManageEmployee {
                    membershipControls(member)
                }
            } else if canManageEmployee {
                if let approvedInvitationRole {
                    LabeledContent(
                        "Approved Access Role",
                        value: approvedInvitationRole.title
                    )
                }

                Button {
                    createInvitation()
                } label: {
                    Label("Create Device Invitation", systemImage: "person.badge.plus")
                }
            } else {
                Text(ownerAccessGuidance)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func membershipControls(_ member: PFSSTenantMember) -> some View {
        switch member.status {
        case .invited:
            Button("Cancel Pending Invitation", role: .destructive) {
                cancelInvitation(member)
            }
        case .active:
            Button {
                createDeviceInvitation(for: member)
            } label: {
                Label(
                    "Create Device Activation Code",
                    systemImage: "iphone.gen3.badge.plus"
                )
            }
            Button("Suspend Access") {
                updateMember(.suspend)
            }
            Button("Revoke Employee Access", role: .destructive) {
                isShowingMemberRevocation = true
            }
        case .suspended:
            Button("Reactivate Access") {
                updateMember(.reactivate)
            }
            Button("Revoke Employee Access", role: .destructive) {
                isShowingMemberRevocation = true
            }
        case .revoked:
            Text("This membership has been permanently revoked.")
                .foregroundStyle(.secondary)
            if let approvedInvitationRole {
                LabeledContent(
                    "Approved Access Role",
                    value: approvedInvitationRole.title
                )
            }
            Button {
                createInvitation()
            } label: {
                Label("Invite Employee Back", systemImage: "person.badge.plus")
            }
        }
    }

    private var deviceSection: some View {
        Section {
            if employeeDevices.isEmpty {
                Text("No devices are enrolled for this employee.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(employeeDevices) { device in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(device.displayName)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(device.revokedAt == nil ? "Active" : "Revoked")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    device.revokedAt == nil ? Color.green : Color.red
                                )
                        }
                        Text(
                            "Last seen " + device.lastSeenAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if device.revokedAt == nil && canRevoke(device) {
                            Button("Revoke Device", role: .destructive) {
                                deviceToRevoke = device
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        } header: {
            Text("Assigned Devices")
        } footer: {
            Text(
                "Revoked devices receive a mandatory company-data removal command the next time they contact PFSS."
            )
        }
    }

    private func canRevoke(_ device: PFSSTenantDevice) -> Bool {
        guard device.id != manager.currentSession?.device.id else {
            return false
        }
        return canManageEmployee
    }

    private func refresh() async {
        guard manager.isEnrolled else { return }
        do {
            try await manager.refresh()
        } catch {
            showError(error)
        }
    }

    private func createInvitation() {
        guard let approvedInvitationRole else {
            showError(PFSSCloudflareBetaError.server(
                "Owner access is created and recovered through the Owner account workflow."
            ))
            return
        }
        Task {
            do {
                invitation = try await manager.createInvitation(
                    displayName: employee.displayName,
                    role: approvedInvitationRole,
                    employeeID: employee.id
                )
            } catch {
                showError(error)
            }
        }
    }

    private func createDeviceInvitation(for member: PFSSTenantMember) {
        Task {
            do {
                invitation = try await manager.createDeviceInvitation(
                    for: member
                )
            } catch {
                showError(error)
            }
        }
    }

    private var ownerAccessGuidance: String {
        if approvedInvitationRole == nil {
            return "Owner access is managed through the Owner account workflow, not an employee device invitation."
        }
        if approvedInvitationRole == .manager && currentRole == .manager {
            return "An Owner must create access for an employee approved as a Manager."
        }
        return "No company login is assigned to this employee."
    }

    private func cancelInvitation(_ member: PFSSTenantMember) {
        Task {
            do {
                try await manager.cancelInvitation(for: member)
            } catch {
                showError(error)
            }
        }
    }

    private func updateMember(_ action: PFSSTenantMemberAction) {
        guard let member = employeeMember else { return }
        Task {
            do {
                try await manager.updateMember(member, action: action)
            } catch {
                showError(error)
            }
        }
    }

    private func revokeSelectedDevice() {
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

    private func showError(_ error: Error) {
        alertTitle = "Unable to Update Company Access"
        alertMessage = error.localizedDescription
        isShowingAlert = true
    }
}

private struct EmployeeInvitationResultView: View {
    @Environment(\.dismiss) private var dismiss

    let employeeName: String
    let invitation: PFSSTenantInvitation

    var body: some View {
        NavigationStack {
            List {
                Section("Single-Use Enrollment Code") {
                    Text(invitation.enrollmentCode)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    ShareLink(
                        item: invitation.enrollmentCode,
                        subject: Text("PFSS device enrollment for \(employeeName)")
                    ) {
                        Label("Share Enrollment Code", systemImage: "square.and.arrow.up")
                    }
                }

                Section("Expires") {
                    Text(
                        invitation.expiresAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }

                Section {
                    Text(
                        "Share this code securely with \(employeeName). It can be used once and cannot be displayed again."
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
