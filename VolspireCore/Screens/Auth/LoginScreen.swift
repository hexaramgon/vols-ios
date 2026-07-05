//
//  LoginScreen.swift
//  Volspire
//
//  Sign-in page mirroring the web app's /login: black background with the
//  radial top glow, "Welcome Back" heading, Apple + Google sign-in, labeled
//  email/password fields, white CTA, and the register link.
//

import AuthenticationServices
import DesignSystem
import Services
import SwiftUI

struct LoginScreen: View {
    @Environment(Dependencies.self) var dependencies
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showRegister = false
    @State private var registerViewModel: RegisterViewModel?

    private var authManager: AuthManager {
        dependencies.authManager
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        ZStack {
            // One shared background — switching between login and register
            // slides the content only, like navigating pages on the web.
            AuthBackground()

            // Crossfade with a small directional drift (±40pt) — the same
            // motion the wizard steps use. Full-width slides read as clunky.
            if showRegister, let registerViewModel {
                RegisterScreen(viewModel: registerViewModel) {
                    withAnimation(.easeOut(duration: 0.25)) { showRegister = false }
                }
                .transition(.opacity.combined(with: .offset(x: 40)))
            } else {
                loginForm
                    .transition(.opacity.combined(with: .offset(x: -40)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: showRegister)
        .preferredColorScheme(.dark)
    }

    private var loginForm: some View {
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VolspireWordmark(height: 30)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)

                    Text("Welcome Back")
                        .font(.appTitleXL)
                        .foregroundStyle(.white)
                        .padding(.top, 44)

                    Text("Log in to your account to continue.")
                        .font(.appCalloutRegular)
                        .foregroundStyle(Color.vText2)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        appleButton
                        GoogleAuthButton(label: "Sign in with Google", isLoading: isLoading) {
                            Task {
                                isLoading = true
                                await authManager.signInWithGoogle()
                                isLoading = false
                            }
                        }
                    }
                    .padding(.top, 32)

                    AuthOrDivider()
                        .padding(.vertical, 24)

                    VStack(spacing: 20) {
                        AuthTextField(
                            label: "Email address",
                            text: $email,
                            keyboard: .emailAddress,
                            contentType: .emailAddress
                        )
                        AuthSecureField(label: "Password", text: $password)
                    }

                    if let error = authManager.errorMessage {
                        AuthErrorBanner(message: error)
                            .padding(.top, 16)
                    }

                    AuthPrimaryButton(
                        title: "Log In",
                        loadingTitle: "Logging in…",
                        isLoading: isLoading,
                        isDisabled: !canSubmit
                    ) {
                        Task {
                            isLoading = true
                            await authManager.signInWithEmail(email: email, password: password)
                            isLoading = false
                        }
                    }
                    .padding(.top, 24)

                    Button {
                        authManager.setError(nil)
                        // Fresh wizard state each visit, built before the
                        // transition so the slide animates real content.
                        registerViewModel = RegisterViewModel(
                            authManager: authManager,
                            supabaseService: dependencies.supabaseService
                        )
                        withAnimation(.easeOut(duration: 0.25)) { showRegister = true }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundStyle(Color.vText3)
                            Text("Sign up")
                                .foregroundStyle(.white)
                                .fontWeight(.medium)
                        }
                        .font(.appCalloutRegular)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 28)
                    .padding(.bottom, 48)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 440)
            }
            .scrollDismissesKeyboard(.interactively)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    isLoading = true
                    await authManager.signInWithApple(credential: credential)
                    isLoading = false
                }
            }
        case .failure(let error):
            dependencies.authManager.setError(error.localizedDescription)
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    LoginScreen()
        .environment(dependencies)
}
