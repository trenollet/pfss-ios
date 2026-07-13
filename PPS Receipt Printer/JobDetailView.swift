//
//  JobDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct JobDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    
    @State var job: JobRecord
    @FocusState private var isInputFocused: Bool
    @State private var activeSheet: ActiveSheet?
    @State private var scheduledDurationHours = 0
    @State private var scheduledDurationMinutes = 0
    
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
    
    var body: some View {
        Form {
            Section("Job") {
                Text(job.jobNumber)
                    .font(.headline)
                
                Text("Customer #: \(job.customerNumber)")
                
                if !job.estimateNumber.isEmpty {
                    Text("Estimate: \(job.estimateNumber)")
                }
                
                Picker("Status", selection: $job.status) {
                    ForEach(JobStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
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
            
            Section("Technicians") {
                TextField("Primary Technician", text: $job.primaryTechnician)
                    .focused($isInputFocused)
                
                TextField("Secondary Technician", text: $job.secondaryTechnician)
                    .focused($isInputFocused)
            }
            
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
                DatePicker("Scheduled Date", selection: $job.scheduledDate, displayedComponents: [.date, .hourAndMinute])
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
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hours")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Picker(
                                "Hours",
                                selection: $scheduledDurationHours
                            ) {
                                ForEach(0...12, id: \.self) { hour in
                                    Text("\(hour)")
                                        .tag(hour)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 100)
                            .clipped()
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Minutes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Picker(
                                "Minutes",
                                selection: $scheduledDurationMinutes
                            ) {
                                ForEach(
                                    [0, 15, 30, 45],
                                    id: \.self
                                ) { minute in
                                    Text("\(minute)")
                                        .tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 100)
                            .clipped()
                        }
                    }
                    
                    HStack {
                        Text("Effective Duration")
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
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
            
            Button("Mark Completed") {
                job.status = .completed
                job.completedDate = Date()
            }
            .disabled(job.status == .completed)
        }
        
        Section {
            Button("Save Changes") {
                isInputFocused = false
                
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
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            
            if job.status == .completed &&
                !store.invoices.contains(where: { $0.jobNumber == job.jobNumber }) {
                
                Button {
                    _ = store.createInvoiceFromJob(job)
                } label: {
                    Label(
                        "Create Invoice",
                        systemImage: "doc.text.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            
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
        .navigationTitle("Edit Job")
        .toolbar {
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
