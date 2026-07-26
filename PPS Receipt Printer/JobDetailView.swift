//
//  JobDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct JobDetailView: View {
    private let showWorkflow = false
    private let showTimeline = false
    private let showCapacity = false
    // Field technicians may add requested work to the existing Job while on
    // site. The same work-order editor is reused so pricing and labor duration
    // remain consistent with office-created line items.
    private let showWorkOrder = true

    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("selectedTechnicianID")
    private var selectedTechnicianIDString = ""
    
    @State var job: JobRecord
    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?
    @State private var scheduledDurationHours = 0
    @State private var scheduledDurationMinutes = 0
    @State private var technicianNoteDraft = ""
    @State private var presentedInvoice: InvoiceRecord?
    @State private var showingRecurrencePicker = false
    
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
    
    private var subtotalValue: Double {
        PricingCalculator.subtotal(for: job)
    }
    
    private var totalValue: Double {
        PricingCalculator.total(for: job)
    }
    
    private var calculatedLaborMinutes: Int {
        SchedulingCalculator.estimatedMinutes(
            for: job.lineItems
        )
    }
    
    private var enteredScheduledDurationMinutes: Int {
        (scheduledDurationHours * 60)
        + scheduledDurationMinutes
    }
    
    private var hasScheduledDurationOverride: Bool {
        enteredScheduledDurationMinutes > 0
    }

    private var arrivalWindowEndBinding: Binding<Date> {
        Binding(
            get: {
                job.arrivalWindowEnd ?? Calendar.current.date(
                    byAdding: .hour,
                    value: 2,
                    to: job.scheduledDate
                ) ?? job.scheduledDate
            },
            set: { job.arrivalWindowEnd = $0 }
        )
    }

    private var completionDeadlineBinding: Binding<Date> {
        Binding(
            get: {
                job.completionDeadline ?? QuarterHourDatePicker.normalized(
                    job.scheduledDate
                )
            },
            set: { job.completionDeadline = $0 }
        )
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
            $0.id != job.primaryTechnicianID
        }
    }
    private var primaryEmployee: EmployeeRecord? {
        guard let employeeID = job.primaryTechnicianID else {
            return nil
        }

        return store.employees.first {
            $0.id == employeeID
        }
    }

    private var secondaryEmployee: EmployeeRecord? {
        guard let employeeID = job.secondaryTechnicianID else {
            return nil
        }

        return store.employees.first {
            $0.id == employeeID
        }
    }
    private var capacityPreviewJob: JobRecord {
        var previewJob = job

        previewJob.scheduledDurationOverrideMinutes =
            hasScheduledDurationOverride
                ? enteredScheduledDurationMinutes
                : nil

        return previewJob
    }


    private var storedJob: JobRecord {
        store.jobs.first(where: {
            $0.id == job.id
        }) ?? job
    }

    private var workflowContext: JobWorkflowContext {
        workflowCoordinator().workflowContext(for: storedJob)
    }

    private var jobLogEvents: [JobTimelineEvent] {
        job.timelineEvents.sorted {
            $0.timestamp > $1.timestamp
        }
    }

    private var selectedTechnicianID: UUID? {
        UUID(uuidString: selectedTechnicianIDString)
    }

    @MainActor
    private func workflowCoordinator() -> FieldOperationsWorkflowCoordinator {
        FieldOperationsWorkflowCoordinator(store: store)
    }

    private var linkedInvoice: InvoiceRecord? {
        store.invoice(for: storedJob)
    }

    private var primaryActionTitle: String {
        if linkedInvoice != nil {
            return "Invoice Complete"
        }

        switch storedJob.status {
        case .toBeScheduled, .scheduled, .assigned:
            return "Start Setup"
        case .inProgress:
            return storedJob.workflowState == .settingUp
                ? "Start Job"
                : "Complete Job"
        case .completed:
            return "Create Invoice"
        case .cancelled:
            return "Job Cancelled"
        }
    }

    private var primaryActionSystemImage: String {
        if linkedInvoice != nil {
            return "doc.text.magnifyingglass"
        }

        switch storedJob.status {
        case .toBeScheduled, .scheduled, .assigned:
            return "wrench.and.screwdriver.fill"
        case .inProgress:
            return storedJob.workflowState == .settingUp
                ? "play.fill"
                : "checkmark.circle.fill"
        case .completed:
            return "doc.text.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private var isPrimaryActionDisabled: Bool {
        storedJob.status == .cancelled ||
        storedJob.lifecycleStatus == .archived
    }

    private var availableSites: [CustomerSite] {
        store.sites.filter {
            $0.customerNumber == job.customerNumber &&
            ($0.lifecycleStatus == .active || $0.id == job.siteID)
        }
    }
    
    var body: some View {
        Form {
            Section("Job") {
                Text(job.jobNumber)
                    .font(.headline)
                
                Text("Customer #: \(job.customerNumber)")

                Picker("Site", selection: $job.siteID) {
                    Text("No site selected").tag(UUID?.none)
                    ForEach(availableSites) { site in
                        Text(siteDisplayName(site)).tag(Optional(site.id))
                    }
                }
                
                if !job.estimateNumber.isEmpty {
                    Text("Estimate: \(job.estimateNumber)")
                }
                
                LabeledContent(
                    "Status",
                    value: workflowContext.currentState.rawValue
                )
            }

            Section("Job Log") {
                if jobLogEvents.isEmpty {
                    Text("No job activity has been recorded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(jobLogEvents) { event in
                        jobLogRow(event)
                    }
                }

                TextField(
                    "Add a technician note",
                    text: $technicianNoteDraft,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($isInputFocused)

                Button {
                    addTechnicianNote()
                } label: {
                    Label("Add Note", systemImage: "plus.bubble.fill")
                }
                .disabled(
                    technicianNoteDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }

            Section("Technicians") {
                Picker(
                    "Primary Technician",
                    selection: $job.primaryTechnicianID
                ) {
                    Text("Unassigned")
                        .tag(UUID?.none)

                    ForEach(assignableEmployees) { employee in
                        Text(employee.displayName)
                            .tag(UUID?.some(employee.id))
                    }
                }
                .onChange(of: job.primaryTechnicianID) { _, newPrimaryID in
                    if job.secondaryTechnicianID == newPrimaryID {
                        job.secondaryTechnicianID = nil
                    }
                }

                Picker(
                    "Secondary Technician",
                    selection: $job.secondaryTechnicianID
                ) {
                    Text("None")
                        .tag(UUID?.none)

                    ForEach(availableSecondaryEmployees) { employee in
                        Text(employee.displayName)
                            .tag(UUID?.some(employee.id))
                    }
                }
                .disabled(job.primaryTechnicianID == nil)
            }

            if showWorkflow {
            Section("Field Workflow") {
                JobWorkflowStatusCard(
                    context: workflowContext,
                    action: {
                        performPrimaryWorkflowAction()
                    },
                    performAction: { action in
                        performWorkflowAction(action)
                    }
                )
            }

            }
            if showTimeline {
            Section("Job Timeline") {
                JobTimelineView(
                    events: workflowContext.timeline
                ) { employeeID in
                    employeeName(for: employeeID)
                }
            }
            
            Section("Service") {
                Picker("Service Type", selection: $job.serviceType) {
                    ForEach(ServiceType.allCases) { service in
                        Text(service.rawValue).tag(service)
                    }
                }
                
                if job.serviceType == .other {
                    TextField("Other Service", text: $job.otherService)
                        .focused($isInputFocused)
                }
                
                TextField("Work Notes", text: $job.workNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isInputFocused)
            }
            
            }
            if showCapacity {
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
            
            }
            if showWorkOrder {
                WorkOrderEditorView(
                lineItems: $job.lineItems,
                isInputFocused: $isInputFocused,
                onAddLineItem: {
                    PresentationDebug.log("Job detail requested catalog picker")
                    activeSheet = .catalogPicker
                },
                onEditLineItem: { item in
                    PresentationDebug.log(
                        "Job detail requested editor for \(item.id)"
                    )
                    activeSheet = .editLineItem(item)
                }
            )
            
            }
            Section("Pricing") {
                TextField("Discount", value: $job.discount, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
                
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotalValue, format: .currency(code: "USD"))
                        .bold()
                }
                
                HStack {
                    Text("Total")
                    Spacer()
                    Text(totalValue, format: .currency(code: "USD"))
                        .bold()
                }
            }
            
            Section("Schedule") {
                Picker(
                    "Scheduling Mode",
                    selection: $job.assignmentSchedulingMode
                ) {
                    ForEach(AssignmentSchedulingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                schedulingControls

                Picker("Priority", selection: $job.assignmentPriority) {
                    ForEach(AssignmentPriority.allCases) { priority in
                        Text(priority.rawValue).tag(priority)
                    }
                }

                HStack {
                    Text("Estimated Labor")
                    Spacer()
                    Text(
                        SchedulingCalculator.formattedDuration(
                            for: job.lineItems
                        )
                    )
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scheduled Duration")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Picker(
                            "Hours",
                            selection: $scheduledDurationHours
                        ) {
                            ForEach(0...12, id: \.self) { hour in
                                Text(
                                    hour == 1
                                        ? "1 hour"
                                        : "\(hour) hours"
                                )
                                .tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                        Picker(
                            "Minutes",
                            selection: $scheduledDurationMinutes
                        ) {
                            ForEach(
                                [0, 15, 30, 45],
                                id: \.self
                            ) { minute in
                                Text("\(minute) minutes")
                                    .tag(minute)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    HStack {
                        Text("Effective Duration")
                            .foregroundStyle(.secondary)
                    }
                    
                    if hasScheduledDurationOverride {
                        Button("Use Calculated Duration") {
                            scheduledDurationHours = 0
                            scheduledDurationMinutes = 0
                            job.scheduledDurationOverrideMinutes = nil
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
                
                Spacer()
                
                Text(
                    SchedulingCalculator.formattedDuration(
                        for: job.lineItems
                    )
                )
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            }
            
            Toggle("Recurring Job", isOn: $job.isRecurring)

            if job.isRecurring {
                Button {
                    showingRecurrencePicker = true
                } label: {
                    LabeledContent(
                        "Frequency",
                        value: job.recurrenceFrequency?.rawValue ?? "Select"
                    )
                }
            }
            
            if job.completedDate != nil {
                DatePicker(
                    "Completed Date",
                    selection: Binding(
                        get: { job.completedDate ?? Date() },
                        set: { job.completedDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            
            
            Section("Next Step") {
                Button {
                    performGuidedPrimaryAction()
                } label: {
                    Label(
                        primaryActionTitle,
                        systemImage: primaryActionSystemImage
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryActionDisabled)
            }

            Section {
                if job.lifecycleStatus == .archived {
                    Button("Restore Job") {
                        store.restoreJob(job)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Job", role: .destructive) {
                        store.archiveJob(job)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard let overrideMinutes =
                    job.scheduledDurationOverrideMinutes,
                  overrideMinutes > 0 else {
                return
            }
            
            scheduledDurationHours =
            overrideMinutes / 60
            
            let remainingMinutes =
            overrideMinutes % 60
            
            scheduledDurationMinutes =
            closestQuarterHour(
                to: remainingMinutes
            )
        }
        .onChange(of: job.isRecurring) {
            if job.isRecurring {
                showingRecurrencePicker = true
            } else {
                job.recurrenceFrequency = nil
            }
        }
        .onChange(of: job.assignmentSchedulingMode) {
            prepareSchedulingFields(for: job.assignmentSchedulingMode)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Job")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveJobChanges(shouldDismiss: true)
                }
                .disabled(job.isRecurring && job.recurrenceFrequency == nil)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .catalogPicker:
                ServiceCatalogPickerView(
                    lineItems: $job.lineItems,
                    onFinished: {
                        activeSheet = nil
                    }
                )
                .environmentObject(store)
                
            case .editLineItem(let item):
                EditableLineItemView(
                    lineItems: $job.lineItems,
                    catalogItem: nil,
                    existingLineItem: item
                )
                .environmentObject(store)
            }
        }
        .sheet(item: $presentedInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(
                    invoice: invoice,
                    showsDismissButton: true
                )
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showingRecurrencePicker) {
            JobRecurrencePickerView(selection: $job.recurrenceFrequency)
        }
    }

    private func siteDisplayName(_ site: CustomerSite) -> String {
        if site.siteName.isEmpty { return site.serviceAddress }
        if site.serviceAddress.isEmpty { return site.siteName }
        return "\(site.siteName) — \(site.serviceAddress)"
    }

    @ViewBuilder
    private var schedulingControls: some View {
        switch job.assignmentSchedulingMode {
        case .fixedTime:
            QuarterHourDatePicker(
                selection: $job.scheduledDate,
                dateLabel: "Service Date",
                timeLabel: "Fixed Start"
            )

        case .arrivalWindow:
            QuarterHourDatePicker(
                selection: $job.scheduledDate,
                dateLabel: "Service Date",
                timeLabel: "Earliest Arrival"
            )
            QuarterHourDatePicker(
                selection: arrivalWindowEndBinding,
                dateLabel: "Window End Date",
                timeLabel: "Latest Arrival"
            )

        case .flexibleDay:
            DatePicker(
                "Service Date",
                selection: $job.scheduledDate,
                displayedComponents: .date
            )

        case .deadline:
            QuarterHourDatePicker(
                selection: completionDeadlineBinding,
                dateLabel: "Deadline Date",
                timeLabel: "Complete By"
            )
        }
    }

    private func prepareSchedulingFields(
        for mode: AssignmentSchedulingMode
    ) {
        switch mode {
        case .fixedTime:
            job.scheduledDate = QuarterHourDatePicker.normalized(
                job.scheduledDate
            )
            job.arrivalWindowEnd = nil
            job.completionDeadline = nil

        case .arrivalWindow:
            job.scheduledDate = QuarterHourDatePicker.normalized(
                job.scheduledDate
            )
            if job.arrivalWindowEnd == nil ||
                job.arrivalWindowEnd! <= job.scheduledDate {
                job.arrivalWindowEnd = Calendar.current.date(
                    byAdding: .hour,
                    value: 2,
                    to: job.scheduledDate
                )
            }
            job.completionDeadline = nil

        case .flexibleDay:
            job.scheduledDate = Calendar.current.startOfDay(
                for: job.scheduledDate
            )
            job.arrivalWindowEnd = nil
            job.completionDeadline = nil

        case .deadline:
            if job.completionDeadline == nil {
                job.completionDeadline = QuarterHourDatePicker.normalized(
                    job.scheduledDate
                )
            }
            job.arrivalWindowEnd = nil
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
                on: job.scheduledDate
            )

        let previouslyScheduledMinutes =
            SchedulingCalculator.scheduledMinutes(
                for: employee,
                on: job.scheduledDate,
                from: store.jobs,
                excludingJobID: job.id
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
                job.scheduledDate,
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
    private func saveJobChanges(shouldDismiss: Bool) {
        isInputFocused = false

        switch job.assignmentSchedulingMode {
        case .fixedTime:
            job.scheduledDate = QuarterHourDatePicker.normalized(
                job.scheduledDate
            )
            job.arrivalWindowEnd = nil
            job.completionDeadline = nil

        case .arrivalWindow:
            job.scheduledDate = QuarterHourDatePicker.normalized(
                job.scheduledDate
            )
            job.arrivalWindowEnd = QuarterHourDatePicker.normalized(
                arrivalWindowEndBinding.wrappedValue
            )
            job.completionDeadline = nil

        case .flexibleDay:
            job.scheduledDate = Calendar.current.startOfDay(
                for: job.scheduledDate
            )
            job.arrivalWindowEnd = nil
            job.completionDeadline = nil

        case .deadline:
            job.completionDeadline = QuarterHourDatePicker.normalized(
                completionDeadlineBinding.wrappedValue
            )
            job.scheduledDate = Calendar.current.startOfDay(
                for: job.completionDeadline ?? job.scheduledDate
            )
            job.arrivalWindowEnd = nil
        }

        if job.status == .completed && job.completedDate == nil {
            job.completedDate = Date()
        }

        job.scheduledDurationOverrideMinutes =
            hasScheduledDurationOverride
                ? enteredScheduledDurationMinutes
                : nil

        job.lineItems = PricingCalculator.updatedLineItems(job.lineItems)
        job.subtotal = PricingCalculator.subtotal(for: job)
        job.total = PricingCalculator.total(for: job)
        store.updateJob(job)

        if shouldDismiss {
            dismiss()
        }
    }

    private func refreshJobFromStore() {
        guard let refreshed = store.jobs.first(where: {
            $0.id == job.id
        }) else {
            return
        }

        job = refreshed
    }

    private func performGuidedPrimaryAction() {
        saveJobChanges(shouldDismiss: false)

        if let invoice = store.invoice(forJobID: job.id) {
            presentedInvoice = invoice
            return
        }

        guard workflowCoordinator().performGuidedPrimaryAction(
            for: storedJob,
            employeeID: job.primaryTechnicianID
        ) else {
            return
        }

        if let invoice = store.invoice(forJobID: job.id),
           storedJob.status == .completed {
            presentedInvoice = invoice
        }

        refreshJobFromStore()
    }

    private func performPrimaryWorkflowAction() {
        performWorkflowAction(workflowContext.nextAction)
    }

    private func performWorkflowAction(_ action: JobWorkflowAction) {
        _ = workflowCoordinator().performWorkflowAction(
            jobID: job.id,
            action: action,
            employeeID: job.primaryTechnicianID
        )

        if let refreshed = store.jobs.first(where: {
            $0.id == job.id
        }) {
            job = refreshed
        }
    }

    private func employeeName(
        for employeeID: UUID?
    ) -> String? {
        guard let employeeID else {
            return nil
        }

        return store.employees.first(where: {
            $0.id == employeeID
        })?.displayName
    }

    private func addTechnicianNote() {
        let trimmedNote = technicianNoteDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedNote.isEmpty else {
            return
        }

        let authorID = selectedTechnicianID
            ?? job.primaryTechnicianID

        guard let event = store.addTechnicianNote(
            jobID: job.id,
            text: trimmedNote,
            employeeID: authorID
        ) else {
            return
        }

        job.timelineEvents.append(event)
        technicianNoteDraft = ""
        isInputFocused = false
    }

    @ViewBuilder
    private func jobLogRow(
        _ event: JobTimelineEvent
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: jobLogIcon(for: event.type))
                .foregroundStyle(
                    event.type == .note
                        ? .blue
                        : .secondary
                )
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .fontWeight(.semibold)

                    Spacer()

                    Text(
                        event.timestamp.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let note = event.note,
                   !note.isEmpty {
                    Text(note)
                }

                if let author = employeeName(
                    for: event.employeeID
                ) {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func jobLogIcon(
        for type: JobTimelineEventType
    ) -> String {
        switch type {
        case .note:
            return "text.bubble.fill"
        case .assigned:
            return "person.crop.circle.badge.checkmark"
        case .travelStarted:
            return "car.fill"
        case .arrived:
            return "mappin.circle.fill"
        case .setupStarted:
            return "wrench.and.screwdriver.fill"
        case .workStarted:
            return "play.circle.fill"
        case .workPaused:
            return "pause.circle.fill"
        case .workResumed:
            return "play.circle.fill"
        case .packUpStarted:
            return "shippingbox.fill"
        case .workCompleted:
            return "checkmark.circle.fill"
        case .invoiceCreated:
            return "doc.text.fill"
        case .invoiceSent:
            return "paperplane.fill"
        case .paymentReceived:
            return "dollarsign.circle.fill"
        case .jobCompleted:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private func closestQuarterHour(
        to minutes: Int
    ) -> Int {
        let validMinutes = [0, 15, 30, 45]
        
        return validMinutes.min {
            abs($0 - minutes) <
                abs($1 - minutes)
        } ?? 0
    }
}
