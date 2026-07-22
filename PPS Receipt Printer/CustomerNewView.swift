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
    @State private var createdCustomer: Customer?
    @State private var isCreatingInitialSite = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let createdCustomer {
                    if isCreatingInitialSite {
                        SiteNewView(
                            preselectedCustomerNumber: createdCustomer.customerNumber,
                            onSaved: { _ in
                                isCreatingInitialSite = false
                            },
                            onCancel: {
                                isCreatingInitialSite = false
                            }
                        )
                    } else {
                        CustomerDetailView(customer: currentCreatedCustomer)
                    }
                } else {
                    Form {
                        Section("Customer") {
                            TextField("Business Name", text: $businessName)
                                .focused($isInputFocused)
                            TextField("Contact Name", text: $contactName)
                                .focused($isInputFocused)
                            TextField("Phone", text: $phone)
                                .keyboardType(.phonePad)
                                .focused($isInputFocused)
                            TextField("Email", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .focused($isInputFocused)
                            Picker("Lead Source", selection: $leadSource) {
                                ForEach(LeadSource.allCases) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            Picker("Status", selection: $estimateStatus) {
                                ForEach(EstimateStatus.allCases) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            TextField("Assigned Employee", text: $assignedEmployee)
                                .focused($isInputFocused)
                            DatePicker(
                                "Follow-Up Date",
                                selection: $followUpDate,
                                displayedComponents: .date
                            )
                        }
                    }
                    .navigationTitle("New Customer")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveCustomer() }
                                .disabled(!hasName)
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
        }
    }

    private var currentCreatedCustomer: Customer {
        guard let createdCustomer else {
            preconditionFailure("A created customer is required for Customer Detail.")
        }

        return store.customers.first(where: { $0.id == createdCustomer.id }) ??
            createdCustomer
    }

    private var hasName: Bool {
        !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveCustomer() {
        isInputFocused = false
        let customer = Customer(
            customerNumber: store.generateCustomerNumber(),
            businessName: businessName,
            contactName: contactName,
            phone: phone,
            email: email,
            leadSource: leadSource,
            estimateStatus: estimateStatus,
            assignedEmployee: assignedEmployee,
            followUpDate: followUpDate
        )

        store.addCustomer(customer)
        createdCustomer = customer
        isCreatingInitialSite = true
    }
}
