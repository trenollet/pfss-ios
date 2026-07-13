//
//  BusinessProfileView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import SwiftUI
import PhotosUI

struct BusinessProfileView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile = BusinessProfile()
    @State private var previewPDFURL: URL?
    @State private var thermalPreviewText = ""
    @State private var isShowingThermalPreview = false
    @State private var previewErrorMessage: String?
    @State private var isShowingPreviewError = false
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var logoLoadError: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("Business Logo") {
                VStack(spacing: 16) {
                    if let logoData = profile.logoData,
                       let logoImage = UIImage(data: logoData) {

                        Image(uiImage: logoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 12)
                            )
                            .accessibilityLabel("Business logo")
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No business logo selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PhotosPicker(
                        selection: $selectedLogoItem,
                        matching: .images
                    ) {
                        Label(
                            profile.logoData == nil
                                ? "Select Logo"
                                : "Replace Logo",
                            systemImage: "photo.on.rectangle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if profile.logoData != nil {
                        Button(
                            "Remove Logo",
                            role: .destructive
                        ) {
                            selectedLogoItem = nil
                            profile.logoData = nil
                            logoLoadError = nil
                        }
                    }

                    if let logoLoadError {
                        Text(logoLoadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Business Information") {
                TextField(
                    "Business Name",
                    text: $profile.businessName
                )
                .textContentType(.organizationName)
                .focused($isInputFocused)

                TextField(
                    "Contact Name",
                    text: $profile.contactName
                )
                .textContentType(.name)
                .focused($isInputFocused)
            }

            Section("Contact Information") {
                TextField(
                    "Phone",
                    text: $profile.phone
                )
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($isInputFocused)
                .onChange(of: profile.phone) { _, newValue in
                    profile.phone = formattedPhoneNumber(newValue)
                }

                TextField(
                    "Email",
                    text: $profile.email
                )
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .focused($isInputFocused)

                TextField(
                    "Website",
                    text: $profile.website
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .focused($isInputFocused)
            }

            Section("Business Address") {
                TextField(
                    "Address Line 1",
                    text: $profile.addressLine1
                )
                .textContentType(.streetAddressLine1)
                .focused($isInputFocused)

                TextField(
                    "Address Line 2",
                    text: $profile.addressLine2
                )
                .textContentType(.streetAddressLine2)
                .focused($isInputFocused)

                TextField(
                    "City",
                    text: $profile.city
                )
                .textContentType(.addressCity)
                .focused($isInputFocused)

                TextField(
                    "State",
                    text: $profile.state
                )
                .textInputAutocapitalization(.characters)
                .textContentType(.addressState)
                .focused($isInputFocused)

                TextField(
                    "ZIP Code",
                    text: $profile.postalCode
                )
                .keyboardType(.numbersAndPunctuation)
                .textContentType(.postalCode)
                .focused($isInputFocused)
            }

            Section("Document Defaults") {
                TextField(
                    "Document Header Text",
                    text: $profile.invoiceHeaderText,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($isInputFocused)

                TextField(
                    "Document Footer Text",
                    text: $profile.invoiceFooterText,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($isInputFocused)
            }
            
            Section("Document Previews") {
                Button {
                    createSamplePDFPreview()
                } label: {
                    Label(
                        "Preview Sample PDF Invoice",
                        systemImage: "doc.richtext"
                    )
                }

                Button {
                    createSampleThermalPreview()
                } label: {
                    Label(
                        "Preview Sample Thermal Receipt",
                        systemImage: "receipt"
                    )
                }
            }
            Section {
                Button {
                    saveProfile()
                } label: {
                    HStack {
                        Spacer()

                        Label(
                            "Save Business Profile",
                            systemImage: "checkmark.circle.fill"
                        )

                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Business Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            profile = store.businessProfile
            profile.phone = formattedPhoneNumber(profile.phone)
        }
        .onChange(of: selectedLogoItem) { _, newItem in
            guard let newItem else {
                return
            }

            Task {
                do {
                    guard let data = try await newItem.loadTransferable(
                        type: Data.self
                    ) else {
                        await MainActor.run {
                            logoLoadError = "The selected image could not be loaded."
                        }
                        return
                    }

                    guard UIImage(data: data) != nil else {
                        await MainActor.run {
                            logoLoadError = "The selected file is not a supported image."
                        }
                        return
                    }

                    await MainActor.run {
                        profile.logoData = data
                        logoLoadError = nil
                    }
                } catch {
                    await MainActor.run {
                        logoLoadError = "Logo loading failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { previewPDFURL != nil },
                set: { isPresented in
                    if !isPresented {
                        previewPDFURL = nil
                    }
                }
            )
        ) {
            if let previewPDFURL {
                ActivityView(
                    activityItems: [previewPDFURL]
                )
            }
        }
        .sheet(isPresented: $isShowingThermalPreview) {
            NavigationStack {
                ScrollView {
                    Text(thermalPreviewText)
                        .font(.system(.body, design: .monospaced))
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding()
                }
                .navigationTitle("Thermal Receipt Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isShowingThermalPreview = false
                        }
                    }
                }
            }
        }
        .alert(
            "Unable to Create Preview",
            isPresented: $isShowingPreviewError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                previewErrorMessage ??
                "The preview could not be created."
            )
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

    private func saveProfile() {
        isInputFocused = false

        profile.businessName = profile.businessName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.contactName = profile.contactName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.phone = profile.phone
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.email = profile.email
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.website = profile.website
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.addressLine1 = profile.addressLine1
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.addressLine2 = profile.addressLine2
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.city = profile.city
            .trimmingCharacters(in: .whitespacesAndNewlines)

        profile.state = profile.state
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        profile.postalCode = profile.postalCode
            .trimmingCharacters(in: .whitespacesAndNewlines)

        store.businessProfile = profile
        dismiss()
    }
    private func formattedPhoneNumber(
        _ value: String
    ) -> String {
        let digits = value.filter(\.isNumber)
        let limitedDigits = String(digits.prefix(10))

        switch limitedDigits.count {
        case 0...3:
            return limitedDigits

        case 4...6:
            let areaCode = limitedDigits.prefix(3)
            let prefix = limitedDigits.dropFirst(3)

            return "(\(areaCode)) \(prefix)"

        default:
            let areaCode = limitedDigits.prefix(3)
            let prefix = limitedDigits.dropFirst(3).prefix(3)
            let lineNumber = limitedDigits.dropFirst(6)

            return "(\(areaCode)) \(prefix)-\(lineNumber)"
        }
    }
    private func createSamplePDFPreview() {
        let customer = InvoicePreviewFactory.sampleCustomer()
        let site = InvoicePreviewFactory.sampleSite(
            customerNumber: customer.customerNumber
        )
        let catalogItems = InvoicePreviewFactory.sampleCatalogItems()
        let invoice = InvoicePreviewFactory.sampleInvoice(
            catalogItems: catalogItems
        )

        do {
            previewPDFURL = try InvoicePDFRenderer.createPDF(
                invoice: invoice,
                businessProfile: profile,
                customer: customer,
                site: site,
                catalogItems: catalogItems
            )
        } catch {
            previewErrorMessage = error.localizedDescription
            isShowingPreviewError = true
        }
    }

    private func createSampleThermalPreview() {
        let customer = InvoicePreviewFactory.sampleCustomer()
        let site = InvoicePreviewFactory.sampleSite(
            customerNumber: customer.customerNumber
        )
        let catalogItems = InvoicePreviewFactory.sampleCatalogItems()
        let invoice = InvoicePreviewFactory.sampleInvoice(
            catalogItems: catalogItems
        )

        thermalPreviewText = ThermalReceiptRenderer.render(
            invoice: invoice,
            businessProfile: profile,
            customer: customer,
            site: site,
            catalogItems: catalogItems
        )

        isShowingThermalPreview = true
    }
}
