//
//  PPS_Receipt_PrinterApp.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/23/26.
//

import SwiftUI

@main
struct PPS_Receipt_PrinterApp: App {
    @StateObject private var store = AppDataStore()
    @StateObject private var printer = BluetoothPrinter()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(printer)
        }
    }
}
