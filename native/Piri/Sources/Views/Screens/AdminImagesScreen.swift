import SwiftUI

private let statusFilters: [(labelKey: String, value: ImageCandidateStatus?)] = [
    ("adminImages.filters.pending", .pending),
    ("adminImages.filters.approved", .approved),
    ("adminImages.filters.applied", .applied),
    ("adminImages.filters.rejected", .rejected),
    ("adminImages.filters.all", nil),
]

/// Port of `mobile/app/admin-images.tsx`.
struct AdminImagesScreen: View {
    var body: some View {
        AdminGateView {
            AdminImagesContent()
        }
        .navigationTitle("adminImages.hero.title")
    }
}

private struct AdminImagesContent: View {
    @Environment(\.adminToken) private var token

    @State private var statusFilter: ImageCandidateStatus? = .pending
    @State private var candidates: [ImageCandidate] = []
    @State private var allPlaces: [Place] = []
    @State private var isLoading = true
    @State private var isDiscovering = false
    @State private var activeCandidateId: String?
    @State private var candidateQuery = ""
    @State private var discoverQuery = ""
    @State private var selectedDiscoverPlace: Place?
    @State private var reassignQueries: [String: String] = [:]
    @State private var selectedReassignPlace: [String: Place] = [:]
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var coverage: (total: Int, verified: Int, missing: Int, pendingStrong: Int) {
        let total = allPlaces.count
        let verified = allPlaces.filter(\.image.verified).count
        let pendingStrong = candidates.filter { $0.status == .pending && $0.confidence >= 70 }.count
        return (total, verified, max(0, total - verified), pendingStrong)
    }

    private var discoverSuggestions: [Place] {
        let query = discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        return Array(allPlaces.filter { $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query) }.prefix(5))
    }

    private var visibleCandidates: [ImageCandidate] {
        let query = candidateQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.placeName.lowercased().contains(query) || $0.placeId.lowercased().contains(query) || $0.pageTitle.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("adminImages.hero.title").font(.title.bold())
                    Text("adminImages.hero.body").foregroundStyle(.secondary)
                }

                card {
                    Text("adminImages.coverage.title").font(.headline)
                    HStack {
                        metric(coverage.total, "adminImages.coverage.places")
                        metric(coverage.verified, "adminImages.coverage.verifiedMainPhotos")
                        metric(coverage.missing, "adminImages.coverage.stillMissing")
                    }
                    Text(L("adminImages.coverage.strongPending", String(coverage.pendingStrong))).font(.caption).foregroundStyle(.secondary)
                }

                card {
                    Text("adminImages.actions.title").font(.headline)
                    HStack {
                        Button("adminImages.actions.refresh") { Task { await loadCandidates() } }.buttonStyle(.bordered)
                        Button(isDiscovering ? String(localized: "adminImages.actions.discovering") : String(localized: "adminImages.actions.discoverMissing")) {
                            Task { await discoverMissing() }
                        }.buttonStyle(.bordered).disabled(isDiscovering)
                    }

                    Text("adminImages.discoverOne.title").font(.subheadline.bold())
                    TextField(String(localized: "adminImages.searchPlacePlaceholder"), text: $discoverQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: discoverQuery) { _, _ in selectedDiscoverPlace = nil }
                    if let selectedDiscoverPlace {
                        Text(L("adminImages.selectedPlace", selectedDiscoverPlace.name)).font(.caption).foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(discoverSuggestions) { place in
                            Button(place.name) {
                                selectedDiscoverPlace = place
                                discoverQuery = place.name
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Button(isDiscovering ? String(localized: "adminImages.actions.discovering") : String(localized: "adminImages.discoverOne.discoverThisPlace")) {
                        Task { await discoverSingle() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDiscovering || selectedDiscoverPlace == nil)

                    if let infoMessage { Text(infoMessage).foregroundStyle(.green) }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }

                FlowLayout(spacing: 8) {
                    ForEach(statusFilters, id: \.labelKey) { filter in
                        let selected = filter.value == statusFilter
                        Button(String(localized: String.LocalizationValue(filter.labelKey))) {
                            statusFilter = filter.value
                            Task { await loadCandidates() }
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? .blue : .gray)
                    }
                }

                card {
                    Text("adminImages.searchCandidates.title").font(.headline)
                    TextField(String(localized: "adminImages.searchCandidates.placeholder"), text: $candidateQuery).textFieldStyle(.roundedBorder)
                    Text(L("adminImages.searchCandidates.showing", String(visibleCandidates.count), String(candidates.count))).font(.caption).foregroundStyle(.secondary)
                }

                if isLoading { Text("adminImages.loadingCandidates").foregroundStyle(.secondary) }
                if !isLoading, visibleCandidates.isEmpty {
                    card { Text("adminImages.noCandidates").foregroundStyle(.secondary) }
                }

                ForEach(visibleCandidates) { candidate in
                    candidateCard(candidate)
                }
            }
            .padding(16)
        }
        .task {
            await loadCandidates()
            await loadPlaces()
        }
    }

    private func metric(_ value: Int, _ labelKey: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.bold())
            Text(String(localized: String.LocalizationValue(labelKey))).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder
    private func candidateCard(_ candidate: ImageCandidate) -> some View {
        let isBusy = activeCandidateId == candidate.id
        let query = reassignQueries[candidate.id] ?? ""
        let suggestions: [Place] = query.trimmingCharacters(in: .whitespaces).count >= 2
            ? Array(allPlaces.filter { $0.id != candidate.placeId && ($0.name.lowercased().contains(query.lowercased()) || $0.id.lowercased().contains(query.lowercased())) }.prefix(4))
            : []

        card {
            Text(candidate.placeName).font(.headline)
            Text(L("adminImages.candidate.statusLine", candidate.status.rawValue, String(candidate.confidence), String(candidate.rank)))
                .font(.caption).foregroundStyle(.secondary)

            CachedAsyncImage(url: URL(string: candidate.imageUrl), maxPixelSize: 700) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(candidate.pageTitle)
            if let notes = candidate.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
            Text(L(
                "adminImages.candidate.currentImage",
                candidate.currentPlaceImage.verified ? String(localized: "adminImages.candidate.verified") : String(localized: "adminImages.candidate.placeholder"),
                candidate.currentPlaceImage.sourceName.map { " · \($0)" } ?? ""
            )).font(.caption).foregroundStyle(.secondary)
            if let license = candidate.imageLicense {
                Text(L("adminImages.candidate.license", license)).font(.caption).foregroundStyle(.secondary)
            }
            if let attribution = candidate.imageAttribution {
                Text(attribution).font(.caption).foregroundStyle(.secondary)
            }
            if let url = URL(string: candidate.sourceUrl) {
                Link(String(localized: "adminImages.candidate.openSourcePage"), destination: url)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("adminImages.reassign.title").font(.subheadline.bold())
                TextField(String(localized: "adminImages.searchPlacePlaceholder"), text: Binding(
                    get: { reassignQueries[candidate.id] ?? "" },
                    set: { reassignQueries[candidate.id] = $0; selectedReassignPlace[candidate.id] = nil }
                )).textFieldStyle(.roundedBorder)
                if let selected = selectedReassignPlace[candidate.id] {
                    Text(L("adminImages.selectedPlace", selected.name)).font(.caption).foregroundStyle(.secondary)
                }
                FlowLayout(spacing: 8) {
                    ForEach(suggestions) { place in
                        Button(place.name) {
                            selectedReassignPlace[candidate.id] = place
                            reassignQueries[candidate.id] = place.name
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Button(isBusy ? String(localized: "common.saving") : String(localized: "adminImages.reassign.matchToPlace")) {
                    Task { await reassign(candidate) }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || selectedReassignPlace[candidate.id] == nil)
            }

            HStack {
                Button(isBusy ? String(localized: "common.saving") : String(localized: "adminImages.actions.approveApply")) {
                    Task { await approveAndApply(candidate) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button("adminImages.actions.reject") {
                    Task { await reject(candidate) }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    private func loadCandidates() async {
        guard !token.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            candidates = try await AdminAPI.fetchImageCandidates(status: statusFilter, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadPlaces() async {
        allPlaces = (try? await PlacesAPI.fetchPlaces()) ?? []
    }

    private func discoverMissing() async {
        guard !token.isEmpty else { return }
        isDiscovering = true
        errorMessage = nil
        do {
            let result = try await AdminAPI.discoverImageCandidates(DiscoverImageCandidatesRequest(placeId: nil, limit: 4, includeVerified: nil), token: token)
            infoMessage = L("adminImages.info.discoveredAcross", String(result.discoveredCandidates), String(result.discoveredPlaces))
            await loadCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDiscovering = false
    }

    private func discoverSingle() async {
        guard !token.isEmpty, let place = selectedDiscoverPlace else { return }
        isDiscovering = true
        errorMessage = nil
        do {
            let result = try await AdminAPI.discoverImageCandidates(DiscoverImageCandidatesRequest(placeId: place.id, limit: 6, includeVerified: true), token: token)
            infoMessage = L("adminImages.info.discoveredFor", String(result.discoveredCandidates), place.name)
            await loadCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDiscovering = false
    }

    private func approveAndApply(_ candidate: ImageCandidate) async {
        guard !token.isEmpty else { return }
        activeCandidateId = candidate.id
        errorMessage = nil
        do {
            try await AdminAPI.approveImageCandidate(id: candidate.id, token: token)
            try await AdminAPI.applyImageCandidate(id: candidate.id, token: token)
            infoMessage = String(localized: "adminImages.info.approvedApplied")
            await loadCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
        activeCandidateId = nil
    }

    private func reject(_ candidate: ImageCandidate) async {
        guard !token.isEmpty else { return }
        activeCandidateId = candidate.id
        errorMessage = nil
        do {
            try await AdminAPI.rejectImageCandidate(id: candidate.id, token: token)
            infoMessage = String(localized: "adminImages.info.rejected")
            await loadCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
        activeCandidateId = nil
    }

    private func reassign(_ candidate: ImageCandidate) async {
        guard !token.isEmpty, let place = selectedReassignPlace[candidate.id] else { return }
        activeCandidateId = candidate.id
        errorMessage = nil
        do {
            try await AdminAPI.reassignImageCandidate(id: candidate.id, placeId: place.id, token: token)
            infoMessage = L("adminImages.info.movedTo", place.name)
            reassignQueries[candidate.id] = ""
            selectedReassignPlace[candidate.id] = nil
            await loadCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
        activeCandidateId = nil
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
