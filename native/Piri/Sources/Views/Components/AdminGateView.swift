import SwiftUI

/// Port of `mobile/components/admin-gate.tsx`.
struct AdminGateView<Content: View>: View {
    @Environment(AdminAuthStore.self) private var adminAuthStore
    @State private var draftToken = ""

    @ViewBuilder let content: () -> Content

    var body: some View {
        if let token = adminAuthStore.adminToken {
            content()
                .environment(\.adminToken, token)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("components.adminGate.title").font(.system(size: 20, weight: .bold))
                Text("components.adminGate.body").font(.system(size: 15)).foregroundStyle(.secondary)
                SecureField(String(localized: "components.adminGate.placeholder"), text: $draftToken)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.navy, lineWidth: 1.5))
                Button {
                    adminAuthStore.setAdminToken(draftToken)
                } label: {
                    Text("components.adminGate.unlock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.navy))
                }
                .disabled(draftToken.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draftToken.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct AdminTokenKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var adminToken: String {
        get { self[AdminTokenKey.self] }
        set { self[AdminTokenKey.self] = newValue }
    }
}
