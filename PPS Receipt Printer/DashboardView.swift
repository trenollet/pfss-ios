//
//  DashboardView.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 4.6 – Primary application navigation hub.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppDataStore
    @Binding var selectedSection: AppSection

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var todaysJobCount: Int {
        store.activeJobs.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: Date())
        }.count
    }

    private var dispatchQueueCount: Int {
        store.assignmentEngine.unassignedAssignments.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        dashboardTile(
                            title: "Sales",
                            value: "\(store.activeLeads.count + store.activeEstimates.count)",
                            icon: "chart.line.uptrend.xyaxis",
                            subtitle: "Leads and estimates",
                            color: .blue,
                            section: .sales
                        )

                        dashboardTile(
                            title: "Service",
                            value: "\(store.activeJobs.count)",
                            icon: "wrench.and.screwdriver.fill",
                            subtitle: "Jobs and customers",
                            color: .orange,
                            section: .service
                        )
                    }

                    dashboardTile(
                        title: "My Day",
                        value: "\(todaysJobCount)",
                        icon: "calendar.day.timeline.left",
                        subtitle: "Today's technician work",
                        color: .cyan,
                        section: .myDay
                    )
                    .frame(maxWidth: 360)

                    LazyVGrid(columns: columns, spacing: 16) {
                        dashboardTile(
                            title: "Operations",
                            value: "\(dispatchQueueCount)",
                            icon: "person.3.sequence.fill",
                            subtitle: "Awaiting dispatch",
                            color: .purple,
                            section: .operations
                        )

                        dashboardTile(
                            title: "Admin",
                            value: "Manage",
                            icon: "gearshape.2.fill",
                            subtitle: "Business settings",
                            color: .gray,
                            section: .admin
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func dashboardTile(
        title: String,
        value: String,
        icon: String,
        subtitle: String,
        color: Color,
        section: AppSection
    ) -> some View {
        Button {
            selectedSection = section
        } label: {
            DashboardStatCard(
                title: title,
                value: value,
                icon: icon,
                subtitle: subtitle,
                accentColor: color,
                trend: .neutral,
                navigationIndicator: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title)")
    }
}
