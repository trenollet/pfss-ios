//
//  BusinessProfileView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import SwiftUI
import PhotosUI
import PDFKit

struct BusinessProfileView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile = BusinessProfile()
    @State private var originalProfile = BusinessProfile()
    @State private var didLoadProfile = false
    @State private var showingUnsavedChangesAlert = false

    var body: some View {
        Form {
            Section("Business Setup") {
                profileSectionLink(
                    title: "Business Logo",
                    subtitle: profile.logoData == nil
                        ? "No logo selected"
                        : "Logo configured",
                    symbol: "photo.on.rectangle.angled"
                ) {
                    BusinessLogoEditorView(profile: $profile)
                }

                profileSectionLink(
                    title: "Business Information",
                    subtitle: businessInformationSummary,
                    symbol: "building.2.fill"
                ) {
                    BusinessInformationEditorView(profile: $profile)
                }

                profileSectionLink(
                    title: "Contact Information",
                    subtitle: contactSummary,
                    symbol: "person.crop.circle.fill.badge.checkmark"
                ) {
                    BusinessContactEditorView(profile: $profile)
                }

                profileSectionLink(
                    title: "Business Address",
                    subtitle: addressSummary,
                    symbol: "mappin.and.ellipse"
                ) {
                    BusinessAddressEditorView(profile: $profile)
                }

                profileSectionLink(
                    title: "Document Defaults",
                    subtitle: documentDefaultsSummary,
                    symbol: "doc.text.fill"
                ) {
                    BusinessDocumentDefaultsEditorView(profile: $profile)
                }

                profileSectionLink(
                    title: "Business Operations",
                    subtitle: operationsSummary,
                    symbol: "gearshape.2.fill"
                ) {
                    BusinessOperationsEditorView(
                        operations: $profile.operations
                    )
                }

                profileSectionLink(
                    title: "Document Previews",
                    subtitle: "PDF invoice and thermal receipt",
                    symbol: "doc.text.magnifyingglass"
                ) {
                    BusinessDocumentPreviewsView(profile: $profile)
                }
            }
        }
        .navigationTitle("Business Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            guard !didLoadProfile else { return }
            var savedProfile = store.businessProfile
            savedProfile.phone = Self.formattedPhoneNumber(savedProfile.phone)
            profile = savedProfile
            originalProfile = savedProfile
            didLoadProfile = true
        }
        .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
            Button("Save Changes") { saveProfile() }
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Continue Editing", role: .cancel) { }
        } message: {
            Text("This business profile has changes that have not been saved.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestDismissal()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveProfile() }
                    .disabled(
                        profile.businessName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
            }
        }
    }

    private func profileSectionLink<Destination: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
            }
            .padding(.vertical, 5)
        }
    }

    private var businessInformationSummary: String {
        let name = profile.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = profile.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !contact.isEmpty { return "\(name) · \(contact)" }
        if !name.isEmpty { return name }
        if !contact.isEmpty { return contact }
        return "Not configured"
    }

    private var contactSummary: String {
        [profile.phone, profile.email]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nonEmpty ?? "Not configured"
    }

    private var addressSummary: String {
        let street = profile.addressLine1.trimmingCharacters(in: .whitespacesAndNewlines)
        let locality = [profile.city, profile.state, profile.postalCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [street, locality].filter { !$0.isEmpty }.joined(separator: ", ").nonEmpty
            ?? "Not configured"
    }

    private var documentDefaultsSummary: String {
        let headerSet = !profile.invoiceHeaderText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let footerSet = !profile.invoiceFooterText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (headerSet, footerSet) {
        case (true, true): return "Header and footer configured"
        case (true, false): return "Header configured"
        case (false, true): return "Footer configured"
        case (false, false): return "No document text configured"
        }
    }

    private var operationsSummary: String {
        let operations = profile.operations
        return "\(Int(operations.averageDrivingSpeedMPH.rounded())) mph · \(operations.dailyRouteBufferMinutes) min daily · \(operations.perStopBufferMinutes) min/stop"
    }

    private var hasUnsavedChanges: Bool {
        encodedProfile(profile) != encodedProfile(originalProfile)
    }

    private func encodedProfile(_ profile: BusinessProfile) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(profile)
    }

    private func requestDismissal() {
        if hasUnsavedChanges {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func saveProfile() {
        normalizeProfile()
        store.businessProfile = profile
        originalProfile = profile
        dismiss()
    }

    private func normalizeProfile() {
        profile.businessName = profile.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.contactName = profile.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phone = profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.website = profile.website.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.addressLine1 = profile.addressLine1.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.addressLine2 = profile.addressLine2.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.city = profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.state = profile.state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        profile.postalCode = profile.postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.invoiceHeaderText = profile.invoiceHeaderText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.invoiceFooterText = profile.invoiceFooterText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.operations.normalize()
    }

    static func formattedPhoneNumber(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(10))
        switch digits.count {
        case 0...3:
            return digits
        case 4...6:
            return "(\(digits.prefix(3))) \(digits.dropFirst(3))"
        default:
            return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
        }
    }

}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct BusinessLogoEditorView: View {
    @Binding var profile: BusinessProfile
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var logoLoadError: String?

    var body: some View {
        Form {
            Section("Business Logo") {
                VStack(spacing: 16) {
                    if let data = profile.logoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Business logo")
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No business logo selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                        Label(
                            profile.logoData == nil ? "Select Logo" : "Replace Logo",
                            systemImage: "photo.on.rectangle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if profile.logoData != nil {
                        Button("Remove Logo", role: .destructive) {
                            selectedLogoItem = nil
                            profile.logoData = nil
                            logoLoadError = nil
                        }
                    }

                    if let logoLoadError {
                        Text(logoLoadError).font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Business Logo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedLogoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          UIImage(data: data) != nil else {
                        await MainActor.run { logoLoadError = "The selected file is not a supported image." }
                        return
                    }
                    await MainActor.run {
                        profile.logoData = data
                        logoLoadError = nil
                    }
                } catch {
                    await MainActor.run { logoLoadError = "Logo loading failed: \(error.localizedDescription)" }
                }
            }
        }
    }
}

private struct BusinessInformationEditorView: View {
    @Binding var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Business Information") {
                TextField("Business Name", text: $profile.businessName)
                    .textContentType(.organizationName)
                TextField("Contact Name", text: $profile.contactName)
                    .textContentType(.name)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Business Information")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BusinessContactEditorView: View {
    @Binding var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Contact Information") {
                TextField("Phone", text: $profile.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .onChange(of: profile.phone) { _, value in
                        profile.phone = BusinessProfileView.formattedPhoneNumber(value)
                    }
                TextField("Email", text: $profile.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                TextField("Website", text: $profile.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Contact Information")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BusinessAddressEditorView: View {
    @Binding var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Business Address") {
                TextField("Address Line 1", text: $profile.addressLine1)
                    .textContentType(.streetAddressLine1)
                TextField("Address Line 2", text: $profile.addressLine2)
                    .textContentType(.streetAddressLine2)
                TextField("City", text: $profile.city).textContentType(.addressCity)
                TextField("State", text: $profile.state)
                    .textInputAutocapitalization(.characters)
                    .textContentType(.addressState)
                TextField("ZIP Code", text: $profile.postalCode)
                    .keyboardType(.numbersAndPunctuation)
                    .textContentType(.postalCode)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Business Address")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BusinessDocumentDefaultsEditorView: View {
    @Binding var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Document Defaults") {
                TextField("Document Header Text", text: $profile.invoiceHeaderText, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Document Footer Text", text: $profile.invoiceFooterText, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Document Defaults")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BusinessOperationsEditorView: View {
    @Binding var operations: BusinessOperationsSettings

    var body: some View {
        Form {
            Section {
                routePlanningStepper(
                    title: "Average Driving Speed",
                    value: Binding(
                        get: { Int(operations.averageDrivingSpeedMPH.rounded()) },
                        set: { operations.averageDrivingSpeedMPH = Double($0) }
                    ),
                    range: 5...80,
                    step: 5,
                    unit: "mph"
                )
                routePlanningStepper(
                    title: "Daily Route Buffer",
                    value: $operations.dailyRouteBufferMinutes,
                    range: 0...240,
                    step: 5,
                    unit: "minutes"
                )
                routePlanningStepper(
                    title: "Per Stop Buffer",
                    value: $operations.perStopBufferMinutes,
                    range: 0...60,
                    step: 1,
                    unit: "minutes"
                )
                Toggle(
                    "Include Buffers in Planned Route Time",
                    isOn: $operations.includeBuffersInRouteTime
                )
            } header: {
                Text("Route Planning")
            } footer: {
                Text("These settings control technician route estimates throughout PFSS. Drive time remains visible separately from planning buffers.")
            }
        }
        .navigationTitle("Business Operations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func routePlanningStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) \(unit)").foregroundStyle(.secondary)
            }
        }
    }
}

private struct BusinessDocumentPreviewsView: View {
    @Binding var profile: BusinessProfile

    @State private var generatingPreview: PreviewKind?
    @State private var previewPDFURL: URL?
    @State private var thermalPreviewText = ""
    @State private var isShowingThermalPreview = false
    @State private var previewErrorMessage: String?
    @State private var isShowingPreviewError = false

    private enum PreviewKind: Equatable {
        case pdf
        case thermal

        var message: String {
            switch self {
            case .pdf: return "Generating PDF Preview…"
            case .thermal: return "Generating Thermal Preview…"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Previews may take a moment to generate. Please wait for the preview to open before pressing the button again.")
                } icon: {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(.blue)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Document Previews") {
                Button {
                    generatePreview(.pdf)
                } label: {
                    previewButtonLabel(
                        title: "Preview Sample PDF Invoice",
                        symbol: "doc.richtext",
                        kind: .pdf
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    generatePreview(.thermal)
                } label: {
                    previewButtonLabel(
                        title: "Preview Sample Thermal Receipt",
                        symbol: "receipt",
                        kind: .thermal
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("For iPhone, rotate your screen to landscape to view the thermal receipt preview properly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Document Previews")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(generatingPreview != nil)
        .overlay {
            if let generatingPreview {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(generatingPreview.message)
                            .font(.headline)
                        Text("This may take a moment.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 12)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { previewPDFURL != nil },
                set: { if !$0 { previewPDFURL = nil } }
            )
        ) {
            if let previewPDFURL {
                NavigationStack {
                    PFSSPDFDocumentPreview(fileURL: previewPDFURL)
                        .navigationTitle("Sample PDF Invoice")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { self.previewPDFURL = nil }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $isShowingThermalPreview) {
            NavigationStack {
                ScrollView([.vertical, .horizontal]) {
                    Text(thermalPreviewText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Thermal Receipt Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingThermalPreview = false }
                    }
                }
            }
        }
        .alert("Unable to Create Preview", isPresented: $isShowingPreviewError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(previewErrorMessage ?? "The preview could not be created.")
        }
    }

    private func previewButtonLabel(
        title: String,
        symbol: String,
        kind: PreviewKind
    ) -> some View {
        HStack(spacing: 12) {
            if generatingPreview == kind {
                ProgressView()
            } else {
                Image(systemName: symbol)
            }
            Text(title)
                .fontWeight(.semibold)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func generatePreview(_ kind: PreviewKind) {
        guard generatingPreview == nil else { return }
        generatingPreview = kind

        Task { @MainActor in
            // Give SwiftUI one frame to visibly acknowledge the button press.
            try? await Task.sleep(nanoseconds: 150_000_000)

            switch kind {
            case .pdf:
                createSamplePDFPreview()
            case .thermal:
                createSampleThermalPreview()
            }
            generatingPreview = nil
        }
    }

    private func createSamplePDFPreview() {
        let customer = InvoicePreviewFactory.sampleCustomer()
        let site = InvoicePreviewFactory.sampleSite(customerNumber: customer.customerNumber)
        let catalogItems = InvoicePreviewFactory.sampleCatalogItems()
        let invoice = InvoicePreviewFactory.sampleInvoice(catalogItems: catalogItems)
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
        let site = InvoicePreviewFactory.sampleSite(customerNumber: customer.customerNumber)
        let catalogItems = InvoicePreviewFactory.sampleCatalogItems()
        let invoice = InvoicePreviewFactory.sampleInvoice(catalogItems: catalogItems)
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

private struct PFSSPDFDocumentPreview: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: fileURL)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != fileURL else { return }
        view.document = PDFDocument(url: fileURL)
    }
}
