//
//  TechnicianDailyAgendaView.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/16/26.
//

import SwiftUI
import CoreLocation

struct TechnicianDailyAgendaView: View {
    private struct InvoiceDestination: Identifiable, Hashable {
        let id: UUID
    }

    @EnvironmentObject var store: AppDataStore
    
    @Environment(\.openURL)
    private var openURL

    let employee: EmployeeRecord
    
    @State private var navigationAddress = ""
    @State private var showingNavigationOptions = false
    @State private var navigationErrorMessage = ""
    @State private var showingNavigationError = false
    
    @State private var selectedDate = Date()
    @State private var selectedJobID: UUID?
    @State private var selectedInvoiceDestination: InvoiceDestination?
    @State private var showingDatePicker = false

    @StateObject private var locationManager = TechnicianLocationManager()
    @State private var displayedJobs: [JobRecord] = []
    @State private var isOptimizingRoute = false
    @State private var routeOptimizationErrorMessage = ""
    @State private var showingRouteOptimizationError = false
    @State private var routeSummary: DailyRouteOptimizer.RouteSummary?
    @State private var isRouteOptimized = false
    @State private var optimizedStartByJobID: [UUID: Date] = [:]

    @MainActor
    private func workflowCoordinator() -> FieldOperationsWorkflowCoordinator {
        FieldOperationsWorkflowCoordinator(store: store)
    }

    private var currentEmployee: EmployeeRecord {
        store.employees.first(where: { $0.id == employee.id }) ?? employee
    }

    private var agenda: TechnicianAgenda {
        SchedulingEngine.dailyAgenda(
            for: currentEmployee,
            on: selectedDate,
            from: store.jobs
        )
    }

    private var sortedJobs: [JobRecord] {
        agenda.jobs.sorted { first, second in
            let firstIsFinished = isFinishedForAgenda(first)
            let secondIsFinished = isFinishedForAgenda(second)

            if firstIsFinished != secondIsFinished {
                return !firstIsFinished
            }

            if firstIsFinished && secondIsFinished {
                let firstCompletion = completionDate(for: first)
                let secondCompletion = completionDate(for: second)
                if firstCompletion != secondCompletion {
                    return firstCompletion > secondCompletion
                }
                return first.id.uuidString < second.id.uuidString
            }

            let firstStart = plannedStart(for: first)
            let secondStart = plannedStart(for: second)
            if firstStart != secondStart {
                return firstStart < secondStart
            }

            let firstSequence = store.assignment(forJobID: first.id)?.routeSequence
            let secondSequence = store.assignment(forJobID: second.id)?.routeSequence

            switch (firstSequence, secondSequence) {
            case let (.some(left), .some(right)) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return first.id.uuidString < second.id.uuidString
            }
        }
    }

    private var plannedStartByJobID: [UUID: Date] {
        let plan = store.dailyPlan(
            for: currentEmployee,
            on: selectedDate
        )
        return Dictionary(
            uniqueKeysWithValues: plan.assignmentItems.compactMap { item in
                guard let jobID = item.jobID else { return nil }
                return (jobID, item.serviceStart)
            }
        )
    }

    private func plannedStart(for job: JobRecord) -> Date {
        optimizedStartByJobID[job.id]
            ?? plannedStartByJobID[job.id]
            ?? job.scheduledDate
    }

    private var completedJobCount: Int {
        sortedJobs.filter(isFinishedForAgenda).count
    }

    private var firstJob: JobRecord? {
        displayedJobs.first { !isFinishedForAgenda($0) }
    }

    private var estimatedFinishDate: Date? {
        sortedJobs.filter { !isFinishedForAgenda($0) }.compactMap { job in
            Calendar.current.date(
                byAdding: .minute,
                value: SchedulingEngine.scheduledMinutes(
                    for: job
                ),
                to: plannedStart(for: job)
            )
        }
        .max()
    }

    var body: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 18
            ) {
                greetingHeader

                dateNavigator

                dailySummaryCard

                NavigationLink {
                    TechnicianCalendarView(
                        initialEmployeeID: currentEmployee.id
                    )
                    .environmentObject(store)
                } label: {
                    DashboardStatCard(
                        title: "Calendar View",
                        value: "",
                        icon: "calendar",
                        subtitle: "1, 3, or 5-day job schedule",
                        accentColor: .orange,
                        trend: .neutral,
                        navigationIndicator: true
                    )
                }
                .buttonStyle(.plain)

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
                    OfflineSyncStatusBadge(
                        queue: store.offlineOperationQueue,
                        connectivity: store.offlineConnectivityMonitor,
                        mode: store.offlineSynchronizationMode,
                        cloudAccessStatus: store.cloudSynchronizationAccessStatus
                    )
                }
                .buttonStyle(.plain)

                scheduleHeader

                if let routeSummary {
                    RouteSummaryCard(
                        summary: routeSummary,
                        isOptimized: isRouteOptimized
                    )
                }

                if displayedJobs.isEmpty {
                    emptyScheduleCard
                } else {
                    ForEach(displayedJobs) { job in
                        technicianJobCard(
                            job,
                            stopNumber: routeStopNumber(for: job)
                        )
                    }
                }
            }
            .padding()
        }
        .background(
            Color(uiColor: .systemGroupedBackground)
        )
        .navigationTitle("My Day")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.startOfflineServices()
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Day",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose a Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .navigationDestination(
            item: $selectedJobID
        ) { jobID in
            if let job = store.jobs.first(where: {
                $0.id == jobID
            }) {
                JobDetailView(job: job)
                    .environmentObject(store)
            } else {
                ContentUnavailableView(
                    "Job Not Found",
                    systemImage: "briefcase",
                    description: Text(
                        "This job may have been removed or archived."
                    )
                )
            }
        }
        .navigationDestination(
            item: $selectedInvoiceDestination
        ) { destination in
            if let invoice = store.invoices.first(where: {
                $0.id == destination.id
            }) {
                InvoiceDetailView(invoice: invoice)
                    .environmentObject(store)
            } else {
                ContentUnavailableView(
                    "Invoice Not Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(
                        "The invoice may have been removed or archived."
                    )
                )
            }
        }
        .confirmationDialog(
            "Choose Navigation App",
            isPresented: $showingNavigationOptions,
            titleVisibility: .visible
        ) {
            Button("Apple Maps") {
                openAppleMaps(
                    to: navigationAddress
                )
            }

            Button("Google Maps") {
                openGoogleMaps(
                    to: navigationAddress
                )
            }

            Button(
                "Cancel",
                role: .cancel
            ) {}
        } message: {
            Text(navigationAddress)
        }
        .alert(
            "Unable to Open Navigation",
            isPresented: $showingNavigationError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(navigationErrorMessage)
        }
        .task(id: selectedDate) {
            displayedJobs = sortedJobs
            routeSummary = nil
            isRouteOptimized = false
            optimizedStartByJobID = [:]

            if locationManager.authorizationStatus == .authorizedAlways ||
               locationManager.authorizationStatus == .authorizedWhenInUse {
                locationManager.refreshLocation()
            }
        }
        .onChange(of: agenda.jobs.map(\.id)) {
            displayedJobs = sortedJobs
            routeSummary = nil
            isRouteOptimized = false
            optimizedStartByJobID = [:]
        }
        .onChange(of: finishedJobIDs) {
            displayedJobs = sortedJobs
        }
        .alert(
            "Route Optimization",
            isPresented: $showingRouteOptimizationError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(routeOptimizationErrorMessage)
        }
    }

    private var greetingHeader: some View {
        HStack(
            alignment: .center,
            spacing: 12
        ) {
            Circle()
                .fill(
                    employeeColor(
                        named: currentEmployee.colorName
                    )
                )
                .frame(
                    width: 46,
                    height: 46
                )
                .overlay {
                    Text(employeeInitials)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    "\(greetingText), \(currentEmployee.firstName)"
                )
                .font(.title2)
                .fontWeight(.bold)

                Button {
                    showingDatePicker = true
                } label: {
                    HStack(spacing: 5) {
                        Text(
                            selectedDate.formatted(
                                date: .complete,
                                time: .omitted
                            )
                        )
                        Image(systemName: "calendar")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose agenda date")
            }

            Spacer()
        }
    }

    private var dateNavigator: some View {
        HStack {
            Button {
                changeDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(
                        width: 40,
                        height: 40
                    )
            }
            .buttonStyle(.bordered)

            Spacer()

            if !Calendar.current.isDateInToday(
                selectedDate
            ) {
                Button("Return to Today") {
                    selectedDate = Date()
                }
                .font(.subheadline)
            } else {
                Text("Today")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                changeDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(
                        width: 40,
                        height: 40
                    )
            }
            .buttonStyle(.bordered)
        }
    }

    private var dailySummaryCard: some View {
        return VStack(
            alignment: .leading,
            spacing: 16
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("TODAY'S PLAN")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(dailyHeadline)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                Text(
                    "\(agenda.utilizationPercentage)%"
                )
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(utilizationColor)
            }

            ProgressView(
                value: safeUtilizationFraction,
                total: 1
            )
            .tint(utilizationColor)
            .scaleEffect(
                x: 1,
                y: 1.8,
                anchor: .center
            )

            HStack(
                alignment: .top,
                spacing: 12
            ) {
                summaryMetric(
                    title: "Jobs",
                    value: "\(agenda.jobCount)",
                    systemImage: "briefcase.fill"
                )

                Spacer()

                summaryMetric(
                    title: "Scheduled",
                    value: durationText(
                        agenda.scheduledMinutes
                    ),
                    systemImage: "clock.fill"
                )

                Spacer()

                summaryMetric(
                    title: "Finish",
                    value: estimatedFinishText,
                    systemImage: "flag.checkered"
                )
            }

            Divider()

            HStack {
                Label(
                    progressText,
                    systemImage: progressIcon
                )
                .font(.subheadline)
                .foregroundStyle(utilizationColor)

                Spacer()

                Text(
                    "\(completedJobCount) of "
                    + "\(agenda.jobCount) complete"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !agenda.isWorkingDay {
                Label(
                    agenda.scheduledMinutes > 0
                        ? "Work is assigned on a non-working day."
                        : "You are not normally scheduled today.",
                    systemImage:
                        "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if agenda.isOverCapacity {
                Label(
                    "Schedule exceeds daily capacity by "
                    + durationText(
                        abs(agenda.remainingMinutes)
                    ),
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }

    private var scheduleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canOverrideNonWorkingDay {
                Button {
                    enableOvertimeWorkday()
                } label: {
                    Label(
                        "Work This Day (Overtime)",
                        systemImage: "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityHint(
                    "Uses the technician's normal start and end times for this day only."
                )
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Schedule")
                        .font(.title3)
                        .fontWeight(.bold)

                    if let firstJob {
                        Text(
                            "Starts "
                            + plannedStart(for: firstJob).formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    optimizeRoute()
                } label: {
                    if isOptimizingRoute {
                        ProgressView()
                            .controlSize(.small)
                    } else if isRouteOptimized {
                        Label(
                            "Optimized",
                            systemImage: "checkmark.circle.fill"
                        )
                    } else {
                        Label(
                            "Optimize",
                            systemImage: "arrow.triangle.swap"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    isOptimizingRoute
                    || displayedJobs.count < 2
                )
                .accessibilityLabel("Optimize daily route")
            }

            locationStatusBadge
        }
    }

    private var locationStatusBadge: some View {
        Label(
            locationManager.status.title,
            systemImage: locationManager.status.systemImage
        )
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(locationStatusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            locationStatusColor.opacity(0.12)
        )
        .clipShape(Capsule())
        .accessibilityLabel(
            "Location status: \(locationManager.status.title)"
        )
    }

    private var locationStatusColor: Color {
        switch locationManager.status {
        case .ready:
            return .green

        case .requestingPermission,
             .acquiringLocation:
            return .orange

        case .denied,
             .restricted,
             .servicesDisabled,
             .unavailable:
            return .red

        case .notRequested:
            return .secondary
        }
    }

    private var emptyScheduleCard: some View {
        VStack(spacing: 14) {
            Image(
                systemName:
                    "calendar.badge.checkmark"
            )
            .font(.system(size: 40))
            .foregroundStyle(.secondary)

            Text("No Jobs Scheduled")
                .font(.headline)

            Text(
                "There are no assigned jobs for this day."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(.vertical, 40)
        .padding(.horizontal)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }

    private func technicianJobCard(
        _ job: JobRecord,
        stopNumber: Int?
    ) -> some View {
        return VStack(
            alignment: .leading,
            spacing: 14
        ) {
            Button {
                selectedJobID = job.id
            } label: {
                technicianJobInformation(
                    job,
                    stopNumber: stopNumber
                )
            }
            .buttonStyle(.plain)

            Divider()

            technicianActionRow(for: job)
        }
        .padding()
        .background(
            Color(
                uiColor:
                    .secondarySystemGroupedBackground
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16
            )
        )
    }

    private func technicianJobInformation(
        _ job: JobRecord,
        stopNumber: Int?
    ) -> some View {
        let presentation = workflowContext(for: job).presentation

        return VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(
                alignment: .center,
                spacing: 12
            ) {
                if let stopNumber {
                    RouteStopBadge(number: stopNumber)
                }

                Text(
                    customerDisplayName(
                        for: job.customerNumber
                    )
                )
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)

                Spacer()

                Text(
                    SchedulingCalculator
                        .formattedScheduledDuration(
                            for: job
                        )
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }

            HStack(
                alignment: .firstTextBaseline,
                spacing: 12
            ) {
                Text(serviceName(for: job))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                Text(
                    twentyFourHourTime(
                        plannedStart(for: job)
                    )
                )
                .font(.system(size: 16))
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
            }

            VStack(spacing: 5) {
                Label(
                    presentation.statusTitle,
                    systemImage: presentation.statusSystemImage
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(presentation.accent.color)

                if let completionTitle = presentation.completionTitle {
                    Text(completionTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(presentation.accent.color)
                }
            }
            .frame(maxWidth: .infinity)

            if let site = site(for: job) {
                Label {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        if !site.siteName.isEmpty {
                            Text(site.siteName)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }

                        Text(site.serviceAddress)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(
                        systemName:
                            "mappin.and.ellipse"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func technicianActionRow(
        for job: JobRecord
    ) -> some View {
        let utilityActions = [
            ActionTileItem(
                title: "Navigate",
                systemImage: "location.fill",
                isEnabled:
                    hasUsableAddress(for: job) &&
                    !isTechnicianComplete(job)
            ) {
                prepareNavigation(for: job)
            },

            ActionTileItem(
                title: "Call",
                systemImage: "phone.fill",
                isEnabled: hasUsablePhoneNumber(for: job)
            ) {
                callCustomer(for: job)
            }
        ]

        let workflowActions: [ActionTileItem]
        if isTechnicianComplete(job) {
            workflowActions = [
                ActionTileItem(
                    title: "COMPLETE",
                    systemImage: "flag.checkered",
                    tint: .green,
                    isInteractive: false
                ) {}
            ]
        } else {
            let context = workflowContext(for: job)
            workflowActions = context.availableActions.map {
                workflowAction($0, for: job)
            }
        }

        return VStack(spacing: 10) {
            if workflowActions.count > 1 {
                ActionTileRow(actions: utilityActions)
                ActionTileRow(actions: workflowActions)
            } else {
                ActionTileRow(
                    actions: utilityActions + workflowActions
                )
            }
        }
    }

    private func workflowAction(
        _ action: JobWorkflowAction,
        for job: JobRecord
    ) -> ActionTileItem {
        return ActionTileItem(
            title: action.title,
            systemImage: action.systemImage,
            tint: action.presentation.accent.color
        ) {
            performWorkflowAction(
                action,
                for: job
            )
        }
    }

    private func workflowContext(
        for job: JobRecord
    ) -> JobWorkflowContext {
        workflowCoordinator().workflowContext(for: job)
    }

    private func isTechnicianComplete(_ job: JobRecord) -> Bool {
        workflowContext(for: job).presentation.isTechnicianComplete
    }

    private func isFinishedForAgenda(_ job: JobRecord) -> Bool {
        job.status == .completed ||
        job.status == .cancelled ||
        isTechnicianComplete(job)
    }

    private var finishedJobIDs: [UUID] {
        agenda.jobs
            .filter(isFinishedForAgenda)
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private func completionDate(for job: JobRecord) -> Date {
        job.completedDate ??
        job.timelineEvents
            .filter {
                $0.type == .jobCompleted ||
                $0.type == .paymentReceived ||
                $0.type == .invoiceSent
            }
            .map(\.timestamp)
            .max() ??
        .distantPast
    }

    private func performWorkflowAction(
        _ action: JobWorkflowAction,
        for job: JobRecord
    ) {
        if action == .recordPayment,
           let invoice = store.invoice(forJobID: job.id) {
            selectedInvoiceDestination = InvoiceDestination(
                id: invoice.id
            )
            return
        }

        if action == .viewDetails {
            selectedJobID = job.id
            return
        }

        _ = workflowCoordinator().performWorkflowAction(
            jobID: job.id,
            action: action,
            employeeID: currentEmployee.id
        )
    }

    private func summaryMetric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Label(
                title,
                systemImage: systemImage
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
        }
    }

    private var dailyHeadline: String {
        switch agenda.jobCount {
        case 0:
            return "Your day is clear"

        case 1:
            return "1 job scheduled"

        default:
            return "\(agenda.jobCount) jobs scheduled"
        }
    }

    private var estimatedFinishText: String {
        guard let estimatedFinishDate else {
            return "—"
        }

        return estimatedFinishDate.formatted(
            date: .omitted,
            time: .shortened
        )
    }

    private var progressText: String {
        if agenda.jobCount == 0 {
            return "No work scheduled"
        }

        if completedJobCount ==
            agenda.jobCount {

            return "Day complete"
        }

        if completedJobCount > 0 {
            return "Day in progress"
        }

        return "Ready to begin"
    }

    private var progressIcon: String {
        if agenda.jobCount == 0 {
            return "calendar.badge.checkmark"
        }

        if completedJobCount ==
            agenda.jobCount {

            return "checkmark.seal.fill"
        }

        if completedJobCount > 0 {
            return "figure.walk.motion"
        }

        return "play.circle.fill"
    }

    private var safeUtilizationFraction: Double {
        let fraction = agenda.utilization

        guard fraction.isFinite else {
            return 0
        }

        return min(
            max(fraction, 0),
            1
        )
    }

    private var utilizationColor: Color {
        if !agenda.isWorkingDay {
            return .gray
        }

        if agenda.isOverCapacity {
            return .red
        }

        if agenda.utilizationPercentage >= 80 {
            return .yellow
        }

        return .green
    }

    private var canOverrideNonWorkingDay: Bool {
        guard !agenda.isWorkingDay,
              agenda.scheduledMinutes > 0 else {
            return false
        }

        return !availabilityExceptionsForSelectedDay.contains {
            $0.kind == .unavailable
        }
    }

    private var availabilityExceptionsForSelectedDay: [WorkforceAvailabilityException] {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        guard let nextDay = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: dayStart
        ) else {
            return []
        }

        let interval = DateInterval(start: dayStart, end: nextDay)
        return currentEmployee.workforceProfile.availabilityExceptions.filter {
            $0.overlaps(interval)
        }
    }

    private func enableOvertimeWorkday() {
        var updatedEmployee = currentEmployee
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)

        guard let overrideStart = calendar.date(
            byAdding: .minute,
            value: updatedEmployee.defaultStartMinutes,
            to: dayStart
        ),
        let overrideEnd = calendar.date(
            byAdding: .minute,
            value: updatedEmployee.defaultEndMinutes,
            to: dayStart
        ),
        overrideEnd > overrideStart else {
            return
        }

        updatedEmployee.workforceProfile.availabilityExceptions.removeAll {
            $0.kind == .available &&
            $0.overlaps(DateInterval(start: dayStart, end: overrideEnd))
        }
        updatedEmployee.workforceProfile.availabilityExceptions.append(
            WorkforceAvailabilityException(
                kind: .available,
                startDate: overrideStart,
                endDate: overrideEnd,
                reason: "Overtime workday enabled from My Day."
            )
        )

        store.updateEmployee(updatedEmployee)
        displayedJobs = sortedJobs
        routeSummary = nil
        isRouteOptimized = false
        optimizedStartByJobID = [:]
    }

    private var greetingText: String {
        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )

        switch hour {
        case 0..<12:
            return "Good Morning"

        case 12..<17:
            return "Good Afternoon"

        default:
            return "Good Evening"
        }
    }

    private var employeeInitials: String {
        let firstInitial =
            currentEmployee.firstName.first.map(String.init)
            ?? ""

        let lastInitial =
            currentEmployee.lastName.first.map(String.init)
            ?? ""

        let initials =
            firstInitial + lastInitial

        return initials.isEmpty
            ? "?"
            : initials.uppercased()
    }

    private func serviceName(
        for job: JobRecord
    ) -> String {
        if job.serviceType == .other {
            return job.otherService.isEmpty
                ? "Other Service"
                : job.otherService
        }

        return job.serviceType.rawValue
    }

    private func customerDisplayName(
        for customerNumber: String
    ) -> String {
        guard let customer =
                store.customers.first(where: {
                    $0.customerNumber ==
                        customerNumber
                })
        else {
            return customerNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return customerNumber
    }

    private func site(
        for job: JobRecord
    ) -> CustomerSite? {
        guard let siteID = job.siteID else {
            return nil
        }

        return store.sites.first {
            $0.id == siteID
        }
    }

    private func statusIcon(
        for status: JobStatus
    ) -> String {
        switch status {
        case .toBeScheduled:
            return "calendar.badge.questionmark"

        case .scheduled:
            return "calendar"

        case .assigned:
            return "person.badge.clock"

        case .inProgress:
            return "play.circle.fill"

        case .completed:
            return "checkmark.circle.fill"

        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private func statusColor(
        for status: JobStatus
    ) -> Color {
        switch status {
        case .toBeScheduled:
            return .secondary

        case .scheduled, .assigned:
            return .blue

        case .inProgress:
            return .orange

        case .completed:
            return .green

        case .cancelled:
            return .red
        }
    }

    private func durationText(
        _ minutes: Int
    ) -> String {
        guard minutes > 0 else {
            return "0 min"
        }

        return SchedulingCalculator.formattedDuration(
            minutes: minutes
        )
    }

    private func twentyFourHourTime(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func changeDate(
        by dayOffset: Int
    ) {
        selectedDate =
            Calendar.current.date(
                byAdding: .day,
                value: dayOffset,
                to: selectedDate
            )
            ?? selectedDate
    }

    private func customer(
        for job: JobRecord
    ) -> Customer? {
        store.customers.first {
            $0.customerNumber ==
                job.customerNumber
        }
    }

    private func hasUsablePhoneNumber(
        for job: JobRecord
    ) -> Bool {
        guard let customer = customer(for: job) else {
            return false
        }

        return !customer.phone
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }

    private func hasUsableAddress(
        for job: JobRecord
    ) -> Bool {
        guard let site = site(for: job) else {
            return false
        }

        return !site.serviceAddress
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }
    
    private func prepareNavigation(
        for job: JobRecord
    ) {
        guard let site = site(for: job) else {
            return
        }

        let address =
            site.serviceAddress
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !address.isEmpty else {
            return
        }

        navigationAddress = address
        showingNavigationOptions = true
    }

    private func openAppleMaps(
        to address: String
    ) {
        Task {
            do {
                try await NavigationService.shared
                    .navigateWithAppleMaps(
                        to: address
                    )
            } catch {
                navigationErrorMessage =
                    error.localizedDescription

                showingNavigationError = true
            }
        }
    }

    private func openGoogleMaps(
        to address: String
    ) {
        Task {
            do {
                try await NavigationService.shared
                    .navigateWithGoogleMaps(
                        to: address
                    )
            } catch {
                navigationErrorMessage =
                    error.localizedDescription

                showingNavigationError = true
            }
        }
    }
    
    private func callCustomer(
        for job: JobRecord
    ) {
        guard let customer = customer(
            for: job
        ) else {
            return
        }

        let phoneNumber =
            customer.phone
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let allowedCharacters =
            CharacterSet(
                charactersIn: "+0123456789"
            )

        let sanitizedPhoneNumber =
            phoneNumber.unicodeScalars
                .filter {
                    allowedCharacters.contains($0)
                }
                .map(String.init)
                .joined()

        guard !sanitizedPhoneNumber.isEmpty,
              let phoneURL = URL(
                  string:
                    "tel:\(sanitizedPhoneNumber)"
              )
        else {
            return
        }

        openURL(phoneURL)
    }
    
    private func optimizeRoute() {
        guard !isOptimizingRoute else {
            return
        }

        isOptimizingRoute = true

        locationManager.requestCurrentLocation { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let currentLocation):
                    performRouteOptimization(
                        from: currentLocation
                    )

                case .failure(let error):
                    isOptimizingRoute = false
                    routeOptimizationErrorMessage =
                        error.localizedDescription
                    showingRouteOptimizationError = true
                }
            }
        }
    }

    private func performRouteOptimization(
        from currentLocation: CLLocation
    ) {
        Task {
            let activeJobs = sortedJobs.filter {
                !isFinishedForAgenda($0)
            }
            let plan = store.dailyPlan(
                for: currentEmployee,
                on: selectedDate,
                includingJobIDs: Set(activeJobs.map(\.id))
            )
            let routePlan = await store.routePlan(
                from: plan,
                origin: RouteOrigin(
                    coordinate: RouteCoordinate(
                        latitude: currentLocation.coordinate.latitude,
                        longitude: currentLocation.coordinate.longitude
                    ),
                    label: "Technician Location"
                ),
                source: .recommended,
                preferRoadNetwork: true,
                preserveHumanRouteSequence: false
            )

            let jobsByID = Dictionary(
                uniqueKeysWithValues: activeJobs.map { ($0.id, $0) }
            )
            let routeOrderedJobs = routePlan.stops.compactMap {
                jobsByID[$0.jobID]
            }
            let routedJobIDs = Set(routeOrderedJobs.map(\.id))
            let remainingActiveJobs = activeJobs.filter {
                !routedJobIDs.contains($0.id)
            }

            var settings = store.businessProfile.operations
            settings.normalize()
            let planningBufferMinutes = settings.dailyRouteBufferMinutes +
                (settings.perStopBufferMinutes * routePlan.stopCount)
            let summary = DailyRouteOptimizer.RouteSummary(
                stopCount: routePlan.stopCount,
                totalDistanceMeters: routePlan.totalDistanceMeters,
                estimatedDriveTimeSeconds: routePlan.totalDriveTimeSeconds,
                planningBufferSeconds: TimeInterval(planningBufferMinutes * 60),
                includeBuffersInPlannedTime: settings.includeBuffersInRouteTime
            )
            let optimizedStarts = Dictionary(
                uniqueKeysWithValues: routePlan.stops.map {
                    ($0.jobID, $0.serviceStartDate)
                }
            )

            await MainActor.run {
                let completeRouteOrder = routeOrderedJobs + remainingActiveJobs

                do {
                    try store.applyTechnicianRouteOrder(
                        jobIDs: completeRouteOrder.map(\.id),
                        technician: currentEmployee
                    )
                    store.rememberAcceptedRoutePlan(routePlan)
                    optimizedStartByJobID = optimizedStarts
                    displayedJobs = sortedJobs
                    routeSummary = summary
                    isRouteOptimized = !routePlan.stops.isEmpty
                    if routePlan.hasBlockingConflicts {
                        routeOptimizationErrorMessage = routePlan.conflicts
                            .filter { $0.severity == .error }
                            .map(routeConflictMessage)
                            .joined(separator: "\n")
                        showingRouteOptimizationError = true
                    }
                } catch {
                    routeOptimizationErrorMessage = error.localizedDescription
                    showingRouteOptimizationError = true
                }
                isOptimizingRoute = false
            }
        }
    }

    private func routeConflictMessage(
        _ conflict: RoutePlanningConflict
    ) -> String {
        guard let assignmentID = conflict.assignmentID,
              let assignment = store.assignmentStore.assignment(id: assignmentID),
              let job = store.jobs.first(where: {
                  $0.id == assignment.jobID
              }) else {
            return conflict.message
        }

        let customerName = customerDisplayName(for: job.customerNumber)
        let reference = "\(customerName) (\(assignment.assignmentNumber))"
        if conflict.message.contains(assignment.assignmentNumber) {
            return conflict.message.replacingOccurrences(
                of: assignment.assignmentNumber,
                with: reference
            )
        }
        return "\(customerName) (\(assignment.assignmentNumber)): \(conflict.message)"
    }

    private func routeStopNumber(
        for job: JobRecord
    ) -> Int? {
        guard isRouteOptimized,
              !isFinishedForAgenda(job),
              let index = displayedJobs.firstIndex(where: {
                  $0.id == job.id
              })
        else {
            return nil
        }

        let activeJobsThroughIndex = displayedJobs[...index].filter {
            $0.status != .completed &&
            $0.status != .cancelled
        }

        return activeJobsThroughIndex.count
    }

    private func employeeColor(
        named colorName: String
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
