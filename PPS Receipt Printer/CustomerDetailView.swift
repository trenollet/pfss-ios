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
    @State private var showingNewSite = false
    @FocusState private var isInputFocused: Bool

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

                TextField("Assigned Employee", text: $customer.assignedEmployee)
                    .focused($isInputFocused)

                DatePicker(
                    "Follow-Up Date",
                    selection: $customer.followUpDate,
                    displayedComponents: .date
                )
            }

            Section {
                if customer.lifecycleStatus == .archived {
                    Button("Restore Customer") {
                        store.restoreCustomer(customer)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Customer", role: .destructive) {
                        store.archiveCustomer(customer)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Customer")
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isInputFocused = false
                    store.updateCustomer(customer)
                    dismiss()
                }
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
