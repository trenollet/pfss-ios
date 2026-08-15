//
//  MileageWorkspaceView.swift
//  PPS Receipt Printer
//
//  Phase 19 – Mileage permission, status, and trip review workspace.
//

import MapKit
import SwiftUI

struct MileageTrackingSettingsView: View {
    @ObservedObject private var coordinator = MileageLocationCoordinator.shared
    @State private var isShowingPermissionExplanation = false

    var body: some View {
        List {
            Section {
                Toggle(
                    "Automatic Mileage Tracking",
                    isOn: Binding(
                        get: { coordinator.isAutomaticTrackingEnabled },
                        set: handleTrackingToggle
                    )
                )

                HStack {
                    Label(
                        coordinator.status.title,
                        systemImage: coordinator.status.systemImage
                    )
                    Spacer()
                    if coordinator.status == .permissionRequired {
                        Button("Review Access") {
                            isShowingPermissionExplanation = true
                        }
                    }
                }

                if !coordinator.lastErrorMessage.isEmpty {
                    Text(coordinator.lastErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Automatic Tracking")
            } footer: {
                Text(
                    "Trip review and manual mileage entry are available from the Mileage tile on Dashboard. Force-quitting PFSS or disabling Location Services can prevent automatic detection until PFSS is reopened."
                )
            }
        }
        .navigationTitle("Mileage Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Allow Automatic Mileage Tracking?",
            isPresented: $isShowingPermissionExplanation
        ) {
            Button("Continue") {
                coordinator.enableAutomaticTracking()
            }
            Button("Not Now", role: .cancel) { }
            if coordinator.authorizationStatus == .denied {
                Button("Open Settings") {
                    coordinator.openSystemSettings()
                }
            }
        } message: {
            Text(
                "PFSS uses location in the background to detect likely vehicle trips, measure the route, and place completed trips in your private review queue. PFSS requests Always access only after you choose to enable this feature."
            )
        }
        .task {
            if !coordinator.isConfigured {
                await coordinator.configureFromCurrentSession()
            }
        }
    }

    private func handleTrackingToggle(_ enabled: Bool) {
        if enabled {
            isShowingPermissionExplanation = true
        } else {
            coordinator.disableAutomaticTracking()
        }
    }
}

struct MileageWorkspaceView: View {
    private enum Destination: String, CaseIterable, Identifiable {
        case review = "To Review"
        case history = "Trip History"
        case reports = "Reports"

        var id: String { rawValue }
    }

    private enum HistoryClassification: String, CaseIterable, Identifiable {
        case all = "All"
        case business = "Business"
        case personal = "Personal"

        var id: String { rawValue }
    }

    private enum HistoryOrder: String, CaseIterable, Identifiable {
        case newest = "Newest First"
        case oldest = "Oldest First"

        var id: String { rawValue }
    }

    @ObservedObject private var coordinator = MileageLocationCoordinator.shared
    @ObservedObject private var repository = MileageTripRepository.shared
    @State private var destination: Destination = .review
    @State private var lastClassification: (
        tripID: UUID,
        previous: MileageTripClassification
    )?
    @State private var errorMessage = ""
    @State private var isShowingError = false
    @State private var historySearch = ""
    @State private var historyClassification = HistoryClassification.all
    @State private var historyOrder = HistoryOrder.newest
    @State private var filterHistoryByDate = false
    @State private var historyStartDate = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var historyEndDate = Date()
    @State private var reportStartDate = Calendar.current.dateInterval(
        of: .month,
        for: Date()
    )?.start ?? Date()
    @State private var reportEndDate = Date()
    @State private var reportClassification = MileageReportClassification.business
    @State private var reportURL: URL?

    private var filteredHistoryTrips: [MileageTrip] {
        let cleanedSearch = historySearch.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let lowerBound = Calendar.current.startOfDay(
            for: min(historyStartDate, historyEndDate)
        )
        let upperDay = Calendar.current.startOfDay(
            for: max(historyStartDate, historyEndDate)
        )
        let upperBound = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: upperDay
        ) ?? upperDay.addingTimeInterval(86_400)

        return repository.classifiedTrips
            .filter { trip in
                switch historyClassification {
                case .all: return true
                case .business: return trip.classification == .business
                case .personal: return trip.classification == .personal
                }
            }
            .filter { trip in
                !filterHistoryByDate ||
                    (trip.startedAt >= lowerBound && trip.startedAt < upperBound)
            }
            .filter { trip in
                guard !cleanedSearch.isEmpty else { return true }
                let searchable = [
                    trip.startAddress ?? "",
                    trip.endAddress ?? "",
                    trip.businessPurpose,
                    trip.note,
                    trip.classification.rawValue,
                    trip.startedAt.formatted(date: .long, time: .shortened)
                ].joined(separator: " ")
                return searchable.localizedCaseInsensitiveContains(cleanedSearch)
            }
            .sorted {
                historyOrder == .newest
                    ? $0.startedAt > $1.startedAt
                    : $0.startedAt < $1.startedAt
            }
    }

    private var reportSummary: MileageReportSummary {
        MileageReportEngine.summary(
            trips: repository.trips,
            startDate: reportStartDate,
            endDate: reportEndDate,
            classification: reportClassification
        )
    }

    var body: some View {
        List {
            Section {
                Picker("Mileage View", selection: $destination) {
                    ForEach(Destination.allCases) { destination in
                        Text(destination.rawValue).tag(destination)
                    }
                }
                .pickerStyle(.segmented)
            }

            if destination == .review {
                tripSection(
                    title: "Unclassified Trips",
                    trips: repository.unclassifiedTrips,
                    emptyTitle: "No Trips to Review",
                    emptyDescription: "Completed drives that need a Business or Personal choice will appear here."
                )
            } else if destination == .history {
                historyFilterSection
                tripSection(
                    title: "Classified Trips",
                    trips: filteredHistoryTrips,
                    emptyTitle: "No Trip History",
                    emptyDescription: "No classified trips match these filters."
                )
            } else {
                reportSections
            }
        }
        .navigationTitle("Mileage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ManualMileageTripView()
                } label: {
                    Label("Add Trip", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let lastClassification {
                HStack {
                    Text("Trip classified")
                    Spacer()
                    Button("Undo") {
                        classify(
                            tripID: lastClassification.tripID,
                            as: lastClassification.previous,
                            preserveUndo: false
                        )
                    }
                }
                .padding(.horizontal)
                .frame(minHeight: 48)
                .background(.bar)
            }
        }
        .alert("Unable to Update Mileage", isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            if !coordinator.isConfigured {
                await coordinator.configureFromCurrentSession()
            }
        }
        .onChange(of: reportStartDate) { _, _ in reportURL = nil }
        .onChange(of: reportEndDate) { _, _ in reportURL = nil }
        .onChange(of: reportClassification) { _, _ in reportURL = nil }
    }

    private var historyFilterSection: some View {
        Section("Find Trips") {
            Label {
                TextField("Search locations, purpose, or notes", text: $historySearch)
                    .textInputAutocapitalization(.never)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
            Picker("Classification", selection: $historyClassification) {
                ForEach(HistoryClassification.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            Picker("Sort", selection: $historyOrder) {
                ForEach(HistoryOrder.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            Toggle("Filter by Date", isOn: $filterHistoryByDate)
            if filterHistoryByDate {
                DatePicker(
                    "From",
                    selection: $historyStartDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "Through",
                    selection: $historyEndDate,
                    displayedComponents: .date
                )
            }
        }
    }

    @ViewBuilder
    private var reportSections: some View {
        Section("Report Options") {
            DatePicker(
                "From",
                selection: $reportStartDate,
                displayedComponents: .date
            )
            DatePicker(
                "Through",
                selection: $reportEndDate,
                displayedComponents: .date
            )
            Picker("Trips", selection: $reportClassification) {
                ForEach(MileageReportClassification.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        }

        Section("Mileage Summary") {
            LabeledContent("Trips", value: reportSummary.trips.count.formatted())
            LabeledContent(
                "Business",
                value: mileageText(reportSummary.businessMiles)
            )
            LabeledContent(
                "Personal",
                value: mileageText(reportSummary.personalMiles)
            )
            LabeledContent("Total", value: mileageText(reportSummary.totalMiles))
                .fontWeight(.semibold)
        }

        Section {
            Button(action: generateCSVReport) {
                Label("Generate CSV Report", systemImage: "doc.badge.plus")
            }
            .disabled(reportSummary.trips.isEmpty)

            if let reportURL {
                ShareLink(
                    item: reportURL,
                    preview: SharePreview("PFSS Mileage Report")
                ) {
                    Label("Share CSV Report", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            Text(
                reportSummary.trips.isEmpty
                    ? "No classified trips match this report."
                    : "CSV reports can be saved, emailed, AirDropped, or shared through another authorized app."
            )
        }
    }

    private func mileageText(_ miles: Double) -> String {
        miles.formatted(.number.precision(.fractionLength(2))) + " mi"
    }

    private func generateCSVReport() {
        let summary = reportSummary
        guard !summary.trips.isEmpty else { return }
        let csv = MileageReportEngine.csv(for: summary)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "PFSS-Mileage-\(formatter.string(from: min(reportStartDate, reportEndDate)))-to-\(formatter.string(from: max(reportStartDate, reportEndDate))).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            try repository.markExported(
                tripIDs: Set(summary.trips.map(\.id))
            )
            reportURL = url
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    @ViewBuilder
    private func tripSection(
        title: String,
        trips: [MileageTrip],
        emptyTitle: String,
        emptyDescription: String
    ) -> some View {
        Section(title) {
            if trips.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "car.rear.road.lane",
                    description: Text(emptyDescription)
                )
            } else {
                ForEach(trips) { trip in
                    MileageTripRow(trip: trip) { classification in
                        classify(tripID: trip.id, as: classification)
                    }
                }
            }
        }
    }

    private func classify(
        tripID: UUID,
        as classification: MileageTripClassification,
        preserveUndo: Bool = true
    ) {
        let previous = repository.trips.first(where: { $0.id == tripID })?
            .classification ?? .unclassified
        do {
            try repository.classify(tripID: tripID, as: classification)
            lastClassification = preserveUndo
                ? (tripID: tripID, previous: previous)
                : nil
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}

private struct ManualMileageTripView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repository = MileageTripRepository.shared
    let tripID: UUID?
    @State private var startedAt = Date()
    @State private var startLocation = ""
    @State private var endLocation = ""
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var endCoordinate: CLLocationCoordinate2D?
    @State private var calculatedDistanceMeters: Double?
    @State private var isCalculatingDistance = false
    @State private var distanceError = ""
    @State private var isSelectingStart = false
    @State private var isSelectingEnd = false
    @State private var isRoundTrip = false
    @State private var classification = MileageTripClassification.business
    @State private var businessPurpose = ""
    @State private var note = ""
    @State private var errorMessage = ""
    @State private var isShowingError = false
    @State private var didLoadTrip = false

    init(tripID: UUID? = nil) {
        self.tripID = tripID
    }

    private var canSave: Bool {
        guard let calculatedDistanceMeters else { return false }
        return calculatedDistanceMeters > 0 && !isCalculatingDistance
    }

    private var finalDistanceMeters: Double? {
        calculatedDistanceMeters.map { isRoundTrip ? $0 * 2 : $0 }
    }

    var body: some View {
        List {
            Section("Trip") {
                DatePicker(
                    "Trip Date & Time",
                    selection: $startedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Button {
                    isSelectingStart = true
                } label: {
                    mileageLocationLabel(
                        title: "Starting Location",
                        address: startLocation,
                        systemImage: "location.fill"
                    )
                }

                Button {
                    isSelectingEnd = true
                } label: {
                    mileageLocationLabel(
                        title: "Ending Location",
                        address: endLocation,
                        systemImage: "flag.checkered"
                    )
                }

                LabeledContent("Driving Distance") {
                    if isCalculatingDistance {
                        ProgressView()
                    } else if let calculatedDistanceMeters {
                        Text(
                            (calculatedDistanceMeters / 1_609.344)
                                .formatted(.number.precision(.fractionLength(1))) + " mi"
                        )
                        .fontWeight(.semibold)
                    } else {
                        Text("Select both locations")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Round Trip", isOn: $isRoundTrip)

                if isRoundTrip, let calculatedDistanceMeters {
                    LabeledContent(
                        "Round-Trip Total",
                        value: (calculatedDistanceMeters * 2 / 1_609.344)
                            .formatted(.number.precision(.fractionLength(1))) + " mi"
                    )
                    .fontWeight(.semibold)
                }

                if !distanceError.isEmpty {
                    Label(distanceError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Classification") {
                Picker("Type", selection: $classification) {
                    Text("Business").tag(MileageTripClassification.business)
                    Text("Personal").tag(MileageTripClassification.personal)
                    Text("Unclassified").tag(MileageTripClassification.unclassified)
                }
                TextField("Business Purpose", text: $businessPurpose)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(tripID == nil ? "Add Mileage Trip" : "Edit Mileage Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .alert("Unable to Add Trip", isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $isSelectingStart) {
            NavigationStack {
                MapAssistedAddressPicker(
                    initialAddress: startLocation,
                    onApplySelection: { address, coordinate in
                        startLocation = address
                        startCoordinate = coordinate
                        isSelectingStart = false
                        recalculateDistanceIfPossible()
                    }
                )
            }
        }
        .sheet(isPresented: $isSelectingEnd) {
            NavigationStack {
                MapAssistedAddressPicker(
                    initialAddress: endLocation,
                    onApplySelection: { address, coordinate in
                        endLocation = address
                        endCoordinate = coordinate
                        isSelectingEnd = false
                        recalculateDistanceIfPossible()
                    }
                )
            }
        }
        .onAppear(perform: loadTripIfNeeded)
    }

    private func mileageLocationLabel(
        title: String,
        address: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(address.isEmpty ? "Select on Map" : address)
                    .font(.caption)
                    .foregroundStyle(
                        address.isEmpty ? Color.blue : Color.secondary
                    )
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func recalculateDistanceIfPossible() {
        calculatedDistanceMeters = nil
        distanceError = ""
        guard let startCoordinate, let endCoordinate else { return }
        isCalculatingDistance = true

        Task { @MainActor in
            defer { isCalculatingDistance = false }
            do {
                let estimate = try await MapKitRouteTravelEstimator()
                    .estimateTravel(
                        from: RouteCoordinate(
                            latitude: startCoordinate.latitude,
                            longitude: startCoordinate.longitude
                        ),
                        to: RouteCoordinate(
                            latitude: endCoordinate.latitude,
                            longitude: endCoordinate.longitude
                        ),
                        departingAt: startedAt
                    )
                calculatedDistanceMeters = estimate.distanceMeters
            } catch {
                distanceError = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let context = repository.configuredContext,
              let finalDistanceMeters,
              finalDistanceMeters > 0 else {
            errorMessage = "Select both locations so PFSS can calculate this trip's mileage."
            isShowingError = true
            return
        }
        let now = Date()
        if let tripID,
           var trip = repository.trips.first(where: { $0.id == tripID }) {
            let previousClassification = trip.classification
            trip.startedAt = startedAt
            trip.endedAt = startedAt
            trip.distanceMeters = finalDistanceMeters
            trip.startAddress = startLocation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            trip.endAddress = endLocation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            trip.startCoordinate = startCoordinate.map {
                MileageTripCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
            trip.endCoordinate = endCoordinate.map {
                MileageTripCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
            trip.isRoundTrip = isRoundTrip
            trip.classification = classification
            trip.businessPurpose = businessPurpose
            trip.note = note
            trip.classifiedAt = classification == .unclassified
                ? nil
                : (trip.classifiedAt ?? now)
            trip.updatedAt = now
            if previousClassification != classification {
                trip.classificationHistory.append(
                    MileageTripClassificationChange(
                        previousValue: previousClassification,
                        newValue: classification,
                        changedAt: now
                    )
                )
            }
            do {
                try repository.save(trip)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
            return
        }

        let trip = MileageTrip(
            id: UUID(),
            accountID: context.accountID,
            userID: context.userID,
            originatingDeviceID: context.deviceID,
            entrySource: .manual,
            startedAt: startedAt,
            endedAt: startedAt,
            timeZoneIdentifier: context.timeZoneIdentifier,
            route: [],
            distanceMeters: finalDistanceMeters,
            startAddress: startLocation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            endAddress: endLocation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            startCoordinate: startCoordinate.map {
                MileageTripCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            endCoordinate: endCoordinate.map {
                MileageTripCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            isRoundTrip: isRoundTrip,
            classification: classification,
            businessPurpose: businessPurpose,
            note: note,
            createdAt: now,
            classifiedAt: classification == .unclassified ? nil : now,
            updatedAt: now,
            detectionVersion: 1,
            accuracy: MileageTripAccuracySummary(
                acceptedPointCount: 0,
                rejectedPointCount: 0,
                averageHorizontalAccuracyMeters: 0
            )
        )
        do {
            try repository.save(trip)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func loadTripIfNeeded() {
        guard !didLoadTrip else { return }
        didLoadTrip = true
        guard let tripID,
              let trip = repository.trips.first(where: { $0.id == tripID }) else {
            return
        }
        startedAt = trip.startedAt
        startLocation = trip.startAddress ?? ""
        endLocation = trip.endAddress ?? ""
        startCoordinate = trip.startCoordinate.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        endCoordinate = trip.endCoordinate.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        isRoundTrip = trip.isRoundTrip == true
        calculatedDistanceMeters = isRoundTrip
            ? trip.distanceMeters / 2
            : trip.distanceMeters
        classification = trip.classification
        businessPurpose = trip.businessPurpose
        note = trip.note
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct MileageTripRow: View {
    let trip: MileageTrip
    let classify: (MileageTripClassification) -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                MileageTripDetailView(tripID: trip.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text(trip.entrySource == .manual
                        ? "\(trip.distanceMiles.formatted(.number.precision(.fractionLength(1)))) mi"
                        : "\(trip.endedAt.formatted(date: .omitted, time: .shortened)) · \(trip.distanceMiles.formatted(.number.precision(.fractionLength(1)))) mi"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text(trip.entrySource == .automatic ? "Automatically tracked" : "Manual entry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if trip.classification == .unclassified {
                classificationButton("P", color: .orange) {
                    classify(.personal)
                }
                classificationButton("B", color: .blue) {
                    classify(.business)
                }
            } else {
                Text(trip.classification == .business ? "Business" : "Personal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        trip.classification == .business ? .blue : .orange
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private func classificationButton(
        _ title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "B" ? "Classify Business" : "Classify Personal")
    }
}

private struct MileageTripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repository = MileageTripRepository.shared
    let tripID: UUID
    @State private var businessPurpose = ""
    @State private var note = ""
    @State private var isShowingDeleteConfirmation = false

    private var trip: MileageTrip? {
        repository.trips.first { $0.id == tripID }
    }

    var body: some View {
        List {
            if let trip {
                if trip.route.count > 1 {
                    Section {
                        Map {
                            MapPolyline(
                                coordinates: trip.route.map {
                                    CLLocationCoordinate2D(
                                        latitude: $0.latitude,
                                        longitude: $0.longitude
                                    )
                                }
                            )
                            .stroke(.blue, lineWidth: 5)
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .listRowInsets(EdgeInsets())
                } else if let start = trip.startCoordinate,
                          let end = trip.endCoordinate {
                    Section {
                        Map {
                            Marker(
                                "Start",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: start.latitude,
                                    longitude: start.longitude
                                )
                            )
                            .tint(.green)
                            Marker(
                                "End",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: end.latitude,
                                    longitude: end.longitude
                                )
                            )
                            .tint(.red)
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .listRowInsets(EdgeInsets())
                }

                Section("Trip") {
                    LabeledContent("Started", value: trip.startedAt.formatted())
                    if trip.entrySource == .automatic {
                        LabeledContent("Ended", value: trip.endedAt.formatted())
                    }
                    LabeledContent(
                        "Distance",
                        value: "\(trip.distanceMiles.formatted(.number.precision(.fractionLength(2)))) miles"
                    )
                    LabeledContent(
                        "Source",
                        value: trip.entrySource == .automatic ? "Automatic" : "Manual"
                    )
                    if trip.entrySource == .manual {
                        LabeledContent(
                            "Trip Type",
                            value: trip.isRoundTrip == true ? "Round Trip" : "One Way"
                        )
                    }
                    if let startAddress = trip.startAddress {
                        LabeledContent("Start", value: startAddress)
                    }
                    if let endAddress = trip.endAddress {
                        LabeledContent("End", value: endAddress)
                    }
                }

                Section("Classification") {
                    Picker(
                        "Type",
                        selection: Binding(
                            get: { trip.classification },
                            set: { try? repository.classify(tripID: tripID, as: $0) }
                        )
                    ) {
                        Text("Unclassified").tag(MileageTripClassification.unclassified)
                        Text("Business").tag(MileageTripClassification.business)
                        Text("Personal").tag(MileageTripClassification.personal)
                    }
                    TextField("Business Purpose", text: $businessPurpose)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Delete Trip", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if trip?.entrySource == .manual {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ManualMileageTripView(tripID: tripID)
                    } label: {
                        Text("Edit")
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? repository.update(
                        tripID: tripID,
                        businessPurpose: businessPurpose,
                        note: note
                    )
                }
            }
        }
        .onAppear {
            businessPurpose = trip?.businessPurpose ?? ""
            note = trip?.note ?? ""
        }
        .confirmationDialog(
            "Delete this mileage trip?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                try? repository.delete(tripID: tripID)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
