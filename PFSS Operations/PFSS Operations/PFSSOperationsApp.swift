import SwiftUI

@main
struct PFSSOperationsApp: App {
    @StateObject private var store = OperationsStore()

    var body: some Scene {
        WindowGroup {
            OperationsRootView()
                .environmentObject(store)
                .task { await store.restoreSession() }
        }
    }
}
