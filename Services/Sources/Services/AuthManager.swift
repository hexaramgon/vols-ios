//
//  AuthManager.swift
//  Services
//
//

import AuthenticationServices
import Foundation
import GoogleSignIn
import Observation
import Supabase
import UIKit

@MainActor
@Observable
public final class AuthManager {
    public enum AuthState: Equatable {
        case loading
        case authenticated(userId: String)
        case unauthenticated
    }

    public enum SignUpOutcome: Equatable {
        /// Confirm-email is off — a session arrived immediately.
        case session
        /// Confirm-email is on — the user must enter the emailed code.
        case needsVerification
        /// Anti-enumeration: a confirmed account already exists for this
        /// email (Supabase returns a fabricated user with no identities).
        case existingAccount
    }

    public private(set) var state: AuthState = .loading
    public private(set) var errorMessage: String?

    /// While the register wizard runs its post-auth steps (verify → profile →
    /// photos), the signedIn event must not flip the app into the main UI.
    /// `finishOnboarding()` releases the hold and reveals the session.
    public var holdSessionForOnboarding = false

    public func setError(_ message: String?) {
        errorMessage = message
    }

    /// Translates raw Supabase auth errors into actionable, human copy.
    /// Falls back to the raw message for anything unrecognised.
    private func friendly(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("invalid login credentials") {
            return "That email and password don't match. Double-check and try again."
        }
        if lower.contains("email not confirmed") {
            return "This email hasn't been verified yet — check your inbox for the code we sent."
        }
        if lower.contains("error sending") {
            return "We couldn't send the verification email just now. Wait a moment and try again."
        }
        if lower.contains("rate limit") || lower.contains("once every") || lower.contains("too many") {
            return "Too many attempts — give it a minute and try again."
        }
        if lower.contains("network") || lower.contains("offline")
            || lower.contains("connection") || lower.contains("timed out")
        {
            return "Can't reach Volspire. Check your connection and try again."
        }
        if lower.contains("expired") {
            return "That code expired — request a new one."
        }
        if lower.contains("weak password") || lower.contains("password should") {
            return "That password is too weak — try a longer one with a mix of characters."
        }
        return raw
    }

    private let client: SupabaseClient

    public init(client: SupabaseClient = supabaseClient) {
        self.client = client
    }

    // MARK: - Session Lifecycle

    /// Check for existing session on app launch
    public func restoreSession() async {
        do {
            let session = try await client.auth.session
            state = .authenticated(userId: session.user.id.uuidString)
        } catch {
            state = .unauthenticated
        }
    }

    /// Listen for auth state changes
    public func listenForAuthChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .signedIn:
                if let session, !holdSessionForOnboarding {
                    state = .authenticated(userId: session.user.id.uuidString)
                }
            case .signedOut:
                state = .unauthenticated
            default:
                break
            }
        }
    }

    // MARK: - Email & Password

    /// Signs up with email/password, stashing the chosen username/location/tags
    /// in the auth metadata (mirrors the web register flow, so the web's
    /// /auth/callback can also auto-create the profile from them).
    /// Returns nil on failure with `errorMessage` set.
    public func signUpWithEmail(
        email: String,
        password: String,
        username: String,
        location: String?,
        tags: [String]
    ) async -> SignUpOutcome? {
        errorMessage = nil
        do {
            let metadata: [String: AnyJSON] = [
                "pending_username": .string(username),
                "pending_location": location.map { .string($0) } ?? .null,
                "pending_tags": tags.isEmpty ? .null : .array(tags.map { .string($0) }),
            ]
            let response = try await client.auth.signUp(email: email, password: password, data: metadata)
            if let identities = response.user.identities, identities.isEmpty {
                return .existingAccount
            }
            return response.session == nil ? .needsVerification : .session
        } catch {
            errorMessage = friendly(error)
            return nil
        }
    }

    /// Verifies the 6-digit signup code. The session stays held for the
    /// remaining onboarding steps when `holdSessionForOnboarding` is on.
    public func verifySignupCode(email: String, code: String) async -> Bool {
        errorMessage = nil
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .signup)
            return response.session != nil
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    public func resendSignupCode(email: String) async -> Bool {
        do {
            try await client.auth.resend(email: email, type: .signup)
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    /// The current session's user id, even while the session is held for
    /// onboarding (when `state` hasn't flipped to authenticated yet).
    public func sessionUserId() async -> String? {
        (try? await client.auth.session)?.user.id.uuidString
    }

    /// Ends the register wizard — releases the hold and reveals the session
    /// (no-op when there is no session).
    public func finishOnboarding() async {
        holdSessionForOnboarding = false
        if let session = try? await client.auth.session {
            state = .authenticated(userId: session.user.id.uuidString)
        }
    }

    public func signInWithEmail(email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            state = .authenticated(userId: session.user.id.uuidString)
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Sign in with Apple

    public func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        errorMessage = nil
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8)
        else {
            errorMessage = "Failed to get Apple ID token"
            return
        }

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )
            state = .authenticated(userId: session.user.id.uuidString)
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Sign in with Google (native, ID token)

    /// Presents Google's native account sheet (GoogleSignIn SDK) and exchanges
    /// the returned ID token with Supabase — no web redirect, mirroring the
    /// Apple flow above. Requires `GIDClientID` + the reversed-client-id URL
    /// scheme in Info.plist, and the iOS client id added to Supabase's Google
    /// provider (Authorized Client IDs).
    public func signInWithGoogle() async {
        errorMessage = nil
        guard let presenter = Self.topViewController() else {
            errorMessage = "Couldn't open Google Sign-In. Please try again."
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Couldn't read your Google credentials. Please try again."
                return
            }
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            )
            state = .authenticated(userId: session.user.id.uuidString)
        } catch {
            // GIDSignInError.canceled (-5): the user dismissed the sheet — no-op.
            if (error as NSError).code == -5 { return }
            errorMessage = friendly(error)
        }
    }

    /// Lets GoogleSignIn consume an OAuth callback URL. The native sheet flow
    /// handles its own callback internally, but Google recommends forwarding
    /// `onOpenURL` for completeness (e.g. browser-based fallback).
    @discardableResult
    public func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Top-most presented view controller of the active foreground scene, used
    /// to anchor the Google sign-in sheet.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    // MARK: - Sign Out

    public func signOut() async {
        do {
            try await client.auth.signOut()
            state = .unauthenticated
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Helpers

    public var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    public var currentUserId: String? {
        if case let .authenticated(userId) = state { return userId }
        return nil
    }
}
