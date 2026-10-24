//
//  APIModels+Social.swift
//  Services
//
//  DTOs for the social/settings surfaces (Settings → Security, collab map
//  opt-in, notification collab responses).
//

import Foundation

/// How the signed-in account can sign in (web `useSignInMethods`): an email
/// password, and/or OAuth providers ("google", "apple").
public struct SignInMethods: Equatable, Sendable {
    public let hasPassword: Bool
    public let providers: [String]

    public init(hasPassword: Bool, providers: [String]) {
        self.hasPassword = hasPassword
        self.providers = providers
    }
}

/// Why a password change was refused before it reached the server.
public enum PasswordChangeError: Error, Equatable, Sendable {
    case incorrectCurrentPassword
}
