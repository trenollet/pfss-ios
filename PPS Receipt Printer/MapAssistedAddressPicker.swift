//
//  MapAssistedAddressPicker.swift
//  PPS Receipt Printer
//
//  Phase 18 – User-confirmed map and GPS address workflow.
//

import CoreLocation
import Combine
import MapKit
import SwiftUI

@MainActor
private final class MapAssistedAddressSession: ObservableObject, Identifiable {
    let id = UUID()
    let initialAddress: String
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var selectedCoordinate: CLLocationCoordinate2D?
    @Published var reviewedAddress: String
    @Published var isResolvingAddress = false
    @Published var errorMessage = ""
    var hasCenteredInitialAddress = false
    var selectionRevision = 0

    init(initialAddress: String) {
        self.initialAddress = initialAddress
        reviewedAddress = initialAddress
    }
}

struct MapAssistedAddressButton: View {
    @Binding var address: String
    let label: String

    @State private var pickerSession: MapAssistedAddressSession?

    var body: some View {
        Button {
            pickerSession = MapAssistedAddressSession(initialAddress: address)
        } label: {
            Label(label, systemImage: "map.fill")
        }
        .accessibilityHint("Opens a map to select and review an address")
        .sheet(item: $pickerSession) { session in
            NavigationStack {
                MapAssistedAddressPicker(
                    session: session,
                    onApply: { selectedAddress in
                        address = selectedAddress
                        pickerSession = nil
                    }
                )
            }
        }
    }
}

struct MapAssistedAddressPicker: View {
    @Environment(\.dismiss) private var dismiss

    let initialAddress: String
    let requiresCoordinate: Bool
    let onApply: (String, CLLocationCoordinate2D?) -> Void

    @StateObject private var locationManager = TechnicianLocationManager()
    @StateObject private var session: MapAssistedAddressSession
    @State private var isSatelliteView = false
    @FocusState private var isAddressFocused: Bool

    private let addressService = AddressSelectionService()

    init(
        initialAddress: String,
        onApply: @escaping (String) -> Void
    ) {
        self.initialAddress = initialAddress
        requiresCoordinate = false
        self.onApply = { address, _ in onApply(address) }
        _session = StateObject(
            wrappedValue: MapAssistedAddressSession(initialAddress: initialAddress)
        )
    }

    fileprivate init(
        session: MapAssistedAddressSession,
        onApply: @escaping (String) -> Void
    ) {
        initialAddress = session.initialAddress
        requiresCoordinate = false
        self.onApply = { address, _ in onApply(address) }
        _session = StateObject(wrappedValue: session)
    }

    init(
        initialAddress: String,
        onApplySelection: @escaping (String, CLLocationCoordinate2D) -> Void
    ) {
        self.initialAddress = initialAddress
        requiresCoordinate = true
        self.onApply = { address, coordinate in
            guard let coordinate else { return }
            onApplySelection(address, coordinate)
        }
        _session = StateObject(
            wrappedValue: MapAssistedAddressSession(initialAddress: initialAddress)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $session.cameraPosition) {
                    UserAnnotation()
                    if let selectedCoordinate = session.selectedCoordinate {
                        Marker(
                            "Selected Property",
                            coordinate: selectedCoordinate
                        )
                        .tint(.blue)
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .mapStyle(isSatelliteView ? .imagery : .standard)
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(
                        point,
                        from: .local
                    ) else { return }
                    selectMapPoint(coordinate)
                }
            }
            .frame(height: isAddressFocused ? 140 : 320)
            .animation(.easeInOut(duration: 0.2), value: isAddressFocused)
            .overlay(alignment: .topTrailing) {
                if !isAddressFocused {
                    Button {
                        isSatelliteView.toggle()
                    } label: {
                        Label(
                            isSatelliteView ? "Standard" : "Satellite",
                            systemImage: isSatelliteView ? "map" : "globe.americas.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .accessibilityLabel(
                        isSatelliteView
                            ? "Switch to standard map"
                            : "Switch to satellite map"
                    )
                }
            }

            Form {
                Section {
                    Button {
                        useCurrentLocation()
                    } label: {
                        Label(
                            currentLocationButtonTitle,
                            systemImage: locationManager.status.systemImage
                        )
                    }
                    .disabled(session.isResolvingAddress)

                    if session.isResolvingAddress {
                        HStack {
                            ProgressView()
                            Text("Finding the street address…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Review Address") {
                    TextField(
                        "Street, City, State ZIP",
                        text: $session.reviewedAddress,
                        axis: .vertical
                    )
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2...4)
                    .focused($isAddressFocused)

                    Text("Tap address above to modify")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !session.errorMessage.isEmpty {
                    Section {
                        Label(
                            session.errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .frame(minHeight: 260)
        }
        .navigationTitle("Select Address")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            EditorKeyboardDismissAction(isVisible: isAddressFocused) {
                isAddressFocused = false
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply Address") {
                    onApply(
                        session.reviewedAddress.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ),
                        session.selectedCoordinate
                    )
                }
                .disabled(
                    session.reviewedAddress.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || session.isResolvingAddress ||
                    (requiresCoordinate && session.selectedCoordinate == nil)
                )
            }
        }
        .task {
            await centerInitialAddressIfPossible()
        }
    }

    private var currentLocationButtonTitle: String {
        switch locationManager.status {
        case .requestingPermission:
            return "Waiting for Location Permission"
        case .acquiringLocation:
            return "Finding My Location"
        case .denied:
            return "Location Denied — Browse Map Instead"
        case .restricted:
            return "Location Restricted — Browse Map Instead"
        case .servicesDisabled:
            return "Location Disabled — Browse Map Instead"
        default:
            return "Use My Current Location"
        }
    }

    private func useCurrentLocation() {
        session.errorMessage = ""
        let requestRevision = beginUserSelection()
        locationManager.requestCurrentLocation { result in
            guard requestRevision == session.selectionRevision else { return }
            switch result {
            case .success(let location):
                session.cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 350,
                        longitudinalMeters: 350
                    )
                )
                resolve(
                    location,
                    source: .currentLocation,
                    revision: requestRevision
                )
            case .failure(let error):
                session.errorMessage = error.localizedDescription +
                    " You can still browse the map or type the address manually."
            }
        }
    }

    private func selectMapPoint(_ coordinate: CLLocationCoordinate2D) {
        let requestRevision = beginUserSelection()
        session.selectedCoordinate = coordinate
        resolve(
            CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            source: .selectedMapPoint,
            revision: requestRevision
        )
    }

    private func beginUserSelection() -> Int {
        session.selectionRevision += 1
        return session.selectionRevision
    }

    private func resolve(
        _ location: CLLocation,
        source: AddressCandidate.Source,
        revision: Int
    ) {
        session.selectedCoordinate = location.coordinate
        session.isResolvingAddress = true
        session.errorMessage = ""

        Task { @MainActor in
            defer {
                if revision == session.selectionRevision {
                    session.isResolvingAddress = false
                }
            }
            do {
                let candidate = try await addressService.candidate(
                    for: location,
                    source: source
                )
                guard revision == session.selectionRevision else { return }
                session.reviewedAddress = candidate.formattedAddress
            } catch {
                guard revision == session.selectionRevision else { return }
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func centerInitialAddressIfPossible() async {
        guard !session.hasCenteredInitialAddress else { return }
        session.hasCenteredInitialAddress = true
        let cleaned = initialAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleaned.isEmpty else { return }
        let startupRevision = session.selectionRevision

        do {
            let location = try await AddressGeocoder().geocode(
                address: cleaned
            )
            guard startupRevision == session.selectionRevision else { return }
            session.selectedCoordinate = location.coordinate
            session.cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
            )
        } catch {
            // Existing or manually entered addresses remain valid even when
            // the network cannot position them on the map.
        }
    }
}
