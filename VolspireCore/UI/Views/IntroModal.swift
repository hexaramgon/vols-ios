//
//  IntroModal.swift
//  Volspire
//
//  First-visit explainers, TikTok-style: the first time someone lands on a
//  section (Listings, Workspace, Marketplace) a centred
//  card pops over everything — dimmed backdrop, big glyph, title, a line of
//  context, "Got it". Dismissing it (button or backdrop) hides it for good on
//  this device, per id, under the same key the old inline IntroCard used
//  (`volspire:intro-dismissed:<id>`), so anyone who closed a card never sees
//  its modal.
//
//  Screens attach `.introModal(_:active:ready:)` (ready = their content has
//  loaded, so the tip never pops over skeletons); the one host lives at the root
//  (OverlaidRootView) above the tab bar and mini-player. One at a time: a
//  request while another shows is dropped and simply asks again next visit.
//
//  A spec with an `action` shows a button plus "Not now" instead of "Tap
//  anywhere to continue" (the push primer); either choice hides it for good.
//

import DesignSystem
import SwiftUI

struct IntroSpec: Identifiable, Equatable {
    let id: String
    let icon: LucideIcon.Name
    let title: String
    let message: String
    /// Button title; the handler is passed to `IntroModalCenter.present`.
    var action: String? = nil
}

/// Each section's first-visit explainer.
extension IntroSpec {
    /// Shown once before the system notification prompt, so the prompt
    /// arrives with a reason (and a "Not now" doesn't burn it).
    static let pushPrimer = IntroSpec(
        id: "push-primer", icon: .bell, title: "Turn on notifications",
        message: "Know when someone messages you, wants to collaborate, or comments on your music.",
        action: "Turn on"
    )
    static let listings = IntroSpec(
        id: "listings", icon: .megaphone, title: "Listings",
        message: "Open calls for collaborators. Post what you need, like a vocalist or a mix engineer, and artists respond to you directly."
    )
    static let workspace = IntroSpec(
        id: "workspace", icon: .folderOpen, title: "Your Workspace",
        message: "Where your projects live. Make a folder, invite collaborators, and keep stems, bounces and references in one place."
    )
    /// The free-packs slice gets its own copy (and id, so the full
    /// marketplace intro still shows once paid features launch).
    static var marketplace: IntroSpec {
        FeatureFlags.freePacksOnly
            ? IntroSpec(
                id: "marketplace-free-packs", icon: .store, title: "Marketplace",
                message: "Free sample packs from artists on Volspire. Grab loops, drum kits and presets, or share your own."
            )
            : IntroSpec(
                id: "marketplace", icon: .store, title: "Marketplace",
                message: "Beats, sample packs and services from artists on Volspire. License a beat, grab a pack, or book a mix."
            )
    }
}

@MainActor @Observable
final class IntroModalCenter {
    static let shared = IntroModalCenter()
    private(set) var current: IntroSpec?
    @ObservationIgnored private var onAction: (() -> Void)?

    static func key(_ id: String) -> String { "volspire:intro-dismissed:\(id)" }
    static func isDismissed(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }

    func present(_ spec: IntroSpec, onAction: (() -> Void)? = nil) {
        guard current == nil, !Self.isDismissed(spec.id) else { return }
        self.onAction = onAction
        withAnimation(.smooth(duration: 0.32)) { current = spec }
    }

    func dismiss() {
        guard let spec = current else { return }
        UserDefaults.standard.set(true, forKey: Self.key(spec.id))
        onAction = nil
        withAnimation(.smooth(duration: 0.22)) { current = nil }
    }

    /// The spec's button: dismiss, then run its handler.
    func runAction() {
        let action = onAction
        dismiss()
        action?()
    }
}

// MARK: - Trigger

private struct IntroModalTrigger: ViewModifier {
    let spec: IntroSpec
    let active: Bool
    /// The section's content has landed — the tip waits for it instead of
    /// popping over skeletons.
    let ready: Bool
    @Environment(\.isActiveRootTab) private var isActiveRootTab

    private var shouldShow: Bool { active && ready && isActiveRootTab }

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
    /// is on screen), once `ready` (its content has loaded), until it's been
    /// dismissed once.
    func introModal(_ spec: IntroSpec, active: Bool = true, ready: Bool) -> some View {
        modifier(IntroModalTrigger(spec: spec, active: active, ready: ready))
    }
}

// MARK: - Host

/// The full-screen dim behind popups and coach marks: a light blur under a
/// black wash, edge to edge. Keep it mounted and fade it with `.opacity` — a
/// material that unmounts blinks instead of fading.
struct DimBackdrop: View {
    /// Material strength (the blur's opacity).
    var blur: Double = 0.5
    /// Black wash on top.
    var dim: Double = 0.85

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(blur)
            Color.black.opacity(dim)
        }
        .ignoresSafeArea()
    }
}

/// The modal itself; mount once, above the app's chrome. Styled exactly like
/// the player's coach marks (FullScreenTapHint): a dark full-screen dim, a big
/// white glyph, an 18pt title and 16pt line in white — no card. A tap anywhere
/// dismisses it; a faint "Tap anywhere to continue" says so.
struct IntroModalHost: View {
    @State private var center = IntroModalCenter.shared
    /// The last tip shown — kept mounted so it fades out with the dim.
    @State private var shownSpec: IntroSpec?
    /// Taps are ignored for a beat after a tip appears, so a frantic or
    /// stray tap can't dismiss it before it's been read.
    @State private var locked = false

    /// How long a tip stays put before a tap can dismiss it.
    private static let minimumShow: Duration = .milliseconds(1200)

    private var visible: Bool { center.current != nil }

    // Dim and content are one layer faded by opacity, like the player's
    // coach marks — no insertion transition on the content, so it can never
    // be left behind (invisible) while the dim shows.
    var body: some View {
        ZStack {
            // Heavier blur than the coach marks: a tip is about the section
            // behind it, not the content, so it shouldn't compete.
            DimBackdrop(blur: 1, dim: 0.7)

            if let spec = center.current ?? shownSpec {
                content(spec)
                    .offset(y: visible ? 0 : 14)
                    .transition(.identity)
            }
        }
        .opacity(visible ? 1 : 0)
        .contentShape(.rect)
        .allowsHitTesting(visible)
        .onTapGesture { if !locked { center.dismiss() } }
        .onChange(of: center.current) { _, spec in
            if let spec { shownSpec = spec }
        }
        .task(id: center.current?.id) {
            guard center.current != nil else { return }
            locked = true
            try? await Task.sleep(for: Self.minimumShow)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { locked = false }
        }
    }

    private func content(_ spec: IntroSpec) -> some View {
        VStack(spacing: 22) {
            LucideIcon(spec.icon, size: 64)
                .foregroundStyle(.white)
                .frame(width: 120, height: 96)

            VStack(spacing: 6) {
                Text(spec.title)
                    .font(.appTitle3)
                    .foregroundStyle(.white)
                Text(spec.message)
                    .font(.appBody)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            // "Tap anywhere" appears once the tip has had its moment; an
            // action tip's buttons show right away (they're deliberate taps).
            Group {
                if let action = spec.action {
                    VStack(spacing: 6) {
                        // White on the dark dim (the app's primary capsule is
                        // ink, which vanished here in light mode).
                        Button { center.runAction() } label: {
                            Text(action)
                                .font(.appSubheadlineSemibold)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(.white, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button { center.dismiss() } label: {
                            Text("Not now")
                                .font(.appSubheadlineMedium)
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 260)
                } else {
                    Text("Tap anywhere to continue")
                        .font(.appFootnote)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.top, 6)
            .opacity(locked && spec.action == nil ? 0 : 1)
            .allowsHitTesting(!locked || spec.action != nil)
        }
        .padding(.horizontal, 32)
        .modifier(IntroAccessibility(hasAction: spec.action != nil))
    }
}

/// A plain tip reads as one dismiss button; an action tip keeps its button
/// separately reachable.
private struct IntroAccessibility: ViewModifier {
    let hasAction: Bool

    func body(content: Content) -> some View {
        if hasAction {
            content.accessibilityAddTraits(.isModal)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits([.isModal, .isButton])
                .accessibilityHint("Dismisses this tip")
        }
    }
}
