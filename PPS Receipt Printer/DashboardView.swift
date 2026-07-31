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

    private var todaysJobCount: Int {
        store.activeJobs.filter {
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: Date())
        }.count
    }

    private var dispatchQueueCount: Int {
        store.assignmentEngine.unassignedAssignments.count
    }

    private var dashboardTileIDs: [String] {
        var tileIDs = ["sales", "service", "myDay", "operations"]
        if store.shouldPresentAdminDashboardTile {
            tileIDs.append("admin")
        }
        return tileIDs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                CustomizableTileGrid(
                    storageKey: "pfss.tile-layout.dashboard.v1",
                    defaultTileIDs: dashboardTileIDs
                ) { tileID in
                    switch tileID {
                    case "sales":
                        dashboardTile(
                            title: "Sales",
                            value: "\(store.activeLeads.count + store.activeEstimates.count)",
                            icon: "chart.line.uptrend.xyaxis",
                            subtitle: "Leads and estimates",
                            color: .blue,
                            section: .sales
                        )
                    case "service":
                        dashboardTile(
                            title: "Service",
                            value: "\(store.activeJobs.count)",
                            icon: "wrench.and.screwdriver.fill",
                            subtitle: "Jobs and customers",
                            color: .orange,
                            section: .service
                        )
                    case "myDay":
                    dashboardTile(
                        title: "My Day",
                        value: "\(todaysJobCount)",
                        icon: "calendar.day.timeline.left",
                        subtitle: "Today's technician work",
                        color: .cyan,
                        section: .myDay
                    )
                    case "operations":
                        if store.canManageCompany {
                            NavigationLink {
                                OperationsView()
                            } label: {
                                DashboardStatCard(
                                    title: "Operations",
                                    value: "\(dispatchQueueCount)",
                                    icon: "person.3.sequence.fill",
                                    subtitle: "Awaiting dispatch",
                                    accentColor: .purple,
                                    trend: .neutral,
                                    navigationIndicator: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens Operations")
                        }
                    case "admin":
                        if store.shouldPresentAdminDashboardTile {
                            dashboardTile(
                                title: "Settings",
                                value: "Manage",
                                icon: "gearshape.2.fill",
                                subtitle: "Business settings",
                                color: .gray,
                                section: .admin
                            )
                        }
                    default:
                        EmptyView()
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
