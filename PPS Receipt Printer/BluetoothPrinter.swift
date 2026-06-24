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
    }

    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func printReceiptText(_ text: String) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            return
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
        if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
            devices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([printerServiceUUID])
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
            }
        }
    }
}
