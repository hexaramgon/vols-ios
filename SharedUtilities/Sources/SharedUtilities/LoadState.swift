//
//  LoadState.swift
//  SharedUtilities
//
//  The shared screen-loading state machine. Replaces the per-screen copies
//  (HomeLoadingState, LibraryLoadingState, …) that had drifted (two weren't
//  Equatable, one dropped `idle`).
//
//  It encodes the app's defensive-empty-state rule: show a skeleton until a
//  response confirms emptiness, flip to `error` only when there's no content
//  already on screen (a failed background refresh must not blank a working
//  list), and flip flags on the RESPONSE — never at fetch start.
//

import Foundation

public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)

    /// Begin a fetch: shows the skeleton only when nothing is on screen yet
    /// (`isEmpty` = the screen's backing content is empty). A background
    /// refresh over existing content stays in its current state.
    public mutating func begin(ifEmpty isEmpty: Bool) {
        if isEmpty { self = .loading }
    }

    /// Record a failure: surfaces the error state only when there's no content
    /// to keep showing; otherwise the stale-but-real content stays up.
    public mutating func fail(_ error: any Error, ifEmpty isEmpty: Bool) {
        if isEmpty { self = .error(error.localizedDescription) }
    }
}
