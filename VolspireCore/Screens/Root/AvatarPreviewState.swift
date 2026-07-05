//
//  AvatarPreviewState.swift
//  Volspire
//
//  App-level state for the full-screen avatar zoom. Lives above the tab bar and
//  mini-player (rendered by `OverlaidRootView`) so the preview covers everything.
//  A screen calls `present(url:sourceFrame:)` with the tapped avatar's on-screen
//  frame; the same circular image then grows in place and shrinks back on dismiss.
//

import Foundation
import SwiftUI

@Observable @MainActor
final class AvatarPreviewState {
    private(set) var url: URL?
    private(set) var sourceFrame: CGRect = .zero
    /// Circular (profile avatar) vs rounded-rect (image attachment).
    private(set) var circular = true
    /// Mounted (overlay present) for the whole open→close lifecycle.
    private(set) var mounted = false
    /// Drives the open/close animation (false = at the source frame, true = zoomed).
    private(set) var zoomed = false

    func present(url: URL, sourceFrame: CGRect, circular: Bool = true) {
        guard sourceFrame != .zero else { return }
        self.url = url
        self.sourceFrame = sourceFrame
        self.circular = circular
        zoomed = false
        mounted = true
        // Mount at the avatar's frame first, then grow on the next tick.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { self.zoomed = true }
        }
    }

    func dismiss() {
        // Unmount exactly when the shrink finishes so it lands back on the avatar.
        withAnimation(.easeOut(duration: 0.24)) {
            zoomed = false
        } completion: {
            self.mounted = false
        }
    }
}
