//
//  JobDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct JobDetailView: View {
    private let showServiceDetails = false
    private let showCapacity = false
    // Field technicians may add requested work to the existing Job while on
    // site. The same work-order editor is reused so pricing and labor duration
    // remain consistent with office-created line items.
    private let showWorkOrder = true

    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    let scrollToScheduleOnAppear: Bool
    let onSave: (() -> Void)?

    @AppStorage("selectedTechnicianID")
    private var selectedTechnicianIDString = ""
    
    @State var job: JobRecord
    @State private var originalJob: JobRecord
    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?
    @State private var scheduledDurationHours = 0
    @State private var scheduledDurationMinutes = 0
    @State private var technicianNoteDraft = ""
    @State private var presentedInvoice: InvoiceRecord?
    @State private var showingRecurrencePicker = false
    @State private var timelineCorrectionEvent: JobTimelineEvent?
    @State private var showingUnsavedChangesAlert = false

    private let scheduleSectionID = "job-schedule-section"

    init(
        job: JobRecord,
        scrollToScheduleOnAppear: Bool = false,
        onSave: (() -> Void)? = nil
    ) {
        _job = State(initialValue: job)
        _originalJob = State(initialValue: job)
        self.scrollToScheduleOnAppear = scrollToScheduleOnAppear
        self.onSave = onSave
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

    private var selectedTechnicianID: UUID? {
        UUID(uuidString: selectedTechnicianIDString)
    }

    private var timelineCorrectionActor: EmployeeRecord? {
        guard let selectedTechnicianID else { return nil }
        return store.employees.first {
            $0.id == selectedTechnicianID && $0.canOverrideScheduling
        }
    }

    @MainActor
    private func workflowCoordinator() -> FieldOperationsWorkflowCoordinator {
        FieldOperationsWorkflowCoordinator(store: store)
    }

    private var availableSites: [CustomerSite] {
        store.sites.filter {
            $0.customerNumber == job.customerNumber &&
            ($0.lifecycleStatus == .active || $0.id == job.siteID)
        }
    }
    
    var body: some View {
        ScrollViewReader { scrollProxy in
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
                    value: workflowContext.presentation.statusTitle
                )
            }

            Section("Job Timeline") {
                JobTimelineView(
                    events: workflowContext.timeline,
                    employeeName: { employeeID in
                        employeeName(for: employeeID)
                    },
                    onCorrect: timelineCorrectionActor == nil
                        ? nil
                        : { event in timelineCorrectionEvent = event }
                )

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
                    Label("Save Note", systemImage: "checkmark.bubble.fill")
                }
                .disabled(
                    technicianNoteDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }

            Section("Technicians") {
                if store.canManageCompany {
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
                } else {
                    LabeledContent(
                        "Primary Technician",
                        value: primaryEmployee?.displayName ?? "Unassigned"
                    )
                    LabeledContent(
                        "Secondary Technician",
                        value: secondaryEmployee?.displayName ?? "None"
                    )
                    Text("Only a Manager or Owner can change job assignments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
            if showServiceDetails {
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
                LabeledContent("Discount") {
                    SelectAllDecimalField(
                        placeholder: "Discount",
                        value: $job.discount
                    )
                    .focused($isInputFocused)
                }
                
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
            .id(scheduleSectionID)
            
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

                if let templateID = job.recurringWorkTemplateID {
                    NavigationLink {
                        RecurringWorkManagementView(
                            templateID: templateID,
                            onSeriesUpdated: {
                                refreshJobFromRecurringSeries(
                                    templateID: templateID
                                )
                            }
                        )
                            .environmentObject(store)
                    } label: {
                        Label("Manage Recurring Work", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }

                    if job.recurrenceSequence > 0 {
                        Text("Changes on this page apply only to this occurrence. Use Manage Recurring Work to edit the complete series.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            
            
            Section {
                if job.lifecycleStatus == .archived {
                    Button {
                        store.restoreJob(job)
                        dismiss()
                    } label: {
                        Label("Restore Job", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveJob(job)
                        dismiss()
                    } label: {
                        CenteredArchiveActionLabel(title: "Archive Job")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .onAppear {
            if scrollToScheduleOnAppear {
                Task { @MainActor in
                    await Task.yield()
                    withAnimation {
                        scrollProxy.scrollTo(scheduleSectionID, anchor: .top)
                    }
                }
            }

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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            EditorKeyboardDismissAction(isVisible: isInputFocused) {
                isInputFocused = false
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveJobChanges(shouldDismiss: true)
                }
                .disabled(job.isRecurring && job.recurrenceFrequency == nil)
            }

        }
        .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
            Button("Save Changes") { saveJobChanges(shouldDismiss: true) }
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This job has changes that have not been saved.")
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
            JobRecurrencePickerView(
                selection: $job.recurrenceFrequency,
                endMode: $job.recurrenceEndMode,
                endDate: $job.recurrenceEndDate,
                occurrenceCount: $job.recurrenceOccurrenceCount
            )
        }
        .sheet(item: $timelineCorrectionEvent) { event in
            if let actor = timelineCorrectionActor {
                TimelineCorrectionEditorView(
                    event: event,
                    actorName: actor.displayName
                ) { correctedTimestamp, reason in
                    let saved = store.correctTimelineTimestamp(
                        jobID: job.id,
                        eventID: event.id,
                        correctedTimestamp: correctedTimestamp,
                        reason: reason,
                        actorEmployeeID: actor.id
                    )
                    if saved != nil {
                        refreshJobFromStore()
                    }
                    return saved != nil
                }
            }
        }
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

                Text(employee.roleDisplayText)
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

        if !store.canManageCompany {
            job.primaryTechnicianID = storedJob.primaryTechnicianID
            job.secondaryTechnicianID = storedJob.secondaryTechnicianID
        }

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

        let pendingNote = technicianNoteDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingNote.isEmpty {
            saveTechnicianNote(pendingNote)
        }

        originalJob = job
        onSave?()

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
        originalJob = refreshed
    }

    private func refreshJobFromRecurringSeries(templateID: UUID) {
        if let refreshed = store.jobs.first(where: {
            $0.recurringWorkTemplateID == templateID &&
            $0.recurrenceSequence == job.recurrenceSequence
        }) {
            job = refreshed
            originalJob = refreshed
            return
        }

        // The edited occurrence may fall outside the rebuilt schedule. Keep
        // the visible recurrence status aligned until the user leaves this
        // obsolete detail screen; saving cannot restore a Job removed by the
        // authoritative series rebuild.
        guard let template = store.recurringWorkTemplates.first(where: {
            $0.id == templateID
        }) else { return }

        job.recurrenceFrequency = template.rule.jobRecurrenceFrequency
        switch template.endCondition {
        case .noEnd:
            job.recurrenceEndMode = .noEnd
            job.recurrenceEndDate = nil
            job.recurrenceOccurrenceCount = nil
        case let .endDate(date):
            job.recurrenceEndMode = .endDate
            job.recurrenceEndDate = date
            job.recurrenceOccurrenceCount = nil
        case let .occurrenceCount(count):
            job.recurrenceEndMode = .occurrenceCount
            job.recurrenceEndDate = nil
            job.recurrenceOccurrenceCount = count
        }
        originalJob = job
    }

    private func performPrimaryWorkflowAction() {
        performWorkflowAction(workflowContext.nextAction)
    }

    private func performWorkflowAction(_ action: JobWorkflowAction) {
        saveJobChanges(shouldDismiss: false)

        if action == .recordPayment,
           let invoice = store.invoice(forJobID: job.id) {
            presentedInvoice = invoice
            return
        }

        let succeeded = workflowCoordinator().performWorkflowAction(
            jobID: job.id,
            action: action,
            employeeID: job.primaryTechnicianID
        )

        guard succeeded else {
            return
        }

        refreshJobFromStore()

        if action == .createInvoice,
           let invoice = store.invoice(forJobID: job.id) {
            presentedInvoice = invoice
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

        saveTechnicianNote(trimmedNote)
    }

    private var hasUnsavedChanges: Bool {
        encodedJob(job) != encodedJob(originalJob) ||
        !technicianNoteDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func requestDismissal() {
        isInputFocused = false
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func saveTechnicianNote(_ text: String) {
        let authorID = selectedTechnicianID ?? job.primaryTechnicianID
        guard let event = store.addTechnicianNote(
            jobID: job.id,
            text: text,
            employeeID: authorID
        ) else { return }

        job.timelineEvents.append(event)
        originalJob.timelineEvents.append(event)
        technicianNoteDraft = ""
        isInputFocused = false
    }

    private func encodedJob(_ job: JobRecord) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(job)
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
