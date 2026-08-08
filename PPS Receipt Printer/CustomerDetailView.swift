//
//  CustomerDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct CustomerDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var customer: Customer
    private let originalCustomer: Customer
    @State private var showingNewSite = false
    @State private var showingUnsavedChangesAlert = false
    @FocusState private var isInputFocused: Bool

    init(customer: Customer) {
        originalCustomer = customer
        _customer = State(initialValue: customer)
    }

    private var associatedSites: [CustomerSite] {
        store.sites(for: customer.customerNumber).sorted {
            if $0.lifecycleStatus != $1.lifecycleStatus {
                return $0.lifecycleStatus == .active
            }

            let firstName = $0.siteName.isEmpty ? $0.serviceAddress : $0.siteName
            let secondName = $1.siteName.isEmpty ? $1.serviceAddress : $1.siteName
            return firstName.localizedCaseInsensitiveCompare(secondName) == .orderedAscending
        }
    }

    private var assignableEmployees: [EmployeeRecord] {
        store.activeEmployees.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section("Customer") {
                Text(customer.customerNumber)
                    .font(.headline)

                TextField("Business Name", text: $customer.businessName)
                    .focused($isInputFocused)

                TextField("Contact Name", text: $customer.contactName)
                    .focused($isInputFocused)

                TextField("Phone", text: $customer.phone)
                    .keyboardType(.phonePad)
                    .focused($isInputFocused)

                TextField("Email", text: $customer.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
            }

            Section {
                if associatedSites.isEmpty {
                    Text("No sites have been added for this customer.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(associatedSites) { site in
                        NavigationLink {
                            SiteDetailView(site: site)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(siteDisplayName(site))
                                    .font(.headline)
                                if !site.serviceAddress.isEmpty {
                                    Text(site.serviceAddress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !site.propertyType.isEmpty {
                                    Text(site.propertyType)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if site.lifecycleStatus == .archived {
                                    Text("Archived")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Sites")
                    Spacer()
                    Button {
                        showingNewSite = true
                    } label: {
                        Label("Add Site", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Site")
                    .disabled(customer.lifecycleStatus == .archived)
                }
            }

            Section("Sales") {
                Picker("Lead Source", selection: $customer.leadSource) {
                    ForEach(LeadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                Picker("Status", selection: $customer.estimateStatus) {
                    ForEach(EstimateStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                HStack {
                    Text("Assigned Employee")
                    Spacer()
                    Picker("Assigned Employee", selection: $customer.assignedEmployee) {
                        Text("Unassigned").tag("")
                        ForEach(assignableEmployees) { employee in
                            Text(employee.displayName).tag(employee.displayName)
                        }
                    }
                    .labelsHidden()
                }

                DatePicker(
                    "Follow-Up Date",
                    selection: $customer.followUpDate,
                    displayedComponents: .date
                )
            }

            Section("Customer Activity") {
                NavigationLink {
                    JobRecordsListView(
                        title: "Customer Jobs",
                        customerNumber: customer.customerNumber
                    )
                } label: {
                    Label("Jobs", systemImage: "wrench.and.screwdriver")
                }

                NavigationLink {
                    InvoiceRecordsListView(
                        title: "Customer Invoices",
                        customerNumber: customer.customerNumber
                    )
                } label: {
                    Label("Invoices", systemImage: "doc.text")
                }
            }

            Section {
                if customer.lifecycleStatus == .archived {
                    Button {
                        store.restoreCustomer(customer)
                        dismiss()
                    } label: {
                        Label("Restore Customer", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveCustomer(customer)
                        dismiss()
                    } label: {
                        CenteredArchiveActionLabel(title: "Archive Customer")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }

            Section {
                Text(
                    "To create a new Estimate or Job for this customer, select the Customer Site first."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Customer")
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingNewSite) {
            NavigationStack {
                SiteNewView(
                    preselectedCustomerNumber: customer.customerNumber,
                    onSaved: { _ in showingNewSite = false },
                    onCancel: { showingNewSite = false }
                )
            }
            .environmentObject(store)
        }
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
        .alert(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert
        ) {
            Button("Save Changes") {
                saveChanges()
            }

            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This customer has changes that have not been saved.")
        }
    }

    private var hasUnsavedChanges: Bool {
        encodedCustomer(customer) != encodedCustomer(originalCustomer)
    }

    private func saveChanges() {
        isInputFocused = false
        store.updateCustomer(customer)
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

    private func encodedCustomer(_ customer: Customer) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(customer)
    }

    private func siteDisplayName(_ site: CustomerSite) -> String {
        if !site.siteName.isEmpty {
            return site.siteName
        }

        if !site.serviceAddress.isEmpty {
            return site.serviceAddress
        }

        return "Unnamed Site"
    }
}
