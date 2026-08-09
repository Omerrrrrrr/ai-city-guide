import SwiftUI

private let dayFields: [(key: String, labelKey: String)] = [
    ("1", "placeHours.weekdayShort.mon"), ("2", "placeHours.weekdayShort.tue"), ("3", "placeHours.weekdayShort.wed"),
    ("4", "placeHours.weekdayShort.thu"), ("5", "placeHours.weekdayShort.fri"), ("6", "placeHours.weekdayShort.sat"),
    ("0", "placeHours.weekdayShort.sun"),
]

private struct HoursFormState {
    var hoursVerified = false
    var alwaysOpen = false
    var temporarilyClosed = false
    var hoursSourceUrl = ""
    var hoursNote = ""
    var dayInputs: [String: String] = Dictionary(uniqueKeysWithValues: dayFields.map { ($0.key, "") })

    init() {}

    init(place: Place) {
        hoursVerified = place.visitInfo.hoursVerified
        temporarilyClosed = place.visitInfo.temporarilyClosed
        hoursSourceUrl = place.visitInfo.hoursSourceUrl ?? ""
        hoursNote = place.visitInfo.hoursNote ?? ""
        if let openingHours = place.visitInfo.openingHours {
            alwaysOpen = openingHours.mode == .alwaysOpen
            for field in dayFields {
                dayInputs[field.key] = (openingHours.days[field.key] ?? []).map { "\($0.start)-\($0.end)" }.joined(separator: ", ")
            }
        }
    }
}

/// Port of `mobile/app/admin-hours.tsx`.
struct AdminHoursScreen: View {
    var body: some View {
        AdminGateView {
            AdminHoursContent()
        }
        .navigationTitle("adminHours.hero.title")
    }
}

private struct AdminHoursContent: View {
    @Environment(\.adminToken) private var token

    @State private var places: [Place] = []
    @State private var search = ""
    @State private var expandedPlaceId: String?
    @State private var forms: [String: HoursFormState] = [:]
    @State private var previews: [String: [GoogleHoursPreview]] = [:]
    @State private var isLoading = true
    @State private var activePlaceId: String?
    @State private var previewLoadingId: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var filteredPlaces: [Place] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = places.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("adminHours.hero.title").font(.title.bold())
                    Text("adminHours.hero.body1").foregroundStyle(.secondary)
                    Text("adminHours.hero.body2").foregroundStyle(.secondary)
                }

                card {
                    Text("adminHours.findPlace").font(.headline)
                    TextField(String(localized: "adminHours.searchPlaceholder"), text: $search)
                        .textFieldStyle(.roundedBorder)
                    Button("adminHours.refreshPlaces") { Task { await load() } }
                    if let infoMessage { Text(infoMessage).foregroundStyle(.green) }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }

                if isLoading { Text("adminHours.loadingPlaces").foregroundStyle(.secondary) }

                ForEach(filteredPlaces) { place in
                    placeCard(place)
                }
            }
            .padding(16)
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            places = try await PlacesAPI.fetchPlaces()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func form(for place: Place) -> HoursFormState {
        forms[place.id] ?? HoursFormState(place: place)
    }

    @ViewBuilder
    private func placeCard(_ place: Place) -> some View {
        let status = PlaceHours.openStatus(for: place)
        let isExpanded = expandedPlaceId == place.id

        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(.headline)
                    Text(place.id).font(.caption).foregroundStyle(.secondary)
                    Text("\(status.shortLabel) · \(status.verified ? String(localized: "adminHours.verifiedHoursLabel") : String(localized: "adminHours.estimatedHoursLabel"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isExpanded ? String(localized: "adminHours.close") : String(localized: "adminHours.editHours")) {
                    if forms[place.id] == nil { forms[place.id] = HoursFormState(place: place) }
                    expandedPlaceId = isExpanded ? nil : place.id
                }
                .buttonStyle(.bordered)
            }

            if isExpanded {
                expandedForm(place)
            }
        }
    }

    @ViewBuilder
    private func expandedForm(_ place: Place) -> some View {
        var formBinding: HoursFormState {
            get { form(for: place) }
        }

        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                toggleChip(String(localized: "adminHours.toggles.verified"), isOn: formBinding.hoursVerified) {
                    forms[place.id, default: form(for: place)].hoursVerified.toggle()
                }
                toggleChip(String(localized: "adminHours.toggles.alwaysOpen"), isOn: formBinding.alwaysOpen) {
                    forms[place.id, default: form(for: place)].alwaysOpen.toggle()
                }
                toggleChip(String(localized: "adminHours.toggles.temporarilyClosed"), isOn: formBinding.temporarilyClosed, danger: true) {
                    forms[place.id, default: form(for: place)].temporarilyClosed.toggle()
                }
            }

            TextField(String(localized: "adminHours.sourceUrlPlaceholder"), text: Binding(
                get: { form(for: place).hoursSourceUrl },
                set: { forms[place.id, default: form(for: place)].hoursSourceUrl = $0 }
            )).textFieldStyle(.roundedBorder)

            TextField(String(localized: "adminHours.notePlaceholder"), text: Binding(
                get: { form(for: place).hoursNote },
                set: { forms[place.id, default: form(for: place)].hoursNote = $0 }
            )).textFieldStyle(.roundedBorder)

            if !formBinding.alwaysOpen {
                ForEach(dayFields, id: \.key) { field in
                    HStack {
                        Text(String(localized: String.LocalizationValue(field.labelKey))).frame(width: 40, alignment: .leading).font(.caption)
                        TextField(String(localized: "adminHours.dayInputPlaceholder"), text: Binding(
                            get: { form(for: place).dayInputs[field.key] ?? "" },
                            set: { forms[place.id, default: form(for: place)].dayInputs[field.key] = $0 }
                        )).textFieldStyle(.roundedBorder)
                    }
                }
            }

            Text("adminHours.formatHint").font(.caption).foregroundStyle(.secondary)

            HStack {
                Button {
                    Task { await fetchPreview(place) }
                } label: {
                    Text(previewLoadingId == place.id ? String(localized: "adminHours.loadingGoogle") : String(localized: "adminHours.fetchGooglePreview"))
                }
                .buttonStyle(.bordered)
                .disabled(previewLoadingId == place.id)

                Button {
                    Task { await save(place) }
                } label: {
                    Text(activePlaceId == place.id ? String(localized: "common.saving") : String(localized: "adminHours.saveHours"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(activePlaceId == place.id)
            }

            if let placePreviews = previews[place.id] {
                VStack(alignment: .leading, spacing: 8) {
                    Text("adminHours.googlePreviewTitle").font(.headline)
                    if placePreviews.isEmpty {
                        Text("adminHours.noGoogleCandidates").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(placePreviews) { preview in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(preview.displayName).font(.subheadline.bold())
                                if let address = preview.formattedAddress {
                                    Text(address).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(preview.matchReason).font(.caption).foregroundStyle(.secondary)
                                ForEach(preview.weekdayDescriptions, id: \.self) { line in
                                    Text(line).font(.caption).foregroundStyle(.secondary)
                                }
                                Button("adminHours.useThisPreview") {
                                    applyPreview(preview, to: place)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        }
                    }
                }
            }
        }
    }

    private func toggleChip(_ label: String, isOn: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(isOn ? (danger ? Color.red.opacity(0.1) : Color.green.opacity(0.1)) : Color(.secondarySystemBackground)))
                .overlay(Capsule().stroke(isOn ? (danger ? Color.red : Color.green).opacity(0.3) : Color.secondary.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private func fetchPreview(_ place: Place) async {
        guard !token.isEmpty else { return }
        if forms[place.id] == nil { forms[place.id] = HoursFormState(place: place) }
        previewLoadingId = place.id
        errorMessage = nil
        infoMessage = nil
        do {
            let result = try await AdminAPI.fetchGoogleHoursPreview(placeId: place.id, token: token)
            previews[place.id] = result
            infoMessage = result.isEmpty ? L("adminHours.info.noPreviewsFound", place.name) : L("adminHours.info.loadedPreviews", String(result.count), place.name)
        } catch {
            errorMessage = error.localizedDescription
        }
        previewLoadingId = nil
    }

    private func applyPreview(_ preview: GoogleHoursPreview, to place: Place) {
        var state = form(for: place)
        state.hoursVerified = true
        if let openingHours = preview.openingHours {
            state.alwaysOpen = openingHours.mode == .alwaysOpen
            for field in dayFields {
                state.dayInputs[field.key] = (openingHours.days[field.key] ?? []).map { "\($0.start)-\($0.end)" }.joined(separator: ", ")
            }
        }
        state.temporarilyClosed = preview.temporarilyClosed
        state.hoursSourceUrl = preview.googleMapsUri ?? preview.websiteUri ?? state.hoursSourceUrl
        state.hoursNote = preview.hoursNote
        forms[place.id] = state
        infoMessage = L("adminHours.info.filledFromPreview", place.name)
    }

    private func save(_ place: Place) async {
        guard !token.isEmpty else { return }
        let state = form(for: place)
        activePlaceId = place.id
        errorMessage = nil
        infoMessage = nil

        var days: [String: [OpeningHoursRange]] = [:]
        do {
            for field in dayFields {
                let label = String(localized: String.LocalizationValue(field.labelKey))
                days[field.key] = state.alwaysOpen ? [] : try parseDayInput(state.dayInputs[field.key] ?? "", label: label)
            }
        } catch let parseError as ParseError {
            errorMessage = parseError.message
            activePlaceId = nil
            return
        } catch {
            activePlaceId = nil
            return
        }

        let request = UpdatePlaceHoursRequest(
            hoursVerified: state.hoursVerified,
            hoursSourceUrl: state.hoursSourceUrl.trimmingCharacters(in: .whitespaces).isEmpty ? nil : state.hoursSourceUrl,
            hoursNote: state.hoursNote.trimmingCharacters(in: .whitespaces).isEmpty ? nil : state.hoursNote,
            temporarilyClosed: state.temporarilyClosed,
            openingHours: OpeningHoursData(timezone: "Europe/Oslo", mode: state.alwaysOpen ? .alwaysOpen : .scheduled, days: days)
        )

        do {
            let updated = try await AdminAPI.updatePlaceHours(placeId: place.id, request: request, token: token)
            if let index = places.firstIndex(where: { $0.id == place.id }) { places[index] = updated }
            forms[place.id] = HoursFormState(place: updated)
            infoMessage = L("adminHours.info.savedHours", updated.name)
        } catch {
            errorMessage = error.localizedDescription
        }
        activePlaceId = nil
    }

    private struct ParseError: Error { let message: String }

    private static let timeRangePattern = try! NSRegularExpression(
        pattern: #"^([01]\d|2[0-3]):([0-5]\d)\s*-\s*([01]\d|2[0-3]):([0-5]\d)$"#
    )

    private func toMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private func parseDayInput(_ value: String, label: String) throws -> [OpeningHoursRange] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "closed" else { return [] }

        let ranges = try trimmed.split(separator: ",").map { rawEntry -> OpeningHoursRange in
            let entry = rawEntry.trimmingCharacters(in: .whitespaces)
            let fullRange = NSRange(entry.startIndex..<entry.endIndex, in: entry)
            guard let match = Self.timeRangePattern.firstMatch(in: entry, range: fullRange),
                  let startRange = Range(match.range(at: 1), in: entry), let startMinRange = Range(match.range(at: 2), in: entry),
                  let endRange = Range(match.range(at: 3), in: entry), let endMinRange = Range(match.range(at: 4), in: entry) else {
                throw ParseError(message: L("adminHours.validation.formatError", label))
            }

            let start = "\(entry[startRange]):\(entry[startMinRange])"
            let end = "\(entry[endRange]):\(entry[endMinRange])"
            guard toMinutes(end) > toMinutes(start) else {
                throw ParseError(message: L("adminHours.validation.endAfterStart", label))
            }
            return OpeningHoursRange(start: start, end: end)
        }
        .sorted { $0.start < $1.start }

        for index in 0..<max(0, ranges.count - 1) {
            if toMinutes(ranges[index].end) > toMinutes(ranges[index + 1].start) {
                throw ParseError(message: L("adminHours.validation.noOverlap", label))
            }
        }

        return ranges
    }

    @ViewBuilder
    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }
}
