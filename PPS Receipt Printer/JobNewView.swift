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
    @State private var selectedLeadNumber = ""
    @State private var selectedSiteID: UUID?
    @State private var selectedEstimateNumber = ""
    @State private var salesperson = ""
    @State private var expirationDate = Calendar.current.date(
        byAdding: .day,
        value: 30,
        to: Date()
    ) ?? Date()
    @State private var jobTitle = ""
    @State private var scopeOfWork = ""

    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""

    @State private var primaryTechnicianID: UUID?
    @State private var secondaryTechnicianID: UUID?

    @State private var scheduledDate = QuarterHourDatePicker.normalized(Date())
    @State private var isMultipleDayWork = false
    @State private var additionalWorkdaySchedules: [JobScheduledWorkday] = []
    @State private var nextAdditionalSchedule = JobScheduledWorkday(
        scheduledDate: QuarterHourDatePicker.normalized(
            Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
    )
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
    @State private var discountMethod: PricingDiscountMethod = .fixedAmount
    @State private var discountInputValue: Double = 0

    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?
    @State private var compactEditorDestination: CompactWorkOrderEditorDestination?

    init(
        preselectedCustomerNumber: String = "",
        preselectedSiteID: UUID? = nil,
        prefilledWorkNotes: String = "",
        initialLineItems: [ServiceLineItem] = []
    ) {
        _selectedCustomerNumber = State(
            initialValue: preselectedCustomerNumber
        )
        _selectedSiteID = State(initialValue: preselectedSiteID)
        _workNotes = State(initialValue: prefilledWorkNotes)
        _scopeOfWork = State(initialValue: prefilledWorkNotes)
        _lineItems = State(initialValue: initialLineItems)
        if let firstItem = initialLineItems.first {
            _serviceType = State(initialValue: firstItem.serviceType)
            _otherService = State(initialValue: firstItem.otherService)
        }
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
        DiscountCalculator.amount(
            subtotal: subtotalValue,
            method: discountMethod,
            inputValue: discountInputValue
        )
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
                CompactCustomerInfoSection(
                    leadNumber: $selectedLeadNumber,
                    customerNumber: $selectedCustomerNumber,
                    siteID: $selectedSiteID,
                    salesperson: $salesperson,
                    expirationDate: $expirationDate,
                    onSelect: { compactEditorDestination = .customerInfo }
                )

                CompactTitleSection(
                    title: $jobTitle,
                    onSelect: { compactEditorDestination = .title }
                )

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(JobStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
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
                
                CompactPricingSection(
                    method: $discountMethod,
                    inputValue: $discountInputValue,
                    subtotal: subtotalValue,
                    onSelect: { compactEditorDestination = .pricing }
                )

                CompactScopeSection(
                    scope: $scopeOfWork,
                    onSelect: { compactEditorDestination = .scope }
                )

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

                    Toggle("Multiple Day Work", isOn: $isMultipleDayWork)

                    if isMultipleDayWork {
                        JobWorkdayScheduleFields(schedule: $nextAdditionalSchedule)
                        Button {
                            addAdditionalScheduledDate()
                        } label: {
                            Label("Add Scheduled Day", systemImage: "calendar.badge.plus")
                        }
                        .disabled(!canAddAdditionalScheduledDate)

                        ForEach(additionalWorkdaySchedules) { workday in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(workday.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                                    Text(workday.schedulingMode.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(workday.scheduledDate.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    additionalWorkdaySchedules.removeAll { $0.id == workday.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
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
                    isMultipleDayWork = false
                    additionalWorkdaySchedules = []
                    showingRecurrencePicker = true
                } else {
                    recurrenceFrequency = nil
                }
            }
            .onChange(of: isMultipleDayWork) { _, enabled in
                if enabled {
                    isRecurring = false
                    recurrenceFrequency = nil
                    prepareNextAdditionalDate()
                } else {
                    additionalWorkdaySchedules = []
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
                        (selectedCustomerNumber.isEmpty && selectedLeadNumber.isEmpty) ||
                        !hasValidScheduling ||
                        (isRecurring && recurrenceFrequency == nil)
                    )
                }
            }
            .compactWorkOrderEditorSheet(
                destination: $compactEditorDestination,
                leadNumber: $selectedLeadNumber,
                customerNumber: $selectedCustomerNumber,
                siteID: $selectedSiteID,
                salesperson: $salesperson,
                expirationDate: $expirationDate,
                title: $jobTitle,
                discountMethod: $discountMethod,
                discountInputValue: $discountInputValue,
                subtotal: subtotalValue,
                scope: $scopeOfWork,
                store: store
            )
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
        let firstItem = lineItems.first

        let job = JobRecord(
            jobNumber: store.generateJobNumber(),
            title: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            leadNumber: selectedLeadNumber,
            customerNumber: selectedCustomerNumber,
            siteID: selectedSiteID,
            estimateNumber: selectedEstimateNumber,
            serviceType: firstItem?.serviceType ?? serviceType,
            otherService: firstItem?.otherService ?? otherService,
            lineItems: lineItems,
            subtotal: subtotalValue,
            discount: discountValue,
            discountMethod: discountMethod,
            discountInputValue: discountInputValue,
            total: totalValue,
            salesperson: salesperson,
            expirationDate: expirationDate,
            primaryTechnicianID: primaryTechnicianID,
            secondaryTechnicianID: secondaryTechnicianID,
            scheduledDate: operationalJobDate,
            additionalScheduledDates: additionalWorkdaySchedules.map(\.scheduledDate),
            additionalWorkdaySchedules: additionalWorkdaySchedules,
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
            scopeOfWork: scopeOfWork.trimmingCharacters(in: .whitespacesAndNewlines),
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
        selectedLeadNumber = ""
        selectedSiteID = nil
        selectedEstimateNumber = ""
        serviceType = .windowCleaning
        otherService = ""
        itemDescription = ""
        itemQuantity = "1"
        itemUnitPrice = ""
        lineItems = []
        discountMethod = .fixedAmount
        discountInputValue = 0
        salesperson = ""
        expirationDate = Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: Date()
        ) ?? Date()
        jobTitle = ""
        scopeOfWork = ""
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
        isMultipleDayWork = false
        additionalWorkdaySchedules = []
    }

    private var canAddAdditionalScheduledDate: Bool {
        let calendar = Calendar.current
        return !calendar.isDate(nextAdditionalSchedule.scheduledDate, inSameDayAs: operationalJobDate)
            && !additionalWorkdaySchedules.contains(where: {
                calendar.isDate($0.scheduledDate, inSameDayAs: nextAdditionalSchedule.scheduledDate)
            })
    }

    private func addAdditionalScheduledDate() {
        guard canAddAdditionalScheduledDate else { return }
        var schedule = nextAdditionalSchedule
        schedule.normalize()
        additionalWorkdaySchedules.append(schedule)
        additionalWorkdaySchedules.sort { $0.scheduledDate < $1.scheduledDate }
        prepareNextAdditionalDate()
    }

    private func prepareNextAdditionalDate() {
        let base = additionalWorkdaySchedules.last?.scheduledDate ?? operationalJobDate
        nextAdditionalSchedule = JobScheduledWorkday(
            scheduledDate: QuarterHourDatePicker.normalized(
                Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
            ),
            schedulingMode: nextAdditionalSchedule.schedulingMode
        )
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
