//
//  LoginScreen.swift
//  Volspire
//
//  The whole unauthenticated stack, over one flat app-base canvas: the welcome
//  landing is the root, with sign-in, register and password-reset pushed from
//  it. The sign-in form itself is v2 — left-aligned wordmark + heading, one
//  grouped email/password card with the gradient CTA beneath, providers under a
//  quiet "or continue with", and the create-account link at the bottom.
//

import AuthenticationServices
import DesignSystem
import Services
import SwiftUI

struct LoginScreen: View {
    /// The pushed destinations — the welcome landing is the stack's root, so it
    /// isn't one of them. A real `NavigationStack` path rather than a flag per
    /// screen, so sign-in gets the system's interactive pop for free.
    private enum Route: Hashable { case signIn, register, forgot }

    @Environment(Dependencies.self) var dependencies
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var path: [Route] = []
    /// Flips true after a failed email sign-in — only then does the
    /// "Forgot password?" link appear.
    @State private var loginFailed = false

    private var authManager: AuthManager {
        dependencies.authManager
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeScreen(
                onCreateAccount: startRegister,
                onSignIn: startSignIn
            )
            .background(AuthCanvas())
            .authNavigationChrome()
            .navigationDestination(for: Route.self, destination: destination)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .signIn:
            loginForm
                .background(AuthCanvas())
                .authNavigationChrome()
        case .register:
            // Built right here rather than hoisted into `@State` and read back:
            // this closure is captured, so it can run before an assignment made
            // in the same update lands, and an optional read as nil rendered a
            // blank screen. RegisterScreen keeps it in its own `@State`, so the
            // wizard still gets exactly one view model per push.
            //
            // The wizard owns its own step-back, so the system pop is off; it
            // exits the stack explicitly through `onExit`.
            RegisterScreen(
                viewModel: RegisterViewModel(
                    authManager: authManager,
                    supabaseService: dependencies.supabaseService
                )
            ) { exit in
                switch exit {
                case .back: pop()
                case .signIn: startSignIn()
                }
            }
            .authNavigationChrome(allowsSystemBack: false)
        case .forgot:
            ForgotPasswordFlow(initialEmail: email) {
                authManager.setError(nil)
                pop()
            }
            .authNavigationChrome(allowsSystemBack: false)
        }
    }

    private func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Opens the wizard on fresh state each visit — the destination builds the
    /// view model, so there is no state to stage before pushing. REPLACES the
    /// path (not append): switching between sign-in and register must never
    /// stack the two forms — back always returns to the welcome landing.
    private func startRegister() {
        authManager.setError(nil)
        path = [.register]
    }

    /// Same contract for sign-in: a fresh page (fields cleared — they live on
    /// this stack host, so they'd otherwise survive a round-trip through
    /// register) and a REPLACED path, so back goes to the welcome landing.
    private func startSignIn() {
        authManager.setError(nil)
        email = ""
        password = ""
        loginFailed = false
        path = [.signIn]
    }

    /// Sign-in runs through the wizards' own `AuthStepPage`, so its heading,
    /// spacing and scroll behaviour are register's by construction rather than
    /// by hand-matched numbers. The wordmark is gone — the welcome screen one
    /// push back already carries the brand, and register never had one.
    private var loginForm: some View {
        VStack(spacing: 0) {
            // Same chevron the wizards use — sign-in is pushed from the landing
            // now, so it needs the way back out.
            AuthWizardBackBar(disabled: isLoading, onBack: pop)

            AuthStepPage(
                title: "Sign in",
                subtitle: "Welcome back — pick up where you left off.",
                error: authManager.errorMessage
            ) {
                VStack(alignment: .leading, spacing: 0) {
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

                    // Appears only once a sign-in attempt has failed.
                    if loginFailed {
                        Button {
                            authManager.setError(nil)
                            path.append(.forgot)
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
                }
            } footer: {
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
                .padding(.top, 24)

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
                        authManager.setError(from: error)
                    }

                    GoogleAuthButton(label: "Continue with Google", isLoading: isLoading) {
                        Task {
                            isLoading = true
                            await authManager.signInWithGoogle()
                            isLoading = false
                        }
                    }
                }

                AuthBottomLink(prompt: "New to Volspire?", action: "Create account", onTap: startRegister)
                    .padding(.top, 8)
            }
        }
        // Load-bearing, not a fallback: measured on iOS 26, hiding the navigation
        // bar also disables the system's interactive pop, so this gesture is the
        // only back swipe sign-in has. Restoring the real finger-tracking pop
        // means letting the bar render, which puts a system back button above
        // our own chevron — see `authNavigationChrome`.
        //
        // The `path.last` check keeps it a no-op if a future iOS revives the
        // system gesture; sign-in only ever sits at depth 1, so even both firing
        // together can't pop past the landing.
        .authSwipeBack(isEnabled: !isLoading) {
            if path.last == .signIn { pop() }
        }
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

    /// Back once the code is verified is a dead end — the reset finishes
    /// forward — so both the chevron and the swipe stop at step 2.
    private var canGoBack: Bool { step < 2 }

    var body: some View {
        VStack(spacing: 0) {
            AuthWizardBackBar(canGoBack: canGoBack, disabled: isLoading, onBack: goBack)

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
        .authSwipeBack(isEnabled: canGoBack && !isLoading, action: goBack)
        .onAppear { email = initialEmail }
    }

    private func goBack() {
        if step == 0 {
            onClose()
        } else {
            go(to: 0)
        }
    }

    private func go(to newStep: Int) {
        forward = newStep > step
        withAnimation(.smooth(duration: 0.35)) { step = newStep }
    }

    private func page(_ title: String, _ subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        AuthStepPage(title: title, subtitle: subtitle, error: authManager.errorMessage) {
            content()
        }
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
                    code: $code,
                    disabled: isLoading,
                    onFilled: { Task { await verify() } }
                )

                AuthCTA(
                    title: "Verify",
                    loadingTitle: "Verifying…",
                    isLoading: isLoading,
                    isDisabled: code.count != 6
                ) {
                    Task { await verify() }
                }

                AuthResendButton(state: resent ? .sent : .idle) {
                    Task {
                        resent = true
                        _ = await authManager.sendPasswordReset(email: email)
                    }
                }
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
                    AuthPasswordMismatchLabel()
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
