import SwiftUI

enum CompactWorkOrderEditorDestination: String, Identifiable {
    case customerInfo
    case title
    case pricing
    case scope

    var id: String { rawValue }
}

struct CompactCustomerInfoSection: View {
    @EnvironmentObject private var store: AppDataStore

    @Binding var leadNumber: String
    @Binding var customerNumber: String
    @Binding var siteID: UUID?
    @Binding var salesperson: String
    @Binding var expirationDate: Date
    let onSelect: () -> Void

    private var recipientName: String {
        if !customerNumber.isEmpty,
           let customer = store.customers.first(where: {
               $0.customerNumber == customerNumber
           }) {
            if !customer.businessName.isEmpty { return customer.businessName }
            if !customer.contactName.isEmpty { return customer.contactName }
        }

        if !leadNumber.isEmpty,
           let lead = store.leads.first(where: {
               $0.leadNumber == leadNumber
           }) {
            if !lead.businessName.isEmpty { return lead.businessName }
            if !lead.contactName.isEmpty { return lead.contactName }
        }

        return "Click to Select Customer"
    }

    var body: some View {
        Section("Customer Info") {
            Button {
                onSelect()
            } label: {
                CompactNavigationRow(
                    text: recipientName,
                    isPlaceholder: customerNumber.isEmpty && leadNumber.isEmpty
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct CompactTitleSection: View {
    @Binding var title: String
    let onSelect: () -> Void

    private var summary: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Click to enter Title" : trimmed
    }

    var body: some View {
        Section("Title") {
            Button {
                onSelect()
            } label: {
                CompactNavigationRow(
                    text: summary,
                    isPlaceholder: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct CompactPricingSection: View {
    @Binding var method: PricingDiscountMethod
    @Binding var inputValue: Double
    let subtotal: Double
    let onSelect: () -> Void

    private var discount: Double {
        DiscountCalculator.amount(
            subtotal: subtotal,
            method: method,
            inputValue: inputValue
        )
    }

    private var total: Double {
        PricingCalculator.total(subtotal: subtotal, discount: discount)
    }

    var body: some View {
        Section("Pricing") {
            Button {
                onSelect()
            } label: {
                HStack {
                    Text("Total Price")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(total, format: .currency(code: "USD"))
                        .bold()
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct CompactScopeSection: View {
    @Binding var scope: String
    let onSelect: () -> Void

    private var summary: String {
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Click to add scope" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        Section("Scope of Work") {
            Button {
                onSelect()
            } label: {
                CompactNavigationRow(
                    text: summary,
                    isPlaceholder: scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompactNavigationRow: View {
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        HStack {
            Text(text)
                .lineLimit(1)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct CompactTextEditorSheet: View {
    let navigationTitle: String
    let placeholder: String
    let isMultiline: Bool
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String
    @FocusState private var isFocused: Bool

    init(
        navigationTitle: String,
        placeholder: String,
        originalText: String,
        isMultiline: Bool,
        onSave: @escaping (String) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.placeholder = placeholder
        self.isMultiline = isMultiline
        self.onSave = onSave
        _draftText = State(initialValue: originalText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isMultiline {
                        TextField(
                            placeholder,
                            text: $draftText,
                            axis: .vertical
                        )
                        .lineLimit(6...14)
                        .focused($isFocused)
                    } else {
                        TextField(placeholder, text: $draftText)
                            .focused($isFocused)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            draftText.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        )
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

struct CustomerInfoEditorSheet: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @Binding var leadNumber: String
    @Binding var customerNumber: String
    @Binding var siteID: UUID?
    @Binding var salesperson: String
    @Binding var expirationDate: Date

    @State private var draftLeadNumber: String
    @State private var draftCustomerNumber: String
    @State private var draftSiteID: UUID?
    @State private var draftSalesperson: String
    @State private var draftExpirationDate: Date

    init(
        leadNumber: Binding<String>,
        customerNumber: Binding<String>,
        siteID: Binding<UUID?>,
        salesperson: Binding<String>,
        expirationDate: Binding<Date>
    ) {
        _leadNumber = leadNumber
        _customerNumber = customerNumber
        _siteID = siteID
        _salesperson = salesperson
        _expirationDate = expirationDate
        _draftLeadNumber = State(initialValue: leadNumber.wrappedValue)
        _draftCustomerNumber = State(initialValue: customerNumber.wrappedValue)
        _draftSiteID = State(initialValue: siteID.wrappedValue)
        _draftSalesperson = State(initialValue: salesperson.wrappedValue)
        _draftExpirationDate = State(initialValue: expirationDate.wrappedValue)
    }

    private var customerOptions: [RecordSelectionOption] {
        store.customers
            .filter {
                $0.lifecycleStatus == .active ||
                $0.customerNumber == draftCustomerNumber
            }
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
            .map {
                RecordSelectionOption(
                    id: $0.customerNumber,
                    title: displayName($0),
                    subtitle: $0.customerNumber
                )
            }
    }

    private var leadOptions: [RecordSelectionOption] {
        store.leads
            .filter {
                $0.lifecycleStatus == .active ||
                $0.leadNumber == draftLeadNumber
            }
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
            .map {
                RecordSelectionOption(
                    id: $0.leadNumber,
                    title: displayName($0),
                    subtitle: $0.leadNumber
                )
            }
    }

    private var availableSites: [CustomerSite] {
        store.sites.filter {
            $0.customerNumber == draftCustomerNumber &&
            ($0.lifecycleStatus == .active || $0.id == draftSiteID)
        }
    }

    private var salesEmployees: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.hasRole(.salesperson) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer or Lead") {
                    SearchableRecordSelectionField(
                        title: "Customer",
                        placeholder: "None",
                        options: customerOptions,
                        selection: $draftCustomerNumber,
                        allowsNone: true
                    )
                    .onChange(of: draftCustomerNumber) { _, value in
                        if !value.isEmpty { draftLeadNumber = "" }
                        if !availableSites.contains(where: { $0.id == draftSiteID }) {
                            draftSiteID = nil
                        }
                    }

                    SearchableRecordSelectionField(
                        title: "Lead",
                        placeholder: "None",
                        options: leadOptions,
                        selection: $draftLeadNumber,
                        allowsNone: true
                    )
                    .onChange(of: draftLeadNumber) { _, value in
                        guard !value.isEmpty else { return }
                        draftCustomerNumber = ""
                        draftSiteID = nil
                    }
                }

                Section("Details") {
                    Picker("Site", selection: $draftSiteID) {
                        Text("No Site Selected").tag(UUID?.none)
                        ForEach(availableSites) { site in
                            Text(siteDisplayName(site)).tag(Optional(site.id))
                        }
                    }
                    .disabled(draftCustomerNumber.isEmpty)

                    Picker("Salesperson", selection: $draftSalesperson) {
                        Text("Unassigned").tag("")
                        ForEach(salesEmployees) { employee in
                            Text(employee.displayName).tag(employee.displayName)
                        }
                    }

                    DatePicker(
                        "Expiration",
                        selection: $draftExpirationDate,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Customer Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        leadNumber = draftLeadNumber
                        customerNumber = draftCustomerNumber
                        siteID = draftSiteID
                        salesperson = draftSalesperson
                        expirationDate = draftExpirationDate
                        dismiss()
                    }
                    .bold()
                    .disabled(
                        draftLeadNumber.isEmpty &&
                        draftCustomerNumber.isEmpty
                    )
                }
            }
        }
    }

    private func displayName(_ customer: Customer) -> String {
        if !customer.businessName.isEmpty { return customer.businessName }
        if !customer.contactName.isEmpty { return customer.contactName }
        return customer.customerNumber
    }

    private func displayName(_ lead: Lead) -> String {
        if !lead.businessName.isEmpty { return lead.businessName }
        if !lead.contactName.isEmpty { return lead.contactName }
        return lead.leadNumber
    }

    private func siteDisplayName(_ site: CustomerSite) -> String {
        if site.siteName.isEmpty { return site.serviceAddress }
        if site.serviceAddress.isEmpty { return site.siteName }
        return "\(site.siteName) — \(site.serviceAddress)"
    }
}

extension View {
    func compactWorkOrderEditorSheet(
        destination: Binding<CompactWorkOrderEditorDestination?>,
        leadNumber: Binding<String>,
        customerNumber: Binding<String>,
        siteID: Binding<UUID?>,
        salesperson: Binding<String>,
        expirationDate: Binding<Date>,
        title: Binding<String>,
        discountMethod: Binding<PricingDiscountMethod>,
        discountInputValue: Binding<Double>,
        subtotal: Double,
        scope: Binding<String>,
        store: AppDataStore
    ) -> some View {
        sheet(item: destination) { selectedDestination in
            switch selectedDestination {
            case .customerInfo:
                CustomerInfoEditorSheet(
                    leadNumber: leadNumber,
                    customerNumber: customerNumber,
                    siteID: siteID,
                    salesperson: salesperson,
                    expirationDate: expirationDate
                )
                .environmentObject(store)

            case .title:
                CompactTextEditorSheet(
                    navigationTitle: "Title",
                    placeholder: "Enter Title",
                    originalText: title.wrappedValue,
                    isMultiline: false
                ) { title.wrappedValue = $0 }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)

            case .pricing:
                DiscountEditorSheet(
                    title: "Pricing Options",
                    method: discountMethod,
                    inputValue: discountInputValue,
                    subtotal: subtotal
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)

            case .scope:
                CompactTextEditorSheet(
                    navigationTitle: "Scope of Work",
                    placeholder: "Enter Scope of Work",
                    originalText: scope.wrappedValue,
                    isMultiline: true
                ) { scope.wrappedValue = $0 }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
