//
//  IntroModal.swift
//  Volspire
//
//  First-visit explainers, TikTok-style: the first time someone lands on a
//  section (Collab, Listings, My Network, Workspace, Marketplace) a centred
//  card pops over everything — dimmed backdrop, big glyph, title, a line of
//  context, "Got it". Dismissing it (button or backdrop) hides it for good on
//  this device, per id, under the same key the old inline IntroCard used
//  (`volspire:intro-dismissed:<id>`), so anyone who closed a card never sees
//  its modal.
//
//  Screens attach `.introModal(_:active:)`; the one host lives at the root
//  (OverlaidRootView) above the tab bar and mini-player. One at a time: a
//  request while another shows is dropped and simply asks again next visit.
//

import DesignSystem
import SwiftUI

struct IntroSpec: Identifiable, Equatable {
    let id: String
    let icon: LucideIcon.Name
    let title: String
    let message: String
}

/// Each section's first-visit explainer.
extension IntroSpec {
    static let collab = IntroSpec(
        id: "collab", icon: .handshake, title: "Welcome to Collab",
        message: "Find people to make music with. Filter by role, see who's nearby, and pitch anyone open to working together."
    )
    static let listings = IntroSpec(
        id: "listings", icon: .megaphone, title: "Listings",
        message: "Open calls for collaborators. Post what you need, like a vocalist or a mix engineer, and artists respond to you directly."
    )
    static let network = IntroSpec(
        id: "network", icon: .users, title: "My Network",
        message: "Your feed from the people you follow. Their new releases land here first."
    )
    static let workspace = IntroSpec(
        id: "workspace", icon: .folderOpen, title: "Your Workspace",
        message: "Where your projects live. Make a folder, invite collaborators, and keep stems, bounces and references in one place."
    )
    static let marketplace = IntroSpec(
        id: "marketplace", icon: .store, title: "Marketplace",
        message: "Beats, sample packs and services from artists on Volspire. License a beat, grab a pack, or book a mix."
    )
}

@MainActor @Observable
final class IntroModalCenter {
    static let shared = IntroModalCenter()
    private(set) var current: IntroSpec?

    static func key(_ id: String) -> String { "volspire:intro-dismissed:\(id)" }
    static func isDismissed(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: key(id)) }

    func present(_ spec: IntroSpec) {
        guard current == nil, !Self.isDismissed(spec.id) else { return }
        withAnimation(.smooth(duration: 0.32)) { current = spec }
    }

    func dismiss() {
        guard let spec = current else { return }
        UserDefaults.standard.set(true, forKey: Self.key(spec.id))
        withAnimation(.smooth(duration: 0.22)) { current = nil }
    }
}

// MARK: - Trigger

private struct IntroModalTrigger: ViewModifier {
    let spec: IntroSpec
    let active: Bool
    @Environment(\.isActiveRootTab) private var isActiveRootTab

    private var shouldShow: Bool { active && isActiveRootTab }

    func body(content: Content) -> some View {
        content
            // A beat after the section settles, and only if it's still the
            // one on screen by then.
            .task(id: shouldShow) {
                guard shouldShow, !IntroModalCenter.isDismissed(spec.id) else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, shouldShow else { return }
                IntroModalCenter.shared.present(spec)
            }
    }
}

extension View {
    /// Shows `spec` as a first-visit modal while `active` (and this root tab
    /// is on screen), until it's been dismissed once.
    func introModal(_ spec: IntroSpec, active: Bool = true) -> some View {
        modifier(IntroModalTrigger(spec: spec, active: active))
    }
}

// MARK: - Host

/// The modal itself; mount once, above the app's chrome. Quiet on purpose:
/// a blurred, dimmed backdrop, a compact card with a small glyph chip, and a soft rise +
/// fade in (no scale pop), so it reads as a tip rather than an interruption.
struct IntroModalHost: View {
    @State private var center = IntroModalCenter.shared

    var body: some View {
        ZStack {
            // Blur + dim, kept mounted and faded (a material that's mounted
            // and unmounted blinks instead of fading).
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.4)
            }
            .ignoresSafeArea()
            .opacity(center.current == nil ? 0 : 1)
            .allowsHitTesting(center.current != nil)
            .onTapGesture { center.dismiss() }

            if let spec = center.current {
                card(spec)
                    .padding(.horizontal, 36)
                    .transition(.offset(y: 14).combined(with: .opacity))
            }
        }
    }

    private func card(_ spec: IntroSpec) -> some View {
        VStack(spacing: 0) {
            LucideIcon(spec.icon, .lg)
                .foregroundStyle(Color.vText2)
                .frame(width: 44, height: 44)
                .background(Color.vControl, in: Circle())
            Text(spec.title)
                .font(.appHeadline)
                .foregroundStyle(Color.vText)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Text(spec.message)
                .font(.appSubheadline)
                .foregroundStyle(Color.vText2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button { center.dismiss() } label: {
                Text("Got it")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.vControl, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(CardPress())
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: 320)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
