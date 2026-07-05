//
//  RegisterViewModel.swift
//  Volspire
//
//  Five-step signup wizard state, mirroring the web register flow:
//  email → password → profile (username/roles/location) → email code →
//  photos, finishing with the create_user RPC.
//

import Foundation
import Services
import SwiftUI

@MainActor
@Observable
final class RegisterViewModel {
    enum UsernameStatus: Equatable { case idle, checking, available, taken }
    enum ResendStatus: Equatable { case idle, sending, sent }

    static let stepTitles = [
        "Create your account",
        "Choose a password",
        "Set up your profile",
        "Verify your email",
        "Add your photos",
        "You're all set!",
    ]

    static let stepSubtitles = [
        "Start with your email, or sign up with Apple or Google.",
        "Pick something strong — you can change it later.",
        "Choose a username and tell us about yourself.",
        "Enter the 6-digit code we just emailed you.",
        "Add a profile photo and banner. You can always do this later.",
        "Your account has been created. Head to your profile to get started.",
    ]

    static let totalSteps = 5

    var step = 0
    /// Slide direction for the step transition (true = advancing).
    var slideForward = true

    var email = ""
    var password = ""
    var confirmPassword = ""
    var username = ""
    var location = ""
    var tags: [String] = []
    var otpCode = ""

    var error: String?
    var verifyError: String?
    var loading = false
    var existingAccount = false
    var usernameStatus: UsernameStatus = .idle
    var resendStatus: ResendStatus = .idle

    var avatarImage: UIImage?
    var bannerImage: UIImage?

    private var usernameTask: Task<Void, Never>?
    private let authManager: AuthManager
    private let supabaseService: SupabaseService

    init(authManager: AuthManager, supabaseService: SupabaseService) {
        self.authManager = authManager
        self.supabaseService = supabaseService
    }

    // MARK: - Validation (mirrors the web's zod schema)

    var emailValid: Bool {
        email.range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil
    }

    var passwordChecks: [(label: String, ok: Bool)] {
        [
            ("At least 8 characters", password.count >= 8),
            ("A lowercase letter", password.range(of: "[a-z]", options: .regularExpression) != nil),
            ("An uppercase letter", password.range(of: "[A-Z]", options: .regularExpression) != nil),
            ("A number", password.range(of: "[0-9]", options: .regularExpression) != nil),
        ]
    }

    var passwordsMatch: Bool { password == confirmPassword }

    var usernameValid: Bool {
        username.count >= 3
            && username.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil
    }

    var canContinue: Bool {
        switch step {
        case 0: emailValid
        case 1: passwordChecks.allSatisfy(\.ok) && passwordsMatch && !confirmPassword.isEmpty
        case 2: usernameValid && usernameStatus != .taken && usernameStatus != .checking
        default: true
        }
    }

    // MARK: - Username availability

    func usernameChanged(_ raw: String) {
        username = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        usernameTask?.cancel()
        guard username.count >= 3 else {
            usernameStatus = .idle
            return
        }
        usernameStatus = .checking
        let candidate = username
        usernameTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                let available = try await supabaseService.checkUsernameAvailable(candidate)
                guard !Task.isCancelled, candidate == username else { return }
                usernameStatus = available ? .available : .taken
            } catch {
                guard candidate == username else { return }
                usernameStatus = .idle
            }
        }
    }

    func toggleTag(_ tag: String) {
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else if tags.count < ProfileRoles.max {
            tags.append(tag)
        }
    }

    // MARK: - Navigation

    func goNext() async {
        guard !loading, canContinue else { return }
        if step == 2 {
            await handleSignUp()
            return
        }
        slideForward = true
        withAnimation(.easeOut(duration: 0.22)) { step += 1 }
    }

    func goBack() {
        slideForward = false
        withAnimation(.easeOut(duration: 0.22)) { step -= 1 }
    }

    func resetToStart() {
        existingAccount = false
        otpCode = ""
        verifyError = nil
        resendStatus = .idle
        slideForward = false
        withAnimation(.easeOut(duration: 0.22)) { step = 0 }
    }

    // MARK: - Sign up + verification

    private func handleSignUp() async {
        loading = true
        error = nil
        // Hold the session so a verified signup doesn't yank the wizard away
        // before the profile + photos steps finish.
        authManager.holdSessionForOnboarding = true
        let outcome = await authManager.signUpWithEmail(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            username: username,
            location: location.isEmpty ? nil : location,
            tags: tags
        )
        loading = false
        switch outcome {
        case .existingAccount:
            existingAccount = true
        case .needsVerification:
            slideForward = true
            withAnimation(.easeOut(duration: 0.22)) { step = 3 }
        case .session:
            slideForward = true
            withAnimation(.easeOut(duration: 0.22)) { step = 4 }
        case nil:
            error = authManager.errorMessage ?? "Registration failed. Please check your details and try again."
        }
    }

    func verifyOtp() async {
        let code = otpCode.trimmingCharacters(in: .whitespaces)
        guard code.count == 6, !loading else { return }
        loading = true
        verifyError = nil
        let verified = await authManager.verifySignupCode(email: email, code: code)
        loading = false
        if verified {
            slideForward = true
            withAnimation(.easeOut(duration: 0.22)) { step = 4 }
            return
        }
        // Expired codes auto-resend so the user isn't left to figure out the
        // recovery step (mirrors the web).
        let message = (authManager.errorMessage ?? "").lowercased()
        if message.contains("expired") || (message.contains("invalid") && message.contains("token")) {
            otpCode = ""
            _ = await authManager.resendSignupCode(email: email)
            resendStatus = .sent
            verifyError = "That code expired — we just sent you a new one."
        } else {
            verifyError = authManager.errorMessage ?? "That code didn't work. Try again or resend."
        }
    }

    func resend() async {
        guard resendStatus == .idle else { return }
        resendStatus = .sending
        let sent = await authManager.resendSignupCode(email: email)
        resendStatus = sent ? .sent : .idle
        if !sent { verifyError = authManager.errorMessage }
    }

    // MARK: - Finish (photos + create_user)

    var finishButtonTitle: String {
        avatarImage != nil || bannerImage != nil ? "Finish" : "Skip for now"
    }

    func finish() async {
        guard !loading else { return }
        loading = true
        error = nil

        guard let userId = await authManager.sessionUserId() else {
            error = "Session expired. Please sign in again."
            loading = false
            return
        }

        var avatarURL: String?
        var bannerURL: String?
        if let avatarImage, let data = avatarImage.jpegData(compressionQuality: 0.85) {
            avatarURL = try? await supabaseService.uploadAvatar(userId: userId, imageData: data).absoluteString
        }
        if let bannerImage, let data = bannerImage.jpegData(compressionQuality: 0.85) {
            bannerURL = try? await supabaseService.uploadBanner(userId: userId, imageData: data).absoluteString
        }

        do {
            try await supabaseService.createUser(
                username: username,
                bio: nil,
                location: location.isEmpty ? nil : location,
                profileImageUrl: avatarURL,
                bannerImageUrl: bannerURL,
                tags: tags.isEmpty ? nil : tags
            )
            loading = false
            slideForward = true
            withAnimation(.easeOut(duration: 0.22)) { step = 5 }
        } catch {
            loading = false
            self.error = "Failed to create profile. Please try again."
        }
    }

    /// Final CTA — releases the held session so the app switches to the main UI.
    func enterApp() async {
        await authManager.finishOnboarding()
    }
}
