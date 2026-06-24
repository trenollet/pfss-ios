//
//  DashboardView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: AppDataStore

    var body: some View {
        NavigationStack {
            List {
                Section("Sales") {
                    statRow("Customers", "\(store.customers.count)")
                    statRow("Sites", "\(store.sites.count)")
                    statRow("New Leads", "\(store.customers.filter { $0.estimateStatus == .newLead }.count)")
                    statRow("Approved", "\(store.customers.filter { $0.estimateStatus == .approved }.count)")
                }

                Section("Next Steps") {
                    Text("Add customers, add work sites, then create printable estimates, invoices, and receipts.")
                }
            }
            .navigationTitle("Dashboard")
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold()
        }
    }
}

