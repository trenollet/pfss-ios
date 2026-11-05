import SwiftUI

@main
struct PFSSWatchApp: App {
    @StateObject private var model = PFSSWatchWorkflowModel()

    var body: some Scene {
        WindowGroup {
            PFSSWatchWorkflowView()
                .environmentObject(model)
        }
    }
}
