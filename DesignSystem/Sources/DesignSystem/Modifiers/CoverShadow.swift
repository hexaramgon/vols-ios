//
//  CoverShadow.swift
//  DesignSystem
//
//  The soft drop shadow under small artwork in list rows — the same one the
//  workspace folder tiles carry (`FolderArt`), so track covers and folders
//  sit on the page the same way.
//

import SwiftUI

public extension View {
    /// Soft shadow under a list row's cover (black 30%, 8pt blur, 4pt down).
    func coverShadow() -> some View {
        shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}
