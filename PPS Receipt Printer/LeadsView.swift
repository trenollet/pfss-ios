//
//  LeadsView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct LeadsView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var businessName = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var leadSource: LeadSource = .website
    @State private var serviceRequested: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var estimatedValue = ""
    @State private var assignedSalesperson = ""
    @State private var status: LeadStatus = .newLead
    @State private var followUpDate = Date()

    @FocusState private var isInputFocused: Bool

    private var estimatedValueAmount: Double {
        Double(estimatedValue) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Lead") {
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

                    Picker("Service Requested", selection: $serviceRequested) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }

                    if serviceRequested == .other {
                        TextField("Other Service", text: $otherService)
                            .focused($isInputFocused)
                    }

                    TextField("Estimated Value", text: $estimatedValue)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    TextField("Assigned Salesperson", text: $assignedSalesperson)
                        .focused($isInputFocused)

                    Picker("Status", selection: $status) {
                        ForEach(LeadStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    DatePicker("Follow-Up Date", selection: $followUpDate, displayedComponents: .date)

                    Button("Add Lead") {
                        isInputFocused = false
                        addLead()
                    }
                }

                Section("Leads") {
                    ForEach(store.leads) { lead in
                        NavigationLink {
                            LeadDetailView(lead: lead)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(displayName(for: lead))
                                    .font(.headline)

                                Text("Lead #: \(lead.leadNumber)")
                                    .font(.caption)

                                Text("Service: \(serviceName(for: lead))")
                                    .font(.caption)

                                Text("Value: \(lead.estimatedValue, format: .currency(code: "USD"))")
                                    .font(.caption)

                                Text("Status: \(lead.status.rawValue)")
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Leads")
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

    private func addLead() {
        let lead = Lead(
            leadNumber: store.generateLeadNumber(),
            businessName: businessName,
            contactName: contactName,
            phone: phone,
            email: email,
            leadSource: leadSource,
            serviceRequested: serviceRequested,
            otherService: otherService,
            estimatedValue: estimatedValueAmount,
            assignedSalesperson: assignedSalesperson,
            status: status,
            followUpDate: followUpDate,
            createdDate: Date()
        )

        store.addLead(lead)

        businessName = ""
        contactName = ""
        phone = ""
        email = ""
        leadSource = .website
        serviceRequested = .windowCleaning
        otherService = ""
        estimatedValue = ""
        assignedSalesperson = ""
        status = .newLead
        followUpDate = Date()
    }

    private func displayName(for lead: Lead) -> String {
        if !lead.businessName.isEmpty {
            return lead.businessName
        }

        if !lead.contactName.isEmpty {
            return lead.contactName
        }

        return "Unnamed Lead"
    }

    private func serviceName(for lead: Lead) -> String {
        if lead.serviceRequested == .other {
            return lead.otherService.isEmpty ? "Other" : lead.otherService
        }

        return lead.serviceRequested.rawValue
    }
}
