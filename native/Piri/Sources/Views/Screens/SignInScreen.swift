import AuthenticationServices
import SwiftUI

/// Sign in with Apple + email/password, both landing on the same account
/// backend. Optional entry point from ProfileScreen's account card -- the
/// app works fully signed-out before and after this screen is ever opened.
struct SignInScreen: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode { case logIn, register }

    @State private var mode: Mode = .logIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isSubmitting)

                    HStack(spacing: 10) {
                        Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                        Text(String(localized: String.LocalizationValue("auth.or")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                    }

                    VStack(spacing: 12) {
                        if mode == .register {
                            TextField(String(localized: String.LocalizationValue("auth.displayName")), text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.words)
                        }
                        TextField(String(localized: String.LocalizationValue("auth.email")), text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        SecureField(String(localized: String.LocalizationValue("auth.password")), text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.closedRed)
                    }

                    Button {
                        Task { await submitEmailForm() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(String(localized: String.LocalizationValue(
                                    mode == .logIn ? "auth.logIn" : "auth.register"
                                )))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
                    }
                    .buttonStyle(.plain)
                    .disabled(email.isEmpty || password.count < 8 || isSubmitting)

                    Button {
                        mode = mode == .logIn ? .register : .logIn
                        errorMessage = nil
                    } label: {
                        Text(String(localized: String.LocalizationValue(
                            mode == .logIn ? "auth.switchToRegister" : "auth.switchToLogIn"
                        )))
                        .font(.footnote)
                        .foregroundStyle(Theme.navy)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
            .navigationTitle(String(localized: String.LocalizationValue("auth.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: String.LocalizationValue("common.cancel"))) { dismiss() }
                }
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = String(localized: String.LocalizationValue("auth.appleFailed"))
                return
            }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            Task {
                await performSignIn {
                    try await authStore.signInWithApple(
                        identityToken: identityToken,
                        email: credential.email,
                        fullName: fullName.isEmpty ? nil : fullName
                    )
                }
            }
        }
    }

    private func submitEmailForm() async {
        await performSignIn {
            switch mode {
            case .logIn:
                try await authStore.logIn(email: email, password: password)
            case .register:
                try await authStore.register(
                    email: email,
                    password: password,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            }
        }
    }

    private func performSignIn(_ action: () async throws -> Void) async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await action()
            await authStore.performInitialSync(
                userProfileStore: userProfileStore,
                savedPlacesStore: savedPlacesStore,
                tripsStore: tripsStore
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
