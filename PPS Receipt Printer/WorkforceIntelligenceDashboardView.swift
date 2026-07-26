//
//  WorkforceIntelligenceDashboardView.swift
//  PPS Receipt Printer
//
//  Phase 14.5 — Workforce Intelligence
//

import SwiftUI

struct WorkforceIntelligenceDashboardView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedDate = Date()

    private var technicians: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.role == .technician }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    private var snapshotsByEmployeeID: [UUID: WorkforceTechnicianSnapshot] {
        Dictionary(
            uniqueKeysWithValues: store.workforceSnapshots(
                on: selectedDate
            ).map { ($0.employeeID, $0) }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                dateCard
                summaryGrid

                if !credentialAlerts.isEmpty {
                    credentialAlertsSection
                }

                Text("Technician Profiles")
                    .font(.title2.bold())

                if technicians.isEmpty {
                    ContentUnavailableView(
                        "No Active Technicians",
                        systemImage: "person.3",
                        description: Text(
                            "Add an active technician employee to begin using Workforce Intelligence."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ForEach(technicians) { technician in
                        NavigationLink {
                            EmployeeDetailView(employee: technician)
                        } label: {
                            WorkforceTechnicianCard(
                                technician: technician,
                                snapshot: snapshotsByEmployeeID[
                                    technician.id
                                ],
                                reviewDate: selectedDate
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    store.refreshWorkforceHistoricalMetrics()
                } label: {
                    Label(
                        "Refresh Historical Metrics",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Metrics are recalculated from Assignment history. Skills, credentials, resources, and availability are edited on each employee record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Workforce Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Operational Date", systemImage: "calendar")
                .font(.headline)

            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {
            summaryTile(
                title: "Technicians",
                value: technicians.count.formatted(),
                icon: "person.3.fill",
                color: .blue
            )

            summaryTile(
                title: "Available",
                value: availableCount.formatted(),
                icon: "person.crop.circle.badge.checkmark",
                color: .green
            )

            summaryTile(
                title: "Profiles Started",
                value: configuredProfileCount.formatted(),
                icon: "person.text.rectangle",
                color: .purple
            )

            summaryTile(
                title: "Credential Alerts",
                value: credentialAlertCount.formatted(),
                icon: "exclamationmark.shield.fill",
                color: credentialAlertCount > 0 ? .orange : .green
            )
        }
    }

    private func summaryTile(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var availableCount: Int {
        snapshotsByEmployeeID.values.filter {
            $0.availability.state.isAvailable
        }.count
    }

    private var configuredProfileCount: Int {
        technicians.filter {
            $0.workforceProfile.hasIntelligenceData
        }.count
    }

    private var credentialAlertCount: Int {
        credentialAlerts.count
    }

    private var credentialAlerts: [WorkforceCredentialAlert] {
        technicians
            .flatMap { technician in
                technician.workforceProfile.certifications.compactMap {
                    certification -> WorkforceCredentialAlert? in
                    let status = certification.status(on: selectedDate)
                    guard status == .expired || status == .expiresSoon else {
                        return nil
                    }

                    return WorkforceCredentialAlert(
                        technicianID: technician.id,
                        technicianName: technician.displayName,
                        certification: certification,
                        status: status
                    )
                }
            }
            .sorted { first, second in
                if first.status != second.status {
                    return first.status == .expired
                }

                if first.technicianName != second.technicianName {
                    return first.technicianName.localizedCaseInsensitiveCompare(
                        second.technicianName
                    ) == .orderedAscending
                }

                return first.certification.name
                    .localizedCaseInsensitiveCompare(
                        second.certification.name
                    ) == .orderedAscending
            }
    }

    private var credentialAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Credential Alerts",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)

            ForEach(credentialAlerts) { alert in
                NavigationLink {
                    if let technician = technicians.first(where: {
                        $0.id == alert.technicianID
                    }) {
                        EmployeeDetailView(employee: technician)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(
                            systemName: alert.status == .expired
                                ? "xmark.octagon.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            alert.status == .expired ? .red : .orange
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.technicianName)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(alert.certification.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(alert.detailText)
                                .font(.caption)
                                .foregroundStyle(
                                    alert.status == .expired ? .red : .orange
                                )
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (alert.status == .expired ? Color.red : Color.orange)
                            .opacity(0.08)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                (alert.status == .expired
                                    ? Color.red
                                    : Color.orange
                                ).opacity(0.35),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WorkforceTechnicianCard: View {
    let technician: EmployeeRecord
    let snapshot: WorkforceTechnicianSnapshot?
    let reviewDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(technician.displayName)
                        .font(.headline)

                    Text(profileSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                availabilityBadge
            }

            Divider()

            HStack(spacing: 18) {
                metric(
                    icon: "wrench.and.screwdriver.fill",
                    value: technician.workforceProfile.skills.count,
                    label: "Skills"
                )

                metric(
                    icon: "checkmark.seal.fill",
                    value: technician.workforceProfile.certifications.count,
                    label: "Credentials"
                )

                metric(
                    icon: "car.fill",
                    value: technician.workforceProfile.resourceAccess
                        .filter(\.isAvailable).count,
                    label: "Resources"
                )
            }

            if credentialAlertCount > 0 {
                Label(
                    credentialAlertLabel,
                    systemImage: hasExpiredCredential
                        ? "xmark.octagon.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasExpiredCredential ? .red : .orange)
            }

            if let workload = snapshot?.workload {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Daily Workload")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(
                            "\(workload.assignmentCount) assignments · \(workload.utilizationPercentage)%"
                        )
                        .font(.caption.weight(.semibold))
                    }

                    ProgressView(
                        value: min(
                            max(workload.utilizationFraction, 0),
                            1
                        )
                    )
                    .tint(workload.utilizationFraction >= 0.9 ? .orange : .blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }

    private var profileSubtitle: String {
        technician.workforceProfile.hasIntelligenceData
            ? "Operational profile configured"
            : "Workforce profile not started"
    }

    private var credentialStatuses: [WorkforceCertificationStatus] {
        technician.workforceProfile.certifications.map {
            $0.status(on: reviewDate)
        }
    }

    private var credentialAlertCount: Int {
        credentialStatuses.filter {
            $0 == .expired || $0 == .expiresSoon
        }.count
    }

    private var hasExpiredCredential: Bool {
        credentialStatuses.contains(.expired)
    }

    private var credentialAlertLabel: String {
        let noun = credentialAlertCount == 1 ? "credential" : "credentials"
        return "\(credentialAlertCount) \(noun) require attention"
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        let state = snapshot?.availability.state ?? .unavailable

        Label(state.rawValue, systemImage: availabilityIcon(state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(availabilityColor(state))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(availabilityColor(state).opacity(0.12))
            .clipShape(Capsule())
    }

    private func metric(
        icon: String,
        value: Int,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(value.formatted(), systemImage: icon)
                .font(.subheadline.weight(.semibold))

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func availabilityIcon(
        _ state: WorkforceAvailabilityState
    ) -> String {
        switch state {
        case .available, .availableOverride:
            return "checkmark.circle.fill"
        case .limited:
            return "clock.fill"
        case .unavailable, .inactive:
            return "xmark.circle.fill"
        case .offSchedule:
            return "calendar.badge.minus"
        }
    }

    private func availabilityColor(
        _ state: WorkforceAvailabilityState
    ) -> Color {
        switch state {
        case .available, .availableOverride:
            return .green
        case .limited:
            return .orange
        case .unavailable, .inactive:
            return .red
        case .offSchedule:
            return .secondary
        }
    }
}

private struct WorkforceCredentialAlert: Identifiable {
    let technicianID: UUID
    let technicianName: String
    let certification: WorkforceCertification
    let status: WorkforceCertificationStatus

    var id: String {
        "\(technicianID.uuidString)-\(certification.id.uuidString)"
    }

    var detailText: String {
        switch status {
        case .expired:
            if let expirationDate = certification.expirationDate {
                return "Expired \(expirationDate.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Expired"

        case .expiresSoon:
            if let expirationDate = certification.expirationDate {
                return "Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Expires soon"

        case .active:
            return "Active"

        case .inactive:
            return "Inactive"
        }
    }
}
