//
//  Int+ByteLabel.swift
//  SharedUtilities
//
//  The one byte-count formatter (decimal/1000-based, matching Finder and the
//  upload flow's original convention). Three hand-rolled copies had drifted —
//  one was 1024-based, so the same file showed different sizes per screen.
//

import Foundation

public extension Int {
    /// "824 KB", "3.2 MB" — decimal units.
    var byteLabel: String {
        self >= 1_000_000
            ? String(format: "%.1f MB", Double(self) / 1_000_000)
            : String(format: "%.0f KB", Double(self) / 1_000)
    }
}
