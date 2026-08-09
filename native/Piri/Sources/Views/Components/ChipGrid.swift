import SwiftUI

/// Shared chip-grid picker used by both the Settings and Onboarding screens
/// — port of the repeated `chipGrid`/`chip` pattern in `settings.tsx` and
/// `onboarding.tsx`.
struct ChipGrid<Value: Hashable>: View {
    let options: [ProfileOption<Value>]
    let isSelected: (Value) -> Bool
    let onSelect: (Value) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.value) { option in
                let selected = isSelected(option.value)
                Button {
                    onSelect(option.value)
                } label: {
                    HStack(spacing: 5) {
                        if let emoji = option.emoji { Text(emoji) }
                        Text(String(localized: String.LocalizationValue(option.labelKey)))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(selected ? Theme.navy : Color(.secondarySystemBackground)))
                    .foregroundStyle(selected ? .white : .primary)
                    .overlay(Capsule().stroke(selected ? Theme.navy : Color(.separator), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
