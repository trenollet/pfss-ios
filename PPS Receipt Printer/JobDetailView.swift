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

            Section("Schedule") {
                DatePicker("Scheduled Date", selection: $job.scheduledDate, displayedComponents: [.date, .hourAndMinute])

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

                    store.updateJob(job)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

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
        .navigationTitle("Edit Job")
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
