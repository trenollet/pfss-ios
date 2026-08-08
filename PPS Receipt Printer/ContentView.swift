import SwiftUI

enum AppSection: Hashable {
    case dashboard
    case sales
    case myDay
    case service
    case admin

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .sales: return "Sales"
        case .myDay: return "My Day"
        case .service: return "Service"
        case .admin: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar"
        case .sales: return "chart.line.uptrend.xyaxis"
        case .myDay: return "calendar.day.timeline.left"
        case .service: return "wrench.and.screwdriver"
        case .admin: return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedSection: AppSection = .dashboard
    @State private var sectionResetGeneration: [AppSection: Int] = [:]

    private var isOperationalAccessBlocked: Bool {
        switch store.cloudSynchronizationAccessStatus {
        case .accountHold, .suspended: return true
        case .checking, .available, .unavailable: return false
        }
    }

    private var availableSections: [AppSection] {
        if isOperationalAccessBlocked {
            return [.dashboard, .admin]
        }
        return [.dashboard, .sales, .myDay, .service, .admin]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                sectionLayer(.dashboard) {
                    DashboardView(selectedSection: $selectedSection)
                }

                if !isOperationalAccessBlocked {
                    sectionLayer(.sales) {
                        SalesDashboardView()
                    }

                    sectionLayer(.myDay) {
                        TechnicianWorkspaceView()
                    }

                    sectionLayer(.service) {
                        ServiceDashboardView()
                    }
                }

                sectionLayer(.admin) {
                    NavigationStack {
                        AdminView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PFSSPrimaryNavigationBar(
                selection: $selectedSection,
                sections: availableSections,
                onReselect: resetToSectionRoot
            )
        }
        .onChange(of: isOperationalAccessBlocked) { _, blocked in
            if blocked && selectedSection != .admin {
                selectedSection = .dashboard
            }
        }
    }

    private func sectionLayer<Content: View>(
        _ section: AppSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(sectionResetGeneration[section, default: 0])
            .opacity(selectedSection == section ? 1 : 0)
            .allowsHitTesting(selectedSection == section)
            .accessibilityHidden(selectedSection != section)
            .zIndex(selectedSection == section ? 1 : 0)
    }

    private func resetToSectionRoot(_ section: AppSection) {
        sectionResetGeneration[section, default: 0] += 1
    }
}

private struct PFSSPrimaryNavigationBar: View {
    @Binding var selection: AppSection
    let sections: [AppSection]
    let onReselect: (AppSection) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sections, id: \.self) { section in
                Button {
                    if selection == section {
                        onReselect(section)
                    } else {
                        selection = section
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                        Text(section.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(
                        selection == section ? Color.accentColor : Color.secondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(
                    selection == section ? .isSelected : []
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary navigation")
    }
}
