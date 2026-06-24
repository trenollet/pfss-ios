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
    @FocusState private var isInputFocused: Bool
    
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
                
                DatePicker("Follow-Up Date", selection: $customer.followUpDate, displayedComponents: .date)
            }
            
            Section {
                Button("Save Changes") {
                    isInputFocused = false
                    store.updateCustomer(customer)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
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
            .navigationTitle("Edit Customer")
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
}
