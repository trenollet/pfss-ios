import SwiftUI

struct CustomerNewView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var businessName = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var leadSource: LeadSource = .website
    @State private var estimateStatus: EstimateStatus = .newLead
    @State private var assignedEmployee = ""
    @State private var followUpDate = Date()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Business Name", text: $businessName).focused($isInputFocused)
                    TextField("Contact Name", text: $contactName).focused($isInputFocused)
                    TextField("Phone", text: $phone).keyboardType(.phonePad).focused($isInputFocused)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($isInputFocused)
                    Picker("Lead Source", selection: $leadSource) {
                        ForEach(LeadSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Status", selection: $estimateStatus) {
                        ForEach(EstimateStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Assigned Employee", text: $assignedEmployee).focused($isInputFocused)
                    DatePicker("Follow-Up Date", selection: $followUpDate, displayedComponents: .date)
                }
            }
            .navigationTitle("New Customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCustomer() }.disabled(!hasName)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { isInputFocused = false }
                }
            }
        }
    }

    private var hasName: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveCustomer() {
        isInputFocused = false
        store.addCustomer(Customer(
            customerNumber: store.generateCustomerNumber(),
            businessName: businessName,
            contactName: contactName,
            phone: phone,
            email: email,
            leadSource: leadSource,
            estimateStatus: estimateStatus,
            assignedEmployee: assignedEmployee,
            followUpDate: followUpDate
        ))
        dismiss()
    }
}
