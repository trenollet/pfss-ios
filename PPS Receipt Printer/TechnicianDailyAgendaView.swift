//
//  TechnicianDailyAgendaView.swift
//  PPS Receipt Printer
//
//  Created by Reno Renollet on 7/16/26.
//

import SwiftUI
import CoreLocation

struct TechnicianDailyAgendaView: View {
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
    @State private var jobPendingCompletionID: UUID?
    @State private var showingCompletionConfirmation = false

    @StateObject private var locationManager = TechnicianLocationManager()
    @State private var displayedJobs: [JobRecord] = []
    @State private var isOptimizingRoute = false
    @State private var routeOptimizationErrorMessage = ""
    @State private var showingRouteOptimizationError = false

    private var summary: EmployeeCapacitySummary {
        SchedulingCalculator.capacitySummary(
            for: employee,
            on: selectedDate,
            from: store.jobs
        )
    }

    private var sortedJobs: [JobRecord] {
        summary.assignedJobs.sorted {
            $0.scheduledDate < $1.scheduledDate
        }
    }

    private var completedJobCount: Int {
        sortedJobs.filter {
            $0.status == .completed
        }
        .count
    }

    private var firstJob: JobRecord? {
        displayedJobs.first
    }

    private var estimatedFinishDate: Date? {
        sortedJobs.compactMap { job in
            Calendar.current.date(
                byAdding: .minute,
                value: SchedulingCalculator.scheduledMinutes(
                    for: job
                ),
                to: job.scheduledDate
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

                scheduleHeader

                if displayedJobs.isEmpty {
                    emptyScheduleCard
                } else {
                    ForEach(displayedJobs) { job in
                        technicianJobCard(job)
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

            if locationManager.authorizationStatus == .authorizedAlways ||
               locationManager.authorizationStatus == .authorizedWhenInUse {
                locationManager.refreshLocation()
            }
        }
        .onChange(of: summary.assignedJobs.map(\.id)) {
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
        .confirmationDialog(
            "Complete This Job?",
            isPresented:
                $showingCompletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark Completed") {
                completePendingJob()
            }

            Button(
                "Cancel",
                role: .cancel
            ) {
                jobPendingCompletionID = nil
            }
        } message: {
            Text(
                "The job will be marked completed "
                + "and the completion time will be recorded."
            )
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
                        named: employee.colorName
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
                    "\(greetingText), \(employee.firstName)"
                )
                .font(.title2)
                .fontWeight(.bold)

                Text(
                    selectedDate.formatted(
                        date: .complete,
                        time: .omitted
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        VStack(
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
                    "\(summary.utilizationPercentage)%"
                )
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(utilizationColor)
            }

            ProgressView(
                value: min(
                    summary.utilizationFraction,
                    1
                )
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
                    value: "\(summary.assignedJobCount)",
                    systemImage: "briefcase.fill"
                )

                Spacer()

                summaryMetric(
                    title: "Scheduled",
                    value: durationText(
                        summary.scheduledMinutes
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
                    + "\(summary.assignedJobCount) complete"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !summary.isWorkingDay {
                Label(
                    summary.scheduledMinutes > 0
                        ? "Work is assigned on a non-working day."
                        : "You are not normally scheduled today.",
                    systemImage:
                        "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if summary.isOverCapacity {
                Label(
                    "Schedule exceeds daily capacity by "
                    + durationText(
                        abs(summary.remainingMinutes)
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Schedule")
                        .font(.title3)
                        .fontWeight(.bold)

                    if let firstJob {
                        Text(
                            "Starts "
                            + firstJob.scheduledDate.formatted(
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
        _ job: JobRecord
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            Button {
                selectedJobID = job.id
            } label: {
                technicianJobInformation(job)
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
        _ job: JobRecord
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: 12
            ) {
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
                        job.scheduledDate
                    )
                )
                .font(.system(size: 16))
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
            }

            HStack {
                Spacer()

                Label(
                    job.status.rawValue,
                    systemImage:
                        statusIcon(
                            for: job.status
                        )
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    statusColor(
                        for: job.status
                    )
                )

                Spacer()
            }

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
        ActionTileRow(
            actions: [
                ActionTileItem(
                    title: "Navigate",
                    systemImage: "location.fill",
                    isEnabled: hasUsableAddress(
                        for: job
                    )
                ) {
                    prepareNavigation(
                        for: job
                    )
                },

                ActionTileItem(
                    title: "Call",
                    systemImage: "phone.fill",
                    isEnabled: hasUsablePhoneNumber(
                        for: job
                    )
                ) {
                    callCustomer(
                        for: job
                    )
                },

                workflowAction(
                    for: job
                )
            ]
        )
    }

    private func workflowAction(
        for job: JobRecord
    ) -> ActionTileItem {
        switch job.status {
        case .scheduled, .assigned:
            return ActionTileItem(
                title: "Start Job",
                systemImage: "play.fill",
                tint: .orange
            ) {
                startJob(job)
            }

        case .inProgress:
            return ActionTileItem(
                title: "Complete",
                systemImage:
                    "checkmark.circle.fill",
                tint: .green
            ) {
                requestCompletion(
                    for: job
                )
            }

        case .completed:
            return ActionTileItem(
                title: "Details",
                systemImage: "doc.text.fill"
            ) {
                selectedJobID = job.id
            }

        case .toBeScheduled, .cancelled:
            return ActionTileItem(
                title: "Details",
                systemImage: "doc.text.fill"
            ) {
                selectedJobID = job.id
            }
        }
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
        switch summary.assignedJobCount {
        case 0:
            return "Your day is clear"

        case 1:
            return "1 job scheduled"

        default:
            return "\(summary.assignedJobCount) jobs scheduled"
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
        if summary.assignedJobCount == 0 {
            return "No work scheduled"
        }

        if completedJobCount ==
            summary.assignedJobCount {

            return "Day complete"
        }

        if completedJobCount > 0 {
            return "Day in progress"
        }

        return "Ready to begin"
    }

    private var progressIcon: String {
        if summary.assignedJobCount == 0 {
            return "calendar.badge.checkmark"
        }

        if completedJobCount ==
            summary.assignedJobCount {

            return "checkmark.seal.fill"
        }

        if completedJobCount > 0 {
            return "figure.walk.motion"
        }

        return "play.circle.fill"
    }

    private var utilizationColor: Color {
        if !summary.isWorkingDay {
            return .gray
        }

        if summary.isOverCapacity {
            return .red
        }

        if summary.utilizationPercentage >= 80 {
            return .yellow
        }

        return .green
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
            employee.firstName.first.map(String.init)
            ?? ""

        let lastInitial =
            employee.lastName.first.map(String.init)
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
    
    private func startJob(
        _ job: JobRecord
    ) {
        _ = store.startJob(
            jobID: job.id
        )
    }

    private func requestCompletion(
        for job: JobRecord
    ) {
        jobPendingCompletionID = job.id
        showingCompletionConfirmation = true
    }

    private func completePendingJob() {
        guard let jobID =
                jobPendingCompletionID
        else {
            return
        }

        _ = store.completeJob(
            jobID: jobID
        )

        jobPendingCompletionID = nil
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
            let optimizer = DailyRouteOptimizer()
            let optimized = await optimizer.optimizedRoute(
                jobs: sortedJobs,
                sites: store.sites,
                startingLocation: currentLocation
            )
            let optimizedIDs = Set(optimized.map(\.id))
            let remaining = sortedJobs.filter {
                !optimizedIDs.contains($0.id)
            }

            await MainActor.run {
                displayedJobs = optimized + remaining
                isOptimizingRoute = false
            }
        }
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
