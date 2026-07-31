//
//  PPS_Receipt_PrinterApp.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 6/23/26.
//

import SwiftUI
import UIKit

@main
@MainActor
struct PPS_Receipt_PrinterApp: App {
    @StateObject private var store: AppDataStore
    @StateObject private var printer = BluetoothPrinter()

    init() {
        _store = StateObject(
            wrappedValue: PFSSCloudflareAppDataStoreFactory.make()
        )
    }

    var body: some Scene {
        WindowGroup {
            PFSSProtectedRootView()
                .environmentObject(store)
                .environmentObject(printer)
        }
    }
}

private struct PFSSProtectedRootView: View {
    @State private var isCompanyDataRemovalPending =
        PFSSCompanyDataRemovalCoordinator.shared.isRemovalPending
    @State private var needsCompanyActivation =
        !PFSSCloudflareBetaManager().isEnrolled
    @State private var isShowingRemovalMessage = false

    var body: some View {
        Group {
            if isCompanyDataRemovalPending {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Securing Company Data")
                        .font(.headline)
                    Text(
                        "PFSS is removing company information from this device."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding()
            } else if needsCompanyActivation {
                PFSSCompanyActivationView()
            } else {
                ContentView()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .pfssCompanyDataRemovalStateDidChange
            )
        ) { _ in
            isCompanyDataRemovalPending =
                PFSSCompanyDataRemovalCoordinator.shared.isRemovalPending
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .pfssCompanyDataWasRemoved
            )
        ) { _ in
            needsCompanyActivation = true
            isShowingRemovalMessage = true
        }
        .alert(
            "Company Access Removed",
            isPresented: $isShowingRemovalMessage
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(
                "This device no longer has access to company information. Enter a new activation code only after an administrator adds this device to an employee profile."
            )
        }
    }
}

private struct PFSSCompanyActivationView: View {
    @StateObject private var manager = PFSSCloudflareBetaManager()
    @State private var enrollmentCode = ""
    @State private var isActivating = false
    @State private var messageTitle = ""
    @State private var message = ""
    @State private var isShowingMessage = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "No Company Access",
                            systemImage: "lock.shield"
                        )
                        .font(.headline)
                        Text(
                            "Contact your system administrator to have this device added to your employee profile."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    SecureField(
                        "One-time activation code",
                        text: $enrollmentCode
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        activate()
                    } label: {
                        Label(
                            isActivating ? "Activating" : "Activate Company Access",
                            systemImage: "person.badge.key.fill"
                        )
                    }
                    .disabled(
                        isActivating || enrollmentCode.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                } header: {
                    Text("Activate This Device")
                } footer: {
                    Text(
                        "Activation codes are single-use and must be created from the employee's Company Access page."
                    )
                }
            }
            .navigationTitle("Device Activation")
            .alert(messageTitle, isPresented: $isShowingMessage) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(message)
            }
        }
    }

    private func activate() {
        isActivating = true
        Task {
            defer { isActivating = false }
            do {
                try await manager.enroll(
                    code: enrollmentCode,
                    deviceName: UIDevice.current.name
                )
                enrollmentCode = ""
                messageTitle = "Company Access Activated"
                message = "Close and reopen PFSS to securely load the company workspace."
            } catch {
                messageTitle = "Unable to Activate Device"
                message = error.localizedDescription
            }
            isShowingMessage = true
        }
    }
}
