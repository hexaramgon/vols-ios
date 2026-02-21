//
//  AuthManager.swift
//  Services
//
//

import AuthenticationServices
import Foundation
import Observation
import Supabase

@MainActor
@Observable
public final class AuthManager {
    public enum AuthState: Equatable {
        case loading
        case authenticated(userId: String)
        case unauthenticated
    }

    public private(set) var state: AuthState = .loading
    public private(set) var errorMessage: String?

    public func setError(_ message: String?) {
        errorMessage = message
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
                if let session {
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

    public func signUpWithEmail(email: String, password: String) async {
        errorMessage = nil
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            state = .authenticated(userId: response.user.id.uuidString)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func signInWithEmail(email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            state = .authenticated(userId: session.user.id.uuidString)
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign in with Google (OAuth)

    public func signInWithGoogle() async {
        errorMessage = nil
        do {
            try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: SupabaseConfig.redirectURL)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Handle OAuth callback URL (for Google redirect)
    public func handleOAuthCallback(url: URL) async {
        do {
            let session = try await client.auth.session(from: url)
            state = .authenticated(userId: session.user.id.uuidString)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign Out

    public func signOut() async {
        do {
            try await client.auth.signOut()
            state = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
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
