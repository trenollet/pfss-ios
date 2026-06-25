//
//  JobsView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct JobsView: View {
    @EnvironmentObject var store: AppDataStore

    @State private var selectedCustomerNumber = ""
    @State private var selectedSiteID: UUID?
    @State private var selectedEstimateNumber = ""

    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""

    @State private var primaryTechnician = ""
    @State private var secondaryTechnician = ""

    @State private var scheduledDate = Date()
    @State private var status: JobStatus = .toBeScheduled
    @State private var workNotes = ""
    @State private var isRecurring = false
    @State private var showArchived = false
    @State private var itemDescription = ""
    @State private var itemQuantity = "1"
    @State private var itemUnitPrice = ""
    @State private var lineItems: [ServiceLineItem] = []
    @State private var discount = ""

    @FocusState private var isInputFocused: Bool

    private var availableSites: [CustomerSite] {
        store.activeSites.filter { $0.customerNumber == selectedCustomerNumber }
    }

    private var availableEstimates: [EstimateRecord] {
        store.activeEstimates.filter { $0.customerNumber == selectedCustomerNumber }
    }
    private var itemQuantityValue: Double {
        Double(itemQuantity) ?? 1
    }

    private var itemUnitPriceValue: Double {
        Double(itemUnitPrice) ?? 0
    }

    private var itemLineTotal: Double {
        itemQuantityValue * itemUnitPriceValue
    }
    private var subtotalValue: Double {
        PricingCalculator.subtotal(for: lineItems)
    }

    private var discountValue: Double {
        Double(discount) ?? 0
    }

    private var totalValue: Double {
        PricingCalculator.total(for: lineItems, discount: discountValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Job") {
                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.activeCustomers) { customer in
                            Text(customerName(customer))
                                .tag(customer.customerNumber)
                        }
                    }

                    Picker("Site", selection: $selectedSiteID) {
                        Text("Select Site").tag(UUID?.none)
                        ForEach(availableSites) { site in
                            Text(site.siteName.isEmpty ? site.serviceAddress : site.siteName)
                                .tag(Optional(site.id))
                        }
                    }

                    Picker("Estimate", selection: $selectedEstimateNumber) {
                        Text("None / Impromptu").tag("")
                        ForEach(availableEstimates) { estimate in
                            Text("\(estimate.estimateNumber) - \(estimate.total, format: .currency(code: "USD"))")
                                .tag(estimate.estimateNumber)
                        }
                    }
                }

                Section("Service") {
                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }

                    if serviceType == .other {
                        TextField("Other Service", text: $otherService)
                            .focused($isInputFocused)
                    }

                    TextField("Work Notes", text: $workNotes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isInputFocused)
                }
                LineItemEditorView(lineItems: $lineItems, isInputFocused: $isInputFocused)
                
                Section("Pricing") {
                    TextField("Discount", text: $discount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalValue, format: .currency(code: "USD"))
                            .bold()
                    }
                }

                TextField("Quantity", text: $itemQuantity)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)

                TextField("Unit Price", text: $itemUnitPrice)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)

                HStack {
                    Text("Line Total")
                    Spacer()
                    Text(itemLineTotal, format: .currency(code: "USD"))
                        .bold()
                }

                Section("Technicians") {
                    TextField("Primary Technician", text: $primaryTechnician)
                        .focused($isInputFocused)

                    TextField("Secondary Technician", text: $secondaryTechnician)
                        .focused($isInputFocused)
                }

                Section("Schedule") {
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    DatePicker("Scheduled Date", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])

                    Toggle("Recurring Job", isOn: $isRecurring)
                }

                Section {
                    Button("Add Job") {
                        isInputFocused = false
                        addJob()
                    }
                    .disabled(selectedCustomerNumber.isEmpty)
                }

                Section("Jobs") {
                    Toggle("Show Archived", isOn: $showArchived)

                    ForEach(showArchived ? store.archivedJobs : store.activeJobs) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.jobNumber)
                                    .font(.headline)

                                Text("Customer: \(job.customerNumber)")
                                    .font(.caption)

                                Text("Service: \(serviceName(for: job))")
                                    .font(.caption)

                                Text("Primary Tech: \(job.primaryTechnician)")
                                    .font(.caption)

                                Text("Status: \(job.status.rawValue)")
                                    .font(.caption)

                                if job.lifecycleStatus == .archived {
                                    Text("Archived")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Jobs")
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

    private func addJob() {
        
        let job = JobRecord(
            jobNumber: store.generateJobNumber(),
            customerNumber: selectedCustomerNumber,
            siteID: selectedSiteID,
            estimateNumber: selectedEstimateNumber,
            serviceType: serviceType,
            otherService: otherService,
            lineItems: lineItems,
            subtotal: subtotalValue,
            discount: discountValue,
            total: totalValue,
            primaryTechnician: primaryTechnician,
            secondaryTechnician: secondaryTechnician,
            scheduledDate: scheduledDate,
            completedDate: status == .completed ? Date() : nil,
            status: status,
            workNotes: workNotes,
            isRecurring: isRecurring,
            createdDate: Date()
            
        )

        store.addJob(job)

        selectedCustomerNumber = ""
        selectedSiteID = nil
        selectedEstimateNumber = ""
        serviceType = .windowCleaning
        otherService = ""
        itemDescription = ""
        itemQuantity = "1"
        itemUnitPrice = ""
        lineItems = []
        discount = ""
        primaryTechnician = ""
        secondaryTechnician = ""
        scheduledDate = Date()
        status = .toBeScheduled
        workNotes = ""
        isRecurring = false
    }

    private func customerName(_ customer: Customer) -> String {
        let name = customer.businessName.isEmpty ? customer.contactName : customer.businessName
        return "\(name) - \(customer.customerNumber)"
    }

    private func serviceName(for job: JobRecord) -> String {
        if job.serviceType == .other {
            return job.otherService.isEmpty ? "Other" : job.otherService
        }

        return job.serviceType.rawValue
    }
}
