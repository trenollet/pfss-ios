//
//  OperationsLiveMapView.swift
//  PPS Receipt Printer
//
//  Phase 14.9 – Live Map View
//

import SwiftUI
import MapKit
import CoreLocation

struct OperationsLiveMapView: View {
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var locationManager = TechnicianLocationManager()

    let initialDate: Date

    @State private var selectedDate: Date
    @State private var snapshot: LiveMapSnapshot?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var reportingTechnicianID: UUID?
    @State private var selection: LiveMapSelection?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var refreshToken = UUID()

    private let calendar = Calendar.current

    init(date: Date = Date()) {
        initialDate = date
        _selectedDate = State(initialValue: date)
    }

    private var activeTechnicians: [EmployeeRecord] {
        store.activeEmployees
            .filter { $0.hasRole(.technician) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dateControls
                summaryStrip
                mapPanel
                reportingPanel
                if let snapshot, snapshot.alerts.isEmpty == false {
                    alertPanel(snapshot.alerts)
                }
                mapLegend
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Live Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshToken = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task(id: refreshToken) { await rebuildSnapshot() }
        .onChange(of: selectedDate) { _, _ in
            refreshToken = UUID()
        }
        .onChange(of: reportingTechnicianID) { _, _ in
            refreshToken = UUID()
        }
        .onReceive(locationManager.$currentLocation) { _ in
            guard reportingTechnicianID != nil else { return }
            refreshToken = UUID()
        }
        .onReceive(locationManager.$status) { _ in
            guard reportingTechnicianID != nil else { return }
            refreshToken = UUID()
        }
        .sheet(item: $selection) { selection in
            destination(for: selection)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { self.selection = nil }
                    }
                }
        }
    }

    private var dateControls: some View {
        HStack(spacing: 12) {
            Button { moveDate(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)

            VStack(spacing: 2) {
                DatePicker(
                    "Map Date",
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

            Button { moveDate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .liveMapSurface()
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            mapMetric(
                title: "Technicians",
                value: snapshot?.reportingTechnicianCount ?? 0,
                symbol: "location.fill",
                color: .blue
            )
            mapMetric(
                title: "Assignments",
                value: snapshot?.locatedAssignmentCount ?? 0,
                symbol: "mappin.and.ellipse",
                color: .green
            )
            mapMetric(
                title: "Alerts",
                value: snapshot?.alerts.count ?? 0,
                symbol: "exclamationmark.triangle.fill",
                color: .orange
            )
        }
    }

    private func mapMetric(
        title: String,
        value: Int,
        symbol: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liveMapSurface()
    }

    private var mapPanel: some View {
        Group {
            if isLoading && snapshot == nil {
                ProgressView("Building live operations map…")
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .liveMapSurface()
            } else if let loadError {
                ContentUnavailableView(
                    "Map Unavailable",
                    systemImage: "map.fill",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, minHeight: 420)
                .liveMapSurface(borderColor: .orange)
            } else if let snapshot {
                Map(position: $cameraPosition) {
                    ForEach(snapshot.routeSegments) { segment in
                        MapPolyline(
                            coordinates: [
                                segment.start.clLocationCoordinate,
                                segment.end.clLocationCoordinate
                            ]
                        )
                        .stroke(
                            technicianColor(segment.technicianID),
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                dash: [8, 6]
                            )
                        )
                    }

                    ForEach(snapshot.assignmentPins) { pin in
                        Annotation(
                            pin.customerName,
                            coordinate: pin.coordinate.clLocationCoordinate
                        ) {
                            Button {
                                selection = .assignment(pin.id)
                            } label: {
                                assignmentMarker(pin)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(snapshot.technicianPins.filter {
                        $0.coordinate != nil
                    }) { pin in
                        if let coordinate = pin.coordinate {
                            Annotation(
                                pin.technicianName,
                                coordinate: coordinate.clLocationCoordinate
                            ) {
                                Button {
                                    selection = .technician(pin.technicianID)
                                } label: {
                                    technicianMarker(pin)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .frame(height: 500)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
            } else {
                ContentUnavailableView(
                    "No Map Data",
                    systemImage: "map",
                    description: Text("Pull to refresh the Operations map.")
                )
                .frame(maxWidth: .infinity, minHeight: 420)
                .liveMapSurface()
            }
        }
    }

    private func assignmentMarker(
        _ pin: LiveMapAssignmentPin
    ) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(pin.priority == .emergency ? Color.red : Color.blue)
                    .frame(width: 42, height: 42)
                if let sequence = pin.routeSequence {
                    Text("\(sequence)")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.white)
                }
            }
            Text(pin.customerName)
                .font(.caption2.bold())
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThickMaterial)
                .clipShape(Capsule())
        }
    }

    private func technicianMarker(
        _ pin: LiveMapTechnicianPin
    ) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(color(named: pin.technicianColorName))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle().stroke(.white, lineWidth: 3)
                    }
                Image(systemName: "car.fill")
                    .foregroundStyle(.white)
            }
            Text(pin.technicianName)
                .font(.caption2.bold())
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThickMaterial)
                .clipShape(Capsule())
        }
    }

    private var reportingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This Device Location", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.headline)

            Text("Choose the technician carrying this device. PFSS will never invent locations for technicians who are not reporting.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Reporting As", selection: $reportingTechnicianID) {
                Text("Not reporting from this device")
                    .tag(UUID?.none)
                ForEach(activeTechnicians) { technician in
                    Text(technician.displayName)
                        .tag(Optional(technician.id))
                }
            }
            .pickerStyle(.menu)

            if reportingTechnicianID != nil {
                HStack {
                    Label(
                        locationManager.status.title,
                        systemImage: locationManager.status.systemImage
                    )
                    .font(.subheadline)
                    Spacer()
                    Button(locationButtonTitle) {
                        requestDeviceLocation()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .liveMapSurface(borderColor: .blue)
    }

    private func alertPanel(_ alerts: [LiveMapAlert]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Map Attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(alerts) { alert in
                Button {
                    if let assignmentID = alert.assignmentID {
                        selection = .assignment(assignmentID)
                    } else if let technicianID = alert.technicianID {
                        selection = .technician(technicianID)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text(alert.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if alert.assignmentID != nil || alert.technicianID != nil {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .liveMapSurface(borderColor: .orange)
    }

    private var mapLegend: some View {
        HStack(spacing: 18) {
            Label("Technician", systemImage: "car.fill")
            Label("Assignment", systemImage: "mappin.circle.fill")
            Label("Emergency", systemImage: "flag.fill")
                .foregroundStyle(.red)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .padding()
        .liveMapSurface()
    }

    @ViewBuilder
    private func destination(for selection: LiveMapSelection) -> some View {
        NavigationStack {
            switch selection {
            case .assignment(let assignmentID):
                AssignmentDetailView(
                    engine: store.assignmentEngine,
                    dispatchEngine: store.dispatchEngine,
                    assignmentID: assignmentID,
                    employees: store.activeEmployees,
                    customers: store.customers,
                    sites: store.sites
                )
            case .technician(let technicianID):
                if let employee = store.activeEmployees.first(where: {
                    $0.id == technicianID
                }) {
                    EmployeeDetailView(employee: employee)
                        .environmentObject(store)
                } else {
                    ContentUnavailableView(
                        "Technician Unavailable",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                }
            }
        }
        .environmentObject(store)
    }

    private func rebuildSnapshot() async {
        isLoading = true
        loadError = nil
        let generatedAt = Date()
        let observations = deviceObservations(generatedAt: generatedAt)
        let result = await store.liveMapSnapshot(
            on: selectedDate,
            technicianObservations: observations,
            generatedAt: generatedAt,
            calendar: calendar
        )
        guard Task.isCancelled == false else { return }
        snapshot = result
        cameraPosition = .automatic
        isLoading = false
    }

    private func deviceObservations(
        generatedAt: Date
    ) -> [LiveTechnicianLocationObservation] {
        guard calendar.isDate(selectedDate, inSameDayAs: generatedAt),
              let technicianID = reportingTechnicianID else {
            return []
        }

        let location = locationManager.currentLocation
        return [
            LiveTechnicianLocationObservation(
                technicianID: technicianID,
                coordinate: location.map {
                    RouteCoordinate(
                        latitude: $0.coordinate.latitude,
                        longitude: $0.coordinate.longitude
                    )
                },
                recordedAt: location?.timestamp,
                horizontalAccuracyMeters: location?.horizontalAccuracy,
                state: mapLocationState(locationManager.status)
            )
        ]
    }

    private func mapLocationState(
        _ status: TechnicianLocationStatus
    ) -> LiveMapLocationState {
        switch status {
        case .ready: return .live
        case .denied: return .permissionDenied
        case .restricted: return .restricted
        case .servicesDisabled: return .servicesDisabled
        case .unavailable: return .unavailable
        case .notRequested, .requestingPermission, .acquiringLocation:
            return .notReported
        }
    }

    private var locationButtonTitle: String {
        switch locationManager.status {
        case .notRequested, .denied, .restricted, .servicesDisabled:
            return "Enable"
        default:
            return "Refresh"
        }
    }

    private func requestDeviceLocation() {
        switch locationManager.status {
        case .notRequested:
            locationManager.requestLocationAccess()
        default:
            locationManager.refreshLocation()
        }
    }

    private func moveDate(by value: Int) {
        if let date = calendar.date(
            byAdding: .day,
            value: value,
            to: selectedDate
        ) {
            selectedDate = date
        }
    }

    private func technicianColor(_ technicianID: UUID) -> Color {
        guard let name = snapshot?.technicianPins.first(where: {
            $0.technicianID == technicianID
        })?.technicianColorName else { return .blue }
        return color(named: name)
    }

    private func color(named name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        default: return .blue
        }
    }
}

private enum LiveMapSelection: Identifiable {
    case assignment(UUID)
    case technician(UUID)

    var id: String {
        switch self {
        case .assignment(let id): return "assignment-\(id.uuidString)"
        case .technician(let id): return "technician-\(id.uuidString)"
        }
    }
}

private extension RouteCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

private extension View {
    func liveMapSurface(
        borderColor: Color = Color.secondary.opacity(0.18)
    ) -> some View {
        background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: 1)
            }
    }
}
