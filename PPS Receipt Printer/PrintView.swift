//
//  PrintView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import SwiftUI
import CoreBluetooth

struct PrintView: View {
    @EnvironmentObject var store: AppDataStore
    @EnvironmentObject var printer: BluetoothPrinter

    @State private var selectedCustomerNumber = ""
    @State private var selectedSiteID: UUID?
    @State private var documentType: DocumentType = .estimate
    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var serviceDetails = ""
    @State private var subtotal = ""
    @State private var discount = ""
    @State private var paymentStatus: PaymentStatus = .unpaid
    @State private var notes = ""

    @FocusState private var isInputFocused: Bool

    private let lineWidth = 48

    private var subtotalValue: Double { Double(subtotal) ?? 0 }
    private var discountValue: Double { Double(discount) ?? 0 }
    private var totalValue: Double { max(subtotalValue - discountValue, 0) }

    private var selectedCustomer: Customer? {
        store.customers.first { $0.customerNumber == selectedCustomerNumber }
    }

    private var availableSites: [CustomerSite] {
        store.sites(for: selectedCustomerNumber)
    }

    private var selectedSite: CustomerSite? {
        availableSites.first { $0.id == selectedSiteID }
    }

    private var selectedServiceName: String {
        serviceType == .other ? (otherService.isEmpty ? "Other" : otherService) : serviceType.rawValue
    }

    var body: some View {
        Form {
                Section("Printer") {
                    Button("Scan for Printer") {
                        printer.startScan()
                    }

                    ForEach(printer.devices, id: \.identifier) { device in
                        Button {
                            printer.connect(to: device)
                        } label: {
                            Text(device.name ?? "Unknown Device")
                        }
                    }

                    Text(printer.isReadyToPrint ? "Printer Ready" : "Printer Not Connected")
                        .foregroundStyle(printer.isReadyToPrint ? .green : .red)
                }

                Section("Customer / Site") {
                    Picker("Customer", selection: $selectedCustomerNumber) {
                        Text("Select Customer").tag("")
                        ForEach(store.customers) { customer in
                            Text(customerName(customer)).tag(customer.customerNumber)
                        }
                    }

                    Picker("Site", selection: $selectedSiteID) {
                        Text("Select Site").tag(UUID?.none)
                        ForEach(availableSites) { site in
                            Text(site.siteName.isEmpty ? site.serviceAddress : site.siteName)
                                .tag(Optional(site.id))
                        }
                    }
                }

                Section("Document") {
                    Picker("Type", selection: $documentType) {
                        ForEach(DocumentType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Picker("Payment", selection: $paymentStatus) {
                        ForEach(PaymentStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }

                Section("Service") {
                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }

                    if serviceType == .other {
                        TextField("Other Service", text: $otherService)
                            .focused($isInputFocused)
                    }

                    TextField("Service Details", text: $serviceDetails, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isInputFocused)
                }

                Section("Pricing") {
                    TextField("Subtotal", text: $subtotal)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    TextField("Discount", text: $discount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)

                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalValue, format: .currency(code: "USD"))
                            .bold()
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isInputFocused)
                }

                Section {
                    Button("Print \(documentType.rawValue)") {
                        isInputFocused = false
                        printer.printReceiptText(buildPrintText())
                    }
                    .disabled(!printer.isReadyToPrint || selectedCustomer == nil)
                }
            }
            .navigationTitle("Print")
            .toolbar {
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

    private func buildPrintText() -> String {
        var lines: [String] = []

        lines.append(center("PATRIOT PROPERTY SOLUTIONS"))
        lines.append(center("Veteran Owned & Operated"))
        lines.append(center("www.patriot-ok.com"))
        lines.append(divider())
        lines.append(center(documentType.rawValue.uppercased()))
        lines.append(divider())

        if let customer = selectedCustomer {
            lines.append("Customer #: \(customer.customerNumber)")
            if !customer.businessName.isEmpty {
                lines.append("Business: \(customer.businessName)")
            }
            lines.append("Contact: \(customer.contactName)")
            lines.append("Phone: \(customer.phone)")
            lines.append("Email: \(customer.email)")
        }

        if let site = selectedSite {
            lines.append(divider())
            lines.append("Site: \(site.siteName)")
            lines.append("Address: \(site.serviceAddress)")
            if !site.propertyType.isEmpty {
                lines.append("Property: \(site.propertyType)")
            }
        }

        lines.append(divider())
        lines.append("Service: \(selectedServiceName)")

        if !serviceDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Details:")
            lines.append(contentsOf: wrap(serviceDetails))
        }

        lines.append(divider())
        lines.append(row("Subtotal:", money(subtotalValue)))

        if discountValue > 0 {
            lines.append(row("Discount:", "-\(money(discountValue))"))
        }

        lines.append(divider())
        lines.append(row("TOTAL:", money(totalValue)))
        lines.append(divider())
        lines.append("Status: \(paymentStatus.rawValue)")
        
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(divider())
            lines.append("Notes:")
            lines.append(contentsOf: wrap(notes))
        }

        lines.append(divider())

        switch documentType {
        case .estimate:
            lines.append("Estimate valid for 30 days.")
        case .invoice:
            lines.append("Payment due upon completion.")
        case .receipt:
            lines.append("Thank you for your business!")
        }

        return lines.joined(separator: "\n")
    }

    private func customerName(_ customer: Customer) -> String {
        customer.businessName.isEmpty ? customer.contactName : customer.businessName
    }

    private func divider() -> String {
        String(repeating: "-", count: lineWidth)
    }

    private func center(_ text: String) -> String {
        let trimmed = String(text.prefix(lineWidth))
        let padding = max((lineWidth - trimmed.count) / 2, 0)
        return String(repeating: " ", count: padding) + trimmed
    }

    private func row(_ left: String, _ right: String) -> String {
        let spaceCount = max(lineWidth - left.count - right.count, 1)
        return left + String(repeating: " ", count: spaceCount) + right
    }

    private func wrap(_ text: String) -> [String] {
        var result: [String] = []
        var currentLine = ""

        for word in text.split(separator: " ") {
            if currentLine.count + word.count + 1 > lineWidth {
                result.append(currentLine)
                currentLine = String(word)
            } else {
                currentLine += currentLine.isEmpty ? String(word) : " \(word)"
            }
        }

        if !currentLine.isEmpty {
            result.append(currentLine)
        }

        return result
    }

    private func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
