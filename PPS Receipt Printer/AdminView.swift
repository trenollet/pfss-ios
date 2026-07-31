//
//  AdminView.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/12/26.
//

import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var store: AppDataStore

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
    }

    private var syncPresentationState: OfflineSyncPresentationState {
        OfflineSyncStatusResolver.resolve(
            mode: store.offlineSynchronizationMode,
            queue: store.offlineOperationQueue,
            connectivity: store.offlineConnectivityMonitor.status,
            cloudAccessStatus: store.cloudSynchronizationAccessStatus
        )
    }

    var body: some View {
        List {
                if store.shouldPresentAuthenticatedUserInfo {
                    Section("User Info") {
                        if let employee = store.authenticatedCloudEmployee {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(employee.displayName)
                                    .font(.headline)
                                Text(employee.roleDisplayText)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            Label(
                                "No Linked Employee Profile",
                                systemImage: "person.crop.circle.badge.exclamationmark"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if store.canManageCompany {
                    Section("Business") {
                    NavigationLink {
                        BusinessProfileView()
                    } label: {
                        Label(
                            "Business Profile",
                            systemImage: "building.2"
                        )
                    }
                    NavigationLink {
                        EmployeesView()
                    } label: {
                        Label(
                            "Employees & Capacity",
                            systemImage: "person.3"
                        )
                    }
                    }
                }

                Section("Reports") {
                    NavigationLink {
                        SitesView()
                    } label: {
                        Label(
                            "Sites",
                            systemImage: "house"
                        )
                    }

                    NavigationLink {
                        JobHistoryReportView()
                    } label: {
                        Label(
                            "Job History Report",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }

                if store.canManageCompany {
                    Section("Configuration") {
                    NavigationLink {
                        RecommendationRuleEditorView()
                    } label: {
                        Label(
                            "Recommendation Rules",
                            systemImage: "sparkles"
                        )
                    }
                    }
                }

                Section("Printing") {
                    if store.canManageCompany {
                        NavigationLink {
                            ServiceCatalogView()
                        } label: {
                            Label("Catalog Items", systemImage: "square.grid.2x2")
                        }
                    }

                    NavigationLink {
                        PrintView()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                }

                if store.canManageCompany {
                    Section("Data") {
                        NavigationLink {
                            DataManagementView()
                        } label: {
                            Label(
                                "Data Management",
                                systemImage: "externaldrive"
                            )
                        }
                    }
                }

                Section("App Information") {
                    if store.shouldPresentAuthenticatedUserInfo {
                        NavigationLink {
                            OfflineSyncDetailsView(
                                queue: store.offlineOperationQueue,
                                connectivity: store.offlineConnectivityMonitor,
                                mode: store.offlineSynchronizationMode,
                                cloudAccessStatus: store.cloudSynchronizationAccessStatus,
                                canOverrideConflicts: store.canOverrideSynchronizationConflicts,
                                onSyncNow: store.offlineSynchronizationService.map { service in
                                    { service.syncNow() }
                                },
                                onResolveConflict: { operationID, resolution in
                                    try store.resolveRecordConflict(
                                        operationID: operationID,
                                        resolution: resolution
                                    )
                                }
                            )
                        } label: {
                            HStack {
                                Text("Sync Status")
                                Spacer()
                                Label(
                                    syncPresentationState.title,
                                    systemImage: syncPresentationState.systemImage
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(syncPresentationState.color)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "Synchronization status: \(syncPresentationState.title)"
                            )
                            .accessibilityHint(syncPresentationState.detail)
                        }
                    }
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}
