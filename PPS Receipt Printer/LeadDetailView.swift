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
    @FocusState private var isInputFocused: Bool

    private var estimatedValueBinding: Binding<Double> {
        Binding(
            get: { lead.estimatedValue },
            set: { lead.estimatedValue = $0 }
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

                TextField("Phone", text: $lead.phone)
                    .keyboardType(.phonePad)
                    .focused($isInputFocused)

                TextField("Email", text: $lead.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
            }

            Section("Sales") {
                Picker("Lead Source", selection: $lead.leadSource) {
                    ForEach(LeadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                Picker("Service Requested", selection: $lead.serviceRequested) {
                    ForEach(ServiceType.allCases) { service in
                        Text(service.rawValue).tag(service)
                    }
                }

                if lead.serviceRequested == .other {
                    TextField("Other Service", text: $lead.otherService)
                        .focused($isInputFocused)
                }

                TextField("Estimated Value", value: estimatedValueBinding, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)

                TextField("Assigned Salesperson", text: $lead.assignedSalesperson)
                    .focused($isInputFocused)

                Picker("Status", selection: $lead.status) {
                    ForEach(LeadStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                DatePicker("Follow-Up Date", selection: $lead.followUpDate, displayedComponents: .date)
            }

            Section {
                Button("Convert to Customer") {
                    store.convertLeadToCustomer(lead)
                    dismiss()
                }
                .disabled(lead.status == .converted || lead.lifecycleStatus == .archived)

                if lead.lifecycleStatus == .archived {
                    Button("Restore Lead") {
                        store.restoreLead(lead)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Lead", role: .destructive) {
                        store.archiveLead(lead)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Lead")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isInputFocused = false
                    store.updateLead(lead)
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
}
