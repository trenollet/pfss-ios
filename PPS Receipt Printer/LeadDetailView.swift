//
//  LeadDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct LeadDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var lead: Lead
    @State private var originalLead: Lead
    @State private var convertedCustomer: Customer?
    @State private var showingUnsavedChangesAlert = false
    @FocusState private var isInputFocused: Bool

    init(lead: Lead) {
        var normalizedLead = lead
        if normalizedLead.quoteOptions?.isEmpty != false {
            normalizedLead.quoteOptions = [
                LeadQuoteOption(
                    quotedPrice: normalizedLead.estimatedValue,
                    frequency: .oneTime
                )
            ]
        }
        _lead = State(initialValue: normalizedLead)
        _originalLead = State(initialValue: normalizedLead)
    }

    private var salesEmployees: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.hasRole(.salesperson) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { lead.notes ?? "" },
            set: { lead.notes = $0 }
        )
    }

    var body: some View {
        Form {
            Section("Lead") {
                Text(lead.leadNumber)
                    .font(.headline)

                TextField("Business Name", text: $lead.businessName)
                    .focused($isInputFocused)

                TextField("Contact Name", text: $lead.contactName)
                    .focused($isInputFocused)

                TextField("Location", text: Binding(
                    get: { lead.location ?? "" },
                    set: { lead.location = $0 }
                ))
                .focused($isInputFocused)

                MapAssistedAddressButton(
                    address: Binding(
                        get: { lead.location ?? "" },
                        set: { lead.location = $0 }
                    ),
                    label: "Select Location on Map"
                )

                TextField("Phone", text: $lead.phone)
                    .keyboardType(.phonePad)
                    .focused($isInputFocused)

                TextField("Email", text: $lead.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
            }

            Section("Sales Info") {
                HStack {
                    Text("Assigned Salesperson")
                    Spacer()
                    Picker("Assigned Salesperson", selection: $lead.assignedSalesperson) {
                        Text("Unassigned").tag("")
                        ForEach(salesEmployees) { employee in
                            Text(employee.displayName).tag(employee.displayName)
                        }
                    }
                    .labelsHidden()
                }

                Picker("Status", selection: $lead.status) {
                    ForEach(LeadStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                DatePicker("Follow-Up Date", selection: $lead.followUpDate, displayedComponents: .date)

                Picker("Lead Source", selection: $lead.leadSource) {
                    ForEach(LeadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                HStack {
                    Text("Service Requested")
                    Spacer()
                    Picker("Service Requested", selection: $lead.serviceRequested) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }
                    .labelsHidden()
                }

                if lead.serviceRequested == .other {
                    TextField("Other Service", text: $lead.otherService)
                        .focused($isInputFocused)
                }

                LeadQuoteOptionsEditor(
                    quoteOptions: Binding(
                        get: { lead.quoteOptions ?? [] },
                        set: { options in
                            lead.quoteOptions = options
                            lead.estimatedValue = options.first?.quotedPrice ?? 0
                        }
                    ),
                    isInputFocused: $isInputFocused
                )
            }

            Section("Notes") {
                TextEditor(text: notesBinding)
                    .frame(minHeight: 110)
                    .focused($isInputFocused)
            }

            Section {
                Button {
                    convertedCustomer = store.convertLeadToCustomer(lead)
                    if convertedCustomer != nil {
                        lead.status = .converted
                        originalLead = lead
                    }
                } label: {
                    Text("Convert to Customer")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(lead.status == .converted || lead.lifecycleStatus == .archived)

                if lead.lifecycleStatus == .archived {
                    Button {
                        store.restoreLead(lead)
                        dismiss()
                    } label: {
                        Label("Restore Lead", systemImage: "arrow.uturn.backward.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveLead(lead)
                        dismiss()
                    } label: {
                        CenteredArchiveActionLabel(title: "Archive Lead")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .navigationTitle("Edit Lead")
        .sheet(item: $convertedCustomer) { customer in
            NavigationStack {
                CustomerDetailView(customer: customer)
            }
            .environmentObject(store)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            EditorKeyboardDismissAction(isVisible: isInputFocused) {
                isInputFocused = false
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(!hasUnsavedChanges)
            }

        }
        .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
            Button("Save Changes") { saveChanges() }
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This lead has changes that have not been saved.")
        }
    }

    private var hasUnsavedChanges: Bool {
        encodedLead(lead) != encodedLead(originalLead)
    }

    private func saveChanges() {
        isInputFocused = false
        store.updateLead(lead)
        originalLead = lead
        dismiss()
    }

    private func requestDismissal() {
        isInputFocused = false
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func encodedLead(_ lead: Lead) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(lead)
    }
}
