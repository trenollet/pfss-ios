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
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    hubTile(
                        title: "Leads",
                        value: "\(store.activeLeads.count)",
                        icon: "person.crop.circle.badge.plus",
                        subtitle: "Sales opportunities",
                        color: .blue
                    ) {
                        LeadsView()
                    }

                    hubTile(
                        title: "Estimates",
                        value: "\(store.activeEstimates.count)",
                        icon: "doc.text.fill",
                        subtitle: "Quotes and approvals",
                        color: .indigo
                    ) {
                        EstimatesView()
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
                VStack(spacing: 16) {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        hubTile(
                            title: "Jobs",
                            value: "\(store.activeJobs.count)",
                            icon: "wrench.and.screwdriver.fill",
                            subtitle: "Service work",
                            color: .orange
                        ) {
                            JobsView()
                        }

                        hubTile(
                            title: "Invoices",
                            value: "\(store.activeInvoices.count)",
                            icon: "doc.text.fill",
                            subtitle: "Billing and payments",
                            color: .green
                        ) {
                            InvoicesView()
                        }
                    }

                    hubTile(
                        title: "Customers",
                        value: "\(store.activeCustomers.count)",
                        icon: "person.2.fill",
                        subtitle: "Customers and sites",
                        color: .blue
                    ) {
                        CustomersView()
                    }
                    .frame(maxWidth: 360)
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
