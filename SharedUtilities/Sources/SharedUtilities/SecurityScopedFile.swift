//
//  SecurityScopedFile.swift
//  SharedUtilities
//
//  The start/defer/stop security-scoped access dance around reading a
//  picker-returned file, shared by the upload forms' file handlers.
//

import Foundation

public enum SecurityScopedFile {
    /// Reads a file picked via `fileImporter` inside its security-scoped access
    /// session. Returns nil when scoped access is denied (callers skip those
    /// silently, matching the forms' behaviour) and throws when the read fails.
    public static func read(_ url: URL) throws -> Data? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return try Data(contentsOf: url)
    }
}
