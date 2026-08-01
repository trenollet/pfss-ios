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
    @StateObject private var printer = BluetoothPrinter()

    var body: some Scene {
        WindowGroup {
            PFSSAppSessionHost()
                .environmentObject(printer)
        }
    }
}

/// Recreates the complete company data session whenever device credentials
/// change. This lets activation, Owner sign-in, and logout transition in place
/// instead of requiring the process to be terminated and relaunched.
private struct PFSSAppSessionHost: View {
    @State private var sessionID = UUID()

    var body: some View {
        PFSSAppDataSessionView()
            .id(sessionID)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .pfssCompanyAccessWasActivated
                )
            ) { _ in
                sessionID = UUID()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .pfssUserDidLogOut
                )
            ) { _ in
                sessionID = UUID()
            }
    }
}

private struct PFSSAppDataSessionView: View {
    @StateObject private var store: AppDataStore

    init() {
        _store = StateObject(
            wrappedValue: PFSSCloudflareAppDataStoreFactory.make()
        )
    }

    var body: some View {
        PFSSProtectedRootView()
            .environmentObject(store)
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
                PFSSFirstRunView()
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: .pfssUserDidLogOut
            )
        ) { _ in
            needsCompanyActivation = true
            isShowingRemovalMessage = false
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

private struct PFSSFirstRunView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "building.2.crop.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        Text("Welcome to PFSS")
                            .font(.title2.weight(.semibold))
                        Text(
                            "Create a PFSS company, connect an employee device, or securely access an existing business."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Choose How to Begin") {
#if DEBUG
                    NavigationLink {
                        PFSSOwnerRegistrationStartView()
                    } label: {
                        firstRunOption(
                            "Create New Company",
                            detail: "First-time setup",
                            systemImage: "building.2.fill"
                        )
                    }
#endif

                    NavigationLink {
                        PFSSCompanyActivationView()
                    } label: {
                        firstRunOption(
                            "Activate Employee Device",
                            detail: "Add a new employee device to an existing company",
                            systemImage: "person.badge.key.fill"
                        )
                    }

                    NavigationLink {
                        PFSSExistingOwnerSignInView()
                    } label: {
                        firstRunOption(
                            "Sign In as Existing Business Owner",
                            detail: "Log in to a second or new device as the company owner",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }

                    NavigationLink {
                        PFSSOwnerInvitationAcceptanceView()
                    } label: {
                        firstRunOption(
                            "Accept Business Owner Invitation",
                            detail: "For businesses with more than one owner",
                            systemImage: "person.2.badge.gearshape"
                        )
                    }

                    NavigationLink {
                        PFSSOwnerRecoveryView()
                    } label: {
                        firstRunOption(
                            "Use Business Owner Recovery Code",
                            detail: "Enter a recovery code if a business owner's device is lost",
                            systemImage: "key.viewfinder"
                        )
                    }
                }

                Section {
                    Text(
                        "Employee activation uses a one-time code from an authorized Manager or Business Owner. New-company registration verifies the first Business Owner before creating company access."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Get Started")
        }
    }

    private func firstRunOption(
        _ title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 3)
    }
}

private struct PFSSOwnerInvitationAcceptanceView: View {
    @StateObject private var coordinator: PFSSOwnerAuthenticationCoordinator
    @StateObject private var browser = PFSSOwnerAuthenticationBrowser()
    @StateObject private var manager = PFSSCloudflareBetaManager()
    private let accountService = PFSSCloudflareOwnerAccountService()
    @State private var invitationCode = ""
    @State private var email = ""
    @State private var deviceName = UIDevice.current.name
    @State private var isWorking = false
    @State private var isShowingEmailNotice = false
    @State private var messageTitle = ""
    @State private var message = ""
    @State private var isShowingMessage = false

    init() {
        _coordinator = StateObject(wrappedValue:
            PFSSOwnerAuthenticationCoordinator(
                service: PFSSCloudflareOwnerAccountService(),
                redirectURI:
                    PFSSCloudflareOwnerAccountService.stagingRedirectURI
            )
        )
    }

    var body: some View {
        Form {
            Section {
                SecureField("Owner invitation code", text: $invitationCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("invited-owner@company.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("This device", text: $deviceName)
            } header: {
                Text("Join as an Owner")
            } footer: {
                Text(
                    "PFSS activates the invitation only after WorkOS verifies the exact email address selected by the inviting Owner."
                )
            }

            Section {
                Button {
                    isShowingEmailNotice = true
                } label: {
                    Label(
                        isWorking ? "Verifying Invitation" : "Verify and Join Company",
                        systemImage: "person.badge.shield.checkmark"
                    )
                }
                .disabled(
                    isWorking || invitationCode.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || deviceName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .navigationTitle("Owner Invitation")
        .disabled(isWorking)
        .alert(
            "Watch for Your Verification Email",
            isPresented: $isShowingEmailNotice
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") { acceptInvitation() }
        } message: {
            Text(
                "WorkOS will send a verification email. Check your Inbox and also your Junk or Spam folder if it does not arrive promptly."
            )
        }
        .alert(messageTitle, isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
        }
    }

    private func acceptInvitation() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let authorizationSession = try await coordinator.start(
                    emailHint: email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).lowercased(),
                    screenHint: "sign-in"
                )
                let callback = try await browser.authenticate(
                    at: authorizationSession.authorizationURL,
                    callbackURL:
                        PFSSCloudflareOwnerAccountService.stagingRedirectURI,
                    prefersEphemeralSession: true
                )
                let authorization = try coordinator.consumeCallback(callback)
                let identity = try await accountService.exchange(authorization)
                let receipt = try await accountService.acceptOwnerInvitation(
                    invitationCode: invitationCode,
                    identity: identity,
                    deviceID: manager.registrationDeviceID(),
                    deviceName: deviceName
                )
                try await manager.acceptProvisionedOwnerDevice(
                    token: receipt.deviceToken,
                    deviceID: receipt.deviceID
                )
                messageTitle = "Owner Access Activated"
                message = "This device is connected to \(receipt.tenantName) with independent Owner access."
            } catch {
                messageTitle = "Unable to Accept Invitation"
                message = error.localizedDescription
            }
            isShowingMessage = true
        }
    }
}

private struct PFSSOwnerRecoveryView: View {
    @StateObject private var manager = PFSSCloudflareBetaManager()
    private let accountService = PFSSCloudflareOwnerAccountService()
    @State private var recoveryCode = ""
    @State private var deviceName = UIDevice.current.name
    @State private var isWorking = false
    @State private var messageTitle = ""
    @State private var message = ""
    @State private var isShowingMessage = false

    var body: some View {
        Form {
            Section {
                SecureField("PFSS recovery code", text: $recoveryCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("This device", text: $deviceName)
            } header: {
                Text("Owner Account Recovery")
            } footer: {
                Text(
                    "Use one unused recovery code that was previously saved by an Owner. Each code can connect one device only once."
                )
            }

            Section {
                Button {
                    recover()
                } label: {
                    Label(
                        isWorking ? "Recovering Access" : "Recover Company Access",
                        systemImage: "lock.open.rotation"
                    )
                }
                .disabled(
                    isWorking ||
                    recoveryCode.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    deviceName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .navigationTitle("Owner Recovery")
        .disabled(isWorking)
        .alert(messageTitle, isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
        }
    }

    private func recover() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let receipt = try await accountService.recover(
                    recoveryCode: recoveryCode,
                    deviceID: manager.registrationDeviceID(),
                    deviceName: deviceName
                )
                try await manager.acceptProvisionedOwnerDevice(
                    token: receipt.deviceToken,
                    deviceID: receipt.deviceID
                )
                recoveryCode = ""
                messageTitle = "Company Access Recovered"
                message = "This device is connected to \(receipt.tenantName). The recovery code has been permanently consumed."
            } catch {
                messageTitle = "Unable to Recover Access"
                message = error.localizedDescription
            }
            isShowingMessage = true
        }
    }
}

private struct PFSSExistingOwnerSignInView: View {
    @StateObject private var coordinator: PFSSOwnerAuthenticationCoordinator
    @StateObject private var browser = PFSSOwnerAuthenticationBrowser()
    @StateObject private var manager = PFSSCloudflareBetaManager()
    private let accountService = PFSSCloudflareOwnerAccountService()
    @State private var email = ""
    @State private var deviceName = UIDevice.current.name
    @State private var isWorking = false
    @State private var isShowingEmailNotice = false
    @State private var messageTitle = ""
    @State private var message = ""
    @State private var isShowingMessage = false

    init() {
        _coordinator = StateObject(wrappedValue:
            PFSSOwnerAuthenticationCoordinator(
                service: PFSSCloudflareOwnerAccountService(),
                redirectURI:
                    PFSSCloudflareOwnerAccountService.stagingRedirectURI
            )
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("owner@company.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("This device", text: $deviceName)
            } header: {
                Text("Owner Sign In")
            } footer: {
                Text(
                    "Securely verify the existing Owner account to reconnect this device or add another Owner device."
                )
            }

            Section {
                Button {
                    isShowingEmailNotice = true
                } label: {
                    Label(
                        isWorking ? "Opening Secure Sign-In" : "Continue",
                        systemImage: "lock.shield.fill"
                    )
                }
                .disabled(
                    isWorking ||
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .navigationTitle("Owner Sign In")
        .disabled(isWorking)
        .alert(
            "Watch for Your Verification Email",
            isPresented: $isShowingEmailNotice
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") { signIn() }
        } message: {
            Text(
                "WorkOS will send a verification email. Check your Inbox and also your Junk or Spam folder if it does not arrive promptly."
            )
        }
        .alert(messageTitle, isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
        }
    }

    private func signIn() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let authorizationSession = try await coordinator.start(
                    emailHint: email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).lowercased(),
                    screenHint: "sign-in"
                )
                let callback = try await browser.authenticate(
                    at: authorizationSession.authorizationURL,
                    callbackURL:
                        PFSSCloudflareOwnerAccountService.stagingRedirectURI
                )
                let authorization = try coordinator.consumeCallback(callback)
                let identity = try await accountService.exchange(authorization)
                let receipt = try await accountService.signIn(
                    identity: identity,
                    deviceID: manager.registrationDeviceID(),
                    deviceName: deviceName
                )
                try await manager.acceptProvisionedOwnerDevice(
                    token: receipt.deviceToken,
                    deviceID: receipt.deviceID
                )
                messageTitle = "Owner Signed In"
                message = "This device is connected to \(receipt.tenantName). PFSS is loading the company workspace now."
            } catch {
                messageTitle = "Unable to Sign In"
                message = error.localizedDescription
            }
            isShowingMessage = true
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
        .navigationTitle("Employee Activation")
        .alert(messageTitle, isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
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
                message = "PFSS is securely loading the company workspace now."
            } catch {
                messageTitle = "Unable to Activate Device"
                message = error.localizedDescription
            }
            isShowingMessage = true
        }
    }
}

#if DEBUG
private struct PFSSOwnerRegistrationStartView: View {
    @StateObject private var coordinator: PFSSOwnerAuthenticationCoordinator
    @StateObject private var browser = PFSSOwnerAuthenticationBrowser()
    @StateObject private var manager = PFSSCloudflareBetaManager()
    private let accountService = PFSSCloudflareOwnerAccountService()
    @State private var email = ""
    @State private var verifiedIdentity: PFSSVerifiedOwnerIdentity?
    @State private var ownerName = ""
    @State private var companyName = ""
    @State private var deviceName = UIDevice.current.name
    @State private var acceptedAgreements = false
    @State private var ownerIsSalesperson = true
    @State private var ownerIsTechnician = true
    @State private var idempotencyKey = UUID()
    @State private var isWorking = false
    @State private var isShowingVerificationEmailNotice = false
    @State private var messageTitle = ""
    @State private var message = ""
    @State private var isShowingMessage = false

    init() {
        _coordinator = StateObject(wrappedValue:
            PFSSOwnerAuthenticationCoordinator(
                service: PFSSCloudflareOwnerAccountService(),
                redirectURI:
                    PFSSCloudflareOwnerAccountService.stagingRedirectURI
            )
        )
    }

    var body: some View {
        Form {
            Section {
                Label("Create Your Company", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Text(
                    "Verify the first Owner, then create the company and this device's secure access together."
                )
                .foregroundStyle(.secondary)
            }

            if let verifiedIdentity {
                Section("Verified Owner") {
                    LabeledContent("Email", value: verifiedIdentity.email)
                    TextField("Full name", text: $ownerName)
                        .textContentType(.name)
                }

                Section {
                    TextField("Company name", text: $companyName)
                        .textContentType(.organizationName)
                    TextField("This device", text: $deviceName)
                } header: {
                    Text("Company")
                } footer: {
                    Text(
                        "The staging company receives temporary beta access. Subscription selection will be added before production registration is enabled."
                    )
                }


                Section {
                    Toggle("Sales", isOn: $ownerIsSalesperson)
                    Toggle("Technician", isOn: $ownerIsTechnician)
                } header: {
                    Text("Owner Work Roles")
                } footer: {
                    Text(
                        "These roles add the Owner to the employee list so work can be assigned to them. Owner account authority is unchanged."
                    )
                }

                Section("Agreements") {
                    Toggle(
                        "I accept the PFSS Terms and Privacy Policy",
                        isOn: $acceptedAgreements
                    )

                    Button {
                        createCompany(with: verifiedIdentity)
                    } label: {
                        Label(
                            isWorking ? "Creating Company" : "Create Company",
                            systemImage: "building.2.crop.circle.fill"
                        )
                    }
                    .disabled(
                        isWorking || !acceptedAgreements ||
                        ownerName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        companyName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        deviceName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        (!ownerIsSalesperson && !ownerIsTechnician)
                    )
                }
            } else {
                Section("Owner Email") {
                    TextField("owner@company.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()

                    Button {
                        isShowingVerificationEmailNotice = true
                    } label: {
                        Label(
                            isWorking ? "Opening Secure Sign-In" : "Verify Owner",
                            systemImage: "lock.shield.fill"
                        )
                    }
                    .disabled(isWorking || email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                    .alert(
                        "Watch for Your Verification Email",
                        isPresented: $isShowingVerificationEmailNotice
                    ) {
                        Button("Cancel", role: .cancel) { }
                        Button("Continue") {
                            verifyOwner()
                        }
                    } message: {
                        Text(
                            "WorkOS will send a verification email to complete secure Owner setup. Check your Inbox and also your Junk or Spam folder if it does not arrive promptly."
                        )
                    }
                }
            }

            Section {
                Text(
                    "This development build uses the isolated PFSS staging account system. It does not create a production subscription."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("New Company")
        .disabled(isWorking)
        .alert(messageTitle, isPresented: $isShowingMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message)
        }
    }

    private func verifyOwner() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let session = try await coordinator.start(
                    emailHint: email.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).lowercased()
                )
                let callback = try await browser.authenticate(
                    at: session.authorizationURL,
                    callbackURL:
                        PFSSCloudflareOwnerAccountService.stagingRedirectURI
                )
                let authorization = try coordinator.consumeCallback(callback)
                let identity = try await accountService.exchange(authorization)
                verifiedIdentity = identity
                ownerName = identity.displayName
                email = identity.email
            } catch {
                messageTitle = "Unable to Verify Owner"
                message = error.localizedDescription
                isShowingMessage = true
            }
        }
    }

    private func createCompany(
        with identity: PFSSVerifiedOwnerIdentity
    ) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let deviceID = manager.registrationDeviceID()
                let request = PFSSOwnerRegistrationRequest(
                    idempotencyKey: idempotencyKey,
                    identityAssertion: identity.identityAssertion,
                    authenticationMethod: identity.authenticationMethod,
                    owner: PFSSOwnerRegistrationIdentity(
                        displayName: ownerName,
                        email: identity.email
                    ),
                    company: PFSSCompanyRegistrationProfile(
                        displayName: companyName,
                        timeZoneID: TimeZone.current.identifier
                    ),
                    requestedPlanCode: "beta-90-day",
                    consent: PFSSRegistrationConsent(
                        termsVersion: "terms-2026-07",
                        privacyVersion: "privacy-2026-07",
                        acceptedAt: Date()
                    ),
                    device: PFSSRegistrationDevice(
                        id: deviceID,
                        displayName: deviceName
                    )
                )
                let receipt = try await accountService.register(request)
                try await manager.acceptProvisionedOwnerDevice(
                    token: receipt.deviceToken,
                    deviceID: receipt.deviceID
                )
                var workRoles = Set<PFSSOwnerOperationalRole>()
                if ownerIsSalesperson { workRoles.insert(.salesperson) }
                if ownerIsTechnician { workRoles.insert(.technician) }
                _ = try await manager.configureOwnerWorkProfile(
                    roles: workRoles
                )
                messageTitle = "Company Created"
                message = "\(receipt.tenantName) and this Owner device are active. PFSS is loading the new company workspace now."
                isShowingMessage = true
            } catch {
                messageTitle = "Unable to Create Company"
                message = error.localizedDescription
                isShowingMessage = true
            }
        }
    }
}
#endif
