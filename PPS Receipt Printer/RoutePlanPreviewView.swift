//
//  RoutePlanPreviewView.swift
//  PPS Receipt Printer
//
//  Phase 14.4 – Route review and acceptance UI
//

import SwiftUI
import CoreLocation

struct RoutePlanPreviewView: View {
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var locationManager = TechnicianLocationManager()

    let dailyPlan: DailyPlan
    let technicianName: String

    @State private var routePlan: RoutePlan?
    @State private var isBuildingRoute = false
    @State private var isApplyingRoute = false
    @State private var allowConstraintOverride = false
    @State private var overrideReason = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingApplyConfirmation = false
    @State private var appliedMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                routeControls

                if let routePlan {
                    summaryCard(routePlan)
                    stopsSection(routePlan)
                    conflictsSection(routePlan)
                    applySection(routePlan)
                } else {
                    instructionsCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Route Preview")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Route Planning", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "Apply this route?",
            isPresented: $showingApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(routePlan?.hasBlockingConflicts == true
                ? "Apply Reviewed Override"
                : "Apply Route") {
                applyRoute()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This writes the displayed stop order to the Assignments and records each change in Assignment history.")
        }
    }

    // MARK: - Controls

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(technicianName)
                        .font(.title2.bold())

                    Text(dailyPlan.date.formatted(date: .complete, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    locationManager.status.title,
                    systemImage: locationManager.status.systemImage
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(locationStatusColor)
            }

            Divider()

            Button(action: buildRoute) {
                HStack {
                    if isBuildingRoute {
                        ProgressView()
                    } else {
                        Image(systemName: routePlan == nil
                            ? "map.fill"
                            : "arrow.clockwise")
                    }

                    Text(routePlan == nil ? "Build Road Route" : "Refresh Route")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBuildingRoute || dailyPlan.assignmentItems.isEmpty)

            Text("The current device location is used as the route starting point. Generating this preview does not change Assignments.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review Before Applying", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Build the road route to review stop order, mileage, drive time, estimated arrivals, completion time, and scheduling conflicts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("PFSS recommends; you make the final decision.")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Summary

    private func summaryCard(_ plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Route Summary", systemImage: "map.fill")
                    .font(.headline)

                Spacer()

                routeStatusBadge(plan)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                metric("Stops", "\(plan.stopCount)", "mappin.and.ellipse")
                metric("Distance", miles(plan.totalDistanceMiles), "road.lanes")
                metric("Drive Time", duration(plan.totalDriveMinutes), "car.fill")
                metric(
                    "Completion",
                    plan.estimatedCompletionDate.map(time) ?? "—",
                    "flag.checkered"
                )
            }

            HStack {
                Label(plan.source.rawValue, systemImage: plan.source == .humanAdjusted
                    ? "person.fill.checkmark"
                    : "sparkles")
                Spacer()
                Text("Generated \(time(plan.generatedAt))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func routeStatusBadge(_ plan: RoutePlan) -> some View {
        let color: Color = plan.isComplete ? .green : .orange
        return Label(
            plan.isComplete ? "Ready" : "Review",
            systemImage: plan.isComplete
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Stops

    private func stopsSection(_ plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Proposed Stops", icon: "list.number")

            if plan.stops.isEmpty {
                messageCard(
                    title: "No routeable stops",
                    detail: "Review missing-location conflicts below."
                )
            } else {
                ForEach(plan.stops.sorted(by: { $0.sequence < $1.sequence })) {
                    stopCard($0)
                }
            }
        }
    }

    private func stopCard(_ stop: RouteStopPlan) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(stop.sequence)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(stopColor(stop))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customerName(for: stop.assignmentID))
                            .font(.headline)
                        Text(siteName(for: stop.assignmentID))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text(stop.schedulingMode.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stopColor(stop))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(stopColor(stop).opacity(0.12))
                        .clipShape(Capsule())
                }

                if !stop.displayAddress.isEmpty {
                    Label(stop.displayAddress, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label(
                        "Arrive \(time(stop.estimatedArrivalDate))",
                        systemImage: "car.fill"
                    )
                    Spacer()
                    Text("\(miles(stop.travel.distanceMiles)) · \(duration(stop.travel.expectedTravelMinutes))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Label(
                        "Service \(time(stop.serviceStartDate))–\(time(stop.serviceEndDate))",
                        systemImage: "clock"
                    )

                    Spacer()

                    constraintBadge(stop.constraintResult)
                }
                .font(.caption)

                if stop.preservesHumanSequence {
                    Label("Preserves technician-adjusted order", systemImage: "person.fill.checkmark")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func constraintBadge(_ result: RouteConstraintResult) -> some View {
        let color: Color
        switch result {
        case .satisfied: color = .green
        case .atRisk: color = .orange
        case .violated: color = .red
        case .notApplicable: color = .secondary
        }

        return Text(result.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    // MARK: - Conflicts and Apply

    @ViewBuilder
    private func conflictsSection(_ plan: RoutePlan) -> some View {
        if !plan.conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Route Conflicts", icon: "exclamationmark.triangle.fill")

                ForEach(plan.conflicts) { conflict in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: conflict.severity == .error
                            ? "xmark.octagon.fill"
                            : "exclamationmark.triangle.fill")
                            .foregroundStyle(conflict.severity == .error
                                ? Color.red
                                : Color.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.kind.rawValue)
                                .font(.headline)

                            if let assignmentID = conflict.assignmentID {
                                Text(customerName(for: assignmentID))
                                    .font(.subheadline.weight(.semibold))

                                Label(
                                    siteName(for: assignmentID),
                                    systemImage: "mappin.and.ellipse"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }

                            Text(displayMessage(for: conflict))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private func applySection(_ plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Apply Reviewed Route", systemImage: "checkmark.shield.fill")
                .font(.headline)

            if !plan.unrouteableAssignmentIDs.isEmpty {
                Text("Resolve every missing or invalid site address before applying this route.")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if plan.hasBlockingConflicts {
                Toggle(
                    "I reviewed the scheduling conflicts",
                    isOn: $allowConstraintOverride
                )

                if allowConstraintOverride {
                    TextField("Required override reason", text: $overrideReason, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                showingApplyConfirmation = true
            } label: {
                HStack {
                    if isApplyingRoute { ProgressView() }
                    Label(
                        plan.hasBlockingConflicts ? "Apply Route Override" : "Apply Route",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(plan.hasBlockingConflicts ? .orange : .blue)
            .disabled(
                isApplyingRoute ||
                !plan.unrouteableAssignmentIDs.isEmpty ||
                (plan.hasBlockingConflicts &&
                    (!allowConstraintOverride || normalizedOverrideReason.isEmpty))
            )

            if let appliedMessage {
                Label(appliedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("Applying writes only the reviewed stop sequence. It does not change customer scheduling constraints or Job duration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Actions

    private func buildRoute() {
        guard !isBuildingRoute else { return }
        isBuildingRoute = true
        appliedMessage = nil

        locationManager.requestCurrentLocation { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let location):
                    Task { @MainActor in
                        let origin = RouteOrigin(
                            coordinate: RouteCoordinate(
                                latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude
                            ),
                            label: "Current Location"
                        )
                        let newPlan = await store.routePlan(
                            from: dailyPlan,
                            origin: origin,
                            source: routePlan == nil ? .recommended : .replanned
                        )
                        routePlan = newPlan
                        allowConstraintOverride = false
                        overrideReason = ""
                        isBuildingRoute = false
                    }

                case .failure(let error):
                    isBuildingRoute = false
                    showError(error.localizedDescription)
                }
            }
        }
    }

    private func applyRoute() {
        guard let routePlan else { return }
        isApplyingRoute = true

        do {
            let results = try store.dispatchEngine.applyRoutePlan(
                routePlan,
                actor: .system,
                allowConstraintOverride: allowConstraintOverride,
                reason: normalizedOverrideReason.isEmpty
                    ? nil
                    : normalizedOverrideReason
            )
            appliedMessage = results.isEmpty
                ? "This route order was already current."
                : "Applied \(results.count) route position\(results.count == 1 ? "" : "s")."
        } catch {
            showError(error.localizedDescription)
        }

        isApplyingRoute = false
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    // MARK: - Display Helpers

    private var normalizedOverrideReason: String {
        overrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var locationStatusColor: Color {
        switch locationManager.status {
        case .ready: return .green
        case .requestingPermission, .acquiringLocation: return .orange
        case .notRequested: return .secondary
        case .denied, .restricted, .servicesDisabled, .unavailable: return .red
        }
    }

    private func assignment(for id: UUID) -> Assignment? {
        store.assignmentEngine.assignment(id: id)
    }

    private func customerName(for assignmentID: UUID) -> String {
        guard let assignment = assignment(for: assignmentID),
              let customer = store.customers.first(where: {
                  $0.customerNumber == assignment.customerNumber
              }) else {
            return assignment(for: assignmentID)?.customerNumber ?? "Customer"
        }

        let business = customer.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = customer.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !business.isEmpty { return business }
        if !contact.isEmpty { return contact }
        return customer.customerNumber
    }

    private func siteName(for assignmentID: UUID) -> String {
        guard let assignment = assignment(for: assignmentID),
              let siteID = assignment.siteID,
              let site = store.sites.first(where: { $0.id == siteID }) else {
            return "No site assigned"
        }
        let name = site.siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Site" : name
    }

    /// Converts engine-facing conflict text into an operator-facing message.
    ///
    /// RouteEngine retains the Assignment number in its immutable diagnostic
    /// output for logs and tests. The live Operations UI replaces that number
    /// with the Customer and Site names so a dispatcher immediately knows
    /// which record needs attention.
    private func displayMessage(
        for conflict: RoutePlanningConflict
    ) -> String {
        guard let assignmentID = conflict.assignmentID,
              let assignment = assignment(for: assignmentID) else {
            return conflict.message
        }

        let customer = customerName(for: assignmentID)
        let site = siteName(for: assignmentID)
        let displayIdentity = "\(customer) at \(site)"

        if conflict.message.contains(assignment.assignmentNumber) {
            return conflict.message.replacingOccurrences(
                of: assignment.assignmentNumber,
                with: displayIdentity
            )
        }

        return "\(displayIdentity): \(conflict.message)"
    }

    private func stopColor(_ stop: RouteStopPlan) -> Color {
        switch stop.constraintResult {
        case .violated: return .red
        case .atRisk: return .orange
        case .satisfied: return .blue
        case .notApplicable: return .teal
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title2.bold())
    }

    private func messageCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func duration(_ minutes: Int) -> String {
        let safe = max(minutes, 0)
        let hours = safe / 60
        let remainder = safe % 60
        if hours > 0 && remainder > 0 { return "\(hours) hr \(remainder) min" }
        if hours > 0 { return "\(hours) hr" }
        return "\(remainder) min"
    }

    private func miles(_ value: Double) -> String {
        String(format: "%.1f mi", max(value.isFinite ? value : 0, 0))
    }
}
