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

                TextField("Phone", text: $lead.phone)
                    .keyboardType(.phonePad)
                    .focused($isInputFocused)

                TextField("Email", text: $lead.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
            }

            Section("Sales Info") {
                TextField("Assigned Salesperson", text: $lead.assignedSalesperson)
                    .focused($isInputFocused)

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

                Picker("Service Requested", selection: $lead.serviceRequested) {
                    ForEach(ServiceType.allCases) { service in
                        Text(service.rawValue).tag(service)
                    }
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
                Button("Convert to Customer") {
                    store.convertLeadToCustomer(lead)
                    dismiss()
                }
                .disabled(lead.status == .converted || lead.lifecycleStatus == .archived)

                if lead.lifecycleStatus == .archived {
                    Button {
                        store.restoreLead(lead)
                        dismiss()
                    } label: {
                        Label("Restore Lead", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveLead(lead)
                        dismiss()
                    } label: {
                        Label("Archive Lead", systemImage: "archivebox.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Edit Lead")
        .onAppear {
            if lead.quoteOptions?.isEmpty != false {
                lead.quoteOptions = [
                    LeadQuoteOption(
                        quotedPrice: lead.estimatedValue,
                        frequency: .oneTime
                    )
                ]
            }
        }
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
