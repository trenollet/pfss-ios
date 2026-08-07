import SwiftUI

struct LeadNewView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var businessName = ""
    @State private var contactName = ""
    @State private var location = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var leadSource: LeadSource = .doorKnock
    @State private var serviceRequested: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var quoteOptions = [
        LeadQuoteOption(quotedPrice: 0, frequency: .monthly)
    ]
    @State private var assignedSalesperson = ""
    @State private var status: LeadStatus = .newLead
    @State private var followUpDate = Date()
    @FocusState private var isInputFocused: Bool

    private var salesEmployees: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.hasRole(.salesperson) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lead") {
                    TextField("Business Name", text: $businessName).focused($isInputFocused)
                    TextField("Contact Name", text: $contactName).focused($isInputFocused)
                    TextField("Location", text: $location).focused($isInputFocused)
                    TextField("Phone", text: $phone).keyboardType(.phonePad).focused($isInputFocused)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($isInputFocused)
                }

                Section("Sales Info") {
                    Picker("Assigned Salesperson", selection: $assignedSalesperson) {
                        Text("Unassigned").tag("")
                        ForEach(salesEmployees) { employee in
                            Text(employee.displayName).tag(employee.displayName)
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(LeadStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Follow-Up Date", selection: $followUpDate, displayedComponents: .date)
                    Picker("Lead Source", selection: $leadSource) {
                        ForEach(LeadSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Service Requested", selection: $serviceRequested) {
                        ForEach(ServiceType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if serviceRequested == .other {
                        TextField("Other Service", text: $otherService).focused($isInputFocused)
                    }
                    LeadQuoteOptionsEditor(
                        quoteOptions: $quoteOptions,
                        isInputFocused: $isInputFocused
                    )
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 110)
                        .focused($isInputFocused)
                }
            }
            .navigationTitle("New Lead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLead() }.disabled(!hasName)
                }
                if isInputFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                    }
                }
            }
        }
    }

    private var hasName: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveLead() {
        isInputFocused = false
        store.addLead(Lead(
            leadNumber: store.generateLeadNumber(),
            businessName: businessName,
            contactName: contactName,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone,
            email: email,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            leadSource: leadSource,
            serviceRequested: serviceRequested,
            otherService: otherService,
            estimatedValue: quoteOptions.first?.quotedPrice ?? 0,
            quoteOptions: quoteOptions,
            assignedSalesperson: assignedSalesperson,
            status: status,
            followUpDate: followUpDate,
            createdDate: Date()
        ))
        dismiss()
    }
}
