//
//  DashboardView.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 4.6 – Primary application navigation hub.
//

import SwiftUI
import Combine

struct DashboardView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var mileageRepository = MileageTripRepository.shared
    @ObservedObject private var declineCenter = PFSSJobDeclineReviewCenter.shared
    @ObservedObject private var notificationRouter =
        PFSSNotificationNavigationRouter.shared
    @StateObject private var cloudManager = PFSSCloudflareBetaManager()
    @State private var synchronizationHealth: PFSSSynchronizationHealth?
    @State private var offlineQueueRevision = 0
    @State private var notificationPath:
        [PFSSNotificationNavigationDestination] = []
    @Binding var selectedSection: AppSection

    private var todaysJobCount: Int {
        store.activeJobs.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: Date())
        }.count
    }

    private var mileageReviewCount: Int {
        mileageRepository.unclassifiedTrips.count
    }

    private var deviceMyDayEmployee: EmployeeRecord? {
        guard let employee = store.authenticatedCloudEmployee,
              employee.isActive,
              employee.lifecycleStatus == .active,
              employee.hasRole(.technician)
                || employee.hasRole(.manager)
                || employee.hasRole(.owner) else {
            return nil
        }
        return employee
    }

    private var actionableDispatchJobCount: Int {
        let activeJobIDs = Set(
            store.activeJobs
                .filter { $0.status != .completed && $0.status != .cancelled }
                .map(\.id)
        )
        return Set(
            store.assignmentEngine.unassignedAssignments
                .map(\.jobID)
                .filter(activeJobIDs.contains)
        ).count
    }

    private var operationsAttentionCount: Int {
        actionableDispatchJobCount
            + PFSSConflictInbox.unresolvedItems(
                in: store.offlineOperationQueue.orderedOperations
            ).count
            + PFSSQuarantineInbox.unresolvedItems(
                in: store.offlineOperationQueue.orderedOperations
            ).count
            + store.recurringWorkTemplates.filter { $0.status == .held }.count
    }

    private var monthToDateRevenue: Double {
        RevenueSummaryEngine.summary(
            for: .monthly,
            jobs: store.activeJobs,
            invoices: store.invoices
        ).collected
    }

    private var homeFeatureTileIDs: [String] {
        store.canManageCompany
            ? ["myDay", "mileage", "operations", "revenue"]
            : ["myDay", "mileage"]
    }

    private var canOpenSalesCalendar: Bool {
        store.canManageCompany
            || store.authenticatedCloudEmployee?.hasRole(.salesperson) == true
    }

    private var canOpenJobsCalendar: Bool {
        store.canManageCompany
            || store.authenticatedCloudEmployee?.hasRole(.technician) == true
    }

    private var homeShortcutTileIDs: [String] {
        var ids = ["addLead", "customers", "estimates", "invoices", "jobs", "tools"]
        if canOpenSalesCalendar { ids.append("salesCalendar") }
        if canOpenJobsCalendar { ids.append("jobsCalendar") }
        return ids
    }

    var body: some View {
        NavigationStack(path: $notificationPath) {
            ScrollView {
                VStack(spacing: 16) {
                    if let health = synchronizationHealth,
                       health.summary.activeAlerts > 0 {
                        synchronizationHealthBanner(health)
                    }
                    if store.canManageCompany && !declineCenter.pendingReviews.isEmpty {
                        NavigationLink {
                            PFSSJobDeclineReviewListView()
                                .environmentObject(store)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "flag.fill")
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Job Review Required")
                                        .font(.headline)
                                    Text("A technician declined assigned work.")
                                        .font(.subheadline)
                                }
                                Spacer()
                                Text(declineCenter.pendingReviews.count.formatted())
                                    .font(.title2.bold())
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                    if case let .accountHold(hold) =
                        store.cloudSynchronizationAccessStatus {
                        accountHoldNotice(hold)
                    } else if store.cloudSynchronizationAccessStatus == .suspended {
                        suspendedAccessNotice
                    } else {
                        VStack(spacing: 18) {
                            CustomizableTileGrid(
                                storageKey: "pfss.tile-layout.home.shortcuts.v1",
                                defaultTileIDs: homeShortcutTileIDs,
                                columnCount: 4
                            ) { tileID in
                                homeShortcut(tileID)
                            }

                            CustomizableTileGrid(
                                storageKey: "pfss.tile-layout.home.features.v1",
                                defaultTileIDs: homeFeatureTileIDs,
                                columnCount: 3
                            ) { tileID in
                                switch tileID {
                                case "myDay":
                                    if let employee = deviceMyDayEmployee {
                                        NavigationLink {
                                            TechnicianDailyAgendaView(employee: employee)
                                                .environmentObject(store)
                                        } label: {
                                            LargeHomeTile(
                                                title: "My Day",
                                                icon: "calendar.day.timeline.left",
                                                badgeCount: todaysJobCount,
                                                accentColor: .cyan
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint(
                                            "Opens today's plan for \(employee.displayName)"
                                        )
                                    } else {
                                        Button {
                                            selectedSection = .myDay
                                        } label: {
                                            LargeHomeTile(
                                                title: "My Day",
                                                icon: "calendar.day.timeline.left",
                                                badgeCount: todaysJobCount,
                                                accentColor: .cyan
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Opens the technician selector")
                                    }
                                case "mileage":
                                    NavigationLink {
                                        MileageWorkspaceView()
                                    } label: {
                                        LargeHomeTile(
                                            title: "Mileage",
                                            icon: "car.rear.road.lane",
                                            badgeCount: mileageReviewCount,
                                            accentColor: .green
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens mileage review and manual entry")
                                case "operations":
                                    if store.canManageCompany {
                                        NavigationLink {
                                            OperationsView()
                                        } label: {
                                            LargeHomeTile(
                                                title: "Operations",
                                                icon: "person.3.sequence.fill",
                                                badgeCount: operationsAttentionCount,
                                                showsBadge: operationsAttentionCount > 0,
                                                accentColor: .orange
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Opens jobs awaiting dispatch")
                                    }
                                case "revenue":
                                    if store.canManageCompany {
                                        NavigationLink {
                                            OperationsRevenueView()
                                        } label: {
                                            LargeHomeTile(
                                                title: "Revenue",
                                                icon: "dollarsign.circle.fill",
                                                badgeText: compactCurrency(monthToDateRevenue),
                                                accentColor: .green
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Opens revenue summaries")
                                    }
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(
                for: PFSSNotificationNavigationDestination.self
            ) { destination in
                notificationDestination(destination)
            }
        }
        .onAppear {
            openPendingNotificationDestination()
        }
        .onChange(of: notificationRouter.latestRequest) { _, _ in
            openPendingNotificationDestination()
        }
        .onChange(of: store.cloudSynchronizationAccessStatus) { _, _ in
            openPendingNotificationDestination()
        }
        .task {
            declineCenter.start()
            await declineCenter.refresh()
        }
        .task(id: selectedSection) {
            guard selectedSection == .dashboard else { return }
            await refreshSynchronizationHealthBanner()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, selectedSection == .dashboard else { return }
            Task { await refreshSynchronizationHealthBanner() }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .pfssSynchronizationHealthDidRefresh
            )
        ) { notification in
            guard cloudManager.currentSession?.member.role.canManageAccess == true,
                  let health = notification.object as? PFSSSynchronizationHealth
            else { return }
            synchronizationHealth = health.summary.activeAlerts > 0 ? health : nil
        }
        .onReceive(store.offlineOperationQueue.objectWillChange) { _ in
            offlineQueueRevision &+= 1
        }
    }

    @ViewBuilder
    private func notificationDestination(
        _ destination: PFSSNotificationNavigationDestination
    ) -> some View {
        switch destination {
        case let .job(jobID):
            if let job = store.jobs.first(where: { $0.id == jobID }) {
                JobDetailView(job: job)
            } else {
                ContentUnavailableView(
                    "Job Unavailable",
                    systemImage: "briefcase.fill",
                    description: Text(
                        "This job is not currently available on this device."
                    )
                )
            }
        case .mileage:
            MileageWorkspaceView()
        }
    }

    private func openPendingNotificationDestination() {
        switch store.cloudSynchronizationAccessStatus {
        case .accountHold, .suspended:
            return
        case .checking, .available, .unavailable:
            break
        }

        guard let request = notificationRouter.latestRequest,
              !notificationRouter.isHandled(request) else {
            return
        }
        notificationPath = [request.destination]
        notificationRouter.markHandled(request)
    }

    private func synchronizationHealthBanner(
        _ health: PFSSSynchronizationHealth
    ) -> some View {
        let isCritical = health.summary.criticalAlerts > 0
        let alertCount = health.summary.activeAlerts
        let color: Color = isCritical ? .red : .orange
        return NavigationLink {
            PFSSSynchronizationHealthView()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isCritical
                    ? "exclamationmark.octagon.fill"
                    : "exclamationmark.triangle.fill")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isCritical
                        ? "Synchronization Action Required"
                        : "Synchronization Needs Attention")
                        .font(.headline)
                    Text(
                        "\(alertCount) \(alertCount == 1 ? "issue needs" : "issues need") review. Tap to see what happened and how to correct it."
                    )
                    .font(.subheadline)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(color.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Synchronization needs attention. \(alertCount) active \(alertCount == 1 ? "issue" : "issues")."
        )
        .accessibilityHint("Opens Synchronization Health to review and correct the issue")
    }

    private func refreshSynchronizationHealthBanner() async {
        guard cloudManager.isEnrolled else {
            synchronizationHealth = nil
            return
        }
        do {
            try await cloudManager.refreshSession()
            guard cloudManager.currentSession?.member.role.canManageAccess == true else {
                synchronizationHealth = nil
                return
            }
            let health = try await cloudManager.synchronizationHealth()
            synchronizationHealth = health.summary.activeAlerts > 0 ? health : nil
        } catch {
            // A dashboard monitoring failure must not interrupt normal field work.
            synchronizationHealth = nil
        }
    }

    private var suspendedAccessNotice: some View {
        accountNotice(
            title: "Company Access Suspended",
            message: "This device cannot use company operations while access is suspended. Contact your system administrator for assistance.",
            systemImage: "person.crop.circle.badge.exclamationmark"
        )
    }

    private func accountHoldNotice(_ hold: PFSSAccountHold) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            accountNotice(
                title: hold.title,
                message: hold.message,
                systemImage: hold.type == .securityHold
                    ? "exclamationmark.shield.fill"
                    : "pause.circle.fill"
            )
            if let expiresAt = hold.expiresAt {
                Text("Scheduled to restore automatically \(expiresAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func accountNotice(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.orange.opacity(0.12))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }

    @ViewBuilder
    private func homeShortcut(_ tileID: String) -> some View {
        switch tileID {
        case "addLead":
            NavigationLink {
                LeadNewView()
            } label: {
                CompactHomeTile(
                    title: "New Lead",
                    icon: "person.crop.circle.badge.plus",
                    accentColor: .blue
                )
            }
            .buttonStyle(.plain)
        case "customers":
            NavigationLink {
                CustomersView()
            } label: {
                CompactHomeTile(
                    title: "Customers",
                    icon: "person.2.fill",
                    accentColor: .indigo
                )
            }
            .buttonStyle(.plain)
        case "estimates":
            NavigationLink {
                EstimatesView()
            } label: {
                CompactHomeTile(
                    title: "Estimates",
                    icon: "doc.text.magnifyingglass",
                    accentColor: .blue
                )
            }
            .buttonStyle(.plain)
        case "invoices":
            NavigationLink {
                InvoiceRecordsListView()
            } label: {
                CompactHomeTile(
                    title: "Invoices",
                    icon: "doc.text.fill",
                    accentColor: .green
                )
            }
            .buttonStyle(.plain)
        case "jobs":
            NavigationLink {
                JobsView()
            } label: {
                CompactHomeTile(
                    title: "Jobs",
                    icon: "wrench.and.screwdriver.fill",
                    accentColor: .orange
                )
            }
            .buttonStyle(.plain)
        case "tools":
            NavigationLink {
                ToolsDashboardView()
            } label: {
                CompactHomeTile(
                    title: "Tools",
                    icon: "hammer.fill",
                    accentColor: .orange
                )
            }
            .buttonStyle(.plain)
        case "salesCalendar":
            if canOpenSalesCalendar {
                NavigationLink {
                    SalesFollowUpCalendarView(
                        initialEmployeeID: store.authenticatedCloudEmployee?.id
                    )
                    .environmentObject(store)
                } label: {
                    CompactHomeTile(
                        title: "Sales Cal",
                        icon: "calendar.badge.clock",
                        accentColor: .blue
                    )
                }
                .buttonStyle(.plain)
            }
        case "jobsCalendar":
            if canOpenJobsCalendar {
                NavigationLink {
                    TechnicianCalendarView(
                        initialEmployeeID: store.authenticatedCloudEmployee?.id
                    )
                    .environmentObject(store)
                } label: {
                    CompactHomeTile(
                        title: "Jobs Cal",
                        icon: "calendar.badge.checkmark",
                        accentColor: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        default:
            EmptyView()
        }
    }

    private func compactCurrency(_ amount: Double) -> String {
        let value = max(amount, 0)
        if value >= 1_000_000 {
            return "$\((value / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
        }
        if value >= 1_000 {
            return "$\((value / 1_000).formatted(.number.precision(.fractionLength(0...1))))K"
        }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

private struct LargeHomeTile: View {
    let title: String
    let icon: String
    let accentColor: Color
    private let badgeText: String
    private let showsBadge: Bool

    init(
        title: String,
        icon: String,
        badgeCount: Int,
        showsBadge: Bool = true,
        accentColor: Color
    ) {
        self.title = title
        self.icon = icon
        self.badgeText = badgeCount.formatted()
        self.showsBadge = showsBadge
        self.accentColor = accentColor
    }

    init(
        title: String,
        icon: String,
        badgeText: String,
        showsBadge: Bool = true,
        accentColor: Color
    ) {
        self.title = title
        self.icon = icon
        self.badgeText = badgeText
        self.showsBadge = showsBadge
        self.accentColor = accentColor
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))

                Text(title)
                    .font(
                        title == "Operations"
                            ? .system(size: 13, weight: .bold)
                            : .subheadline.weight(.bold)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(
                accentColor.gradient,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: accentColor.opacity(0.25), radius: 7, y: 4)

            if showsBadge {
                Text(badgeText)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 26, minHeight: 26)
                    .padding(.horizontal, badgeText.count > 2 ? 5 : 0)
                    .background(.red, in: Capsule())
                    .overlay {
                        Capsule().stroke(.white, lineWidth: 2)
                    }
                    .offset(x: 8, y: -8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(badgeText)")
    }
}

private struct CompactHomeTile: View {
    let title: String
    let icon: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(accentColor.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: accentColor.opacity(0.22), radius: 5, y: 3)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}
