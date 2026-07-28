//
//  BluetoothPrinter.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/24/26.
//

import Foundation
import CoreBluetooth
import Combine
import UIKit

enum BluetoothPrinterConnectionState: Equatable {
    case idle
    case scanning
    case connecting(String)
    case ready(String)
    case failed(String)
}

struct BluetoothPrinterDiscoveryClassifier {
    static func isLikelyPrinter(
        name: String?,
        advertisedServiceUUIDs: [String]
    ) -> Bool {
        let services = Set(advertisedServiceUUIDs.map {
            $0.uppercased().replacingOccurrences(of: "-", with: "")
        })
        if services.contains("18F0") { return true }

        let normalizedName = (name ?? "")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty else { return false }

        let descriptiveTerms = [
            "PRINTER", "THERMAL", "RECEIPT", "POS PRINTER", "BTPRINTER"
        ]
        if descriptiveTerms.contains(where: normalizedName.contains) {
            return true
        }

        let commonPrinterPrefixes = [
            "RPP", "MTP", "MPT", "RP-", "PT-", "XP-"
        ]
        return commonPrinterPrefixes.contains(where: normalizedName.hasPrefix)
    }
}

final class BluetoothPrinter: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var devices: [CBPeripheral] = []
    @Published var isReadyToPrint = false
    @Published private(set) var hiddenDeviceCount = 0
    @Published private(set) var connectionState: BluetoothPrinterConnectionState = .idle
    @Published var showsAllNearbyDevices = false {
        didSet { refreshVisibleDevices() }
    }

    private struct DiscoveredDevice {
        var peripheral: CBPeripheral
        var advertisedName: String?
        var advertisedServiceUUIDs: [String]
        var rssi: Int
        var isLikelyPrinter: Bool
    }

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var discoveredDevices: [UUID: DiscoveredDevice] = [:]

    private let printerServiceUUID = CBUUID(string: "18F0")
    private let printerWriteUUID = CBUUID(string: "2AF1")
    private let verifiedPrinterIdentifierKey = "pfss.verifiedPrinterIdentifier"

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
        if !isReadyToPrint {
            connectionState = .scanning
        }
        discoveredDevices.removeAll()
        refreshVisibleDevices()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func displayName(for peripheral: CBPeripheral) -> String {
        let discoveredName = discoveredDevices[peripheral.identifier]?
            .advertisedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let discoveredName, !discoveredName.isEmpty {
            return discoveredName
        }

        let peripheralName = peripheral.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let peripheralName, !peripheralName.isEmpty {
            return peripheralName
        }

        return "Unnamed Bluetooth Device"
    }

    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        isReadyToPrint = false
        writeCharacteristic = nil
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting(displayName(for: peripheral))
        centralManager.connect(peripheral, options: nil)
    }

    @discardableResult
    func printReceiptText(_ text: String) -> Bool {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            return false
        }

        var data = Data()
        data.append(contentsOf: [0x1B, 0x40])

        // Logo temporarily disabled

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("TOTAL:") {
                data.append(contentsOf: [0x1B, 0x61, 0x01])
                data.append(contentsOf: [0x1D, 0x21, 0x11])
                data.append(line.data(using: .ascii) ?? Data())
                data.append("\n".data(using: .ascii) ?? Data())
                data.append(contentsOf: [0x1D, 0x21, 0x00])
                data.append(contentsOf: [0x1B, 0x61, 0x00])
            } else {
                data.append(line.data(using: .ascii) ?? Data())
                data.append("\n".data(using: .ascii) ?? Data())
            }
        }

        data.append("\n\n\n\n\n".data(using: .ascii) ?? Data())
        data.append(contentsOf: [0x1B, 0x64, 0x05])

        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        return true
    }

    private func logoRasterData(named imageName: String) -> Data? {
        guard let image = UIImage(named: imageName),
              let cgImage = image.cgImage else {
            print("Logo not found.")
            return nil
        }

        let targetWidth = 240
        let scale = CGFloat(targetWidth) / CGFloat(cgImage.width)
        let targetHeight = Int(CGFloat(cgImage.height) * scale)

        let size = CGSize(width: targetWidth, height: targetHeight)
        let renderer = UIGraphicsImageRenderer(size: size)

        let resizedImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let resizedCG = resizedImage.cgImage else { return nil }

        let width = resizedCG.width
        let height = resizedCG.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(resizedCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bytesPerImageRow = (width + 7) / 8
        var imageBytes = [UInt8](repeating: 0, count: bytesPerImageRow * height)

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4
                let r = pixels[pixelIndex]
                let g = pixels[pixelIndex + 1]
                let b = pixels[pixelIndex + 2]

                let gray = (UInt16(r) + UInt16(g) + UInt16(b)) / 3

                if gray < 160 {
                    let byteIndex = y * bytesPerImageRow + x / 8
                    imageBytes[byteIndex] |= 0x80 >> UInt8(x % 8)
                }
            }
        }

        var data = Data()

        data.append(contentsOf: [0x1B, 0x61, 0x01])

        let xL = UInt8(bytesPerImageRow & 0xFF)
        let xH = UInt8((bytesPerImageRow >> 8) & 0xFF)
        let yL = UInt8(height & 0xFF)
        let yH = UInt8((height >> 8) & 0xFF)

        data.append(contentsOf: [0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH])
        data.append(contentsOf: imageBytes)

        data.append(contentsOf: [0x1B, 0x61, 0x00])

        return data
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey]
            as? String
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey]
            as? [CBUUID] ?? []).map(\.uuidString)
        let bestName = advertisedName ?? peripheral.name
        let isRememberedPrinter = UserDefaults.standard.string(
            forKey: verifiedPrinterIdentifierKey
        ) == peripheral.identifier.uuidString
        let isLikelyPrinter = isRememberedPrinter ||
            BluetoothPrinterDiscoveryClassifier.isLikelyPrinter(
                name: bestName,
                advertisedServiceUUIDs: serviceUUIDs
            )

        discoveredDevices[peripheral.identifier] = DiscoveredDevice(
            peripheral: peripheral,
            advertisedName: advertisedName,
            advertisedServiceUUIDs: serviceUUIDs,
            rssi: RSSI.intValue,
            isLikelyPrinter: isLikelyPrinter
        )
        refreshVisibleDevices()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([printerServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        isReadyToPrint = false
        connectionState = .failed(
            error?.localizedDescription ??
            "PFSS could not connect to \(displayName(for: peripheral))."
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard connectedPeripheral?.identifier == peripheral.identifier else {
            return
        }
        isReadyToPrint = false
        writeCharacteristic = nil
        connectionState = error == nil
            ? .idle
            : .failed(error?.localizedDescription ?? "Printer disconnected.")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([printerWriteUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == printerWriteUUID {
                writeCharacteristic = characteristic
                isReadyToPrint = true
                connectionState = .ready(displayName(for: peripheral))
                UserDefaults.standard.set(
                    peripheral.identifier.uuidString,
                    forKey: verifiedPrinterIdentifierKey
                )
                if var device = discoveredDevices[peripheral.identifier] {
                    device.isLikelyPrinter = true
                    discoveredDevices[peripheral.identifier] = device
                    refreshVisibleDevices()
                }
            }
        }


        if writeCharacteristic == nil {
            isReadyToPrint = false
            connectionState = .failed(
                "\(displayName(for: peripheral)) does not expose the supported receipt-printer connection."
            )
        }
    }

    private func refreshVisibleDevices() {
        let allDevices = Array(discoveredDevices.values)
        let likelyPrinters = allDevices.filter(\.isLikelyPrinter)
        hiddenDeviceCount = allDevices.count - likelyPrinters.count

        let visibleDevices = showsAllNearbyDevices ? allDevices : likelyPrinters
        devices = visibleDevices.sorted { first, second in
            let firstName = displayName(for: first.peripheral)
            let secondName = displayName(for: second.peripheral)
            let comparison = firstName.localizedCaseInsensitiveCompare(secondName)
            if comparison == .orderedSame {
                return first.rssi > second.rssi
            }
            return comparison == .orderedAscending
        }.map(\.peripheral)
    }
}
