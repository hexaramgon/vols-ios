//
//  Error+Cancellation.swift
//  SharedUtilities
//
//  SwiftUI cancels a screen's `.task` when it disappears and a pull-to-refresh
//  when the list re-renders under it. The in-flight request then throws a
//  cancellation — which is not a failure, and must never surface as an error
//  ("Can't reach Volspire") or replace content.
//

import Foundation

public extension Error {
    /// True for Swift task cancellation and URLSession's "cancelled".
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError { return urlError.code == .cancelled }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}
