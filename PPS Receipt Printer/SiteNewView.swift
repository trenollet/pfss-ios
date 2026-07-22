import SwiftUI

struct SiteNewView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    private static let builtInPropertyTypes = [
        "Retail",
        "Restaurant",
        "Office",
        "Home",
        "Warehouse",
        "Gas Station"
    ]
    private static let newPropertyTypeOption = "New Property Type"

    private let preselectedCustomerNumber: String?
    private let onSaved: ((CustomerSite) -> Void)?
    private let onCancel: (() -> Void)?

    @State private var selectedCustomerNumber: String
    @State private var siteName = ""
    @State private var serviceAddress = ""
    @State private var selectedPropertyType = ""
    @State private var newPropertyType = ""
    @State private var accessNotes = ""
    @State private var workNotes = ""
    @FocusState private var isInputFocused: Bool

    init(
        preselectedCustomerNumber: String? = nil,
        onSaved: ((CustomerSite) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.preselectedCustomerNumber = preselectedCustomerNumber
        self.onSaved = onSaved
        self.onCancel = onCancel
        _selectedCustomerNumber = State(
            initialValue: preselectedCustomerNumber ?? ""
        )
    }

    var body: some View {
        Form {
            Section("Site") {
                if preselectedCustomerNumber != nil {
                    LabeledContent(
                        "Customer",
                        value: selectedCustomerDisplayName
                    )
                } else {
                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.activeCustomers) { customer in
                            Text(customerDisplayName(customer))
                                .tag(customer.customerNumber)
                        }
                    }
                }

                TextField("Site Name", text: $siteName)
                    .focused($isInputFocused)
                TextField("Service Address", text: $serviceAddress)
                    .focused($isInputFocused)

                Picker("Property Type", selection: $selectedPropertyType) {
                    Text("Select Property Type").tag("")
                    ForEach(availablePropertyTypes, id: \.self) { propertyType in
                        Text(propertyType).tag(propertyType)
                    }
                }

                if selectedPropertyType == Self.newPropertyTypeOption {
                    TextField("New Property Type", text: $newPropertyType)
                        .focused($isInputFocused)
                }

                TextField("Access Notes", text: $accessNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($isInputFocused)
                TextField("Work Notes", text: $workNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isInputFocused)
            }
        }
        .navigationTitle("New Site")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveSite() }
                    .disabled(!canSave)
            }
            if isInputFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss Keyboard")
                }
            }
        }
    }

    private var availablePropertyTypes: [String] {
        let existingCustomTypes = Set(
            store.sites
                .map { $0.propertyType.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter {
                    !$0.isEmpty &&
                    !Self.builtInPropertyTypes.contains($0)
                }
        )

        return Self.builtInPropertyTypes +
            existingCustomTypes.sorted() +
            [Self.newPropertyTypeOption]
    }

    private var resolvedPropertyType: String {
        if selectedPropertyType == Self.newPropertyTypeOption {
            return newPropertyType.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return selectedPropertyType
    }

    private var canSave: Bool {
        !selectedCustomerNumber.isEmpty && !resolvedPropertyType.isEmpty
    }

    private var selectedCustomerDisplayName: String {
        guard let customer = store.customers.first(where: {
            $0.customerNumber == selectedCustomerNumber
        }) else {
            return "Customer Not Found"
        }

        return customerDisplayName(customer)
    }

    private func saveSite() {
        isInputFocused = false

        let site = CustomerSite(
            customerNumber: selectedCustomerNumber,
            siteName: siteName,
            serviceAddress: serviceAddress,
            propertyType: resolvedPropertyType,
            accessNotes: accessNotes,
            workNotes: workNotes
        )

        store.addSite(site)

        if let onSaved {
            onSaved(site)
        } else {
            dismiss()
        }
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func customerDisplayName(_ customer: Customer) -> String {
        if !customer.businessName.isEmpty {
            return customer.businessName
        }

        if !customer.contactName.isEmpty {
            return customer.contactName
        }

        return "Unnamed Customer"
    }
}
