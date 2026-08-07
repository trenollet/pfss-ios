import SwiftUI

enum AppSection: Hashable {
    case dashboard
    case sales
    case myDay
    case service
    case admin
}

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedSection: AppSection = .dashboard

    private var isOperationalAccessBlocked: Bool {
        switch store.cloudSynchronizationAccessStatus {
        case .accountHold, .suspended: return true
        case .checking, .available, .unavailable: return false
        }
    }

    var body: some View {
        TabView(selection: $selectedSection) {
            DashboardView(selectedSection: $selectedSection)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar")
                }
                .tag(AppSection.dashboard)

            if !isOperationalAccessBlocked {
                SalesDashboardView()
                    .tabItem {
                        Label("Sales", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tag(AppSection.sales)

                TechnicianWorkspaceView()
                    .tabItem {
                        Label(
                            "My Day",
                            systemImage: "calendar.day.timeline.left"
                        )
                    }
                    .tag(AppSection.myDay)

                ServiceDashboardView()
                    .tabItem {
                        Label("Service", systemImage: "wrench.and.screwdriver")
                    }
                    .tag(AppSection.service)
            }

            NavigationStack {
                AdminView()
            }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppSection.admin)
        }
        .onChange(of: isOperationalAccessBlocked) { _, blocked in
            if blocked && selectedSection != .admin {
                selectedSection = .dashboard
            }
        }
    }
}
