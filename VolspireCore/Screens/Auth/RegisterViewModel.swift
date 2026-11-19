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

    /// How the wizard was entered.
    enum Mode: Equatable {
        /// The full email signup: email → password → profile → code → photos.
        case signUp
        /// An existing, already-verified session that owns no profile row —
        /// a first-time social sign-in, or a signup abandoned after the code
        /// step. Email/password/verification are all moot, so this resumes at
        /// the profile step and finishes with the same `create_user` call.
        case completeProfile
    }

    static let stepTitles = [
        "Create your account",
        "Choose a password",
        "Set up your profile",
        "Verify your email",
        FeatureFlags.profileBanners ? "Add your photos" : "Add a profile photo",
        "You're all set!",
    ]

    static let stepSubtitles = [
        "Start with your email, or sign up with Apple or Google.",
        "Pick something strong — you can change it later.",
        "Choose a username and tell us about yourself.",
        "Enter the 6-digit code we just emailed you.",
        FeatureFlags.profileBanners
            ? "Add a profile photo and banner. You can always do this later."
            : "Add a profile photo. You can always do this later.",
        "Your account has been created. Head to your profile to get started.",
    ]

    static let totalSteps = 5

    var step = 0
    /// Slide direction for the step transition (true = advancing).
    var slideForward = true

    var email = ""
    /// EULA gate (App Store 1.2): both consents must be checked before an
    /// account can be created via email, Apple, or Google.
    var agreedToTerms = false
    var agreedToPrivacy = false
    /// Both signup consents (Terms + Privacy) — gates the Continue on whichever
    /// step precedes account creation (password for email, profile for social).
    var agreedToLegal: Bool { agreedToTerms && agreedToPrivacy }
    var password = ""
    var confirmPassword = ""
    var username = ""
    var location = ""
    var tags: [String] = []
    /// Collab-map opt-in from the profile step (web: `pending_open_to_collab`).
    /// Off by default; applied via `set_open_to_collab` once the profile exists.
    var openToCollab = false
    var otpCode = ""

    var error: String?
    var verifyError: String?
    var loading = false
    var existingAccount = false
    /// Set when step 0 finds this email already has an account — the screen
    /// switches to Sign in with it filled in ("Welcome back").
    var existingAccountEmail: String?
    var usernameStatus: UsernameStatus = .idle
    var resendStatus: ResendStatus = .idle

    var avatarImage: UIImage?
    var bannerImage: UIImage?

    /// True once the username field was seeded from the social provider's own
    /// identity — drives the step copy ("confirm" vs "pick").
    private(set) var usernamePrefilled = false

    /// A verified session exists (signup returned one, the code was verified,
    /// or `.completeProfile` resumed one) — from here the wizard writes the
    /// profile row instead of signing up again.
    private var hasSession = false
    /// `create_user` has succeeded; the photos step only updates it.
    private var profileCreated = false
    /// The username/location/roles the row was last written with — stepping
    /// back from photos and editing them makes `finish()` resend.
    private var savedProfileFields: String?
    private var profileFields: String { "\(username)|\(location)|\(tags)" }

    private var usernameTask: Task<Void, Never>?
    private let authManager: AuthManager
    private let supabaseService: SupabaseService
    let mode: Mode

    init(authManager: AuthManager, supabaseService: SupabaseService, mode: Mode = .signUp) {
        self.authManager = authManager
        self.supabaseService = supabaseService
        self.mode = mode
        // Resuming an existing session starts at the profile step; there is
        // nothing to collect before it.
        self.step = mode == .completeProfile ? 2 : 0
        self.hasSession = mode == .completeProfile
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

    var usernameValid: Bool { Self.isValidUsername(username) }

    // MARK: - Username shape
    //
    // 3–30 characters of lowercase letters, digits and underscores (the
    // Instagram-style handle). Mirrors the `users_username_format` check
    // constraint in the database; web and Android apply the same rule.

    static let usernameMax = InputLimits.usernameMax

    /// Normalizes keystrokes into the handle shape: lowercase, spaces → `_`,
    /// anything else dropped, capped at `usernameMax`.
    static func normalizeUsername(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        let shaped = raw.lowercased().replacingOccurrences(of: " ", with: "_").filter { allowed.contains($0) }
        return String(shaped.prefix(usernameMax))
    }

    static func isValidUsername(_ name: String) -> Bool {
        name.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil
    }

    var canContinue: Bool {
        switch step {
        case 0: emailValid
        // The EULA gates whichever step precedes account creation, rather than
        // the entry screen: the password step for email (`handleSignUp` runs
        // from step 2), and the profile step for a social sign-in that skipped
        // straight here (`create_user` runs from step 4). Social sign-in used
        // to create accounts with no consent recorded at all (App Store 1.2).
        case 1: passwordChecks.allSatisfy(\.ok) && passwordsMatch && !confirmPassword.isEmpty
            && agreedToLegal
        case 2: usernameValid && usernameStatus != .taken && usernameStatus != .checking
            && (mode == .signUp || agreedToLegal)
        default: true
        }
    }

    // MARK: - Username availability

    func usernameChanged(_ raw: String) {
        username = Self.normalizeUsername(raw)
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

    // MARK: - Generated handle

    /// Fills the username with a generated handle so a social sign-in never
    /// faces an empty required field — the whole point of the guideline 4 fix:
    /// nothing about the person has to be typed in, least of all a name Apple
    /// already supplied. Everyone gets the same style of handle rather than the
    /// shape varying with what the provider happened to hand over. The field
    /// stays fully editable; this only decides what it starts as, and a taken
    /// handle is resolved to a free one here rather than after a failed submit.
    func prefillGeneratedUsername() async {
        guard mode == .completeProfile, username.isEmpty, usernameStatus == .idle else { return }
        guard let userId = await authManager.sessionUserId() else { return }
        // The round-trip above gives the user time to start typing — whatever
        // they typed wins, so an empty field (not the status, which their own
        // debounced check also drives) is what gates the write.
        guard username.isEmpty else { return }

        usernameStatus = .checking
        let (candidate, status) = await firstFreeUsername(userId: userId)
        guard username.isEmpty else { return }
        username = candidate
        usernameStatus = status
        usernamePrefilled = true
    }

    /// First generated handle the server says is free. A failed check is not
    /// worth blocking a prefill on — the first candidate goes in unmarked and
    /// the normal on-edit check settles it.
    private func firstFreeUsername(userId: String) async -> (String, UsernameStatus) {
        let candidates = (0 ..< 4).map { Self.generatedHandle(userId: userId, attempt: $0) }
        for candidate in candidates {
            do {
                if try await supabaseService.checkUsernameAvailable(candidate) {
                    return (candidate, .available)
                }
            } catch {
                return (candidates[0], .idle)
            }
        }
        // Four collisions across a 2.5M-combination space: fill the field
        // anyway, flagged, so the user edits a near-miss instead of facing an
        // empty required field.
        return (candidates[candidates.count - 1], .taken)
    }

    /// A Reddit-style handle — two words and four digits, e.g. `avid_listener_4821`.
    /// Everything is derived from the auth user id rather than randomly, so a
    /// create that fails and gets retried offers the same handle again instead
    /// of a new one each attempt. `attempt` salts the derivation to produce a
    /// different combination when one is already taken.
    ///
    /// Word lengths are capped (6 + 8) so a handle is never longer than the
    /// 20 characters — well inside the 30-character username limit.
    private static func generatedHandle(userId: String, attempt: Int) -> String {
        let seed = userId.replacingOccurrences(of: "-", with: "")
        let adjective = handleAdjectives[digest(seed, salt: attempt * 3, modulo: handleAdjectives.count)]
        let noun = handleNouns[digest(seed, salt: attempt * 3 + 1, modulo: handleNouns.count)]
        let number = digest(seed, salt: attempt * 3 + 2, modulo: 10000)
        return "\(adjective)_\(noun)_\(String(format: "%04d", number))"
    }

    /// FNV-1a over the id plus a SplitMix64 finalizer, in unsigned arithmetic so
    /// it can't trap on overflow. Deterministic on purpose — see `generatedHandle`.
    ///
    /// The finalizer is load-bearing, not decoration: a plain multiply-and-add
    /// hash (djb2's 33) leaves the low bits correlated across salts, and because
    /// 33 ≡ 1 modulo a 16-word list it degenerates into a sum — every user gets
    /// the same adjective/noun chain, merely rotated, and the two words stay
    /// locked one index apart. Avalanche first, then take the modulus.
    private static func digest(_ text: String, salt: Int, modulo: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a offset basis
        for scalar in text.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01b3 // FNV-1a prime
        }
        hash ^= UInt64(salt)
        hash ^= hash >> 30
        hash = hash &* 0xbf58_476d_1ce4_e5b9
        hash ^= hash >> 27
        hash = hash &* 0x94d0_49bb_1331_11eb
        hash ^= hash >> 31
        return Int(hash % UInt64(modulo))
    }

    private static let handleAdjectives = [
        "avid", "mellow", "golden", "velvet", "cosmic", "analog", "lucid", "amber",
        "hazy", "wired", "humble", "nimble", "quiet", "warm", "bright", "plush",
    ]

    private static let handleNouns = [
        "listener", "producer", "drummer", "crate", "riff", "reverb", "tempo", "chorus",
        "vinyl", "sampler", "cadence", "echo", "groove", "bassline", "melody", "session",
    ]

    // MARK: - Navigation

    func goNext() async {
        guard !loading, canContinue else { return }
        if step == 2 {
            // With a session already in hand (`.completeProfile`, or a signup
            // sent back here because its username was taken) there's no
            // account to sign up for — write the profile row, then photos.
            if hasSession {
                await createProfileThenPhotos()
            } else {
                await handleSignUp()
            }
            return
        }
        // Step 0: a returning user in the wrong flow (e.g. signed out and
        // tapped Create account) goes to Sign in with their email filled in,
        // instead of "create a password" for an account that exists (web
        // parity). A failed check just carries on with sign-up.
        if step == 0, mode != .completeProfile {
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            loading = true
            let exists = await supabaseService.emailHasAccount(trimmed)
            loading = false
            if exists {
                existingAccountEmail = trimmed
                return
            }
        }
        slideForward = true
        withAnimation(.smooth(duration: 0.35)) { step += 1 }
    }

    func goBack() {
        slideForward = false
        // `.completeProfile` jumps 2 → 4, so it has to come back the same way
        // (3 is the email-code step, which that mode never runs).
        let previous = (mode == .completeProfile && step == 4) ? 2 : step - 1
        withAnimation(.smooth(duration: 0.35)) { step = previous }
    }

    /// The only way out of `.completeProfile`: there is no screen behind it —
    /// the app itself is gated on the profile row — so backing out ends the
    /// session rather than dropping the user somewhere they can't act.
    func abandonProfileSetup() async {
        await authManager.signOut()
    }

    /// Step copy, adjusted for the entry mode.
    func subtitle(for step: Int) -> String {
        if mode == .completeProfile, step == 2 {
            return usernamePrefilled
                ? "You're signed in — here's your username. Change it if you like, then you're done."
                : "You're signed in — pick a username to finish setting up your account."
        }
        return Self.stepSubtitles[step]
    }

    func resetToStart() {
        existingAccount = false
        otpCode = ""
        verifyError = nil
        resendStatus = .idle
        slideForward = false
        withAnimation(.smooth(duration: 0.35)) { step = 0 }
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
            location: location.trimmedOrNil,
            tags: tags
        )
        loading = false
        switch outcome {
        case .existingAccount:
            existingAccount = true
        case .needsVerification:
            slideForward = true
            withAnimation(.smooth(duration: 0.35)) { step = 3 }
        case .session:
            hasSession = true
            await createProfileThenPhotos()
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
            hasSession = true
            await createProfileThenPhotos()
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

    // MARK: - Profile (create_user as soon as there's a session)

    /// Writes the profile row the moment a session exists (mirrors the web's
    /// `ensureProfile()`), so an account never sits profile-less behind the
    /// photos step. A taken username sends the user back to pick another.
    private func createProfileThenPhotos() async {
        guard await ensureProfile() else { return }
        slideForward = true
        withAnimation(.smooth(duration: 0.35)) { step = 4 }
    }

    /// Idempotent `create_user`. Returns false (with `error` set, and the
    /// wizard back on the profile step for a taken username) on failure.
    private func ensureProfile() async -> Bool {
        if profileCreated { return true }
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await supabaseService.createUser(
                username: username,
                bio: nil,
                location: location.trimmedOrNil,
                profileImageUrl: nil,
                bannerImageUrl: nil,
                tags: tags.isEmpty ? nil : tags
            )
            profileCreated = true
            savedProfileFields = profileFields
        } catch {
            if "\(error)".localizedCaseInsensitiveContains("username already taken") {
                usernameStatus = .taken
                self.error = "That username was just taken. Pick another one to continue."
                if step != 2 {
                    slideForward = false
                    withAnimation(.smooth(duration: 0.35)) { step = 2 }
                }
            } else {
                self.error = "Failed to create profile. Please try again."
            }
            return false
        }
        // Best effort: the collab-map opt-in must never block signup — it can
        // be flipped any time in Settings → Profile.
        if openToCollab {
            try? await supabaseService.setOpenToCollab(true)
        }
        return true
    }

    // MARK: - Finish (photos → update_user)

    var finishButtonTitle: String {
        avatarImage != nil || bannerImage != nil ? "Finish" : "Skip for now"
    }

    func finish() async {
        guard !loading else { return }
        // Normally already written when the session arrived; retried here in
        // case that attempt failed on the network.
        guard await ensureProfile() else { return }
        guard avatarImage != nil || bannerImage != nil || savedProfileFields != profileFields else {
            advanceToDone()
            return
        }
        loading = true
        error = nil
        defer { loading = false }

        guard let userId = await authManager.sessionUserId() else {
            error = "Session expired. Please sign in again."
            return
        }

        var avatarURL: String?
        var bannerURL: String?
        do {
            if let avatarImage, let data = avatarImage.jpegData(compressionQuality: 0.85) {
                avatarURL = try await supabaseService.uploadAvatar(userId: userId, imageData: data).absoluteString
            }
            if let bannerImage, let data = bannerImage.jpegData(compressionQuality: 0.85) {
                bannerURL = try await supabaseService.uploadBanner(userId: userId, imageData: data).absoluteString
            }
        } catch {
            self.error = "Couldn't upload your photos. Try again, or remove them to skip for now."
            return
        }

        do {
            // `update_user` writes every column as passed, so resend the
            // values the profile was just created with.
            _ = try await supabaseService.updateUserProfile(
                userId: userId,
                username: username,
                bio: nil,
                accountType: nil,
                location: location.trimmedOrNil,
                profileImageUrl: avatarURL,
                bannerImageUrl: bannerURL,
                tags: tags.isEmpty ? nil : tags
            )
            savedProfileFields = profileFields
            advanceToDone()
        } catch {
            if "\(error)".localizedCaseInsensitiveContains("username already taken") {
                usernameStatus = .taken
                self.error = "That username was just taken. Pick another one to continue."
            } else {
                self.error = "Couldn't save your profile. Please try again."
            }
        }
    }

    private func advanceToDone() {
        slideForward = true
        withAnimation(.smooth(duration: 0.35)) { step = 5 }
    }

    /// Final CTA — releases the held session so the app switches to the main UI.
    func enterApp() async {
        await authManager.finishOnboarding()
    }
}
