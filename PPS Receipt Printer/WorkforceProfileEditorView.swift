//
//  WorkforceProfileEditorView.swift
//  PPS Receipt Printer
//
//  Phase 14.5 — Workforce Intelligence
//

import SwiftUI

struct WorkforceProfileEditorView: View {
    @Binding var profile: WorkforceOperationalProfile
    let employeeName: String

    @State private var skillDraft: WorkforceSkill?
    @State private var certificationDraft: WorkforceCertification?
    @State private var resourceDraft: WorkforceResourceAccess?
    @State private var availabilityDraft: WorkforceAvailabilityException?

    @FocusState private var notesAreFocused: Bool

    var body: some View {
        Form {
            overviewSection
            skillsSection
            certificationsSection
            resourcesSection
            availabilitySection
            planningSection
            metricsSection
            notesSection
        }
        .navigationTitle("Workforce Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notesAreFocused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        notesAreFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss Keyboard")
                }
            }
        }
        .sheet(item: $skillDraft) { draft in
            WorkforceSkillEditorView(skill: draft) { updated in
                replaceSkill(updated)
            }
        }
        .sheet(item: $certificationDraft) { draft in
            WorkforceCertificationEditorView(
                certification: draft
            ) { updated in
                replaceCertification(updated)
            }
        }
        .sheet(item: $resourceDraft) { draft in
            WorkforceResourceEditorView(resource: draft) { updated in
                replaceResource(updated)
            }
        }
        .sheet(item: $availabilityDraft) { draft in
            WorkforceAvailabilityEditorView(exception: draft) { updated in
                replaceAvailability(updated)
            }
        }
    }

    private var overviewSection: some View {
        Section("Operational Profile") {
            LabeledContent("Employee", value: employeeName)

            LabeledContent("Skills") {
                Text(profile.skills.count.formatted())
            }

            LabeledContent("Active Certifications") {
                Text(
                    profile.certifications.filter {
                        $0.isValid()
                    }.count.formatted()
                )
            }

            LabeledContent("Available Resources") {
                Text(
                    profile.resourceAccess.filter(\.isAvailable)
                        .count.formatted()
                )
            }

            if !profile.hasIntelligenceData {
                Label(
                    "No workforce intelligence has been entered yet. Missing optional information will not prevent normal scheduling.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var skillsSection: some View {
        Section {
            ForEach(sortedSkills) { skill in
                Button {
                    skillDraft = skill
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.name)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)

                            Text(skillSubtitle(skill))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if skill.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                                .accessibilityLabel("Verified")
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        profile.skills.removeAll { $0.id == skill.id }
                    }
                }
            }

            Button {
                skillDraft = WorkforceSkill(name: "")
            } label: {
                Label("Add Skill", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Skills and Proficiency")
        } footer: {
            Text("Skills can match a service type or describe a custom field capability.")
        }
    }

    private var certificationsSection: some View {
        Section {
            ForEach(sortedCertifications) { certification in
                Button {
                    certificationDraft = certification
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(certification.name)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)

                            Text(certificationSubtitle(certification))
                                .font(.caption)
                                .foregroundStyle(
                                    certification.status() == .expired
                                        ? .red
                                        : .secondary
                                )
                        }

                        Spacer()

                        certificationStatusIcon(certification)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        profile.certifications.removeAll {
                            $0.id == certification.id
                        }
                    }
                }
            }

            Button {
                certificationDraft = WorkforceCertification(name: "")
            } label: {
                Label(
                    "Add Certification",
                    systemImage: "plus.circle.fill"
                )
            }
        } header: {
            Text("Certifications")
        } footer: {
            Text("Expired or inactive required certifications will be reported as dispatch blockers.")
        }
    }

    private var resourcesSection: some View {
        Section {
            ForEach(sortedResources) { resource in
                Button {
                    resourceDraft = resource
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: resourceIcon(resource.type))
                            .foregroundStyle(
                                resource.isAvailable ? .blue : .secondary
                            )
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(resource.name)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)

                            Text(
                                resource.isAvailable
                                    ? resource.type.rawValue
                                    : "\(resource.type.rawValue) · Unavailable"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        profile.resourceAccess.removeAll {
                            $0.id == resource.id
                        }
                    }
                }
            }

            Button {
                resourceDraft = WorkforceResourceAccess(
                    name: "",
                    type: .equipment
                )
            } label: {
                Label("Add Equipment or Vehicle", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Equipment and Vehicle Access")
        } footer: {
            Text("Record resources this employee can actually take into the field.")
        }
    }

    private var availabilitySection: some View {
        Section {
            ForEach(sortedAvailability) { exception in
                Button {
                    availabilityDraft = exception
                } label: {
                    HStack {
                        Image(systemName: availabilityIcon(exception.kind))
                            .foregroundStyle(
                                availabilityColor(exception.kind)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exception.kind.rawValue)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)

                            Text(availabilitySubtitle(exception))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        profile.availabilityExceptions.removeAll {
                            $0.id == exception.id
                        }
                    }
                }
            }

            Button {
                let start = Calendar.current.date(
                    bySettingHour: 8,
                    minute: 0,
                    second: 0,
                    of: Date()
                ) ?? Date()
                availabilityDraft = WorkforceAvailabilityException(
                    kind: .unavailable,
                    startDate: start,
                    endDate: start.addingTimeInterval(8 * 60 * 60)
                )
            } label: {
                Label("Add Availability Exception", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Availability Exceptions")
        } footer: {
            Text("Normal working days and hours remain on the employee record. Add only temporary exceptions here.")
        }
    }

    private var planningSection: some View {
        Section("Planning Preferences") {
            Toggle(
                "Limit Daily Assignments",
                isOn: maximumAssignmentsEnabled
            )

            if profile.maximumDailyAssignments != nil {
                Stepper(
                    value: maximumAssignmentsBinding,
                    in: 1...20
                ) {
                    LabeledContent(
                        "Maximum Jobs",
                        value: maximumAssignmentsBinding.wrappedValue.formatted()
                    )
                }
            }

            Toggle(
                "Limit Travel Distance",
                isOn: maximumTravelEnabled
            )

            if profile.maximumTravelDistanceMiles != nil {
                Stepper(
                    value: maximumTravelBinding,
                    in: 5...500,
                    step: 5
                ) {
                    LabeledContent("Maximum Travel") {
                        Text(
                            "\(maximumTravelBinding.wrappedValue.formatted(.number.precision(.fractionLength(0)))) mi"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        let metrics = profile.historicalMetrics

        Section {
            LabeledContent(
                "Completed Assignments",
                value: metrics.completedAssignmentCount.formatted()
            )

            LabeledContent("Recorded Labor") {
                Text(
                    SchedulingCalculator.formattedDuration(
                        minutes: metrics.totalRecordedLaborMinutes
                    )
                )
            }

            if let average = metrics.averageAssignmentMinutes {
                LabeledContent("Average Assignment") {
                    Text(
                        SchedulingCalculator.formattedDuration(
                            minutes: Int(average.rounded())
                        )
                    )
                }
            }

            if let rating = metrics.averageCustomerRating {
                LabeledContent("Customer Rating") {
                    Text(
                        rating.formatted(
                            .number.precision(.fractionLength(1))
                        ) + " / 5"
                    )
                }
            }

            if let calculatedDate = metrics.calculatedDate {
                LabeledContent("Last Calculated") {
                    Text(
                        calculatedDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
            } else {
                Text("Metrics will populate from completed Assignment history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Operational History")
        }
    }

    private var notesSection: some View {
        Section("Operational Notes") {
            TextEditor(text: $profile.operationalNotes)
                .frame(minHeight: 100)
                .focused($notesAreFocused)
        }
    }

    private var sortedSkills: [WorkforceSkill] {
        profile.skills.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    private var sortedCertifications: [WorkforceCertification] {
        profile.certifications.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    private var sortedResources: [WorkforceResourceAccess] {
        profile.resourceAccess.sorted {
            if $0.type != $1.type {
                return $0.type.rawValue < $1.type.rawValue
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    private var sortedAvailability: [WorkforceAvailabilityException] {
        profile.availabilityExceptions.sorted {
            $0.startDate < $1.startDate
        }
    }

    private var maximumAssignmentsEnabled: Binding<Bool> {
        Binding(
            get: { profile.maximumDailyAssignments != nil },
            set: { enabled in
                profile.maximumDailyAssignments = enabled ? 8 : nil
            }
        )
    }

    private var maximumAssignmentsBinding: Binding<Int> {
        Binding(
            get: { profile.maximumDailyAssignments ?? 8 },
            set: { profile.maximumDailyAssignments = max($0, 1) }
        )
    }

    private var maximumTravelEnabled: Binding<Bool> {
        Binding(
            get: { profile.maximumTravelDistanceMiles != nil },
            set: { enabled in
                profile.maximumTravelDistanceMiles = enabled ? 50 : nil
            }
        )
    }

    private var maximumTravelBinding: Binding<Double> {
        Binding(
            get: { profile.maximumTravelDistanceMiles ?? 50 },
            set: { profile.maximumTravelDistanceMiles = max($0, 0) }
        )
    }

    private func replaceSkill(_ skill: WorkforceSkill) {
        profile.skills.removeAll { $0.id == skill.id }
        profile.skills.append(skill)
    }

    private func replaceCertification(
        _ certification: WorkforceCertification
    ) {
        profile.certifications.removeAll {
            $0.id == certification.id
        }
        profile.certifications.append(certification)
    }

    private func replaceResource(_ resource: WorkforceResourceAccess) {
        profile.resourceAccess.removeAll { $0.id == resource.id }
        profile.resourceAccess.append(resource)
    }

    private func replaceAvailability(
        _ exception: WorkforceAvailabilityException
    ) {
        profile.availabilityExceptions.removeAll {
            $0.id == exception.id
        }
        profile.availabilityExceptions.append(exception)
    }

    private func skillSubtitle(_ skill: WorkforceSkill) -> String {
        let match = skill.serviceType?.rawValue ?? skill.category
        return "\(skill.proficiency.displayName) · \(match)"
    }

    private func certificationSubtitle(
        _ certification: WorkforceCertification
    ) -> String {
        switch certification.status() {
        case .active:
            if let expiration = certification.expirationDate {
                return "Active · Expires \(expiration.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Active · No expiration"
        case .expiresSoon:
            return "Expires soon"
        case .expired:
            return "Expired"
        case .inactive:
            return "Inactive"
        }
    }

    @ViewBuilder
    private func certificationStatusIcon(
        _ certification: WorkforceCertification
    ) -> some View {
        switch certification.status() {
        case .active:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .expiresSoon:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .expired, .inactive:
            Image(systemName: "xmark.seal.fill")
                .foregroundStyle(.red)
        }
    }

    private func resourceIcon(_ type: WorkforceResourceType) -> String {
        switch type {
        case .vehicle: return "car.fill"
        case .equipment: return "wrench.and.screwdriver.fill"
        case .tool: return "hammer.fill"
        case .safetyGear: return "shield.fill"
        case .specialty: return "shippingbox.fill"
        }
    }

    private func availabilityIcon(
        _ kind: WorkforceAvailabilityKind
    ) -> String {
        switch kind {
        case .unavailable: return "calendar.badge.minus"
        case .available: return "calendar.badge.plus"
        case .limited: return "calendar.badge.clock"
        }
    }

    private func availabilityColor(
        _ kind: WorkforceAvailabilityKind
    ) -> Color {
        switch kind {
        case .unavailable: return .red
        case .available: return .green
        case .limited: return .orange
        }
    }

    private func availabilitySubtitle(
        _ exception: WorkforceAvailabilityException
    ) -> String {
        let interval = "\(exception.startDate.formatted(date: .abbreviated, time: .shortened)) – \(exception.endDate.formatted(date: .abbreviated, time: .shortened))"
        return exception.reason.isEmpty
            ? interval
            : "\(interval) · \(exception.reason)"
    }
}

private struct WorkforceSkillEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var skill: WorkforceSkill
    @State private var matchesServiceType: Bool
    @State private var selectedServiceType: ServiceType
    @FocusState private var isInputFocused: Bool

    let onSave: (WorkforceSkill) -> Void

    init(
        skill: WorkforceSkill,
        onSave: @escaping (WorkforceSkill) -> Void
    ) {
        _skill = State(initialValue: skill)
        _matchesServiceType = State(
            initialValue: skill.serviceType != nil
        )
        _selectedServiceType = State(
            initialValue: skill.serviceType ?? .windowCleaning
        )
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Skill") {
                    TextField("Skill Name", text: $skill.name)
                        .focused($isInputFocused)

                    TextField("Category", text: $skill.category)
                        .focused($isInputFocused)

                    Picker("Proficiency", selection: $skill.proficiency) {
                        ForEach(WorkforceProficiency.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }

                    Stepper(
                        value: $skill.yearsOfExperience,
                        in: 0...60,
                        step: 0.5
                    ) {
                        LabeledContent("Experience") {
                            Text(
                                skill.yearsOfExperience.formatted(
                                    .number.precision(.fractionLength(0...1))
                                ) + " years"
                            )
                        }
                    }

                    Toggle("Verified", isOn: $skill.isVerified)
                }

                Section("Service Matching") {
                    Toggle(
                        "Match a Service Type",
                        isOn: $matchesServiceType
                    )

                    if matchesServiceType {
                        Picker(
                            "Service Type",
                            selection: $selectedServiceType
                        ) {
                            ForEach(ServiceType.allCases) { serviceType in
                                Text(serviceType.rawValue).tag(serviceType)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $skill.notes)
                        .frame(minHeight: 90)
                        .focused($isInputFocused)
                }
            }
            .navigationTitle("Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        skill.name = skill.name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        skill.category = skill.category.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        skill.serviceType = matchesServiceType
                            ? selectedServiceType
                            : nil
                        skill.updatedDate = Date()
                        onSave(skill)
                        dismiss()
                    }
                    .disabled(
                        skill.name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                if isInputFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                    }
                }
            }
        }
    }
}

private struct WorkforceCertificationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var certification: WorkforceCertification
    @State private var hasIssuedDate: Bool
    @State private var issuedDate: Date
    @State private var hasExpirationDate: Bool
    @State private var expirationDate: Date
    @FocusState private var isInputFocused: Bool

    let onSave: (WorkforceCertification) -> Void

    init(
        certification: WorkforceCertification,
        onSave: @escaping (WorkforceCertification) -> Void
    ) {
        _certification = State(initialValue: certification)
        _hasIssuedDate = State(
            initialValue: certification.issuedDate != nil
        )
        _issuedDate = State(
            initialValue: certification.issuedDate ?? Date()
        )
        _hasExpirationDate = State(
            initialValue: certification.expirationDate != nil
        )
        _expirationDate = State(
            initialValue: certification.expirationDate
                ?? Calendar.current.date(
                    byAdding: .year,
                    value: 1,
                    to: Date()
                )
                ?? Date()
        )
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Certification") {
                    TextField(
                        "Certification Name",
                        text: $certification.name
                    )
                    .focused($isInputFocused)

                    TextField(
                        "Issuing Organization",
                        text: $certification.issuingOrganization
                    )
                    .focused($isInputFocused)

                    TextField(
                        "Credential Number",
                        text: $certification.credentialNumber
                    )
                    .focused($isInputFocused)

                    Toggle("Active", isOn: $certification.isActive)
                }

                Section("Dates") {
                    Toggle("Record Issue Date", isOn: $hasIssuedDate)

                    if hasIssuedDate {
                        DatePicker(
                            "Issued",
                            selection: $issuedDate,
                            displayedComponents: .date
                        )
                    }

                    Toggle("Certification Expires", isOn: $hasExpirationDate)

                    if hasExpirationDate {
                        DatePicker(
                            "Expiration",
                            selection: $expirationDate,
                            displayedComponents: .date
                        )
                    }
                }

                Section("Notes") {
                    TextEditor(text: $certification.notes)
                        .frame(minHeight: 90)
                        .focused($isInputFocused)
                }
            }
            .navigationTitle("Certification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        certification.name = certification.name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        certification.issuingOrganization = certification
                            .issuingOrganization
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        certification.credentialNumber = certification
                            .credentialNumber
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        certification.issuedDate = hasIssuedDate
                            ? issuedDate
                            : nil
                        certification.expirationDate = hasExpirationDate
                            ? expirationDate
                            : nil
                        onSave(certification)
                        dismiss()
                    }
                    .disabled(
                        certification.name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                if isInputFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                    }
                }
            }
        }
    }
}

private struct WorkforceResourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var resource: WorkforceResourceAccess
    @State private var capabilityTagsText: String
    @FocusState private var isInputFocused: Bool

    let onSave: (WorkforceResourceAccess) -> Void

    init(
        resource: WorkforceResourceAccess,
        onSave: @escaping (WorkforceResourceAccess) -> Void
    ) {
        _resource = State(initialValue: resource)
        _capabilityTagsText = State(
            initialValue: resource.capabilityTags.joined(separator: ", ")
        )
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resource") {
                    TextField("Name", text: $resource.name)
                        .focused($isInputFocused)

                    Picker("Type", selection: $resource.type) {
                        ForEach(WorkforceResourceType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Toggle("Available", isOn: $resource.isAvailable)
                }

                Section {
                    TextField(
                        "Example: ladder, roof, water-fed pole",
                        text: $capabilityTagsText
                    )
                    .focused($isInputFocused)
                } header: {
                    Text("Capability Tags")
                } footer: {
                    Text("Separate tags with commas.")
                }

                Section("Notes") {
                    TextEditor(text: $resource.notes)
                        .frame(minHeight: 90)
                        .focused($isInputFocused)
                }
            }
            .navigationTitle("Equipment or Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        resource.name = resource.name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        resource.capabilityTags = capabilityTagsText
                            .split(separator: ",")
                            .map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }
                            .filter { !$0.isEmpty }
                        onSave(resource)
                        dismiss()
                    }
                    .disabled(
                        resource.name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                if isInputFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                    }
                }
            }
        }
    }
}

private struct WorkforceAvailabilityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exception: WorkforceAvailabilityException
    @FocusState private var isInputFocused: Bool

    let onSave: (WorkforceAvailabilityException) -> Void

    init(
        exception: WorkforceAvailabilityException,
        onSave: @escaping (WorkforceAvailabilityException) -> Void
    ) {
        _exception = State(initialValue: exception)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Availability") {
                    Picker("Type", selection: $exception.kind) {
                        ForEach(WorkforceAvailabilityKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }

                    DatePicker(
                        "Starts",
                        selection: $exception.startDate
                    )

                    DatePicker(
                        "Ends",
                        selection: $exception.endDate,
                        in: exception.startDate...
                    )
                }

                Section("Reason") {
                    TextField("Optional reason", text: $exception.reason)
                        .focused($isInputFocused)
                }
            }
            .navigationTitle("Availability Exception")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        exception.reason = exception.reason
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(exception)
                        dismiss()
                    }
                    .disabled(exception.endDate <= exception.startDate)
                }

                if isInputFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isInputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss Keyboard")
                    }
                }
            }
        }
    }
}
