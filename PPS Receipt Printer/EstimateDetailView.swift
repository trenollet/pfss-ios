//
//  EstimateDetailView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct EstimateDetailView: View {
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State var estimate: EstimateRecord
    @FocusState private var isInputFocused: Bool

    private var subtotalValue: Double {
        PricingCalculator.subtotal(for: estimate)
    }

    private var totalValue: Double {
        PricingCalculator.total(for: estimate)
    }

    var body: some View {
        Form {
            Section("Estimate") {
                Text(estimate.estimateNumber)
                    .font(.headline)

                Text("Customer #: \(estimate.customerNumber)")

                if !estimate.leadNumber.isEmpty {
                    Text("Lead: \(estimate.leadNumber)")
                }

                Picker("Status", selection: $estimate.status) {
                    ForEach(EstimateRecordStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                DatePicker("Expiration Date", selection: $estimate.expirationDate, displayedComponents: .date)
            }

            WorkOrderEditorView(lineItems: $estimate.lineItems, isInputFocused: $isInputFocused)

            Section("Pricing") {
                TextField("Discount", value: $estimate.discount, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)

                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotalValue, format: .currency(code: "USD"))
                        .bold()
                }

                HStack {
                    Text("Total")
                    Spacer()
                    Text(totalValue, format: .currency(code: "USD"))
                        .bold()
                }
            }

            Section {
                Button("Create Job from Estimate") {
                    estimate.lineItems = PricingCalculator.updatedLineItems(estimate.lineItems)
                    estimate.subtotal = subtotalValue
                    estimate.total = totalValue

                    store.updateEstimate(estimate)
                    store.createJobFromEstimate(estimate)
                    dismiss()
                }
                .disabled(estimate.lifecycleStatus == .archived)

                Button("Save Changes") {
                    isInputFocused = false

                    estimate.lineItems = PricingCalculator.updatedLineItems(estimate.lineItems)
                    estimate.subtotal = PricingCalculator.subtotal(for: estimate)
                    estimate.total = PricingCalculator.total(for: estimate)

                    if let firstItem = estimate.lineItems.first {
                        estimate.serviceType = firstItem.serviceType
                        estimate.otherService = firstItem.otherService
                    }

                    estimate.serviceDetails = estimate.lineItems.map { item in
                        item.description.isEmpty ? serviceName(for: item) : item.description
                    }.joined(separator: "\n")

                    store.updateEstimate(estimate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                if estimate.lifecycleStatus == .archived {
                    Button("Restore Estimate") {
                        store.restoreEstimate(estimate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Archive Estimate", role: .destructive) {
                        store.archiveEstimate(estimate)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Edit Estimate")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
    }

    private func serviceName(for item: ServiceLineItem) -> String {
        if item.serviceType == .other {
            return item.otherService.isEmpty ? "Other" : item.otherService
        }

        return item.serviceType.rawValue
    }
}
