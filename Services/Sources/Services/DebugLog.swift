//
//  DebugLog.swift
//  Services
//
//  Debug-only logging. Compiles to a no-op in release builds so diagnostics and
//  PII-ish details (user ids, filenames, upload paths, analytics, error dumps)
//  never reach the device console in production.
//

import Foundation

/// Logs only in DEBUG builds; a no-op in release. `message` is an
/// `@autoclosure`, so its string interpolation isn't even evaluated in release —
/// no runtime cost and nothing sensitive is emitted in shipping builds.
func debugLog(_ message: @autoclosure () -> String = "") {
    #if DEBUG
    print(message())
    #endif
}
