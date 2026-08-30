import SwiftUI

/// Generic ISO 4217 code picker, reused for BOTH sides of a conversion (the
/// traveler's own currency and the destination/counterpart currency) --
/// `ProfileScreen.cityCard` opens this once per side with a different
/// `title`/`selectedCode`/`onSelect`, rather than hardcoding one side to
/// "whatever the current city's country uses." Fetches its own master list
/// of currency codes (keyed off USD, but only the *set of codes* matters
/// here) rather than depending on `CityStore`'s per-city cache, so it works
/// the same regardless of which side is open or whether a city is set at all.
struct CurrencyPickerSheet: View {
    let title: String
    let selectedCode: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var allCodes: [String] = []
    @State private var isLoading = true

    private var filteredCodes: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).uppercased()
        return trimmed.isEmpty ? allCodes : allCodes.filter { $0.contains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if filteredCodes.isEmpty {
                        Text(L("cityPicker.noResults", query))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        ForEach(filteredCodes, id: \.self) { code in
                            row(code)
                            Divider()
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationBarHidden(true)
        .task { await loadCodes() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button("common.cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 56)
            }
            .padding(.horizontal, 20)

            TextField(String(localized: "currencyPicker.searchPlaceholder"), text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .piriGlassSurface()
    }

    private func row(_ code: String) -> some View {
        Button {
            Haptics.light()
            onSelect(code)
            dismiss()
        } label: {
            HStack {
                Text(code).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
                if code == selectedCode {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.gold)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadCodes() async {
        guard let rates = try? await CityContextAPI.currencyRates(base: "USD") else {
            isLoading = false
            return
        }
        allCodes = Array(Set(rates.rates.keys).union(["USD"])).sorted()
        isLoading = false
    }
}
