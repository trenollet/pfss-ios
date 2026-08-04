import SwiftUI

struct OperationsRootView: View {
    @EnvironmentObject private var store: OperationsStore

    var body: some View {
        Group {
            switch store.state {
            case .restoring:
                ProgressView("Securing PFSS Operations…")
            case .signedOut:
                OperationsSignInView()
            case .signedIn:
                OperationsDashboardView()
            }
        }
        .tint(.blue)
        .alert(
            "PFSS Operations",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct OperationsSignInView: View {
    @EnvironmentObject private var store: OperationsStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 68))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("PFSS Operations")
                    .font(.largeTitle.bold())
                Text("Private platform administration")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text("Only explicitly authorized PFSS administrators may sign in. Every administrative action is recorded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Button {
                Task { await store.signIn() }
            } label: {
                Label("Secure Administrator Sign In", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: 360)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isWorking)
            if store.isWorking { ProgressView() }
        }
        .padding(32)
    }
}

private struct OperationsDashboardView: View {
    @EnvironmentObject private var store: OperationsStore
    @State private var selectedAccountID: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedAccountID) {
                Section("Platform") {
                    NavigationLink(value: "overview") {
                        Label("Overview", systemImage: "gauge.with.dots.needle.67percent")
                    }
                }
                Section("Accounts") {
                    NavigationLink(value: "accounts") {
                        Label("Review Accounts", systemImage: "building.2")
                    }
                }
            }
            .navigationTitle("PFSS Operations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Status", selection: $store.statusFilter) {
                            Text("All Accounts").tag("all")
                            Text("Active").tag("active")
                            Text("Billing Hold").tag("billingHold")
                            Text("Security Hold").tag("securityHold")
                            Text("Support Hold").tag("supportHold")
                            Text("Archived").tag("archived")
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onChange(of: store.statusFilter) { _, _ in
                Task { await store.refresh() }
            }
        } detail: {
            NavigationStack {
                if selectedAccountID == "accounts" {
                    OperationsAccountsView()
                } else if let selectedAccountID, selectedAccountID != "overview" {
                    OperationsAccountDetailView(accountID: selectedAccountID)
                } else {
                    OperationsOverviewView()
                }
            }
        }
    }
}

private struct AccountListRow: View {
    let account: OperationsAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.displayName).font(.headline)
            HStack {
                Text(account.planCode ?? "No plan")
                Text("•")
                Text(account.lifecycleStatus.displayLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(account.id)
    }
}

private struct OperationsOverviewView: View {
    @EnvironmentObject private var store: OperationsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Platform Overview").font(.largeTitle.bold())
                        if let administrator = store.administrator {
                            Text("Signed in as \(administrator.displayName)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Sign Out", role: .destructive) { store.signOut() }
                }
                if let summary = store.summary {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190))],
                        spacing: 16
                    ) {
                        NavigationLink {
                            OperationsAccountsView()
                        } label: {
                            SummaryCard("Accounts", value: summary.accounts.total,
                                        icon: "building.2")
                        }
                        .buttonStyle(.plain)
                        SummaryCard("Active Users", value: summary.users.active, icon: "person.2")
                        SummaryCard("Active Devices", value: summary.devices.active, icon: "iphone.gen3")
                        SummaryCard("Pending Removal", value: summary.devices.pendingDataRemoval, icon: "iphone.slash")
                        SummaryCard("Sync Conflicts", value: summary.errors.unresolvedSynchronizationConflicts, icon: "exclamationmark.arrow.triangle.2.circlepath")
                        SummaryCard("Failed Registrations", value: summary.errors.failedRegistrations, icon: "person.crop.circle.badge.exclamationmark")
                    }
                } else {
                    ProgressView()
                }
                if let monitoring = store.monitoring {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Provider Usage").font(.title2.bold())
                        Text("Measured usage and configured free-plan thresholds")
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(monitoring.providerMetrics) { metric in
                                ProviderMetricCard(metric: metric)
                            }
                        }
                    }
                    if !monitoring.accountAlerts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Account Threshold Alerts").font(.title2.bold())
                            ForEach(monitoring.accountAlerts) { alert in
                                HStack {
                                    Image(systemName: alert.severity == "critical"
                                          ? "exclamationmark.octagon.fill"
                                          : "exclamationmark.triangle.fill")
                                        .foregroundStyle(alert.severity == "critical"
                                                         ? .red : .orange)
                                    VStack(alignment: .leading) {
                                        Text(alert.accountName).font(.headline)
                                        Text("\(alert.resource.displayLabel): \(alert.used.formatted()) of \(alert.limit.formatted())")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(alert.utilization.formatted(.percent.precision(.fractionLength(0))))
                                        .font(.headline)
                                }
                                .padding()
                                .background(.regularMaterial,
                                            in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                    ErrorLogSummaryCard(errors: monitoring.errors)
                    Text("Updated \(monitoring.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading platform monitoring…")
                }
            }
            .padding(24)
        }
    }
}

private struct OperationsAccountsView: View {
    enum DateOrder: String, CaseIterable, Identifiable {
        case newestFirst
        case oldestFirst

        var id: String { rawValue }
        var label: String {
            switch self {
            case .newestFirst: "Newest First"
            case .oldestFirst: "Oldest First"
            }
        }
    }

    @EnvironmentObject private var store: OperationsStore
    @State private var searchText = ""
    @State private var dateOrder: DateOrder = .newestFirst

    private var visibleAccounts: [OperationsAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? store.accounts : store.accounts.filter { account in
            [account.displayName, account.id, account.planCode,
             account.lifecycleStatus]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return filtered.sorted {
            dateOrder == .newestFirst
                ? $0.createdAt > $1.createdAt
                : $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        List {
            if visibleAccounts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Accounts" : "No Matching Accounts",
                    systemImage: searchText.isEmpty ? "building.2" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                                      ? "No PFSS customer accounts are available."
                                      : "Try a different company, plan, status, or account ID.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(visibleAccounts) { account in
                    NavigationLink {
                        OperationsAccountDetailView(accountID: account.id)
                    } label: {
                        AccountListRow(account: account)
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .searchable(
            text: $searchText,
            prompt: "Company, plan, status, or account ID"
        )
        .refreshable { await store.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Status", selection: $store.statusFilter) {
                        Text("All Accounts").tag("all")
                        Text("Active").tag("active")
                        Text("Billing Hold").tag("billingHold")
                        Text("Security Hold").tag("securityHold")
                        Text("Support Hold").tag("supportHold")
                        Text("Archived").tag("archived")
                    }
                } label: {
                    Label("Filter Status", systemImage: "line.3.horizontal.decrease.circle")
                }

                Menu {
                    Picker("Date Order", selection: $dateOrder) {
                        ForEach(DateOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    Label("Sort by Date", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .onChange(of: store.statusFilter) { _, _ in
            Task { await store.refresh() }
        }
    }
}

private struct ErrorLogSummaryCard: View {
    let errors: [OperationsMonitoring.ErrorItem]

    private var criticalCount: Int {
        errors.filter { $0.severity == "critical" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary Error Log")
                        .font(.title2.bold())
                    if errors.isEmpty {
                        Label("No current operational errors",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("\(errors.count.formatted()) current issue\(errors.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if criticalCount > 0 {
                    Label(criticalCount.formatted(),
                          systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.headline)
                }
            }

            NavigationLink {
                OperationsErrorLogView(errors: errors)
            } label: {
                Label("Review Error Logs", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct OperationsErrorLogView: View {
    enum DateOrder: String, CaseIterable, Identifiable {
        case newestFirst
        case oldestFirst

        var id: String { rawValue }
        var label: String {
            switch self {
            case .newestFirst: "Newest First"
            case .oldestFirst: "Oldest First"
            }
        }
    }

    let errors: [OperationsMonitoring.ErrorItem]
    @State private var searchText = ""
    @State private var dateOrder: DateOrder = .newestFirst

    private var visibleErrors: [OperationsMonitoring.ErrorItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? errors : errors.filter { item in
            [item.summary, item.accountName, item.category, item.email,
             item.entityType, item.deviceName]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return filtered.sorted {
            dateOrder == .newestFirst
                ? $0.occurredAt > $1.occurredAt
                : $0.occurredAt < $1.occurredAt
        }
    }

    var body: some View {
        List {
            if visibleErrors.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Operational Errors" : "No Matching Errors",
                    systemImage: searchText.isEmpty
                        ? "checkmark.circle" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                                      ? "PFSS has no current errors requiring review."
                                      : "Try a different company, email, category, or message.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(visibleErrors) { item in
                    OperationsErrorRow(item: item)
                }
            }
        }
        .navigationTitle("Error Logs")
        .searchable(
            text: $searchText,
            prompt: "Company, email, category, or message"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Date Order", selection: $dateOrder) {
                        ForEach(DateOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    Label("Sort by Date", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
}

private struct OperationsErrorRow: View {
    let item: OperationsMonitoring.ErrorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(item.summary,
                  systemImage: item.severity == "critical"
                  ? "exclamationmark.octagon.fill"
                  : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(item.severity == "critical" ? .red : .orange)

            HStack {
                Text(item.accountName ?? "Platform")
                Spacer()
                Text(item.occurredAt.formatted(
                    date: .abbreviated, time: .shortened))
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                Text(item.category.displayLabel)
                if let email = item.email { Text(email) }
                if let deviceName = item.deviceName { Text(deviceName) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderMetricCard: View {
    let metric: OperationsMonitoring.ProviderMetric

    private var statusColor: Color {
        switch metric.status {
        case "critical": .red
        case "warning": .orange
        case "unavailable": .secondary
        default: .green
        }
    }

    private var percentageText: String {
        guard let utilization = metric.utilization else { return "—" }
        return utilization.formatted(.percent.precision(.fractionLength(0)))
    }

    private var valueText: String {
        guard let used = metric.used else { return "Telemetry not connected" }
        if metric.unit == "bytes" {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let current = formatter.string(fromByteCount: Int64(used))
            guard let limit = metric.limit else { return current }
            return "\(current) of \(formatter.string(fromByteCount: Int64(limit)))"
        }
        guard let limit = metric.limit else { return Int(used).formatted() }
        return "\(Int(used).formatted()) of \(Int(limit).formatted()) \(metric.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(metric.provider, systemImage: "fuelpump.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentageText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(statusColor)
            }

            Text(metric.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            FuelGauge(
                utilization: metric.utilization,
                color: statusColor
            )

            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(valueText), \(percentageText)")
    }
}

private struct FuelGauge: View {
    let utilization: Double?
    let color: Color

    private let segmentCount = 10

    private var filledSegments: Int {
        guard let utilization else { return 0 }
        if utilization <= 0 { return 0 }
        return min(segmentCount, max(1, Int(ceil(utilization * Double(segmentCount)))))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < filledSegments ? color : Color.secondary.opacity(0.18))
            }
        }
        .frame(height: 13)
        .padding(3)
        .background(
            Capsule()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: Int
    let icon: String

    init(_ title: String, value: Int, icon: String) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Text(value.formatted()).font(.system(.largeTitle, design: .rounded).bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct OperationsAccountDetailView: View {
    @EnvironmentObject private var store: OperationsStore
    let accountID: String
    @State private var showingPlanOverride = false
    @State private var showingHold = false
    @State private var showingReactivation = false
    @State private var recoveryMember: OperationsAccountDetail.Member?
    @State private var accessMember: OperationsAccountDetail.Member?
    @State private var accessDevice: OperationsAccountDetail.Device?
    @State private var showingAccountLifecycle = false

    var body: some View {
        Group {
            if let detail = store.selectedDetail,
               detail.account.id == accountID {
                List {
                    Section("Account") {
                        LabeledContent("Company", value: detail.account.displayName)
                        LabeledContent("Status", value: detail.account.lifecycleStatus.displayLabel)
                        if let expires = detail.account.holdExpiresAt,
                           detail.account.lifecycleStatus.hasSuffix("Hold") {
                            LabeledContent("Hold Expires") {
                                Text(expires.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if let archivedAt = detail.account.archivedAt {
                            LabeledContent("Archived") {
                                Text(archivedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if let deletionDate = detail.account.deletionScheduledAt {
                            LabeledContent("Deletion Eligible") {
                                Text(deletionDate.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        LabeledContent("Plan", value: detail.account.planCode ?? "No active plan")
                        LabeledContent("Access", value: detail.account.accessSource?.displayLabel ?? "None")
                        if let expires = detail.account.planExpiresAt {
                            LabeledContent("Plan Expires") {
                                Text(expires.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if let reason = detail.account.overrideReason {
                            LabeledContent("Override Reason", value: reason)
                        }
                        if store.administrator?.role == "platformOwner" ||
                            store.administrator?.role == "billingAdministrator" {
                            Button {
                                showingPlanOverride = true
                            } label: {
                                Label("Grant Beta or Override Plan", systemImage: "checkmark.seal")
                            }
                        }
                        if detail.account.lifecycleStatus.hasSuffix("Hold") {
                            Button("Reactivate Account") {
                                showingReactivation = true
                            }
                        } else if detail.account.lifecycleStatus == "active",
                                  store.administrator?.role != "readOnlyAuditor" {
                            Button {
                                showingHold = true
                            } label: {
                                Label("Place Account on Hold", systemImage: "pause.circle")
                            }
                        }
                        if store.administrator?.role == "platformOwner" {
                            Button {
                                showingAccountLifecycle = true
                            } label: {
                                Label("Archive & Deletion Controls",
                                      systemImage: "archivebox")
                            }
                        }
                    }
                    Section("Usage") {
                        AccountUsageRow(
                            title: "Users",
                            used: detail.members.filter {
                                ["invited", "active", "suspended"].contains($0.status)
                            }.count,
                            limit: detail.account.entitlements.userLimit
                        )
                        ForEach(detail.usage) { item in
                            AccountUsageRow(
                                title: item.entityType.displayLabel,
                                used: item.count,
                                limit: detail.account.entitlements.limit(
                                    for: item.entityType)
                            )
                        }
                    }
                    Section("Users") {
                        ForEach(detail.members) { member in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.displayName)
                                Text(member.email ?? "No email on file")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(member.role.displayLabel) • \(member.operationsStatus.displayLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if member.recoveryAvailable == 1,
                                   ["platformOwner", "supportAdministrator"]
                                    .contains(store.administrator?.role ?? "") {
                                    Button("Recovery & Sessions") {
                                        recoveryMember = member
                                    }
                                    .font(.subheadline.weight(.semibold))
                                }
                                if ["platformOwner", "supportAdministrator"]
                                    .contains(store.administrator?.role ?? ""),
                                   member.removedAt == nil {
                                    Button("Manage Access") { accessMember = member }
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                    Section("Devices") {
                        ForEach(detail.devices) { device in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.displayName)
                                Text(
                                    device.memberEmail.map {
                                        "\(device.memberName) • \($0)"
                                    } ?? device.memberName
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                Text(device.status.displayLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        device.status == "active"
                                            ? Color.green
                                            : Color.red
                                    )
                                Text("Last seen \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if ["platformOwner", "supportAdministrator"]
                                    .contains(store.administrator?.role ?? ""),
                                   device.removedAt == nil {
                                    Button("Manage Device") { accessDevice = device }
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                    Section("Errors") {
                        LabeledContent(
                            "Unresolved sync conflicts",
                            value: detail.errors.unresolvedSynchronizationConflicts.formatted()
                        )
                    }
                    Section("Recent Activity") {
                        ForEach(detail.recentAudit) { event in
                            VStack(alignment: .leading) {
                                Text(event.eventType.displayLabel)
                                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle(detail.account.displayName)
                .sheet(isPresented: $showingPlanOverride) {
                    PlanOverrideView(accountID: accountID,
                                     accountName: detail.account.displayName)
                }
                .sheet(isPresented: $showingHold) {
                    AccountHoldView(accountID: accountID,
                                    accountName: detail.account.displayName)
                }
                .sheet(isPresented: $showingReactivation) {
                    AccountReactivationView(accountID: accountID,
                        accountName: detail.account.displayName,
                        currentStatus: detail.account.lifecycleStatus)
                }
                .sheet(item: $recoveryMember) { member in
                    RecoveryAssistanceView(
                        accountID: accountID,
                        accountName: detail.account.displayName,
                        member: member
                    )
                }
                .sheet(item: $accessMember) { member in
                    MemberAccessView(accountID: accountID,
                        accountName: detail.account.displayName, member: member)
                }
                .sheet(item: $accessDevice) { device in
                    DeviceAccessView(accountID: accountID,
                        accountName: detail.account.displayName, device: device)
                }
                .sheet(isPresented: $showingAccountLifecycle) {
                    AccountArchiveView(accountID: accountID,
                        accountName: detail.account.displayName,
                        lifecycleStatus: detail.account.lifecycleStatus,
                        deletionScheduledAt: detail.account.deletionScheduledAt)
                }
            } else {
                ProgressView("Loading account…")
            }
        }
        .task(id: accountID) { await store.loadAccount(id: accountID) }
    }
}

private struct AccountUsageRow: View {
    let title: String
    let used: Int
    let limit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(limit.map { "\(used.formatted()) of \($0.formatted())" }
                     ?? used.formatted())
            }
            if let limit, limit > 0 {
                let utilization = Double(used) / Double(limit)
                ProgressView(value: min(utilization, 1))
                    .tint(utilization >= 1 ? .red : utilization >= 0.8 ? .orange : .green)
            }
        }
    }
}

private extension OperationsAccountDetail.Entitlements {
    func limit(for entityType: String) -> Int? {
        switch entityType.lowercased() {
        case "lead": leadLimit
        case "customer": customerLimit
        case "job": jobLimit
        default: nil
        }
    }
}

private struct AccountArchiveView: View {
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    let lifecycleStatus: String
    let deletionScheduledAt: Date?
    @State private var reason = ""
    @State private var companyConfirmation = ""
    @State private var pendingAction: String?
    @State private var completionMessage: String?
    @State private var readiness: OperationsDeletionReadiness?

    private var needsTypedConfirmation: Bool {
        pendingAction == "archive" || pendingAction == "schedule-deletion" ||
            pendingAction == "confirm-cleanup"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Company", value: accountName)
                    LabeledContent("Status", value: lifecycleStatus.displayLabel)
                    if let deletionScheduledAt {
                        LabeledContent("Deletion Eligible") {
                            Text(deletionScheduledAt.formatted(
                                date: .abbreviated, time: .shortened))
                        }
                    }
                }
                Section("Required Reason") {
                    TextField("Explain why this action is authorized",
                              text: $reason, axis: .vertical).lineLimit(3...6)
                }
                if lifecycleStatus == "active" || lifecycleStatus.hasSuffix("Hold") {
                    Section {
                        Button("Archive Account", role: .destructive) {
                            pendingAction = "archive"
                        }
                        .disabled(reason.trimmed.count < 10)
                    } footer: {
                        Text("Archiving blocks account access and requires every enrolled device to remove company data. It remains reversible.")
                    }
                } else if lifecycleStatus == "archived" {
                    Section("Deletion Readiness") {
                        if let readiness {
                            Label(
                                readiness.pendingDevices.isEmpty
                                    ? "Device cleanup confirmed"
                                    : "\(readiness.pendingDevices.count) device(s) awaiting cleanup",
                                systemImage: readiness.pendingDevices.isEmpty
                                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(readiness.pendingDevices.isEmpty ? .green : .orange)
                            ForEach(readiness.pendingDevices) { device in
                                VStack(alignment: .leading) {
                                    Text(device.displayName)
                                    Text("\(device.memberName) • Last seen \(device.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if !readiness.pendingDevices.isEmpty {
                                Button("Confirm Cleanup for Unreachable Devices",
                                       role: .destructive) {
                                    pendingAction = "confirm-cleanup"
                                }
                                .disabled(reason.trimmed.count < 10)
                            }
                            Label(
                                readiness.latestBackupAt.map {
                                    "Recovery archive: \($0.formatted(date: .abbreviated, time: .shortened))"
                                } ?? "Recovery archive required",
                                systemImage: readiness.latestBackupAt == nil
                                    ? "externaldrive.badge.exclamationmark" : "checkmark.circle.fill"
                            )
                            .foregroundStyle(readiness.latestBackupAt == nil ? .orange : .green)
                            if readiness.latestBackupAt == nil {
                                Button("Create Recovery Archive from Cloud Snapshot") {
                                    createRecoveryArchive()
                                }
                                .disabled(reason.trimmed.count < 10 ||
                                          !readiness.synchronizationSnapshotAvailable)
                                if !readiness.synchronizationSnapshotAvailable {
                                    Text("No synchronized cloud snapshot is available. Restore the account temporarily and allow an Owner device to complete synchronization first.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            ProgressView("Checking deletion readiness…")
                        }
                    }
                    Section("Archived Account") {
                        Button("Restore Archived Account") { pendingAction = "restore" }
                            .disabled(reason.trimmed.count < 10)
                        Button("Schedule Protected Deletion", role: .destructive) {
                            pendingAction = "schedule-deletion"
                        }
                        .disabled(reason.trimmed.count < 10 || readiness?.ready != true)
                    }
                } else if lifecycleStatus == "deletionPending" {
                    Section {
                        Button("Cancel Scheduled Deletion") {
                            pendingAction = "cancel-deletion"
                        }
                        .disabled(reason.trimmed.count < 10)
                    } footer: {
                        Text("Cancellation returns the account to its archived, recoverable state.")
                    }
                }
                Section("Deletion Protections") {
                    Text("Deletion can be scheduled only after device cleanup and a current recovery archive are confirmed. PFSS enforces a minimum 30-day retention period.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Account Lifecycle")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            } }
            .sheet(isPresented: Binding(
                get: { needsTypedConfirmation },
                set: { if !$0 { pendingAction = nil; companyConfirmation = "" } }
            )) {
                NavigationStack {
                    Form {
                        Section {
                            Text("Type the exact company name to continue:")
                            Text(accountName).font(.headline)
                            TextField("Company name", text: $companyConfirmation)
                                .textInputAutocapitalization(.never)
                        }
                        Button(pendingAction == "archive" ? "Confirm Archive" :
                               pendingAction == "confirm-cleanup"
                               ? "Confirm Device Cleanup" : "Confirm Deletion Schedule",
                               role: .destructive) {
                            perform(pendingAction ?? "")
                        }
                        .disabled(companyConfirmation != accountName)
                    }
                    .navigationTitle("Confirm Company")
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { pendingAction = nil }
                    } }
                }
                .presentationDetents([.medium])
            }
            .confirmationDialog("Confirm account lifecycle action?",
                isPresented: Binding(
                    get: { pendingAction != nil && !needsTypedConfirmation },
                    set: { if !$0 { pendingAction = nil } }
                ), titleVisibility: .visible) {
                    Button("Confirm") { perform(pendingAction ?? "") }
                    Button("Cancel", role: .cancel) { pendingAction = nil }
                }
            .alert("Account Lifecycle Updated", isPresented: Binding(
                get: { completionMessage != nil },
                set: { if !$0 { completionMessage = nil } }
            )) {
                Button("OK") { dismiss() }
            } message: { Text(completionMessage ?? "") }
            .task { await refreshReadiness() }
        }
    }

    private func perform(_ action: String) {
        pendingAction = nil
        Task {
            if action == "confirm-cleanup" {
                if await store.confirmDeviceCleanup(
                    accountID: accountID, reason: reason.trimmed,
                    confirmation: companyConfirmation
                ) {
                    companyConfirmation = ""
                    await refreshReadiness()
                }
                return
            }
            if let receipt = await store.manageAccountArchive(
                accountID: accountID, action: action, reason: reason.trimmed,
                confirmation: ["archive", "schedule-deletion"].contains(action)
                    ? companyConfirmation : nil
            ) {
                completionMessage = receipt.deletionScheduledAt.map {
                    "Deletion is protected until \($0.formatted(date: .long, time: .shortened))."
                } ?? "The account is now \(receipt.status.displayLabel)."
            }
        }
    }

    private func createRecoveryArchive() {
        Task {
            if await store.createRecoveryArchive(
                accountID: accountID, reason: reason.trimmed
            ) {
                await refreshReadiness()
            }
        }
    }

    private func refreshReadiness() async {
        guard lifecycleStatus == "archived" else { return }
        readiness = await store.deletionReadiness(accountID: accountID)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension OperationsAccountDetail.Member {
    var operationsStatus: String {
        if removedAt != nil { return "removed" }
        if archivedAt != nil { return "archived" }
        return status
    }
}

private struct MemberAccessView: View {
    private struct AccessAction: Identifiable {
        let id: String
        let label: String
        let destructive: Bool
    }
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    let member: OperationsAccountDetail.Member
    @State private var reason = ""
    @State private var pendingAction: String?
    @State private var completed = false

    private var availableActions: [AccessAction] {
        switch member.operationsStatus {
        case "active": return [
            AccessAction(id: "suspend", label: "Suspend User", destructive: false),
            AccessAction(id: "revoke", label: "Permanently Revoke User", destructive: true)
        ]
        case "suspended": return [
            AccessAction(id: "reactivate", label: "Reactivate User", destructive: false),
            AccessAction(id: "revoke", label: "Permanently Revoke User", destructive: true)
        ]
        case "revoked": return [
            AccessAction(id: "archive", label: "Move to Inactive Archive", destructive: false)
        ]
        case "archived": return [
            AccessAction(id: "remove", label: "Permanently Remove Personal Information", destructive: true)
        ]
        default: return []
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("User") {
                    LabeledContent("Company", value: accountName)
                    LabeledContent("Name", value: member.displayName)
                    LabeledContent("Email", value: member.email ?? "Unavailable")
                    LabeledContent("Status", value: member.operationsStatus.displayLabel)
                }
                Section("Required Reason") {
                    TextField("Explain why this action is authorized",
                              text: $reason, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    ForEach(availableActions) { action in
                        Button(role: action.destructive ? .destructive : nil) {
                            pendingAction = action.id
                        } label: { Text(action.label) }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                    }
                } header: {
                    Text("Available Actions")
                } footer: {
                    Text("Revocation removes company access from every enrolled device. Removal is allowed only after device data removal is acknowledged.")
                }
            }
            .navigationTitle("Manage User Access")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            } }
            .confirmationDialog("Apply this user access change?", isPresented: Binding(
                get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
            ), titleVisibility: .visible) {
                Button("Confirm \((pendingAction ?? "action").displayLabel)", role:
                        ["revoke", "remove"].contains(pendingAction ?? "") ? .destructive : nil) {
                    let action = pendingAction ?? ""
                    pendingAction = nil
                    Task { completed = await store.manageMember(
                        accountID: accountID, memberID: member.id,
                        action: action, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            }
            .alert("User Access Updated", isPresented: $completed) {
                Button("OK") { dismiss() }
            }
        }
    }
}

private struct DeviceAccessView: View {
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    let device: OperationsAccountDetail.Device
    @State private var reason = ""
    @State private var pendingAction: String?
    @State private var completed = false

    private var action: (String, String, Bool)? {
        if device.revokedAt == nil { return ("revoke", "Revoke Device and Remove Company Data", true) }
        if device.dataRemovalRequiredAt == nil || device.dataRemovalAcknowledgedAt != nil {
            return ("remove", "Permanently Remove Device Record", true)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("Company", value: accountName)
                    LabeledContent("Device", value: device.displayName)
                    LabeledContent("User", value: device.memberName)
                    LabeledContent("Status", value: device.status.displayLabel)
                }
                Section("Required Reason") {
                    TextField("Explain why this action is authorized",
                              text: $reason, axis: .vertical).lineLimit(3...6)
                }
                Section("Available Action") {
                    if let action {
                        Button(action.1, role: action.2 ? .destructive : nil) {
                            pendingAction = action.0
                        }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                    } else {
                        Text("Waiting for this device to acknowledge company-data removal.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Manage Device")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            } }
            .confirmationDialog("Apply this device access change?", isPresented: Binding(
                get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
            ), titleVisibility: .visible) {
                Button("Confirm", role: .destructive) {
                    let selected = pendingAction ?? ""
                    pendingAction = nil
                    Task { completed = await store.manageDevice(
                        accountID: accountID, deviceID: device.id,
                        action: selected, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            }
            .alert("Device Access Updated", isPresented: $completed) {
                Button("OK") { dismiss() }
            }
        }
    }
}

private struct RecoveryAssistanceView: View {
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    let member: OperationsAccountDetail.Member
    @State private var reason = ""
    @State private var confirmation: Action?
    @State private var receiptMessage: String?

    private enum Action: String, Identifiable {
        case passwordReset
        case revokeSessions
        var id: String { rawValue }
    }

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("User") {
                    LabeledContent("Company", value: accountName)
                    LabeledContent("Name", value: member.displayName)
                    LabeledContent("Email", value: member.email ?? "Unavailable")
                }
                Section {
                    TextField("Explain why assistance is authorized",
                              text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Required Reason")
                } footer: {
                    Text("Enter at least 10 characters (\(min(normalizedReason.count, 10))/10).")
                }
                Section("Recovery Assistance") {
                    Button {
                        confirmation = .passwordReset
                    } label: {
                        Label("Send Password Reset Email", systemImage: "envelope.badge.shield.half.filled")
                    }
                    .disabled(normalizedReason.count < 10)
                    Text("WorkOS sends a secure, single-use reset link. PFSS never receives the password.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Emergency Security") {
                    Button(role: .destructive) {
                        confirmation = .revokeSessions
                    } label: {
                        Label("Sign Out Everywhere", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(normalizedReason.count < 10)
                    Text("Revokes WorkOS sessions and PFSS device access. Affected PFSS devices securely remove company data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recovery & Sessions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                confirmation == .passwordReset
                    ? "Send a reset email to \(member.email ?? member.displayName)?"
                    : "Sign \(member.displayName) out everywhere?",
                isPresented: Binding(
                    get: { confirmation != nil },
                    set: { if !$0 { confirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                if confirmation == .passwordReset {
                    Button("Send Reset Email") { perform(.passwordReset) }
                } else {
                    Button("Revoke All Sessions", role: .destructive) {
                        perform(.revokeSessions)
                    }
                }
                Button("Cancel", role: .cancel) { confirmation = nil }
            }
            .alert("Recovery Assistance Complete", isPresented: Binding(
                get: { receiptMessage != nil },
                set: { if !$0 { receiptMessage = nil } }
            )) {
                Button("OK") { dismiss() }
            } message: {
                Text(receiptMessage ?? "")
            }
        }
    }

    private func perform(_ action: Action) {
        confirmation = nil
        Task {
            let receipt: OperationsRecoveryReceipt?
            switch action {
            case .passwordReset:
                receipt = await store.sendPasswordReset(
                    accountID: accountID, memberID: member.id,
                    reason: normalizedReason
                )
                if let receipt {
                    receiptMessage = "A secure reset email was sent to \(receipt.email ?? member.email ?? "the verified address")."
                }
            case .revokeSessions:
                receipt = await store.revokeSessions(
                    accountID: accountID, memberID: member.id,
                    reason: normalizedReason
                )
                if let receipt {
                    receiptMessage = "Revoked \(receipt.workOSSessions ?? 0) WorkOS session(s) and \(receipt.pfssDevices ?? 0) PFSS device(s)."
                }
            }
        }
    }
}

private struct AccountHoldView: View {
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    @State private var status = "billingHold"
    @State private var permanent = false
    @State private var expiresAt = Calendar.current.date(
        byAdding: .day, value: 7, to: Date()
    ) ?? Date()
    @State private var reason = ""
    @State private var confirming = false

    private var allowedStatuses: [String] {
        switch store.administrator?.role {
        case "billingAdministrator": return ["billingHold"]
        case "supportAdministrator": return ["securityHold", "supportHold"]
        case "platformOwner": return ["billingHold", "securityHold", "supportHold"]
        default: return []
        }
    }

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canApplyHold: Bool {
        allowedStatuses.contains(status) && normalizedReason.count >= 10 &&
            (permanent || expiresAt > Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") { Text(accountName) }
                Section("Hold") {
                    Picker("Type", selection: $status) {
                        ForEach(allowedStatuses, id: \.self) {
                            Text($0.displayLabel).tag($0)
                        }
                    }
                    Toggle("Permanent Hold", isOn: $permanent)
                    if !permanent {
                        DatePicker("Expires", selection: $expiresAt,
                                   in: Date().addingTimeInterval(60)...)
                    }
                }
                Section {
                    TextField("Explain why access must be placed on hold",
                              text: $reason, axis: .vertical).lineLimit(3...6)
                } header: {
                    Text("Required Reason")
                } footer: {
                    if normalizedReason.count < 10 {
                        Text("Enter at least 10 characters (\(normalizedReason.count)/10).")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Reason complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section {
                    Button("Review and Apply Hold") { confirming = true }
                        .disabled(!canApplyHold)
                    if !canApplyHold {
                        Text("Complete the highlighted requirement above to continue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Account Hold")
            .onAppear { if !allowedStatuses.contains(status) { status = allowedStatuses.first ?? "" } }
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            } }
            .confirmationDialog(
                "Place \(accountName) on \(status.displayLabel)?",
                isPresented: $confirming, titleVisibility: .visible
            ) {
                Button("Apply Hold", role: .destructive) {
                    Task {
                        if await store.placeAccountOnHold(
                            accountID: accountID, status: status,
                            reason: normalizedReason,
                            permanent: permanent,
                            expiresAt: permanent ? nil : expiresAt
                        ) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Company devices will lose server access immediately. No company data or plan allocation will be deleted.")
            }
        }
    }
}

private struct AccountReactivationView: View {
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    let currentStatus: String
    @State private var reason = ""
    @State private var confirming = false

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Company", value: accountName)
                    LabeledContent("Current Status", value: currentStatus.displayLabel)
                }
                Section {
                    TextField("Explain why access may be restored",
                              text: $reason, axis: .vertical).lineLimit(3...6)
                } header: {
                    Text("Required Reason")
                } footer: {
                    Text("Enter at least 10 characters (\(min(normalizedReason.count, 10))/10).")
                }
                Button("Review Reactivation") { confirming = true }
                    .disabled(normalizedReason.count < 10)
            }
            .navigationTitle("Reactivate Account")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            } }
            .confirmationDialog(
                "Restore server access for \(accountName)?",
                isPresented: $confirming, titleVisibility: .visible
            ) {
                Button("Reactivate Account") {
                    Task {
                        if await store.reactivateAccount(
                            accountID: accountID,
                            reason: normalizedReason
                        ) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Existing authorized devices will regain server access. Account data and plan allocations remain unchanged.")
            }
        }
    }
}

private struct PlanOverrideView: View {
    @EnvironmentObject private var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    let accountName: String
    @State private var planCode = "beta"
    @State private var isPermanent = false
    @State private var expiresAt = Calendar.current.date(
        byAdding: .day, value: 90, to: Date()
    ) ?? Date()
    @State private var reason = ""
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") { Text(accountName) }
                Section("Access Plan") {
                    Picker("Plan", selection: $planCode) {
                        Text("Beta Test").tag("beta")
                        Text("Trial").tag("trial")
                        Text("Base").tag("base")
                        Text("Pro").tag("pro")
                        Text("Expert").tag("expert")
                    }
                    Toggle("Permanent Override", isOn: $isPermanent)
                    if !isPermanent {
                        DatePicker("Expires", selection: $expiresAt,
                                   in: Date().addingTimeInterval(60)...)
                    }
                }
                Section("Required Reason") {
                    TextField("Explain why this override is authorized",
                              text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                    Text("The reason and entitlement limits become part of the immutable Operations audit history.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Review and Save Override") { confirming = true }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                }
            }
            .navigationTitle("Plan Override")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Apply \(planCode.displayLabel) to \(accountName)?",
                isPresented: $confirming, titleVisibility: .visible
            ) {
                Button("Apply Override") {
                    Task {
                        if await store.createPlanOverride(
                            accountID: accountID, planCode: planCode,
                            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                            permanent: isPermanent,
                            expiresAt: isPermanent ? nil : expiresAt
                        ) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(isPermanent
                     ? "This permanent override takes effect immediately."
                     : "This override takes effect immediately and expires \(expiresAt.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
    }
}

private extension String {
    var displayLabel: String {
        replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
    }
}
