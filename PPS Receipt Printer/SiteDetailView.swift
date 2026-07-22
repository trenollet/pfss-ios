//
//  SiteDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI
import UIKit

struct SiteDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var site: CustomerSite
    @State private var createdJob: JobRecord?
    @State private var isClosing = false
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
                        closeSiteDetail()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Site", role: .destructive) {
                        store.archiveSite(site)
                        closeSiteDetail()
                    }
                }
            }
        }
        .navigationTitle("Edit Site")
        .navigationBarBackButtonHidden(true)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $createdJob) { job in
            NavigationStack {
                JobDetailView(
                    job: store.jobs.first(where: { $0.id == job.id }) ?? job
                )
            }
            .environmentObject(store)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    closeSiteDetail()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(isClosing)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    closeSiteDetail(savingChanges: true)
                }
                .disabled(isClosing)
            }

        }
        .onDisappear {
            isInputFocused = false
        }
    }

    /// Ends text editing before beginning the navigation transition.
    ///
    /// Popping a Form while one of its text fields is still UIKit's first
    /// responder can make the navigation snapshot briefly request a zero-height
    /// image. The Site editor intentionally does not install a keyboard toolbar:
    /// on this navigation path UIKit can invalidate that accessory view's input
    /// session while it is being removed, producing RTIInputSystemClient and
    /// invalid-frame runtime messages. Waiting for the standard keyboard to
    /// resign avoids tearing down navigation and input accessory views together.
    private func closeSiteDetail(savingChanges: Bool = false) {
        guard !isClosing else { return }
        isClosing = true

        resignInputFocus()

        if savingChanges {
            store.updateSite(site)
        }

        Task { @MainActor in
            try? await Task<Never, Never>.sleep(for: .milliseconds(150))
            dismiss()
        }
    }

    private func resignInputFocus() {
        isInputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
