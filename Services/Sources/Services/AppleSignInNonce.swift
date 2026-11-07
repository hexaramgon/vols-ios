//
//  AppleSignInNonce.swift
//  Services
//
//  Binds an Apple ID token to the sign-in attempt that requested it, so a
//  captured token can't be replayed. The SHA-256 of `raw` goes to Apple on the
//  request (Apple embeds it in the token's `nonce` claim); `raw` itself goes to
//  Supabase with the token, which re-hashes it and rejects any mismatch.
//

import CryptoKit
import Foundation

public struct AppleSignInNonce: Sendable {
    /// Sent to Supabase with the ID token. Never sent to Apple.
    public let raw: String

    /// 32 random bytes as hex. `SystemRandomNumberGenerator` is
    /// cryptographically secure on Apple platforms.
    public init() {
        var generator = SystemRandomNumberGenerator()
        raw = (0 ..< 32)
            .map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// Set as `ASAuthorizationAppleIDRequest.nonce`.
    public var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
