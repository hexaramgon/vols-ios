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

// MARK: - In-app push banner

/// A push that arrived while the app is open, shown as the app's OWN banner at
/// the top (the AppDelegate asks iOS for no system banner in the foreground).
/// iOS hides its foreground banners under a Focus / banner-style setting —
/// pushes then only landed silently in Notification Center — so in-app
/// alerts don't depend on that. Tap → the same routing as tapping the push;
/// swipe up or wait to dismiss. One at a time — a newer push replaces it.
@MainActor @Observable
final class PushBannerCenter {
    static let shared = PushBannerCenter()

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let body: String
        let isMessage: Bool
        /// The push's string fields — handed to the tap routing as-is.
        let info: [String: String]
    }

    private(set) var current: Banner?
    private var hideTask: Task<Void, Never>?
    /// The same event can arrive twice (the live check AND its push) —
    /// one banner per conversation / for activity within this window.
    private var recent: [String: Date] = [:]
    private static let dedupeWindow: TimeInterval = 12

    func show(_ info: [String: String]) {
        let title = info["title"] ?? ""
        let body = info["body"] ?? ""
        guard !title.isEmpty || !body.isEmpty else { return }
        let dedupeKey = info["convo_id"]?.lowercased() ?? "activity:\(info["object_id"] ?? "")"
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < Self.dedupeWindow }
        guard recent[dedupeKey] == nil else { return }
        recent[dedupeKey] = now
        let banner = Banner(title: title, body: body, isMessage: info["convo_id"] != nil, info: info)
        withAnimation(.smooth(duration: 0.32)) { current = banner }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.current?.id == banner.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.current = nil }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) { current = nil }
    }

    /// Opens what the push points at — the system-tap path (RootTabView
    /// drains `PushInbox.pending`).
    func open() {
        guard let banner = current else { return }
        dismiss()
        PushInbox.pending = banner.info
        NotificationCenter.default.post(name: .openPushNotification, object: nil)
    }
}

/// The banner card; mount once at the root, top-aligned inside the safe area.
struct PushBannerHost: View {
    @State private var center = PushBannerCenter.shared
    @State private var dragY: CGFloat = 0

    var body: some View {
        ZStack {
            if let banner = center.current {
                HStack(spacing: 12) {
                    LucideIcon(banner.isMessage ? .messagesSquare : .bell, .lg)
                        .foregroundStyle(Color.vOnColor)
                        .frame(width: 40, height: 40)
                        .background(Color.vAccent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        if !banner.title.isEmpty {
                            Text(banner.title)
                                .font(.appCalloutSemibold)
                                .foregroundStyle(Color.vText)
                                .lineLimit(1)
                        }
                        if !banner.body.isEmpty {
                            Text(banner.body)
                                .font(.appSubheadline)
                                .foregroundStyle(Color.vText2)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.vBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .offset(y: min(0, dragY))
                .contentShape(.rect)
                .onTapGesture { center.open() }
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { dragY = $0.translation.height }
                        .onEnded { value in
                            if value.translation.height < -24 { center.dismiss() }
                            withAnimation(.smooth(duration: 0.2)) { dragY = 0 }
                        }
                )
                .id(banner.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens it")
            }
        }
        .allowsHitTesting(center.current != nil)
    }
}
