//
//  EmployeesView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/14/26.
//

import SwiftUI

struct EmployeesView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingNewEmployee = false

    private var filteredEmployees: [EmployeeRecord] {
        let source = showArchived
            ? store.archivedEmployees
            : store.activeEmployees

        if searchText.isEmpty {
            return source.sorted {
                $0.displayName < $1.displayName
            }
        }

        return source.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.email.localizedCaseInsensitiveContains(searchText)
        }
        .sorted {
            $0.displayName < $1.displayName
        }
    }

    var body: some View {
        List {
                Section {
                    NavigationLink {
                        WorkforceCapacityDashboardView()
                            .environmentObject(store)
                    } label: {
                        Label(
                            "Daily Capacity Dashboard",
                            systemImage: "chart.bar.fill"
                        )
                    }

                    Button("Add New Employee") {
                        showingNewEmployee = true
                    }

                    Toggle(
                        "Show Archived",
                        isOn: $showArchived
                    )
                }

                Section("Employees") {

                    if filteredEmployees.isEmpty {

                        ContentUnavailableView(
                            "No Employees",
                            systemImage: "person.3",
                            description: Text(
                                showArchived
                                ? "There are no archived employees."
                                : "Tap 'Add New Employee' to create your first employee."
                            )
                        )

                    } else {

                        ForEach(filteredEmployees) { employee in

                            NavigationLink {

                                // Detail View
                                EmployeeDetailView(
                                    employee: employee
                                )
                                .environmentObject(store)

                            } label: {

                                VStack(
                                    alignment: .leading,
                                    spacing: 6
                                ) {

                                    HStack {

                                        Text(employee.displayName)
                                            .font(.headline)

                                        Spacer()

                                        Text(employee.role.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(
                                        SchedulingCalculator.formattedDuration(
                                            minutes: employee.dailyCapacityMinutes
                                        )
                                        + " capacity"
                                    )
                                    .font(.caption)

                                    if employee.lifecycleStatus == .archived {
                                        Text("Archived")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Employees")
            .searchable(
                text: $searchText,
                prompt: "Search employees"
            )
            .sheet(
                isPresented: $showingNewEmployee
            ) {
                EmployeeNewView()
                    .environmentObject(store)
        }
    }
}
