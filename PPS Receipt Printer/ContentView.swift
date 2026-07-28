import SwiftUI

enum AppSection: Hashable {
    case dashboard
    case sales
    case myDay
    case service
    case admin
}

struct ContentView: View {
    @State private var selectedSection: AppSection = .dashboard

    var body: some View {
        TabView(selection: $selectedSection) {
            DashboardView(selectedSection: $selectedSection)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar")
                }
                .tag(AppSection.dashboard)

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

            NavigationStack {
                AdminView()
            }
                .tabItem {
                    Label("Admin", systemImage: "gear")
                }
                .tag(AppSection.admin)
        }
    }
}
