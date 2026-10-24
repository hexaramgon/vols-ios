//
//  AvatarPreviewState.swift
//  Volspire
//
//  App-level state for the full-screen avatar zoom. Lives above the tab bar and
//  mini-player (rendered by `OverlaidRootView`) so the preview covers everything.
//  A screen calls `present(url:sourceFrame:)` with the tapped avatar's on-screen
//  frame; the same image then grows in place and shrinks back on dismiss
//  (circular for avatars, the bubble's rounded rect for message photos).
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
    /// The open animation has landed — the image viewer swaps its animating
    /// hero copy for the pinch-zoom viewer (and back on dismiss).
    private(set) var settled = false
    /// Live swipe-to-dismiss offset of an image attachment.
    var dragY: CGFloat = 0

    func present(url: URL, sourceFrame: CGRect, circular: Bool = true) {
        guard sourceFrame != .zero else { return }
        self.url = url
        self.sourceFrame = sourceFrame
        self.circular = circular
        zoomed = false
        settled = false
        dragY = 0
        mounted = true
        // Mount at the source frame first, then grow on the next tick.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                self.zoomed = true
            } completion: {
                if self.zoomed { self.settled = true }
            }
        }
    }

    func dismiss() {
        // Hand back to the hero copy (at the viewer's spot, drag included),
        // then shrink it home; unmount exactly when it lands.
        settled = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            zoomed = false
            dragY = 0
        } completion: {
            if !self.zoomed { self.mounted = false }
        }
    }
}
