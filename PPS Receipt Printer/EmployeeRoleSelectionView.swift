//
//  EmployeeRoleSelectionView.swift
//  PPS Receipt Printer
//

import SwiftUI

struct EmployeeRoleSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedRoles: Set<EmployeeRole>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EmployeeRole.allCases) { role in
                        Button {
                            toggle(role)
                        } label: {
                            HStack {
                                Text(role.displayName)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(
                                    systemName: selectedRoles.contains(role)
                                        ? "checkmark.square.fill"
                                        : "square"
                                )
                                .foregroundStyle(
                                    selectedRoles.contains(role)
                                        ? Color.accentColor
                                        : Color.secondary
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Employee Roles")
                } footer: {
                    Text("Select every role this employee performs. At least one role is required.")
                }
            }
            .navigationTitle("Select Roles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ role: EmployeeRole) {
        if selectedRoles.contains(role) {
            guard selectedRoles.count > 1 else { return }
            selectedRoles.remove(role)
        } else {
            selectedRoles.insert(role)
        }
    }
}
