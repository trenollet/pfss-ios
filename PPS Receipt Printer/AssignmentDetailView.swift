//
//  AssignmentDetailView.swift
//  PPS Receipt Printer
//

import SwiftUI

struct AssignmentDetailView: View {
    @ObservedObject var engine: AssignmentEngine
    let dispatchEngine: DispatchEngine?

    let assignmentID: UUID
    let employees: [EmployeeRecord]
    let customers: [Customer]
    let sites: [CustomerSite]
    let actorEmployeeID: UUID?

    @State private var showingCrewEditor = false
    @State private var showingScheduleEditor = false
    @State private var showingCancellation = false
    @State private var cancellationReason = ""
    @State private var showingUnassign = false
    @State private var unassignReason = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    init(
        engine: AssignmentEngine,
        dispatchEngine: DispatchEngine? = nil,
        assignmentID: UUID,
        employees: [EmployeeRecord],
        customers: [Customer],
        sites: [CustomerSite],
        actorEmployeeID: UUID? = nil
    ) {
        self.engine = engine
        self.dispatchEngine = dispatchEngine
        self.assignmentID = assignmentID
        self.employees = employees
        self.customers = customers
        self.sites = sites
        self.actorEmployeeID = actorEmployeeID
    }

    var body: some View {
        Group {
            if let assignment {
                List {
                    customerSiteHeader(assignment)
                    overviewSection(assignment)
                    schedulingSection(assignment)
                    crewSection(assignment)
                    primaryActionSection(assignment)
                    notesSection(assignment)
                    historySection(assignment)
                }
                .contentMargins(.top, 4, for: .scrollContent)
                .navigationTitle("Assignment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit Crew", systemImage: "person.2.fill") {
                                showingCrewEditor = true
                            }

                            if canUnassign(assignment) {
                                Button("Unassign and Return to Queue", systemImage: "person.crop.circle.badge.minus") {
                                    showingUnassign = true
                                }
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
                dispatchEngine: dispatchEngine,
                assignmentID: assignmentID,
                employees: employees,
                actorEmployeeID: actorEmployeeID
            )
        }
        .sheet(isPresented: $showingScheduleEditor) {
            if let assignment {
                AssignmentSchedulingEditorView(
                    engine: engine,
                    assignmentID: assignmentID,
                    scheduling: assignment.scheduling,
                    actorEmployeeID: actorEmployeeID
                )
            }
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
        .alert("Return to Dispatch Queue", isPresented: $showingUnassign) {
            TextField("Reason", text: $unassignReason)
            Button("Unassign", role: .destructive) {
                unassignAssignment()
            }
            Button("Keep Assignment", role: .cancel) {
                unassignReason = ""
            }
        } message: {
            Text("The primary and supporting technicians will be removed and the work will return to the Dispatch Queue. A reason is required.")
        }
    }

    private var assignment: Assignment? {
        engine.assignment(id: assignmentID)
    }

    private func customerSiteHeader(_ assignment: Assignment) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(customerDisplayName(for: assignment))
                    .font(.title2.weight(.bold))

                Label(siteDisplayName(for: assignment), systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.medium))

                if let address = siteAddress(for: assignment) {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(assignment.jobNumber)
                    Text(assignment.assignmentNumber)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 2)
        }
    }

    private func overviewSection(_ assignment: Assignment) -> some View {
        Section("Overview") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("Status")
                    Spacer(minLength: 12)
                    Label(
                        assignment.status.rawValue,
                        systemImage: statusSymbol(for: assignment.status)
                    )
                    .font(.body.weight(.semibold))
                    .foregroundStyle(statusColor(for: assignment.status))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Divider()

                LabeledContent("Scheduled") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(assignment.scheduling.displayDateText)
                        Text(assignment.scheduling.displayTimeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Picker("Priority", selection: priorityBinding(for: assignment)) {
                    ForEach(AssignmentPriority.allCases) { priority in
                        Text(priority.rawValue).tag(priority)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(assignment.priority == .emergency ? 10 : 0)
            .overlay {
                if assignment.priority == .emergency {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red, lineWidth: 2)
                }
            }
        }
    }

    private func schedulingSection(_ assignment: Assignment) -> some View {
        Section("Scheduling") {
            LabeledContent("Mode", value: assignment.scheduling.mode.rawValue)

            Button("Edit Schedule", systemImage: "calendar.badge.clock") {
                showingScheduleEditor = true
            }
            .disabled(
                assignment.status != .scheduled &&
                assignment.status != .dispatched
            )

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

    private func priorityBinding(for assignment: Assignment) -> Binding<AssignmentPriority> {
        Binding(
            get: { assignment.priority },
            set: { newPriority in
                guard newPriority != assignment.priority else { return }
                perform {
                    _ = try engine.updatePriority(
                        assignmentID: assignmentID,
                        priority: newPriority,
                        actorEmployeeID: actorEmployeeID,
                        note: "Priority updated from Assignment Detail."
                    )
                }
            }
        )
    }

    private func customerDisplayName(for assignment: Assignment) -> String {
        guard let customer = customers.first(where: {
            $0.customerNumber == assignment.customerNumber
        }) else {
            return assignment.customerNumber.isEmpty
                ? "Unknown Customer"
                : assignment.customerNumber
        }

        let businessName = customer.businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contactName = customer.contactName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !businessName.isEmpty { return businessName }
        if !contactName.isEmpty { return contactName }
        return customer.customerNumber
    }

    private func siteDisplayName(for assignment: Assignment) -> String {
        guard let site = site(for: assignment) else {
            return "No site assigned"
        }

        let name = site.siteName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Site" : name
    }

    private func siteAddress(for assignment: Assignment) -> String? {
        guard let site = site(for: assignment) else { return nil }
        let address = site.serviceAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    private func site(for assignment: Assignment) -> CustomerSite? {
        guard let siteID = assignment.siteID else { return nil }
        return sites.first { $0.id == siteID }
    }

    private func statusColor(for status: AssignmentStatus) -> Color {
        switch status {
        case .scheduled: return .blue
        case .dispatched: return .indigo
        case .enRoute: return .orange
        case .onSite: return .purple
        case .workComplete: return .teal
        case .invoiceReady: return .mint
        case .closed: return .green
        case .cancelled: return .red
        }
    }

    private func statusSymbol(for status: AssignmentStatus) -> String {
        switch status {
        case .scheduled: return "calendar"
        case .dispatched: return "paperplane.fill"
        case .enRoute: return "car.fill"
        case .onSite: return "location.fill"
        case .workComplete: return "checkmark.circle.fill"
        case .invoiceReady: return "doc.text.fill"
        case .closed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private func canCancel(_ assignment: Assignment) -> Bool {
        assignment.status.isTerminal == false && assignment.status != .invoiceReady
    }

    private func canUnassign(_ assignment: Assignment) -> Bool {
        assignment.primaryTechnicianID != nil &&
        (assignment.status == .scheduled || assignment.status == .dispatched)
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
                if let dispatchEngine {
                    let actor: DispatchActor
                    if let actorEmployeeID,
                       let employee = employees.first(where: {
                           $0.id == actorEmployeeID
                       }) {
                        actor = DispatchActor.employee(employee)
                    } else {
                        actor = .system
                    }

                    _ = try dispatchEngine.dispatch(
                        assignmentID: assignmentID,
                        actor: actor
                    )
                } else {
                    _ = try engine.dispatch(
                        assignmentID: assignmentID,
                        actorEmployeeID: actorEmployeeID
                    )
                }
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

    private func unassignAssignment() {
        perform {
            _ = try engine.unassignCrew(
                assignmentID: assignmentID,
                actorEmployeeID: actorEmployeeID,
                reason: unassignReason
            )
            unassignReason = ""
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
