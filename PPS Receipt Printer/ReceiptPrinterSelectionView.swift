//
//  ReceiptPrinterSelectionView.swift
//  PPS Receipt Printer
//
//  Focused printer selection and automatic receipt handoff.
//

import SwiftUI
import CoreBluetooth

struct ReceiptPrinterSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var printer: BluetoothPrinter

    let receiptText: String

    @State private var isWaitingToPrint = false
    @State private var didPrint = false
    @State private var selectedPrinterID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    connectionStatus

                    if printer.isReadyToPrint {
                        Button {
                            printAndConfirm()
                        } label: {
                            Label(
                                "Print Receipt Now",
                                systemImage: "printer.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            printer.startScan()
                        } label: {
                            Label(
                                "Scan for Receipt Printers",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    }
                } header: {
                    Text("Print Status")
                } footer: {
                    Text(
                        "Select a printer below. PFSS will print automatically as soon as the connection is ready."
                    )
                }

                Section {
                    if printer.devices.isEmpty && !printer.isReadyToPrint {
                        ContentUnavailableView(
                            "Searching for Printers",
                            systemImage: "printer",
                            description: Text(
                                "Keep the receipt printer powered on and nearby."
                            )
                        )
                    } else {
                        ForEach(printer.devices, id: \.identifier) { device in
                            Button {
                                selectedPrinterID = device.identifier
                                isWaitingToPrint = true
                                printer.connect(to: device)
                            } label: {
                                HStack {
                                    Label(
                                        printer.displayName(for: device),
                                        systemImage: "printer.fill"
                                    )
                                    Spacer()
                                    if selectedPrinterID == device.identifier &&
                                        isWaitingToPrint {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isWaitingToPrint)
                        }
                    }

                    if printer.hiddenDeviceCount > 0 ||
                        printer.showsAllNearbyDevices {
                        Button {
                            printer.showsAllNearbyDevices.toggle()
                        } label: {
                            Label(
                                printer.showsAllNearbyDevices
                                    ? "Hide Other Bluetooth Devices"
                                    : "Show \(printer.hiddenDeviceCount) Other Bluetooth Devices",
                                systemImage: printer.showsAllNearbyDevices
                                    ? "eye.slash"
                                    : "eye"
                            )
                        }
                    }
                } header: {
                    Text("Available Printers")
                }
            }
            .navigationTitle("Print Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !printer.isReadyToPrint {
                    printer.startScan()
                }
            }
            .onChange(of: printer.isReadyToPrint) { _, isReady in
                guard isReady, isWaitingToPrint else { return }
                printAndConfirm()
            }
            .alert("Receipt Printed", isPresented: $didPrint) {
                Button("Done") { dismiss() }
                Button("Print Another Copy") { }
            } message: {
                Text("PFSS sent the receipt to the selected printer.")
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch printer.connectionState {
        case .idle:
            Label("Select a receipt printer", systemImage: "printer")
                .foregroundStyle(.secondary)
        case .scanning:
            HStack {
                ProgressView()
                Text("Searching for receipt printers…")
            }
        case .connecting(let name):
            HStack {
                ProgressView()
                Text("Connecting to \(name)…")
            }
        case .ready(let name):
            Label("Ready: \(name)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func printAndConfirm() {
        isWaitingToPrint = false
        guard printer.printReceiptText(receiptText) else { return }
        didPrint = true
    }
}
