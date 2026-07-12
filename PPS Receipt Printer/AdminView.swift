//
//  AdminView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import SwiftUI

struct AdminView: View {
    var body: some View {
        NavigationStack {
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
                        "Employees & Roles",
                        systemImage: "person.3"
                    )
                    .foregroundStyle(.secondary)

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
}
