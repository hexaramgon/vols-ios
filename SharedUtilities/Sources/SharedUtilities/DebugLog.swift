//
//  DebugLog.swift
//  SharedUtilities
//
//  App-wide debug logging. Compiles to a no-op in release builds so diagnostics and
//  PII-ish detail (user ids, filenames, error dumps) never reach the device console
//  in production. Mirrors the Services-internal `debugLog`, exposed publicly here so
//  the app layer (VolspireCore) can log without raw `print()`.
//

import Foundation

/// Logs only in DEBUG builds; a no-op in release. `message` is an `@autoclosure`, so
/// its string interpolation isn't even evaluated in release — no runtime cost and
/// nothing sensitive is emitted in shipping builds.
public func debugLog(_ message: @autoclosure () -> String = "") {
    #if DEBUG
    print(message())
    #endif
}
