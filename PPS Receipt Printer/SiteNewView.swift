import SwiftUI

struct SiteNewView: View {
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCustomerNumber = ""
    @State private var siteName = ""
    @State private var serviceAddress = ""
    @State private var propertyType = ""
    @State private var accessNotes = ""
    @State private var workNotes = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Site") {
                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.activeCustomers) { customer in
                            Text(customerDisplayName(customer)).tag(customer.customerNumber)
                        }
                    }
                    TextField("Site Name", text: $siteName).focused($isInputFocused)
                    TextField("Service Address", text: $serviceAddress).focused($isInputFocused)
                    TextField("Property Type", text: $propertyType).focused($isInputFocused)
                    TextField("Access Notes", text: $accessNotes, axis: .vertical)
                        .lineLimit(2...4).focused($isInputFocused)
                    TextField("Work Notes", text: $workNotes, axis: .vertical)
                        .lineLimit(3...6).focused($isInputFocused)
                }
            }
            .navigationTitle("New Site")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSite() }.disabled(selectedCustomerNumber.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { isInputFocused = false }
                }
            }
        }
    }

    private func saveSite() {
        isInputFocused = false
        store.addSite(CustomerSite(
            customerNumber: selectedCustomerNumber,
            siteName: siteName,
            serviceAddress: serviceAddress,
            propertyType: propertyType,
            accessNotes: accessNotes,
            workNotes: workNotes
        ))
        dismiss()
    }

    private func customerDisplayName(_ customer: Customer) -> String {
        let name = customer.businessName.isEmpty ? customer.contactName : customer.businessName
        return "\(name) - \(customer.customerNumber)"
    }
}
