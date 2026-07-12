import SwiftUI

struct ContentView: View {
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar")
                }
            LeadsView()
                .tabItem {
                    Label("Leads", systemImage: "person.crop.circle.badge.plus")
                }
            CustomersView()
                .tabItem {
                    Label("Customers", systemImage: "person.2")
                }
            JobsView()
                .tabItem {
                    Label("Jobs", systemImage: "wrench.and.screwdriver")
                }
            EstimatesView()
                .tabItem {
                    Label("Estimates", systemImage: "doc.text")
                }
            InvoicesView()
                .tabItem {
                    Label("Invoices", systemImage: "doc.text.fill")
                }
            ServiceCatalogView()
                .tabItem {
                    Label("Catalog Items", systemImage: "book.pages")
                }
            
            SitesView()
                .tabItem {
                    Label("Sites", systemImage: "house")
                }
            
            PrintView()
                .tabItem {
                    Label("Print", systemImage: "printer")
                }
            AdminView()
                .tabItem {
                    Label("Admin", systemImage: "gear")
                }
            }
        }
    }

