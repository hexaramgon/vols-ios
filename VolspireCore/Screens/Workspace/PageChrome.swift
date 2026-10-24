//
//  PageChrome.swift
//  Volspire
//
//  Small shared pieces of the web revamp's pushed-page anatomy, used by the
//  listing detail, folder and workspace screens:
//  - `backTitleBand(_:trailing:)` — the 53pt sticky band with the app's
//    standard back button, translucent canvas + blur, bottom hairline.
//  - `CircleIconButton` — the web `IconButton` (round, 32/36/40, secondary /
//    primary / send), with the toggle-on "pop".
//  - `StatCount` — the app-wide stat format (16pt grey icon + semibold number).
//

import DesignSystem
import SwiftUI

// MARK: - Back-title band

private struct BackTitleBand<Trailing: View>: ViewModifier {
    let label: String
    let onBack: (() -> Void)?
    /// The page runs up under the band, which stays see-through (just the
    /// back label) until the content scrolls, then fades its canvas in.
    let overlaysContent: Bool
    let trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    /// Canvas opacity for `overlaysContent` — written only as it changes
    /// (clamped), so scrolling past the fade costs nothing.
    @State private var canvasOpacity: Double = 0

    static var bandHeight: CGFloat { ViewConst.safeAreaInsets.top + ViewConst.headerBandHeight }

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: .top)
            .background(Color.vBase.ignoresSafeArea())
            // Clear the fixed band with the scroll content (unless the page
            // is meant to run up under it).
            .contentMargins(.top, overlaysContent ? 0 : Self.bandHeight, for: .scrollContent)
            .onScrollGeometryChange(for: Double.self) { geometry in
                // Fade in over the first ~80pt of scroll.
                let y = geometry.contentOffset.y + geometry.contentInsets.top
                return min(max((y - 40) / 80, 0), 1)
            } action: { _, opacity in
                if overlaysContent { canvasOpacity = opacity }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { band }
            .enableSwipeBack()
    }

    private var band: some View {
        ZStack(alignment: .bottom) {
            // Translucent canvas over a blur — kept mounted (materials fade,
            // never unmount).
            Group {
                Rectangle().fill(.ultraThinMaterial)
                Color.vBase.opacity(0.7)
                Rectangle().fill(Color.vDivider).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .opacity(overlaysContent ? canvasOpacity : 1)

            HStack(spacing: 8) {
                // The app's standard back button (same glyph, size and ink as
                // the Settings bar) — icon only; `label` names it for VoiceOver.
                Button { (onBack ?? { dismiss() })() } label: {
                    LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
                        .foregroundStyle(Color.vText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4 - ViewConst.screenPaddings)
                .accessibilityLabel("Back to \(label)")

                Spacer(minLength: 0)

                trailing
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .frame(height: ViewConst.headerBandHeight)
        }
        .frame(height: Self.bandHeight)
        .ignoresSafeArea(edges: .top)
    }
}

extension View {
    /// The pushed-page header band: "‹ {label}" as the back target, optional
    /// trailing round icon buttons. Hides the system bar and keeps swipe-back.
    /// `overlaysContent`: the page runs up to the top of the screen under a
    /// see-through band whose canvas fades in on scroll (pages with a
    /// full-bleed hero) — the page then clears the band itself.
    func backTitleBand<Trailing: View>(
        _ label: String,
        overlaysContent: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        onBack: (() -> Void)? = nil
    ) -> some View {
        modifier(BackTitleBand(label: label, onBack: onBack, overlaysContent: overlaysContent, trailing: trailing()))
    }

    /// Height of the back band (status bar + band) — what an
    /// `overlaysContent` page pads its hero by.
    static var backTitleBandHeight: CGFloat {
        ViewConst.safeAreaInsets.top + ViewConst.headerBandHeight
    }
}

// MARK: - Round icon button

/// The web `IconButton`: a round, single-glyph button. Secondary = control
/// fill + ink@0.70 glyph; primary = ink fill + paper glyph; send = accent.
struct CircleIconButton: View {
    enum Size {
        case sm, md, lg
        var diameter: CGFloat {
            switch self {
            case .sm: 32
            case .md: 36
            case .lg: 40
            }
        }
        var glyph: IconSize { self == .lg ? .lg : .md }
    }

    enum Variant { case secondary, primary, send }

    let icon: LucideIcon.Name
    var size: Size = .sm
    var variant: Variant = .secondary
    /// Plays the 1 → 1.12 → 1 pop each time this flips to true (Save → Saved).
    var popOn: Bool = false
    var busy: Bool = false
    let action: () -> Void

    @State private var popScale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(foreground).controlSize(.small)
                } else {
                    LucideIcon(icon, size.glyph)
                }
            }
            .foregroundStyle(foreground)
            .frame(width: size.diameter, height: size.diameter)
            .background(background, in: Circle())
            .contentShape(Circle())
            .scaleEffect(popScale)
        }
        .buttonStyle(.plain)
        // Ignore taps while busy rather than dimming (optimistic toggles).
        .allowsHitTesting(!busy)
        .onChange(of: popOn) { _, on in
            guard on else { return }
            withAnimation(.spring(duration: 0.16)) { popScale = 1.12 }
            withAnimation(.spring(duration: 0.16).delay(0.16)) { popScale = 1 }
        }
    }

    private var foreground: Color {
        switch variant {
        case .secondary: Color.vControlLabel
        case .primary: Color.vOnInverse
        case .send: Color.vOnColor
        }
    }

    private var background: Color {
        switch variant {
        case .secondary: Color.vControl
        case .primary: Color.vInverse
        case .send: Color.vAccent
        }
    }
}

// MARK: - Stat

/// The app-wide stat: a 16pt grey icon + a semibold tabular number, no label.
struct StatCount: View {
    let icon: LucideIcon.Name
    let value: Int

    var body: some View {
        HStack(spacing: 6) {
            LucideIcon(icon, .md).foregroundStyle(Color.vText3)
            Text(value.compactCount)
                .font(.appSubheadlineSemibold)
                .foregroundStyle(Color.vText)
                .monospacedDigit()
                .fixedSize()
        }
    }
}

// MARK: - New capsule

/// The ink "+" capsule that replaces the accent "New" pill on section heads
/// (accent is reserved for send actions and active states).
struct NewCapsuleButton: View {
    var title: String = "New"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CapsuleButtonLabel(icon: .plus, title: title)
        }
        .buttonStyle(.plain)
    }
}

/// The app's one capsule-button anatomy — icon + label, 36pt, footnote
/// semibold. Primary = ink fill ("+ New", Edit Profile, Play); secondary =
/// the control fill (Share Profile, Add tracks). Workspace, Profile and the
/// playlist page all draw their buttons with it, so they match.
struct CapsuleButtonLabel: View {
    enum Style { case primary, secondary, muted }

    var icon: LucideIcon.Name?
    let title: String
    var style: Style = .primary
    /// Fill the available width (rows of evenly sized buttons).
    var expands = false

    static let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            if let icon { LucideIcon(icon, .sm) }
            Text(title).lineLimit(1)
        }
        .font(.appFootnoteSemibold)
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .frame(maxWidth: expands ? .infinity : nil)
        .frame(height: Self.height)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }

    private var foreground: Color {
        switch style {
        case .primary: Color.vOnInverse
        case .secondary: Color.vText
        case .muted: Color.vText2
        }
    }

    private var background: Color {
        style == .primary ? Color.vInverse : Color.vControl
    }
}

/// The matching icon-only circle (settings / share / "…").
struct CapsuleIconButtonLabel: View {
    let icon: LucideIcon.Name

    var body: some View {
        LucideIcon(icon, .sm)
            .foregroundStyle(Color.vText)
            .frame(width: CapsuleButtonLabel.height, height: CapsuleButtonLabel.height)
            .background(Color.vControl, in: Circle())
            .contentShape(Circle())
    }
}
