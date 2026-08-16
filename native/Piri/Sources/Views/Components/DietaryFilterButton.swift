import SwiftUI

/// Single compact entry point for the halal/kosher/vegetarian/vegan filter,
/// replacing what used to be 4 always-visible chips on both Home and Map —
/// most people have no dietary restriction at all, and the row ate a full
/// extra line of prime above-the-fold space on every screen regardless.
/// Deliberately not gated behind any profile field: `faith` only covers
/// halal/kosher, not vegetarian/vegan, which aren't religious at all, so
/// there's no single signal that predicts who needs this. Picking a filter
/// once is itself the signal — the choice is remembered afterward via
/// whatever `AppStorage` key backs `selection` upstream, so it doesn't need
/// re-picking every visit.
struct DietaryFilterButton: View {
    @Binding var selection: DietTag?

    var body: some View {
        Menu {
            ForEach(DietTag.allCases) { tag in
                Button {
                    selection = selection == tag ? nil : tag
                } label: {
                    let key: String = "diet.\(tag.rawValue)"
                    let label = String(localized: String.LocalizationValue(key))
                    if selection == tag {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            Image(systemName: selection == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(selection == nil ? Color.primary : Theme.gold)
                .frame(width: 44, height: 44)
                .background(Circle().fill(selection == nil ? Color(.secondarySystemBackground) : Theme.gold.opacity(0.15)))
        }
        .accessibilityLabel(String(localized: "dietaryFilter.button"))
        .accessibilityValue(selectedLabel)
    }

    private var selectedLabel: String {
        guard let selection else { return "" }
        let key: String = "diet.\(selection.rawValue)"
        return String(localized: String.LocalizationValue(key))
    }
}
