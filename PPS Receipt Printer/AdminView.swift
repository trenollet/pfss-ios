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
                Section("Coming Soon") {
                    

                    Label(
                        "Printer Settings",
                        systemImage: "printer"
                    )
                    .foregroundStyle(.secondary)

                    Label(
                        "Data Management",
                        systemImage: "externaldrive"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        .navigationTitle("Admin")
    }
}
