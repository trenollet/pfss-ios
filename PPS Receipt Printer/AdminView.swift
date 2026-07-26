//
//  AdminView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import SwiftUI

struct AdminView: View {
    var body: some View {
        List {
                Section("Business") {
                    NavigationLink {
                        BusinessProfileView()
                    } label: {
                        Label(
                            "Business Profile",
                            systemImage: "building.2"
                        )
                    }
                    NavigationLink {
                        EmployeesView()
                    } label: {
                        Label(
                            "Employees & Capacity",
                            systemImage: "person.3"
                        )
                    }
                }

                Section("Reports") {
                    NavigationLink {
                        SitesView()
                    } label: {
                        Label(
                            "Sites",
                            systemImage: "house"
                        )
                    }

                    NavigationLink {
                        JobHistoryReportView()
                    } label: {
                        Label(
                            "Job History Report",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }

                Section("Configuration") {
                    NavigationLink {
                        RecommendationRuleEditorView()
                    } label: {
                        Label(
                            "Recommendation Rules",
                            systemImage: "sparkles"
                        )
                    }
                }

                Section("Catalog & Printing") {
                    NavigationLink {
                        ServiceCatalogView()
                    } label: {
                        Label("Catalog Items", systemImage: "square.grid.2x2")
                    }

                    NavigationLink {
                        PrintView()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                }

                Section("Coming Soon") {
                    Label(
                        "Data Management",
                        systemImage: "externaldrive"
                    )
                    .foregroundStyle(.secondary)
                }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.large)
    }
}
