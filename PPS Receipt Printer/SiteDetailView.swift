//
//  SiteDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct SiteDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var site: CustomerSite
    @State private var createdJobID: UUID?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("Site / Work Location") {
                Text("Customer #: \(site.customerNumber)")
                    .font(.headline)

                TextField("Site Name", text: $site.siteName)
                    .focused($isInputFocused)

                TextField("Service Address", text: $site.serviceAddress)
                    .focused($isInputFocused)

                TextField("Property Type", text: $site.propertyType)
                    .focused($isInputFocused)
            }

            Section("Notes") {
                TextField("Access Notes", text: $site.accessNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($isInputFocused)

                TextField("Work Notes", text: $site.workNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isInputFocused)
            }

            Section {
                Button("Create Job for This Site") {
                    let job = JobRecord(
                        jobNumber: store.generateJobNumber(),
                        customerNumber: site.customerNumber,
                        siteID: site.id,
                        estimateNumber: "",
                        serviceType: .other,
                        otherService: "",
                        subtotal: 0,
                        discount: 0,
                        total: 0,
                        primaryTechnicianID: nil,
                        secondaryTechnicianID: nil,
                        scheduledDate: Date(),
                        completedDate: nil,
                        status: .toBeScheduled,
                        workNotes: site.workNotes,
                        isRecurring: false,
                        createdDate: Date()
                    )

                    store.addJob(job)
                    createdJobID = job.id
                }
                .disabled(site.lifecycleStatus == .archived)

                Button("Save Changes") {
                    isInputFocused = false
                    store.updateSite(site)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                if site.lifecycleStatus == .archived {
                    Button("Restore Site") {
                        store.restoreSite(site)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Site", role: .destructive) {
                        store.archiveSite(site)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Site")
        .navigationDestination(item: $createdJobID) { jobID in
            if let job = store.jobs.first(where: { $0.id == jobID }) {
                JobDetailView(job: job)
            } else {
                Text("Job not found")
            }
        }
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
