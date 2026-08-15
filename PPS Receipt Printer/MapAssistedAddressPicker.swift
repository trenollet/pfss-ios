//
//  MapAssistedAddressPicker.swift
//  PPS Receipt Printer
//
//  Phase 18 – User-confirmed map and GPS address workflow.
//

import CoreLocation
import MapKit
import SwiftUI

struct MapAssistedAddressButton: View {
    @Binding var address: String
    let label: String

    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            Label(label, systemImage: "map.fill")
        }
        .accessibilityHint("Opens a map to select and review an address")
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                MapAssistedAddressPicker(
                    initialAddress: address,
                    onApply: { selectedAddress in
                        address = selectedAddress
                        isShowingPicker = false
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
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var reviewedAddress = ""
    @State private var isResolvingAddress = false
    @State private var errorMessage = ""
    @State private var hasCenteredInitialAddress = false
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
    }

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let selectedCoordinate {
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
                    .disabled(isResolvingAddress)

                    if isResolvingAddress {
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
                        text: $reviewedAddress,
                        axis: .vertical
                    )
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2...4)
                    .focused($isAddressFocused)

                    Text("Tap address above to modify")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Label(
                            errorMessage,
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
                        reviewedAddress.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ),
                        selectedCoordinate
                    )
                }
                .disabled(
                    reviewedAddress.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || isResolvingAddress ||
                    (requiresCoordinate && selectedCoordinate == nil)
                )
            }
        }
        .task {
            reviewedAddress = initialAddress
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
        errorMessage = ""
        locationManager.requestCurrentLocation { result in
            switch result {
            case .success(let location):
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 350,
                        longitudinalMeters: 350
                    )
                )
                resolve(
                    location,
                    source: .currentLocation
                )
            case .failure(let error):
                errorMessage = error.localizedDescription +
                    " You can still browse the map or type the address manually."
            }
        }
    }

    private func selectMapPoint(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        resolve(
            CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            source: .selectedMapPoint
        )
    }

    private func resolve(
        _ location: CLLocation,
        source: AddressCandidate.Source
    ) {
        selectedCoordinate = location.coordinate
        isResolvingAddress = true
        errorMessage = ""

        Task { @MainActor in
            defer { isResolvingAddress = false }
            do {
                let candidate = try await addressService.candidate(
                    for: location,
                    source: source
                )
                reviewedAddress = candidate.formattedAddress
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func centerInitialAddressIfPossible() async {
        guard !hasCenteredInitialAddress else { return }
        hasCenteredInitialAddress = true
        let cleaned = initialAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleaned.isEmpty else { return }

        do {
            let location = try await AddressGeocoder().geocode(
                address: cleaned
            )
            selectedCoordinate = location.coordinate
            cameraPosition = .region(
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
