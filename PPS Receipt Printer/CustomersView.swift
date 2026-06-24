//
//  CustomersView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct CustomersView: View {
    @EnvironmentObject var store: AppDataStore

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
                Section("New Customer") {
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
                        ForEach(LeadSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }

                    Picker("Status", selection: $estimateStatus) {
                        ForEach(EstimateStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    TextField("Assigned Employee", text: $assignedEmployee)
                        .focused($isInputFocused)

                    DatePicker("Follow-Up Date", selection: $followUpDate, displayedComponents: .date)

                    Button("Add Customer") {
                        isInputFocused = false
                        addCustomer()
                    }
                }

                Section("Customers") {
                    ForEach(store.customers) { customer in
                        NavigationLink {
                            CustomerDetailView(customer: customer)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(customer.businessName.isEmpty ? customer.contactName : customer.businessName)
                                    .font(.headline)

                                Text("Contact: \(customer.contactName)")
                                    .font(.caption)

                                Text("Customer #: \(customer.customerNumber)")
                                    .font(.caption)

                                Text("Status: \(customer.estimateStatus.rawValue)")
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
        }
    }

    private func addCustomer() {
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

        businessName = ""
        contactName = ""
        phone = ""
        email = ""
        leadSource = .website
        estimateStatus = .newLead
        assignedEmployee = ""
        followUpDate = Date()
    }
}
