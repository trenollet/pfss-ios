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
                Button("Save Changes") {
                    isInputFocused = false
                    store.updateSite(site)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Edit Site")
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
