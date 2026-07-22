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
    @State private var createdJob: JobRecord?
    @FocusState private var isInputFocused: Bool

    private var customerDisplayName: String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == site.customerNumber
        }) else {
            return "Customer Not Found"
        }

        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return "Unnamed Customer"
    }

    var body: some View {
        Form {
            Section("Site / Work Location") {
                LabeledContent("Customer", value: customerDisplayName)

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
                    createdJob = job
                }
                .disabled(site.lifecycleStatus == .archived)

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
        .sheet(item: $createdJob) { job in
            NavigationStack {
                JobDetailView(
                    job: store.jobs.first(where: { $0.id == job.id }) ?? job
                )
            }
            .environmentObject(store)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isInputFocused = false
                    store.updateSite(site)
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
    }
}
