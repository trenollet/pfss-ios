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
    
    var body: some View {
        Form {
            Section("Estimate") {
                Text(estimate.estimateNumber)
                    .font(.headline)
                
                Picker("Status", selection: $estimate.status) {
                    ForEach(EstimateRecordStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                
                DatePicker("Expiration Date", selection: $estimate.expirationDate, displayedComponents: .date)
            }
            
            Section("Service") {
                Picker("Service Type", selection: $estimate.serviceType) {
                    ForEach(ServiceType.allCases) { service in
                        Text(service.rawValue).tag(service)
                    }
                }
                
                if estimate.serviceType == .other {
                    TextField("Other Service", text: $estimate.otherService)
                }
                
                TextField("Service Details", text: $estimate.serviceDetails, axis: .vertical)
                    .lineLimit(3...6)
            }
            
            Section("Pricing") {
                TextField("Subtotal", value: $estimate.subtotal, format: .number)
                    .keyboardType(.decimalPad)
                
                TextField("Discount", value: $estimate.discount, format: .number)
                    .keyboardType(.decimalPad)
                
                HStack {
                    Text("Total")
                    Spacer()
                    Text(max(estimate.subtotal - estimate.discount, 0), format: .currency(code: "USD"))
                        .bold()
                }
            }
            
            Section {
                Button("Save Changes") {
                    estimate.total = max(estimate.subtotal - estimate.discount, 0)
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
            .navigationTitle("Edit Estimate")
        }
    }
}
