//
//  PFSSPlanUsageView.swift
//  PPS Receipt Printer
//
//  Phase 17 – Server-authoritative plan and usage receipt presentation.
//

import SwiftUI

struct PFSSPlanUsageView: View {
    @ObservedObject var manager: PFSSCloudflareBetaManager

    @State private var loadError = ""
    @State private var isShowingLoadError = false

    private var snapshot: PFSSAccountEntitlementSnapshot? {
        manager.accountEntitlementSnapshot
    }

    var body: some View {
        List {
            if let snapshot {
                Section("Current Plan") {
                    LabeledContent("Plan", value: snapshot.planDisplayName)
                    LabeledContent("Status", value: snapshot.statusDisplayName)
                    LabeledContent("Access", value: snapshot.accessDisplayName)
                    if let expiresAt = snapshot.expiresAt {
                        LabeledContent("Expires") {
                            Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    if snapshot.accessMode != .full {
                        Label(
                            snapshot.accessMode == .readOnly
                                ? "Existing company records remain available, but PFSS cannot create or synchronize new changes until account access is restored."
                                : "Account access is currently blocked. Contact PFSS or restore the subscription to continue.",
                            systemImage: snapshot.accessMode == .readOnly
                                ? "exclamationmark.lock"
                                : "lock.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    usageRow(
                        "Users",
                        used: snapshot.usage.users,
                        limit: snapshot.entitlements.userLimit
                    )
                    usageRow(
                        "Devices",
                        used: snapshot.usage.devices,
                        limit: snapshot.entitlements.deviceLimit
                    )
                } header: {
                    Text("People & Devices")
                } footer: {
                    Text("Owners and employees count together as users.")
                }

                Section {
                    usageRow(
                        "Leads",
                        used: snapshot.usage.leads,
                        limit: snapshot.entitlements.recordLimits.leads
                    )
                    usageRow(
                        "Customers",
                        used: snapshot.usage.customers,
                        limit: snapshot.entitlements.recordLimits.customers
                    )
                    usageRow(
                        "Jobs",
                        used: snapshot.usage.jobs,
                        limit: snapshot.entitlements.recordLimits.jobs
                    )
                } header: {
                    Text("Records")
                } footer: {
                    Text("Archived records count until they are permanently deleted.")
                }

                Section {
                    LabeledContent("Provided By", value: snapshot.sourceDisplayName)
                    LabeledContent("Effective") {
                        Text(snapshot.effectiveAt.formatted(date: .abbreviated, time: .omitted))
                    }
                } header: {
                    Text("Receipt")
                } footer: {
                    Text("PFSS verifies this plan and its limits on the server. This device cannot grant or increase account access.")
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading plan and usage…")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Plan & Usage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
        .alert("Unable to Load Plan", isPresented: $isShowingLoadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(loadError)
        }
    }

    @ViewBuilder
    private func usageRow(_ title: String, used: Int, limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(limit.map { "\(used.formatted()) of \($0.formatted())" } ?? "\(used.formatted()) — Unlimited")
                    .foregroundStyle(.secondary)
            }
            if let limit {
                ProgressView(value: min(Double(used), Double(limit)), total: Double(limit))
                    .tint(used >= limit ? .orange : .accentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        do {
            if manager.currentSession == nil {
                try await manager.refreshSession()
            }
            try await manager.refreshAccountEntitlements()
        } catch {
            loadError = error.localizedDescription
            isShowingLoadError = true
        }
    }
}

private extension PFSSAccountEntitlementSnapshot {
    var planDisplayName: String {
        switch planCode {
        case "beta-90-day": return "Beta Test"
        case "trial-14-day": return "Trial"
        case "base-monthly": return "Base"
        case "pro-monthly": return "Pro"
        case "expert-monthly": return "Expert"
        case "enterprise-custom": return "Enterprise / Custom"
        default: return planCode
        }
    }

    var statusDisplayName: String {
        switch subscriptionStatus {
        case .pending: return "Pending"
        case .trialing: return "Trial"
        case .active: return "Active"
        case .pastDue: return "Payment Required"
        case .suspended: return "Suspended"
        case .cancelled: return "Cancelled"
        }
    }

    var accessDisplayName: String {
        switch accessMode {
        case .full: return "Full Access"
        case .readOnly: return "Read Only"
        case .blocked: return "Blocked"
        }
    }

    var sourceDisplayName: String {
        switch accessSource {
        case .appStoreSubscription: return "App Store"
        case .betaGrant: return "PFSS Beta Program"
        case .internalTesting: return "PFSS Testing"
        case .internalBusinessGrant: return "PFSS Business Grant"
        case .promotionalGrant: return "PFSS Promotion"
        }
    }
}
