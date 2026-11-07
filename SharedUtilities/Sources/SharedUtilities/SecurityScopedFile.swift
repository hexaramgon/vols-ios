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
    /// With `maxBytes`, a larger file throws `FileTooLargeError` BEFORE it's
    /// read into memory (pass the destination bucket's `maxUploadBytes`).
    public static func read(_ url: URL, maxBytes: Int? = nil) throws -> Data? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        if let maxBytes,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxBytes {
            throw FileTooLargeError(maxBytes: maxBytes)
        }
        return try Data(contentsOf: url)
    }

    /// Copies a picked file into the app's temp directory (same size checks as
    /// `read`) and returns the copy — for flows that hold several big files
    /// until a later upload, so they sit on disk instead of in memory. nil when
    /// scoped access is denied. The caller owns (and deletes) the copy.
    public static func stage(_ url: URL, maxBytes: Int? = nil) throws -> URL? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        if let maxBytes,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxBytes {
            throw FileTooLargeError(maxBytes: maxBytes)
        }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("staged-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }
}

/// A file over its upload cap. The message is user-facing.
public struct FileTooLargeError: LocalizedError, Sendable {
    public let maxBytes: Int

    public init(maxBytes: Int) { self.maxBytes = maxBytes }

    public var errorDescription: String? {
        "That file is too large — the limit is \(maxBytes / 1_048_576) MB."
    }
}
