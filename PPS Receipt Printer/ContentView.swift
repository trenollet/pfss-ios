import SwiftUI

struct ContentView: View {
    @StateObject private var store = AppDataStore()
    @StateObject private var printer = BluetoothPrinter()
    
    var body: some View {
        TabView {
            DashboardView()
                .environmentObject(store)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar")
                }
            LeadsView()
                .environmentObject(store)
                .tabItem {
                    Label("Leads", systemImage: "person.crop.circle.badge.plus")
                }
            CustomersView()
                .environmentObject(store)
                .tabItem {
                    Label("Customers", systemImage: "person.2")
                }
            JobsView()
                .environmentObject(store)
                .tabItem {
                    Label("Jobs", systemImage: "wrench.and.screwdriver")
                }
            EstimatesView()
                .environmentObject(store)
                .tabItem {
                    Label("Estimates", systemImage: "doc.text")
                }
            ServiceCatalogView()
                .environmentObject(store)
                .tabItem {
                    Label("Items", systemImage: "book.pages")
                }
            
            SitesView()
                .environmentObject(store)
                .tabItem {
                    Label("Sites", systemImage: "house")
                }
            
            PrintView()
                .environmentObject(store)
                .tabItem {
                    Label("Print", systemImage: "printer")
                }
            RecommendationRuleEditorView()
                .environmentObject(store)
                .tabItem {
                    Label ("Admin" , systemImage: "gear")
                }
            NavigationLink("Recommendation Rules") {
                RecommendationRuleEditorView()
                    .environmentObject(store)
            }
            .environmentObject(store)
            .environmentObject(printer)
        }
    }
}
