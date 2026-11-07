//
//  ToastCenter.swift
//  Volspire
//
//  The app's one transient confirmation: a small pill that rises in just above
//  the tab bar / mini-player ("Track deleted", "Blocked @user") and fades out
//  on its own. Errors carry the error glyph ("Couldn't delete the track — it's
//  back."). One at a time — a new toast replaces the current one. Shown by
//  `ContentActions` after every destructive action; `ToastHost` is mounted
//  once at the root (OverlaidRootView).
//

import DesignSystem
import Observation
import SwiftUI

@MainActor @Observable
final class ToastCenter {
    static let shared = ToastCenter()

    struct Toast: Identifiable, Equatable {
        enum Style { case success, error }
        let id = UUID()
        let text: String
        let style: Style
    }

    private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, style: Toast.Style = .success) {
        let toast = Toast(text: text, style: style)
        withAnimation(.smooth(duration: 0.28)) { current = toast }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .error ? 3.5 : 2.4))
            guard !Task.isCancelled, let self, self.current?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.current = nil }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { current = nil }
    }
}

/// The pill itself; mount once at the root, bottom-aligned above the chrome.
struct ToastHost: View {
    @State private var center = ToastCenter.shared

    var body: some View {
        ZStack {
            if let toast = center.current {
                HStack(spacing: 8) {
                    LucideIcon(toast.style == .error ? .circleX : .circleCheck, .md)
                        .foregroundStyle(toast.style == .error ? Color.vError : Color.vOnInverse)
                    Text(toast.text)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vOnInverse)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.vInverse, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.horizontal, 24)
                .id(toast.id)
                .transition(.offset(y: 12).combined(with: .opacity))
                .onTapGesture { center.dismiss() }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(center.current != nil)
    }
}
