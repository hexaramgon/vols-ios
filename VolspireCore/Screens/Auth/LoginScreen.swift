//
//  LoginScreen.swift
//  Volspire
//
//  Sign-in, v2: flat app-base canvas, left-aligned wordmark + heading, one
//  grouped email/password card with the gradient CTA beneath, providers
//  under a quiet "or continue with", and the create-account link at the
//  bottom. Register slides in over the same canvas.
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
    @State private var showForgot = false
    /// Flips true after a failed email sign-in — only then does the
    /// "Forgot password?" link appear.
    @State private var loginFailed = false
    @State private var registerViewModel: RegisterViewModel?

    private var authManager: AuthManager {
        dependencies.authManager
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        ZStack {
            AuthCanvas()

            if showRegister, let registerViewModel {
                RegisterScreen(viewModel: registerViewModel) {
                    withAnimation(.smooth(duration: 0.35)) { showRegister = false }
                }
                .transition(.push(from: .trailing))
            } else if showForgot {
                ForgotPasswordFlow(initialEmail: email) {
                    authManager.setError(nil)
                    withAnimation(.smooth(duration: 0.35)) { showForgot = false }
                }
                .transition(.push(from: .trailing))
            } else {
                loginForm
                    .transition(.push(from: .leading))
            }
        }
        .animation(.smooth(duration: 0.35), value: showRegister)
        .animation(.smooth(duration: 0.35), value: showForgot)
        .preferredColorScheme(.dark)
    }

    private var loginForm: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VolspireWordmark(height: 32)
                    .foregroundStyle(.white)
                    .padding(.top, 64)

                Text("Sign in")
                    .font(.appTitleXXL)
                    .foregroundStyle(.white)
                    .padding(.top, 48)

                Text("Welcome back — pick up where you left off.")
                    .font(.appCalloutRegular)
                    .foregroundStyle(Color.vText2)
                    .padding(.top, 6)

                AuthFieldGroup {
                    AuthRow(
                        icon: .mail,
                        placeholder: "Email address",
                        text: $email,
                        keyboard: .emailAddress,
                        contentType: .emailAddress
                    )
                    AuthRowDivider()
                    AuthSecureRow(placeholder: "Password", text: $password)
                }
                .padding(.top, 32)

                // Appears only once a sign-in attempt has failed.
                if loginFailed {
                    Button {
                        authManager.setError(nil)
                        withAnimation(.smooth(duration: 0.35)) { showForgot = true }
                    } label: {
                        Text("Forgot password?")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 12)
                    .transition(.opacity)
                }

                if let error = authManager.errorMessage {
                    AuthErrorBanner(message: error)
                        .padding(.top, 14)
                }

                AuthCTA(
                    title: "Sign In",
                    loadingTitle: "Signing in…",
                    isLoading: isLoading,
                    isDisabled: !canSubmit
                ) {
                    Task {
                        isLoading = true
                        await authManager.signInWithEmail(email: email, password: password)
                        if authManager.errorMessage != nil {
                            withAnimation(.easeInOut(duration: 0.25)) { loginFailed = true }
                        }
                        isLoading = false
                    }
                }
                .padding(.top, 16)

                AuthOrDivider()
                    .padding(.vertical, 24)

                VStack(spacing: 10) {
                    AppleAuthButton(label: "Continue with Apple") { credential in
                        Task {
                            isLoading = true
                            await authManager.signInWithApple(credential: credential)
                            isLoading = false
                        }
                    } onError: { error in
                        authManager.setError(error.localizedDescription)
                    }

                    GoogleAuthButton(label: "Continue with Google", isLoading: isLoading) {
                        Task {
                            isLoading = true
                            await authManager.signInWithGoogle()
                            isLoading = false
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 72) // clears the pinned create-account link
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // No rubber-band on a form that fits the screen — keyboard-driven
        // scroll adjustments stay pinned instead of bouncing the page.
        .scrollBounceBehavior(.basedOnSize)
        // Overlay (not safeAreaInset): the link stays anchored to the screen
        // bottom and the keyboard simply covers it, instead of riding up.
        // The overlay content must be FULL-HEIGHT for the keyboard opt-out to
        // work — ignoresSafeArea only expands views whose bounds touch the
        // ignored region, so a bare link would still be pushed up.
        .overlay {
            createAccountLink
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private var createAccountLink: some View {
        Button {
            authManager.setError(nil)
            // Fresh wizard state each visit, built before the transition
            // so the slide animates real content.
            registerViewModel = RegisterViewModel(
                authManager: authManager,
                supabaseService: dependencies.supabaseService
            )
            withAnimation(.smooth(duration: 0.35)) { showRegister = true }
        } label: {
            HStack(spacing: 4) {
                Text("New to Volspire?")
                    .foregroundStyle(Color.vText3)
                Text("Create account")
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
            }
            .font(.appCalloutRegular)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
    }
}

// MARK: - Forgot password (email → code → new password)

/// In-app reset flow: Supabase emails a 6-digit recovery code; verifying it
/// signs the user in (session held, like the register wizard), then the new
/// password is saved and the session is revealed — landing them in the app.
private struct ForgotPasswordFlow: View {
    @Environment(Dependencies.self) private var dependencies

    let initialEmail: String
    let onClose: () -> Void

    @State private var step = 0
    @State private var forward = true
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var resent = false

    private var authManager: AuthManager { dependencies.authManager }

    private var passwordsOK: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ZStack {
                Group {
                    switch step {
                    case 0: emailStep
                    case 1: codeStep
                    default: passwordStep
                    }
                }
                .transition(.push(from: forward ? .trailing : .leading))
            }
        }
        .background(AuthCanvas())
        .onAppear { email = initialEmail }
    }

    private var topBar: some View {
        HStack {
            // No back once the code is verified — the reset finishes forward.
            if step < 2 {
                Button {
                    if step == 0 {
                        onClose()
                    } else {
                        go(to: 0)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                        .imageScale(.large)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            Spacer()
        }
        .frame(height: 44)
    }

    private func go(to newStep: Int) {
        forward = newStep > step
        withAnimation(.smooth(duration: 0.35)) { step = newStep }
    }

    private func page(_ title: String, _ subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.appTitleXXL)
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                Text(subtitle)
                    .font(.appCalloutRegular)
                    .foregroundStyle(Color.vText2)
                    .padding(.top, 6)

                content()
                    .padding(.top, 28)

                if let error = authManager.errorMessage {
                    AuthErrorBanner(message: error)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    // Step 0: email
    private var emailStep: some View {
        page("Reset password", "We'll email you a 6-digit code.") {
            VStack(spacing: 24) {
                AuthFieldGroup {
                    AuthRow(
                        icon: .mail,
                        placeholder: "Email address",
                        text: $email,
                        keyboard: .emailAddress,
                        contentType: .emailAddress
                    )
                }

                AuthCTA(
                    title: "Send Code",
                    loadingTitle: "Sending…",
                    isLoading: isLoading,
                    isDisabled: email.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task {
                        isLoading = true
                        if await authManager.sendPasswordReset(email: email) {
                            code = ""
                            go(to: 1)
                        }
                        isLoading = false
                    }
                }
            }
        }
    }

    // Step 1: code
    private var codeStep: some View {
        page("Enter the code", "We sent a 6-digit code to \(email).") {
            VStack(spacing: 24) {
                AuthCodeField(
                    code: Binding(
                        get: { code },
                        set: { newValue in
                            code = String(newValue.filter(\.isNumber).prefix(6))
                            if code.count == 6 { Task { await verify() } }
                        }
                    ),
                    disabled: isLoading
                )

                AuthCTA(
                    title: "Verify",
                    loadingTitle: "Verifying…",
                    isLoading: isLoading,
                    isDisabled: code.count != 6
                ) {
                    Task { await verify() }
                }

                Button {
                    Task {
                        resent = true
                        _ = await authManager.sendPasswordReset(email: email)
                    }
                } label: {
                    Group {
                        if resent {
                            HStack(spacing: 6) {
                                LucideIcon(.check, .xs)
                                Text("New code sent — check your inbox")
                            }
                            .foregroundStyle(Color.green)
                        } else {
                            Text("Didn't get a code? \(Text("Resend").foregroundStyle(.white).underline())")
                                .foregroundStyle(Color.vText3)
                        }
                    }
                    .font(.appSubheadline)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(resent)
            }
        }
    }

    private func verify() async {
        guard !isLoading, code.count == 6 else { return }
        isLoading = true
        // Verifying signs the user in — hold the session so the auth UI stays
        // until the new password is saved.
        authManager.holdSessionForOnboarding = true
        if await authManager.verifyRecoveryCode(email: email, code: code) {
            go(to: 2)
        } else {
            authManager.holdSessionForOnboarding = false
        }
        isLoading = false
    }

    // Step 2: new password
    private var passwordStep: some View {
        page("New password", "Use at least 8 characters.") {
            VStack(alignment: .leading, spacing: 24) {
                AuthFieldGroup {
                    AuthSecureRow(placeholder: "New password", text: $newPassword, contentType: .newPassword)
                    AuthRowDivider()
                    AuthSecureRow(placeholder: "Confirm password", text: $confirmPassword, contentType: .newPassword)
                }

                if !confirmPassword.isEmpty, newPassword != confirmPassword {
                    Text("Passwords must match")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vError)
                }

                AuthCTA(
                    title: "Update Password",
                    loadingTitle: "Saving…",
                    isLoading: isLoading,
                    isDisabled: !passwordsOK
                ) {
                    Task {
                        isLoading = true
                        if await authManager.updatePassword(newPassword) {
                            // Reveal the held session — lands them in the app.
                            await authManager.finishOnboarding()
                        }
                        isLoading = false
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    LoginScreen()
        .environment(dependencies)
}
