import Foundation
import UIKit

@MainActor
final class OperationsStore: ObservableObject {
    enum State {
        case restoring
        case signedOut
        case signedIn
    }

    @Published private(set) var state: State = .restoring
    @Published private(set) var administrator: OperationsAdministrator?
    @Published private(set) var summary: OperationsSummary?
    @Published private(set) var monitoring: OperationsMonitoring?
    @Published private(set) var accounts: [OperationsAccount] = []
    @Published private(set) var selectedDetail: OperationsAccountDetail?
    @Published var search = ""
    @Published var statusFilter = "all"
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false

    private let api = OperationsAPIClient()
    private let browser = OperationsAuthenticationBrowser()
    private let redirectURI = URL(
        string: "https://auth-staging.patriot-ok.com/operations-callback/"
    )!
    private let tokenAccount = "operations-session"
    private let deviceAccount = "operations-device-id"
    private var token: String?

    func restoreSession() async {
        guard let token = OperationsCredentialStore.load(tokenAccount) else {
            state = .signedOut
            return
        }
        self.token = token
        do {
            let receipt = try await api.session(token: token)
            administrator = receipt.administrator
            state = .signedIn
            await refresh()
        } catch {
            signOut()
        }
    }

    func signIn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let pkce = try OperationsPKCE.make()
            let authorization = try await api.authorize(
                state: pkce.state,
                challenge: pkce.challenge,
                redirectURI: redirectURI
            )
            let callback = try await browser.authenticate(
                at: authorization.authorizationURL,
                callbackURL: redirectURI
            )
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            let callbackState = components?.queryItems?.first(where: { $0.name == "state" })?.value
            let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
            guard callbackState == pkce.state, let callbackState, let code else {
                throw OperationsAPIError.invalidResponse
            }
            let receipt = try await api.completeAuthorization(
                state: callbackState,
                code: code,
                verifier: pkce.verifier,
                redirectURI: redirectURI,
                deviceID: try deviceID(),
                deviceName: UIDevice.current.name
            )
            try OperationsCredentialStore.save(
                receipt.sessionToken,
                account: tokenAccount
            )
            token = receipt.sessionToken
            administrator = receipt.administrator
            state = .signedIn
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    func refresh() async {
        guard let token else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            async let summary = api.summary(token: token)
            async let monitoring = api.monitoring(token: token)
            async let accounts = api.accounts(
                token: token,
                search: search,
                status: statusFilter
            )
            self.summary = try await summary
            self.monitoring = try await monitoring
            self.accounts = try await accounts.accounts
        } catch {
            handle(error)
        }
    }

    func loadAccount(id: String) async {
        guard let token else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            selectedDetail = try await api.account(token: token, id: id)
        } catch {
            handle(error)
        }
    }

    func createPlanOverride(
        accountID: String, planCode: String, reason: String,
        permanent: Bool, expiresAt: Date?
    ) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.createPlanOverride(
                token: token, accountID: accountID, planCode: planCode,
                reason: reason, permanent: permanent, expiresAt: expiresAt
            )
            selectedDetail = try await api.account(token: token, id: accountID)
            let page = try await api.accounts(
                token: token, search: search, status: statusFilter
            )
            accounts = page.accounts
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func placeAccountOnHold(
        accountID: String, status: String, reason: String,
        permanent: Bool, expiresAt: Date?
    ) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.placeAccountOnHold(
                token: token, accountID: accountID, status: status,
                reason: reason, permanent: permanent, expiresAt: expiresAt
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return true
        } catch { handle(error); return false }
    }

    func reactivateAccount(accountID: String, reason: String) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.reactivateAccount(
                token: token, accountID: accountID, reason: reason
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return true
        } catch { handle(error); return false }
    }

    func manageAccountArchive(
        accountID: String, action: String, reason: String,
        confirmation: String? = nil
    ) async -> OperationsLifecycleReceipt? {
        guard let token else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let receipt = try await api.manageAccountArchive(
                token: token, accountID: accountID, action: action,
                reason: reason, confirmation: confirmation
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return receipt
        } catch { handle(error); return nil }
    }

    func deletionReadiness(accountID: String) async -> OperationsDeletionReadiness? {
        guard let token else { return nil }
        do {
            return try await api.deletionReadiness(token: token, accountID: accountID)
        } catch { handle(error); return nil }
    }

    func confirmDeviceCleanup(
        accountID: String, reason: String, confirmation: String
    ) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.confirmDeviceCleanup(
                token: token, accountID: accountID, reason: reason,
                confirmation: confirmation
            )
            return true
        } catch { handle(error); return false }
    }

    func createRecoveryArchive(accountID: String, reason: String) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.createRecoveryArchive(
                token: token, accountID: accountID, reason: reason
            )
            return true
        } catch { handle(error); return false }
    }

    func sendPasswordReset(
        accountID: String, memberID: String, reason: String
    ) async -> OperationsRecoveryReceipt? {
        guard let token else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let receipt = try await api.sendPasswordReset(
                token: token, accountID: accountID,
                memberID: memberID, reason: reason
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return receipt
        } catch { handle(error); return nil }
    }

    func revokeSessions(
        accountID: String, memberID: String, reason: String
    ) async -> OperationsRecoveryReceipt? {
        guard let token else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let receipt = try await api.revokeSessions(
                token: token, accountID: accountID,
                memberID: memberID, reason: reason
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return receipt
        } catch { handle(error); return nil }
    }

    func manageMember(
        accountID: String, memberID: String, action: String, reason: String
    ) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.manageMember(
                token: token, accountID: accountID, memberID: memberID,
                action: action, reason: reason
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return true
        } catch { handle(error); return false }
    }

    func manageDevice(
        accountID: String, deviceID: String, action: String, reason: String
    ) async -> Bool {
        guard let token else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.manageDevice(
                token: token, accountID: accountID, deviceID: deviceID,
                action: action, reason: reason
            )
            await reloadAccountAndList(accountID: accountID, token: token)
            return true
        } catch { handle(error); return false }
    }

    private func reloadAccountAndList(accountID: String, token: String) async {
        do {
            selectedDetail = try await api.account(token: token, id: accountID)
            accounts = try await api.accounts(
                token: token, search: search, status: statusFilter
            ).accounts
        } catch { handle(error) }
    }

    func signOut() {
        OperationsCredentialStore.delete(tokenAccount)
        token = nil
        administrator = nil
        summary = nil
        accounts = []
        selectedDetail = nil
        state = .signedOut
    }

    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
        if case OperationsAPIError.unauthorized = error { signOut() }
    }

    private func deviceID() throws -> UUID {
        if let stored = OperationsCredentialStore.load(deviceAccount),
           let value = UUID(uuidString: stored) {
            return value
        }
        let value = UUID()
        try OperationsCredentialStore.save(
            value.uuidString.lowercased(),
            account: deviceAccount
        )
        return value
    }
}
