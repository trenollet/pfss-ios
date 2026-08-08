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
    @State private var showingUnsavedChangesAlert = false
    @FocusState private var isInputFocused: Bool

    private var assignableEmployees: [EmployeeRecord] {
        store.activeEmployees.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                == .orderedAscending
        }
    }

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
                            HStack {
                                Text("Assigned Employee")
                                Spacer()
                                Picker("Assigned Employee", selection: $assignedEmployee) {
                                    Text("Unassigned").tag("")
                                    ForEach(assignableEmployees) { employee in
                                        Text(employee.displayName)
                                            .tag(employee.displayName)
                                    }
                                }
                                .labelsHidden()
                            }
                            DatePicker(
                                "Follow-Up Date",
                                selection: $followUpDate,
                                displayedComponents: .date
                            )
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .navigationTitle("New Customer")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { requestDismissal() }
                        }
                        EditorKeyboardDismissAction(isVisible: isInputFocused) {
                            isInputFocused = false
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveCustomer() }
                                .disabled(!hasName)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .alert(
                "Unsaved Customer",
                isPresented: $showingUnsavedChangesAlert
            ) {
                Button("Save") {
                    saveCustomer()
                }
                .disabled(!hasName)

                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }

                Button("Continue Editing", role: .cancel) { }
            } message: {
                Text("Save this customer before leaving, or discard the information entered on this page.")
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard createdCustomer == nil else { return false }
        return !businessName.isEmpty ||
            !contactName.isEmpty ||
            !phone.isEmpty ||
            !email.isEmpty ||
            leadSource != .website ||
            estimateStatus != .newLead ||
            !assignedEmployee.isEmpty ||
            !Calendar.current.isDateInToday(followUpDate)
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

    private func requestDismissal() {
        isInputFocused = false
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }
}
