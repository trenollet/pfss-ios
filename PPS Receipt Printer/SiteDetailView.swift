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
    private let originalSite: CustomerSite
    @State private var createdJob: JobRecord?
    @State private var isShowingNewEstimate = false
    @State private var isClosing = false
    @State private var showingUnsavedChangesAlert = false
    @FocusState private var isInputFocused: Bool

    init(site: CustomerSite) {
        originalSite = site
        _site = State(initialValue: site)
    }

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
                Button {
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
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                        Text("Create Job for This Site")
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .disabled(site.lifecycleStatus == .archived)

                Button {
                    isShowingNewEstimate = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                        Text("Create Estimate for This Site")
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .disabled(site.lifecycleStatus == .archived)

                if site.lifecycleStatus == .archived {
                    Button {
                        store.restoreSite(site)
                        closeSiteDetail()
                    } label: {
                        Label("Restore Site", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive) {
                        store.archiveSite(site)
                        closeSiteDetail()
                    } label: {
                        Label("Archive Site", systemImage: "archivebox.fill")
                    }
                    .buttonStyle(.borderedProminent)
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
        .sheet(isPresented: $isShowingNewEstimate) {
            NavigationStack {
                EstimateNewView(
                    preselectedCustomerNumber: site.customerNumber,
                    preselectedSiteID: site.id
                )
                .environmentObject(store)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
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
        .alert(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert
        ) {
            Button("Save Changes") {
                closeSiteDetail(savingChanges: true)
            }

            Button("Discard Changes", role: .destructive) {
                closeSiteDetail()
            }

            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This site has changes that have not been saved.")
        }
        .onDisappear {
            isInputFocused = false
        }
    }

    private var hasUnsavedChanges: Bool {
        encodedSite(site) != encodedSite(originalSite)
    }

    private func requestDismissal() {
        resignInputFocus()
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            closeSiteDetail()
        }
    }

    private func encodedSite(_ site: CustomerSite) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(site)
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
