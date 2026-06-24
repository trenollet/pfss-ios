import SwiftUI
import CoreBluetooth
import Combine

enum DocumentType: String, CaseIterable, Identifiable {
    case estimate = "Estimate"
    case invoice = "Invoice"
    case receipt = "Receipt"
    var id: String { rawValue }
}

enum PaymentStatus: String, CaseIterable, Identifiable {
    case unpaid = "Unpaid"
    case paid = "Paid"
    case depositPaid = "Deposit Paid"
    var id: String { rawValue }
}

enum ServiceType: String, CaseIterable, Identifiable {
    case windowCleaning = "Window Cleaning"
    case pressureWashing = "Pressure Washing"
    case gutterCleaning = "Gutter Cleaning"
    case handymanServices = "Handyman Services"
    case other = "Other"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var printer = BluetoothPrinter()

    @State private var documentType: DocumentType = .estimate
    @State private var customerName = ""
    @State private var address = ""
    @State private var phone = ""

    @State private var serviceType: ServiceType = .windowCleaning
    @State private var otherService = ""
    @State private var serviceDetails = ""

    @State private var subtotal = ""
    @State private var discount = ""
    @State private var paymentStatus: PaymentStatus = .unpaid
    @State private var notes = ""

    private var subtotalValue: Double {
        Double(subtotal) ?? 0
    }

    private var discountValue: Double {
        Double(discount) ?? 0
    }

    private var totalValue: Double {
        max(subtotalValue - discountValue, 0)
    }

    private var selectedServiceName: String {
        if serviceType == .other {
            return otherService.isEmpty ? "Other" : otherService
        }
        return serviceType.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Printer") {
                    Button("Scan for Printer") {
                        printer.startScan()
                    }

                    ForEach(printer.devices, id: \.identifier) { device in
                        Button(device.name ?? "Unknown Device") {
                            printer.connect(to: device)
                        }
                    }

                    Text(printer.isReadyToPrint ? "Printer Ready" : "Printer Not Connected")
                        .foregroundStyle(printer.isReadyToPrint ? .green : .red)
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

                Section("Customer") {
                    TextField("Customer Name", text: $customerName)
                    TextField("Address", text: $address)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("Service") {
                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }

                    if serviceType == .other {
                        TextField("Other Service", text: $otherService)
                    }

                    TextField("Service Details", text: $serviceDetails, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Pricing") {
                    TextField("Subtotal", text: $subtotal)
                        .keyboardType(.decimalPad)

                    TextField("Discount", text: $discount)
                        .keyboardType(.decimalPad)

                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalValue, format: .currency(code: "USD"))
                            .fontWeight(.bold)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Print \(documentType.rawValue)") {
                        printer.printDocument(
                            type: documentType,
                            customerName: customerName,
                            address: address,
                            phone: phone,
                            serviceName: selectedServiceName,
                            serviceDetails: serviceDetails,
                            subtotal: subtotalValue,
                            discount: discountValue,
                            total: totalValue,
                            paymentStatus: paymentStatus,
                            notes: notes
                        )
                    }
                    .disabled(!printer.isReadyToPrint)
                }
            }
            .navigationTitle("PPS Field App")
        }
    }
}

final class BluetoothPrinter: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [CBPeripheral] = []
    @Published var isReadyToPrint = false

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    private let printerServiceUUID = CBUUID(string: "18F0")
    private let printerWriteUUID = CBUUID(string: "2AF1")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        }
    }

    func startScan() {
        isReadyToPrint = false
        writeCharacteristic = nil
        devices.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        print("Scanning...")
    }

    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        print("Connecting to \(peripheral.name ?? "Unknown Device")...")
    }

    func printDocument(
        type: DocumentType,
        customerName: String,
        address: String,
        phone: String,
        serviceName: String,
        serviceDetails: String,
        subtotal: Double,
        discount: Double,
        total: Double,
        paymentStatus: PaymentStatus,
        notes: String
    ) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            print("Printer is not ready.")
            return
        }

        var data = Data()

        data.append(contentsOf: [0x1B, 0x40])
        data.append(center())
        data.append(boldOn())
        data.append("PATRIOT PROPERTY SOLUTIONS\n".data(using: .ascii)!)
        data.append(boldOff())
        data.append("Veteran Owned & Operated\n".data(using: .ascii)!)
        data.append("www.patriot-ok.com\n".data(using: .ascii)!)
        data.append(left())

        data.append("--------------------------------\n".data(using: .ascii)!)
        data.append(center())
        data.append(boldOn())
        data.append("\(type.rawValue.uppercased())\n".data(using: .ascii)!)
        data.append(boldOff())
        data.append(left())
        data.append("--------------------------------\n".data(using: .ascii)!)

        data.append("Customer: \(customerName)\n".data(using: .ascii)!)
        data.append("Address: \(address)\n".data(using: .ascii)!)
        data.append("Phone: \(phone)\n".data(using: .ascii)!)
        data.append("--------------------------------\n".data(using: .ascii)!)

        data.append("Service: \(serviceName)\n".data(using: .ascii)!)

        if !serviceDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data.append("Details:\n\(serviceDetails)\n".data(using: .ascii)!)
        }

        data.append("--------------------------------\n".data(using: .ascii)!)
        data.append("Subtotal: \(money(subtotal))\n".data(using: .ascii)!)

        if discount > 0 {
            data.append("Discount: -\(money(discount))\n".data(using: .ascii)!)
        }

        data.append(boldOn())
        data.append("Total: \(money(total))\n".data(using: .ascii)!)
        data.append(boldOff())

        data.append("Status: \(paymentStatus.rawValue)\n".data(using: .ascii)!)

        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data.append("--------------------------------\n".data(using: .ascii)!)
            data.append("Notes:\n\(notes)\n".data(using: .ascii)!)
        }

        data.append("--------------------------------\n".data(using: .ascii)!)

        switch type {
        case .estimate:
            data.append("Estimate valid for 30 days.\n".data(using: .ascii)!)
        case .invoice:
            data.append("Payment due upon completion.\n".data(using: .ascii)!)
        case .receipt:
            data.append("Thank you for your business!\n".data(using: .ascii)!)
        }

        data.append("\n\n\n".data(using: .ascii)!)

        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        print("Sent \(type.rawValue).")
    }

    private func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func center() -> Data {
        Data([0x1B, 0x61, 0x01])
    }

    private func left() -> Data {
        Data([0x1B, 0x61, 0x00])
    }

    private func boldOn() -> Data {
        Data([0x1B, 0x45, 0x01])
    }

    private func boldOff() -> Data {
        Data([0x1B, 0x45, 0x00])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
            devices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown Device")")
        peripheral.discoverServices([printerServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Service discovery error: \(error.localizedDescription)")
            return
        }

        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([printerWriteUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("Characteristic discovery error: \(error.localizedDescription)")
            return
        }

        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == printerWriteUUID {
                writeCharacteristic = characteristic
                isReadyToPrint = true
                print("Printer is ready to print.")
            }
        }
    }
}
