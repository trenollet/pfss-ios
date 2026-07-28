//
//  DispatchBoardView.swift
//  PPS Receipt Printer
//
//  Phase 14.7 – Technician Dispatch Board hub
//

import SwiftUI

/// A compact operational hub. Each metric opens a focused work queue instead
/// of placing every lane, Assignment, and warning on one scrolling screen.
struct DispatchBoardView: View {
    @EnvironmentObject private var store: AppDataStore

    @StateObject private var alertAcknowledgements =
        DispatchBoardAlertAcknowledgementStore()
    @State private var selectedDate = Date()
    @State private var generatedAt = Date()

    private let calendar = Calendar.current

    private var snapshot: DispatchBoardSnapshot {
        store.dispatchBoardSnapshot(
            on: selectedDate,
            generatedAt: generatedAt,
            calendar: calendar
        )
    }

    private var attentionCount: Int {
        alertAcknowledgements.visibleAlerts(in: snapshot).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dateControls

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    NavigationLink {
                        DispatchBoardAssignedView(date: selectedDate)
                            .environmentObject(store)
                            .environmentObject(alertAcknowledgements)
                    } label: {
                        metricTile(
                            title: "Assigned",
                            value: snapshot.assignedCount,
                            symbol: "person.crop.circle.badge.checkmark",
                            color: .green,
                            borderColor: .green
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DispatchBoardUnassignedView(date: selectedDate)
                            .environmentObject(store)
                    } label: {
                        metricTile(
                            title: "Unassigned",
                            value: snapshot.unassignedCount,
                            symbol: "tray.full.fill",
                            color: snapshot.unassignedCount > 0 ? .yellow : .secondary,
                            borderColor: .yellow
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DispatchBoardEmergencyView(date: selectedDate)
                            .environmentObject(store)
                    } label: {
                        metricTile(
                            title: "Emergency",
                            value: snapshot.emergencyCount,
                            symbol: "flag.fill",
                            color: snapshot.emergencyCount > 0 ? .red : .secondary,
                            borderColor: .red
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DispatchBoardAttentionView(date: selectedDate)
                            .environmentObject(store)
                            .environmentObject(alertAcknowledgements)
                    } label: {
                        metricTile(
                            title: "Needs Attention",
                            value: attentionCount,
                            symbol: "exclamationmark.triangle.fill",
                            color: attentionCount > 0 ? .orange : .secondary,
                            borderColor: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    OperationsTimelineView(date: selectedDate)
                        .environmentObject(store)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar.day.timeline.leading")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                            .frame(width: 42, height: 42)
                            .background(Color.indigo.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Operations Timeline")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Review technician schedules, constraints, travel, gaps, actual progress, and unused capacity chronologically.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .dispatchBoardSurface(borderColor: .indigo)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OperationsLiveMapView(date: selectedDate)
                        .environmentObject(store)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                            .frame(width: 42, height: 42)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Live Operations Map")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("See service locations, route order, technician reporting state, destinations, and ETAs on one synchronized map.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .dispatchBoardSurface(borderColor: .green)
                }
                .buttonStyle(.plain)

                Label(
                    "Choose a tile to work with that part of the day. All changes remain synchronized through PFSS Operations APIs.",
                    systemImage: "rectangle.grid.2x2.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .dispatchBoardSurface()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dispatch Board")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { generatedAt = Date() }
        .onChange(of: selectedDate) { _, _ in
            generatedAt = Date()
        }
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    moveDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Previous day")

                VStack(spacing: 2) {
                    DatePicker(
                        "Board Date",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)

                    Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    moveDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Next day")
            }

            if calendar.isDateInToday(selectedDate) == false {
                HStack {
                    Spacer()
                    Button("Return to Today") {
                        selectedDate = Date()
                    }
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }
        }
        .padding()
        .dispatchBoardSurface()
    }

    private func metricTile(
        title: String,
        value: Int,
        symbol: String,
        color: Color,
        borderColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Text(value.formatted())
                .font(.largeTitle.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 164,
            maxHeight: 164,
            alignment: .leading
        )
        .padding()
        .dispatchBoardSurface(borderColor: borderColor)
        .contentShape(Rectangle())
    }

    private func moveDate(by days: Int) {
        guard let date = calendar.date(
            byAdding: .day,
            value: days,
            to: selectedDate
        ) else { return }
        selectedDate = date
    }
}

extension View {
    func dispatchBoardSurface(borderColor: Color = .clear) -> some View {
        background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(borderColor, lineWidth: 1.5)
            }
    }
}
