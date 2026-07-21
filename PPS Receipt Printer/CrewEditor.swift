//
//  CrewEditor.swift
//  PPS Receipt Printer
//

import SwiftUI

struct CrewEditor: View {
    @ObservedObject var engine: AssignmentEngine

    let assignmentID: UUID
    let employees: [EmployeeRecord]
    let actorEmployeeID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var pendingRemoval: EmployeeRecord?

    init(
        engine: AssignmentEngine,
        assignmentID: UUID,
        employees: [EmployeeRecord],
        actorEmployeeID: UUID? = nil
    ) {
        self.engine = engine
        self.assignmentID = assignmentID
        self.employees = employees
        self.actorEmployeeID = actorEmployeeID
    }

    var body: some View {
        NavigationStack {
            List {
                if let assignment {
                    Section("Primary Technician") {
                        if let primaryID = assignment.primaryTechnicianID {
                            employeeRow(employeeID: primaryID, role: "Primary")

                            Menu("Replace Primary Technician") {
                                ForEach(availableEmployees(excluding: assignment.crew.activeEmployeeIDs)) { employee in
                                    Button(employee.displayName) {
                                        replacePrimary(with: employee.id)
                                    }
                                }
                            }
                        } else {
                            Menu("Assign Primary Technician") {
                                ForEach(availableEmployees(excluding: assignment.crew.activeEmployeeIDs)) { employee in
                                    Button(employee.displayName) {
                                        assignPrimary(employee.id)
                                    }
                                }
                            }
                        }
                    }

                    Section("Supporting Technicians") {
                        if assignment.crew.supportingTechnicians.isEmpty {
                            Text("No supporting technicians assigned")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(assignment.crew.supportingTechnicians) { member in
                                employeeRow(employeeID: member.employeeID, role: "Supporting")
                                    .swipeActions {
                                        if let employee = employee(member.employeeID) {
                                            Button("Remove", role: .destructive) {
                                                pendingRemoval = employee
                                            }
                                        }
                                    }
                            }
                        }

                        Menu("Add Supporting Technician") {
                            ForEach(availableEmployees(excluding: assignment.crew.activeEmployeeIDs)) { employee in
                                Button(employee.displayName) {
                                    addSupporting(employee.id)
                                }
                            }
                        }
                    }

                    if crewCanChange(assignment) == false {
                        Section {
                            Label(
                                "Crew changes are locked after travel begins.",
                                systemImage: "lock.fill"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Assignment Unavailable",
                        systemImage: "person.2.slash",
                        description: Text("The assignment could not be found.")
                    )
                }
            }
            .navigationTitle("Assignment Crew")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Crew Update", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Remove supporting technician?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if $0 == false { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let employee = pendingRemoval {
                    Button("Remove \(employee.displayName)", role: .destructive) {
                        removeSupporting(employee.id)
                        pendingRemoval = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            }
        }
    }

    private var assignment: Assignment? {
        engine.assignment(id: assignmentID)
    }

    private var activeTechnicians: [EmployeeRecord] {
        employees
            .filter {
                $0.isActive &&
                $0.lifecycleStatus == .active &&
                ($0.role == .technician || $0.role == .owner || $0.role == .manager)
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    @ViewBuilder
    private func employeeRow(employeeID: UUID, role: String) -> some View {
        if let employee = employee(employeeID) {
            HStack {
                Image(systemName: role == "Primary" ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    .foregroundStyle(role == "Primary" ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(employee.displayName)
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("Unknown technician", systemImage: "person.crop.circle.badge.questionmark")
                .foregroundStyle(.secondary)
        }
    }

    private func employee(_ id: UUID) -> EmployeeRecord? {
        employees.first { $0.id == id }
    }

    private func availableEmployees(excluding ids: [UUID]) -> [EmployeeRecord] {
        activeTechnicians.filter { ids.contains($0.id) == false }
    }

    private func crewCanChange(_ assignment: Assignment) -> Bool {
        assignment.status == .scheduled || assignment.status == .dispatched
    }

    private func assignPrimary(_ employeeID: UUID) {
        perform {
            _ = try engine.assignPrimaryTechnician(
                assignmentID: assignmentID,
                employeeID: employeeID,
                actorEmployeeID: actorEmployeeID
            )
        }
    }

    private func replacePrimary(with employeeID: UUID) {
        perform {
            _ = try engine.replacePrimaryTechnician(
                assignmentID: assignmentID,
                with: employeeID,
                actorEmployeeID: actorEmployeeID,
                reason: "Primary technician changed in Crew Editor"
            )
        }
    }

    private func addSupporting(_ employeeID: UUID) {
        perform {
            _ = try engine.addSupportingTechnician(
                assignmentID: assignmentID,
                employeeID: employeeID,
                actorEmployeeID: actorEmployeeID
            )
        }
    }

    private func removeSupporting(_ employeeID: UUID) {
        perform {
            _ = try engine.removeSupportingTechnician(
                assignmentID: assignmentID,
                employeeID: employeeID,
                actorEmployeeID: actorEmployeeID,
                reason: "Supporting technician removed in Crew Editor"
            )
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
