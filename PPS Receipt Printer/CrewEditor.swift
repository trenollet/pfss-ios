//
//  CrewEditor.swift
//  PPS Receipt Printer
//

import SwiftUI

struct CrewEditor: View {
    @ObservedObject var engine: AssignmentEngine
    let dispatchEngine: DispatchEngine?

    let assignmentID: UUID
    let employees: [EmployeeRecord]
    let actorEmployeeID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var pendingRemoval: EmployeeRecord?

    init(
        engine: AssignmentEngine,
        dispatchEngine: DispatchEngine? = nil,
        assignmentID: UUID,
        employees: [EmployeeRecord],
        actorEmployeeID: UUID? = nil
    ) {
        self.engine = engine
        self.dispatchEngine = dispatchEngine
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

                    Section("Supporting Technician") {
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

                            if let currentSupporting = assignment.crew.supportingTechnicians.first {
                                Menu("Replace Supporting Technician", systemImage: "arrow.triangle.2.circlepath") {
                                    ForEach(availableEmployees(excluding: assignment.crew.activeEmployeeIDs)) { employee in
                                        Button(employee.displayName) {
                                            replaceSupporting(
                                                with: employee.id
                                            )
                                        }
                                    }
                                }
                                .disabled(!crewCanChange(assignment))

                                Button(
                                    "Remove Supporting Technician",
                                    systemImage: "person.badge.minus",
                                    role: .destructive
                                ) {
                                    pendingRemoval = employee(currentSupporting.employeeID)
                                }
                                .disabled(!crewCanChange(assignment))
                            }
                        }

                        if assignment.crew.supportingTechnicians.isEmpty {
                            Menu("Add Supporting Technician") {
                                ForEach(availableEmployees(excluding: assignment.crew.activeEmployeeIDs)) { employee in
                                    Button(employee.displayName) {
                                        addSupporting(employee.id)
                                    }
                                }
                            }
                        } else {
                            Text("Version 1 supports one supporting technician.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                ($0.hasRole(.technician) || $0.hasRole(.owner) || $0.hasRole(.manager))
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
            if let dispatchEngine,
               let technician = employee(employeeID) {
                _ = try dispatchEngine.assignPrimaryTechnician(
                    assignmentID: assignmentID,
                    technician: technician,
                    actor: dispatchActor
                )
            } else {
                _ = try engine.assignPrimaryTechnician(
                    assignmentID: assignmentID,
                    employeeID: employeeID,
                    actorEmployeeID: actorEmployeeID
                )
            }
        }
    }

    private func replacePrimary(with employeeID: UUID) {
        perform {
            if let dispatchEngine,
               let technician = employee(employeeID) {
                _ = try dispatchEngine.assignPrimaryTechnician(
                    assignmentID: assignmentID,
                    technician: technician,
                    actor: dispatchActor,
                    note: "Primary technician changed in Crew Editor"
                )
            } else {
                _ = try engine.replacePrimaryTechnician(
                    assignmentID: assignmentID,
                    with: employeeID,
                    actorEmployeeID: actorEmployeeID,
                    reason: "Primary technician changed in Crew Editor"
                )
            }
        }
    }

    private func addSupporting(_ employeeID: UUID) {
        perform {
            if let dispatchEngine,
               let technician = employee(employeeID) {
                _ = try dispatchEngine.addSupportingTechnician(
                    assignmentID: assignmentID,
                    technician: technician,
                    actor: dispatchActor
                )
            } else {
                _ = try engine.addSupportingTechnician(
                    assignmentID: assignmentID,
                    employeeID: employeeID,
                    actorEmployeeID: actorEmployeeID
                )
            }
        }
    }

    private func removeSupporting(_ employeeID: UUID) {
        perform {
            if let dispatchEngine {
                _ = try dispatchEngine.removeSupportingTechnician(
                    assignmentID: assignmentID,
                    technicianID: employeeID,
                    actor: dispatchActor,
                    reason: "Supporting technician removed in Crew Editor"
                )
            } else {
                _ = try engine.removeSupportingTechnician(
                    assignmentID: assignmentID,
                    employeeID: employeeID,
                    actorEmployeeID: actorEmployeeID,
                    reason: "Supporting technician removed in Crew Editor"
                )
            }
        }
    }

    private func replaceSupporting(with replacementEmployeeID: UUID) {
        perform {
            if let dispatchEngine,
               let technician = employee(replacementEmployeeID) {
                _ = try dispatchEngine.replaceSupportingTechnician(
                    assignmentID: assignmentID,
                    technician: technician,
                    actor: dispatchActor,
                    reason: "Supporting technician changed in Crew Editor"
                )
            } else {
                _ = try engine.replaceSupportingTechnician(
                    assignmentID: assignmentID,
                    with: replacementEmployeeID,
                    actorEmployeeID: actorEmployeeID,
                    reason: "Supporting technician changed in Crew Editor"
                )
            }
        }
    }

    private var dispatchActor: DispatchActor {
        guard let actorEmployeeID,
              let employee = employees.first(where: {
                  $0.id == actorEmployeeID
              }) else {
            return .system
        }

        return DispatchActor.employee(employee)
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
