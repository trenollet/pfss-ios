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

    @State private var scheduledDate = QuarterHourDatePicker.normalized(Date())
    @State private var schedulingMode: AssignmentSchedulingMode = .fixedTime
    @State private var arrivalWindowEnd = QuarterHourDatePicker.normalized(
        Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    )
    @State private var completionDeadline = QuarterHourDatePicker.normalized(
        Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
    )
    @State private var assignmentPriority: AssignmentPriority = .normal
    @State private var status: JobStatus = .toBeScheduled
    @State private var workNotes = ""
    @State private var isRecurring = false
    @State private var recurrenceFrequency: JobRecurrenceFrequency?
    @State private var recurrenceEndMode: JobRecurrenceEndMode = .noEnd
    @State private var recurrenceEndDate: Date?
    @State private var recurrenceOccurrenceCount: Int?
    @State private var showingRecurrencePicker = false
    @State private var itemDescription = ""
    @State private var itemQuantity = "1"
    @State private var itemUnitPrice = ""
    @State private var lineItems: [ServiceLineItem] = []
    @State private var discount = ""

    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?

    init(
        preselectedCustomerNumber: String = "",
        preselectedSiteID: UUID? = nil,
        prefilledWorkNotes: String = ""
    ) {
        _selectedCustomerNumber = State(
            initialValue: preselectedCustomerNumber
        )
        _selectedSiteID = State(initialValue: preselectedSiteID)
        _workNotes = State(initialValue: prefilledWorkNotes)
    }

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
    private var customerOptions: [RecordSelectionOption] {
        store.activeCustomers
            .sorted { customerName($0).localizedCaseInsensitiveCompare(customerName($1)) == .orderedAscending }
            .map {
                RecordSelectionOption(
                    id: $0.customerNumber,
                    title: customerName($0),
                    subtitle: $0.customerNumber
                )
            }
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
    private var operationalJobDate: Date {
        switch schedulingMode {
        case .fixedTime, .arrivalWindow:
            return QuarterHourDatePicker.normalized(scheduledDate)
        case .flexibleDay:
            return Calendar.current.startOfDay(for: scheduledDate)
        case .deadline:
            return QuarterHourDatePicker.normalized(completionDeadline)
        }
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
            scheduledDate: operationalJobDate,
            assignmentSchedulingMode: schedulingMode,
            arrivalWindowEnd: schedulingMode == .arrivalWindow
                ? QuarterHourDatePicker.normalized(arrivalWindowEnd)
                : nil,
            completionDeadline: schedulingMode == .deadline
                ? QuarterHourDatePicker.normalized(completionDeadline)
                : nil,
            assignmentPriority: assignmentPriority,
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
                    SearchableRecordSelectionField(
                        title: "Customer",
                        placeholder: "Select Customer",
                        options: customerOptions,
                        selection: $selectedCustomerNumber
                    )

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
                    LabeledContent("Discount") {
                        SelectAllTextField(
                            placeholder: "0.00",
                            text: $discount
                        )
                        .frame(minWidth: 90, minHeight: 30)
                        .focused($isInputFocused)
                    }

                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalValue, format: .currency(code: "USD"))
                            .bold()
                    }
                }

                LabeledContent("Quantity") {
                    SelectAllTextField(
                        placeholder: "1",
                        text: $itemQuantity
                    )
                    .frame(minWidth: 90, minHeight: 30)
                    .focused($isInputFocused)
                }

                LabeledContent("Unit Price") {
                    SelectAllTextField(
                        placeholder: "0.00",
                        text: $itemUnitPrice
                    )
                    .frame(minWidth: 90, minHeight: 30)
                    .focused($isInputFocused)
                }

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

                    Picker("Scheduling Mode", selection: $schedulingMode) {
                        ForEach(AssignmentSchedulingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    schedulingControls

                    Picker("Priority", selection: $assignmentPriority) {
                        ForEach(AssignmentPriority.allCases) { priority in
                            Text(priority.rawValue).tag(priority)
                        }
                    }

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
            .onChange(of: scheduledDate) { _, newDate in
                guard schedulingMode == .arrivalWindow,
                      arrivalWindowEnd <= newDate else { return }
                arrivalWindowEnd = Calendar.current.date(
                    byAdding: .hour,
                    value: 2,
                    to: newDate
                ) ?? newDate
            }
            .sheet(isPresented: $showingRecurrencePicker) {
                JobRecurrencePickerView(
                    selection: $recurrenceFrequency,
                    endMode: $recurrenceEndMode,
                    endDate: $recurrenceEndDate,
                    occurrenceCount: $recurrenceOccurrenceCount
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                EditorKeyboardDismissAction(isVisible: isInputFocused) {
                    isInputFocused = false
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isInputFocused = false
                        addJob()
                    }
                    .disabled(
                        selectedCustomerNumber.isEmpty ||
                        !hasValidScheduling ||
                        (isRecurring && recurrenceFrequency == nil)
                    )
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
            scheduledDate: operationalJobDate,
            assignmentSchedulingMode: schedulingMode,
            arrivalWindowEnd: schedulingMode == .arrivalWindow
                ? QuarterHourDatePicker.normalized(arrivalWindowEnd)
                : nil,
            completionDeadline: schedulingMode == .deadline
                ? QuarterHourDatePicker.normalized(completionDeadline)
                : nil,
            assignmentPriority: assignmentPriority,
            completedDate: status == .completed ? Date() : nil,
            status: status,
            workNotes: workNotes,
            isRecurring: isRecurring,
            recurrenceFrequency: recurrenceFrequency,
            recurrenceEndMode: recurrenceEndMode,
            recurrenceEndDate: recurrenceEndDate,
            recurrenceOccurrenceCount: recurrenceOccurrenceCount,
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
        recurrenceEndMode = .noEnd
        recurrenceEndDate = nil
        recurrenceOccurrenceCount = nil
        primaryTechnicianID = nil
        secondaryTechnicianID = nil
        scheduledDate = Date()
        schedulingMode = .fixedTime
        assignmentPriority = .normal
        status = .toBeScheduled
        workNotes = ""
        isRecurring = false
        recurrenceFrequency = nil
    }

    @ViewBuilder
    private var schedulingControls: some View {
        switch schedulingMode {
        case .fixedTime:
            QuarterHourDatePicker(
                selection: $scheduledDate,
                dateLabel: "Service Date",
                timeLabel: "Fixed Start"
            )

        case .arrivalWindow:
            QuarterHourDatePicker(
                selection: $scheduledDate,
                dateLabel: "Service Date",
                timeLabel: "Earliest Arrival"
            )
            QuarterHourDatePicker(
                selection: $arrivalWindowEnd,
                dateLabel: "Window End Date",
                timeLabel: "Latest Arrival"
            )

        case .flexibleDay:
            DatePicker(
                "Service Date",
                selection: $scheduledDate,
                displayedComponents: .date
            )

        case .deadline:
            QuarterHourDatePicker(
                selection: $completionDeadline,
                dateLabel: "Deadline Date",
                timeLabel: "Complete By"
            )
        }
    }

    private var hasValidScheduling: Bool {
        switch schedulingMode {
        case .fixedTime, .flexibleDay:
            return true
        case .arrivalWindow:
            return arrivalWindowEnd > scheduledDate
        case .deadline:
            return true
        }
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

                Text(employee.roleDisplayText)
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
        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return "Unnamed Customer"
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
