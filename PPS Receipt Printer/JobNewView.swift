//
//  JobsView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct JobNewView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCustomerNumber = ""
    @State private var selectedSiteID: UUID?
    @State private var selectedEstimateNumber = ""

    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""

    @State private var primaryTechnicianID: UUID?
    @State private var secondaryTechnicianID: UUID?

    @State private var scheduledDate = Date()
    @State private var status: JobStatus = .toBeScheduled
    @State private var workNotes = ""
    @State private var isRecurring = false
    @State private var recurrenceFrequency: JobRecurrenceFrequency?
    @State private var showingRecurrencePicker = false
    @State private var itemDescription = ""
    @State private var itemQuantity = "1"
    @State private var itemUnitPrice = ""
    @State private var lineItems: [ServiceLineItem] = []
    @State private var discount = ""

    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case catalogPicker
        case editLineItem(ServiceLineItem)

        var id: String {
            switch self {
            case .catalogPicker:
                return "catalogPicker"

            case .editLineItem(let item):
                return "editLineItem-\(item.id)"
            }
        }
    }

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
    private var assignableEmployees: [EmployeeRecord] {
        store.activeEmployees.sorted {
            $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            ) == .orderedAscending
        }
    }

    private var availableSecondaryEmployees: [EmployeeRecord] {
        assignableEmployees.filter {
            $0.id != primaryTechnicianID
        }
    }
    private var primaryEmployee: EmployeeRecord? {
        guard let employeeID = primaryTechnicianID else {
            return nil
        }

        return store.employees.first {
            $0.id == employeeID
        }
    }

    private var secondaryEmployee: EmployeeRecord? {
        guard let employeeID = secondaryTechnicianID else {
            return nil
        }

        return store.employees.first {
            $0.id == employeeID
        }
    }
    private var capacityPreviewJob: JobRecord {
        JobRecord(
            jobNumber: "PREVIEW",
            customerNumber: selectedCustomerNumber,
            siteID: selectedSiteID,
            estimateNumber: selectedEstimateNumber,
            serviceType: serviceType,
            otherService: otherService,
            lineItems: lineItems,
            subtotal: subtotalValue,
            discount: discountValue,
            total: totalValue,
            primaryTechnicianID: primaryTechnicianID,
            secondaryTechnicianID: secondaryTechnicianID,
            scheduledDate: scheduledDate,
            completedDate: nil,
            status: status,
            workNotes: workNotes,
            isRecurring: isRecurring,
            createdDate: Date()
        )
    }

    var body: some View {
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
                WorkOrderEditorView(
                    lineItems: $lineItems,
                    isInputFocused: $isInputFocused,
                    onAddLineItem: {
                        PresentationDebug.log("New job requested catalog picker")
                        activeSheet = .catalogPicker
                    },
                    onEditLineItem: { item in
                        PresentationDebug.log(
                            "New job requested editor for \(item.id)"
                        )
                        activeSheet = .editLineItem(item)
                    }
                )
                
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
                    Picker(
                        "Primary Technician",
                        selection: $primaryTechnicianID
                    ) {
                        Text("Unassigned")
                            .tag(UUID?.none)

                        ForEach(assignableEmployees) { employee in
                            Text(employee.displayName)
                                .tag(UUID?.some(employee.id))
                        }
                    }
                    .onChange(of: primaryTechnicianID) { _, newPrimaryID in
                        if secondaryTechnicianID == newPrimaryID {
                            secondaryTechnicianID = nil
                        }
                    }

                    Picker(
                        "Secondary Technician",
                        selection: $secondaryTechnicianID
                    ) {
                        Text("None")
                            .tag(UUID?.none)

                        ForEach(availableSecondaryEmployees) { employee in
                            Text(employee.displayName)
                                .tag(UUID?.some(employee.id))
                        }
                    }
                    .disabled(primaryTechnicianID == nil)
                }
                Section("Capacity Preview") {
                    if primaryEmployee == nil &&
                        secondaryEmployee == nil {

                        Text("Assign a technician to view capacity.")
                            .foregroundStyle(.secondary)

                    } else {
                        if let employee = primaryEmployee {
                            employeeCapacitySummary(
                                employee,
                                assignmentLabel: "Primary Technician"
                            )
                        }

                        if let employee = secondaryEmployee {
                            employeeCapacitySummary(
                                employee,
                                assignmentLabel: "Secondary Technician"
                            )
                        }
                    }
                }

                Section("Schedule") {
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    QuarterHourDatePicker(selection: $scheduledDate)

                    Toggle("Recurring Job", isOn: $isRecurring)

                    if isRecurring {
                        Button {
                            showingRecurrencePicker = true
                        } label: {
                            LabeledContent(
                                "Frequency",
                                value: recurrenceFrequency?.rawValue ?? "Select"
                            )
                        }
                    }
                }

            }
            .navigationTitle("New Job")
            .onChange(of: isRecurring) {
                if isRecurring {
                    showingRecurrencePicker = true
                } else {
                    recurrenceFrequency = nil
                }
            }
            .sheet(isPresented: $showingRecurrencePicker) {
                JobRecurrencePickerView(selection: $recurrenceFrequency)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isInputFocused = false
                        addJob()
                    }
                    .disabled(
                        selectedCustomerNumber.isEmpty ||
                        (isRecurring && recurrenceFrequency == nil)
                    )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .catalogPicker:
                    ServiceCatalogPickerView(
                        lineItems: $lineItems,
                        onFinished: {
                            activeSheet = nil
                        }
                    )
                    .environmentObject(store)

                case .editLineItem(let item):
                    EditableLineItemView(
                        lineItems: $lineItems,
                        catalogItem: nil,
                        existingLineItem: item
                    )
                    .environmentObject(store)
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
            primaryTechnicianID: primaryTechnicianID,
            secondaryTechnicianID: secondaryTechnicianID,
            scheduledDate: scheduledDate,
            completedDate: status == .completed ? Date() : nil,
            status: status,
            workNotes: workNotes,
            isRecurring: isRecurring,
            recurrenceFrequency: recurrenceFrequency,
            createdDate: Date()
            
        )

        store.addJob(job)
        dismiss()

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
        primaryTechnicianID = nil
        secondaryTechnicianID = nil
        scheduledDate = Date()
        status = .toBeScheduled
        workNotes = ""
        isRecurring = false
        recurrenceFrequency = nil
    }
    @ViewBuilder
    private func employeeCapacitySummary(
        _ employee: EmployeeRecord,
        assignmentLabel: String
    ) -> some View {
        let capacityMinutes =
            SchedulingCalculator.capacityMinutes(
                for: employee,
                on: scheduledDate
            )

        let previouslyScheduledMinutes =
            SchedulingCalculator.scheduledMinutes(
                for: employee,
                on: scheduledDate,
                from: store.jobs
            )

        let thisJobMinutes =
            SchedulingCalculator.scheduledMinutes(
                for: capacityPreviewJob
            )

        let projectedRemainingMinutes =
            capacityMinutes
            - previouslyScheduledMinutes
            - thisJobMinutes

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(employee.displayName)
                        .font(.headline)

                    Text(assignmentLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(employee.role.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !SchedulingCalculator.isWorkingDay(
                scheduledDate,
                for: employee
            ) {
                Label(
                    "Not normally scheduled to work this day",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            capacityRow(
                label: "Daily Capacity",
                minutes: capacityMinutes
            )

            capacityRow(
                label: "Already Scheduled",
                minutes: previouslyScheduledMinutes
            )

            capacityRow(
                label: "This Job",
                minutes: thisJobMinutes
            )

            HStack {
                Text(
                    projectedRemainingMinutes >= 0
                        ? "Remaining After Job"
                        : "Over Capacity By"
                )

                Spacer()

                Text(
                    capacityDurationText(
                        abs(projectedRemainingMinutes)
                    )
                )
                .fontWeight(.semibold)
                .foregroundStyle(
                    projectedRemainingMinutes < 0
                        ? .red
                        : .green
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func capacityRow(
        label: String,
        minutes: Int
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(
                capacityDurationText(minutes)
            )
            .fontWeight(.medium)
        }
    }

    private func capacityDurationText(
        _ minutes: Int
    ) -> String {
        guard minutes > 0 else {
            return "0 min"
        }

        return SchedulingCalculator.formattedDuration(
            minutes: minutes
        )
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
    private func customerDisplayName(for customerNumber: String) -> String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == customerNumber
        }) else {
            return customerNumber
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return customerNumber
    }
    private func employeeName(
        for employeeID: UUID?
    ) -> String {
        guard
            let employeeID,
            let employee = store.employees.first(where: {
                $0.id == employeeID
            })
        else {
            return "Unassigned"
        }

        return employee.displayName
    }
}
