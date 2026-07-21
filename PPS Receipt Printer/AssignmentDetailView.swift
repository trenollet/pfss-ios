//
//  AssignmentDetailView.swift
//  PPS Receipt Printer
//

import SwiftUI

struct AssignmentDetailView: View {
    @ObservedObject var engine: AssignmentEngine

    let assignmentID: UUID
    let employees: [EmployeeRecord]
    let actorEmployeeID: UUID?

    @State private var showingCrewEditor = false
    @State private var showingCancellation = false
    @State private var cancellationReason = ""
    @State private var errorMessage = ""
    @State private var showingError = false

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
        Group {
            if let assignment {
                List {
                    overviewSection(assignment)
                    schedulingSection(assignment)
                    crewSection(assignment)
                    primaryActionSection(assignment)
                    notesSection(assignment)
                    historySection(assignment)
                }
                .navigationTitle("Assignment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit Crew", systemImage: "person.2.fill") {
                                showingCrewEditor = true
                            }

                            if canCancel(assignment) {
                                Button("Cancel Assignment", systemImage: "xmark.circle", role: .destructive) {
                                    showingCancellation = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Assignment Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This assignment may have been deleted or archived.")
                )
            }
        }
        .sheet(isPresented: $showingCrewEditor) {
            CrewEditor(
                engine: engine,
                assignmentID: assignmentID,
                employees: employees,
                actorEmployeeID: actorEmployeeID
            )
        }
        .alert("Assignment Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Cancel Assignment", isPresented: $showingCancellation) {
            TextField("Reason", text: $cancellationReason)
            Button("Cancel Assignment", role: .destructive) {
                cancelAssignment()
            }
            Button("Keep Assignment", role: .cancel) {
                cancellationReason = ""
            }
        } message: {
            Text("A reason is required and will be added to assignment history.")
        }
    }

    private var assignment: Assignment? {
        engine.assignment(id: assignmentID)
    }

    private func overviewSection(_ assignment: Assignment) -> some View {
        Section("Overview") {
            LabeledContent("Status") {
                AssignmentStatusBadge(status: assignment.status)
            }
            LabeledContent("Assignment", value: assignment.assignmentNumber)
            LabeledContent("Job", value: assignment.jobNumber)
            LabeledContent("Customer", value: assignment.customerNumber)
            LabeledContent("Priority", value: assignment.priority.rawValue)

            if let routeSequence = assignment.routeSequence {
                LabeledContent("Route Stop", value: String(routeSequence))
            }
        }
    }

    private func schedulingSection(_ assignment: Assignment) -> some View {
        Section("Scheduling") {
            LabeledContent("Mode", value: assignment.scheduling.mode.rawValue)

            if assignment.scheduling.schedulingNotes.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduling Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(assignment.scheduling.schedulingNotes)
                }
            }
        }
    }

    private func crewSection(_ assignment: Assignment) -> some View {
        Section("Crew") {
            LabeledContent("Primary", value: employeeName(assignment.primaryTechnicianID))

            ForEach(assignment.crew.supportingTechnicians) { member in
                LabeledContent("Supporting", value: employeeName(member.employeeID))
            }

            Button("Manage Crew", systemImage: "person.2.fill") {
                showingCrewEditor = true
            }
            .disabled(assignment.status != .scheduled && assignment.status != .dispatched)
        }
    }

    @ViewBuilder
    private func primaryActionSection(_ assignment: Assignment) -> some View {
        if let action = nextAction(for: assignment) {
            Section("Next Action") {
                Button {
                    performPrimaryAction(action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ assignment: Assignment) -> some View {
        if assignment.dispatchNotes.isEmpty == false || assignment.fieldNotes.isEmpty == false {
            Section("Notes") {
                if assignment.dispatchNotes.isEmpty == false {
                    noteBlock(title: "Dispatch", text: assignment.dispatchNotes)
                }
                if assignment.fieldNotes.isEmpty == false {
                    noteBlock(title: "Field", text: assignment.fieldNotes)
                }
            }
        }
    }

    private func historySection(_ assignment: Assignment) -> some View {
        Section("Assignment History") {
            if assignment.history.reverseChronologicalEvents.isEmpty {
                Text("No history recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assignment.history.reverseChronologicalEvents) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(event.timestamp, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let note = event.note, note.isEmpty == false {
                            Text(note)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func noteBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
    }

    private func employeeName(_ id: UUID?) -> String {
        guard let id else { return "Not assigned" }
        return employees.first { $0.id == id }?.displayName ?? "Unknown technician"
    }

    private func canCancel(_ assignment: Assignment) -> Bool {
        assignment.status.isTerminal == false && assignment.status != .invoiceReady
    }

    private func nextAction(for assignment: Assignment) -> AssignmentPrimaryAction? {
        switch assignment.status {
        case .scheduled: return .dispatch
        case .dispatched: return .beginTravel
        case .enRoute: return .arrive
        case .onSite: return .completeWork
        case .workComplete: return .markInvoiceReady
        case .invoiceReady: return .close
        case .closed, .cancelled: return nil
        }
    }

    private func performPrimaryAction(_ action: AssignmentPrimaryAction) {
        perform {
            switch action {
            case .dispatch:
                _ = try engine.dispatch(assignmentID: assignmentID, actorEmployeeID: actorEmployeeID)
            case .beginTravel:
                _ = try engine.beginTravel(assignmentID: assignmentID, actorEmployeeID: actorEmployeeID)
            case .arrive:
                _ = try engine.arrive(assignmentID: assignmentID, actorEmployeeID: actorEmployeeID)
            case .completeWork:
                _ = try engine.complete(assignmentID: assignmentID, actorEmployeeID: actorEmployeeID)
            case .markInvoiceReady:
                _ = try engine.markInvoiceReady(assignmentID: assignmentID, actorEmployeeID: actorEmployeeID)
            case .close:
                _ = try engine.close(assignmentID: assignmentID, actorEmployeeID: actorEmployeeID)
            }
        }
    }

    private func cancelAssignment() {
        perform {
            _ = try engine.cancel(
                assignmentID: assignmentID,
                actorEmployeeID: actorEmployeeID,
                reason: cancellationReason
            )
            cancellationReason = ""
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

private enum AssignmentPrimaryAction {
    case dispatch
    case beginTravel
    case arrive
    case completeWork
    case markInvoiceReady
    case close

    var title: String {
        switch self {
        case .dispatch: return "Dispatch Assignment"
        case .beginTravel: return "Start Travel"
        case .arrive: return "Mark Arrived"
        case .completeWork: return "Complete Work"
        case .markInvoiceReady: return "Mark Invoice Ready"
        case .close: return "Close Assignment"
        }
    }

    var symbol: String {
        switch self {
        case .dispatch: return "paperplane.fill"
        case .beginTravel: return "car.fill"
        case .arrive: return "location.fill"
        case .completeWork: return "checkmark.circle.fill"
        case .markInvoiceReady: return "doc.text.fill"
        case .close: return "checkmark.seal.fill"
        }
    }
}
