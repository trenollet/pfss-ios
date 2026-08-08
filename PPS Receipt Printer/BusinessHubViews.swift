//
//  BusinessHubViews.swift
//  PPS Receipt Printer
//
//  Phase 15 Step 4.6 – Sales and Service navigation hubs.
//

import SwiftUI

struct SalesDashboardView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        NavigationStack {
            ScrollView {
                CustomizableTileGrid(
                    storageKey: "pfss.tile-layout.sales.v2",
                    defaultTileIDs: [
                        "leads",
                        "customers",
                        "estimates",
                        "pricing-calculator",
                        "calendar"
                    ]
                ) { tileID in
                    switch tileID {
                    case "leads":
                    hubTile(
                        title: "Leads",
                        value: "\(store.activeLeads.count)",
                        icon: "person.crop.circle.badge.plus",
                        subtitle: "Sales opportunities",
                        color: .blue
                    ) {
                        LeadsView()
                    }
                    case "estimates":
                    hubTile(
                        title: "Estimates",
                        value: "\(store.activeEstimates.count)",
                        icon: "doc.text.fill",
                        subtitle: "Quotes and approvals",
                        color: .indigo
                    ) {
                        EstimatesView()
                    }
                    case "customers":
                        hubTile(
                        title: "Customers",
                        value: "\(store.activeCustomers.count)",
                        icon: "person.2.fill",
                        subtitle: "Customers and sites",
                        color: .blue
                        ) {
                            CustomersView()
                        }
                    case "pricing-calculator":
                        hubTile(
                            title: "Price Calc",
                            value: "",
                            icon: "plus.forwardslash.minus",
                            subtitle: "Routine service pricing",
                            color: .teal
                        ) {
                            FieldPricingCalculatorView()
                        }
                    case "calendar":
                        hubTile(
                            title: "Calendar",
                            value: "",
                            icon: "calendar",
                            subtitle: "Scheduled follow-ups",
                            color: .blue
                        ) {
                            SalesFollowUpCalendarView()
                        }
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sales")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct ServiceDashboardView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        NavigationStack {
            ScrollView {
                CustomizableTileGrid(
                    storageKey: "pfss.tile-layout.service.v1",
                    defaultTileIDs: ["jobs", "invoices", "customers"]
                ) { tileID in
                    switch tileID {
                    case "jobs":
                        hubTile(
                            title: "Jobs",
                            value: "\(store.activeJobs.count)",
                            icon: "wrench.and.screwdriver.fill",
                            subtitle: "Service work",
                            color: .orange
                        ) {
                            JobsView()
                        }
                    case "invoices":
                        hubTile(
                            title: "Invoices",
                            value: "\(store.activeInvoices.count)",
                            icon: "doc.text.fill",
                            subtitle: "Billing and payments",
                            color: .green
                        ) {
                            InvoicesView()
                        }
                    case "customers":
                    hubTile(
                        title: "Customers",
                        value: "\(store.activeCustomers.count)",
                        icon: "person.2.fill",
                        subtitle: "Customers and sites",
                        color: .blue
                    ) {
                        CustomersView()
                    }
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Service")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private func hubTile<Destination: View>(
    title: String,
    value: String,
    icon: String,
    subtitle: String,
    color: Color,
    @ViewBuilder destination: () -> Destination
) -> some View {
    NavigationLink(destination: destination) {
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
