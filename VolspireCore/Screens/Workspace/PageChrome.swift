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
//  - `HeroCapsuleButton` — the 40pt hero action (folder Upload / Invite,
//    pack Download / Share).
//

import DesignSystem
import SwiftUI

// MARK: - Back-title band

private struct BackTitleBand<Trailing: View>: ViewModifier {
    let label: String
    /// Optional visible title (+ a second line) beside the back button —
    /// the app nav bar's title / subtitle type.
    var title: String? = nil
    var subtitle: String? = nil
    /// Scroll offset at which `title` fades in (over ~30pt) — once the page's
    /// own name has slid up under the band. nil = always shown.
    var titleRevealAt: CGFloat? = nil
    let onBack: (() -> Void)?
    /// The page runs up under the band, which stays see-through (just the
    /// back label) until the content scrolls, then fades its canvas in.
    let overlaysContent: Bool
    let trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    /// Canvas opacity for `overlaysContent` — written only as it changes
    /// (clamped), so scrolling past the fade costs nothing.
    @State private var canvasOpacity: Double = 0
    /// `title`'s opacity when it reveals on scroll (written only on change).
    @State private var titleOpacity: Double = 0

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
            .onScrollGeometryChange(for: Double.self) { geometry in
                guard let start = titleRevealAt else { return 1 }
                let y = geometry.contentOffset.y + geometry.contentInsets.top
                return min(max((y - start) / 30, 0), 1)
            } action: { _, opacity in
                titleOpacity = opacity
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
            // Centred on the screen; the inset keeps it clear of the back
            // button and up to three trailing icons (truncates before them).
            .overlay {
                if let title {
                    VStack(spacing: 1) {
                        Text(title)
                            .font(subtitle == nil ? .appHeadline : .appCalloutSemibold)
                            .foregroundStyle(Color.vText)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.appCaption)
                                .foregroundStyle(Color.vText3)
                                .lineLimit(1)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 112)
                    .opacity(titleRevealAt == nil ? 1 : titleOpacity)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
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
        title: String? = nil,
        subtitle: String? = nil,
        titleRevealAt: CGFloat? = nil,
        overlaysContent: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        onBack: (() -> Void)? = nil
    ) -> some View {
        modifier(BackTitleBand(label: label, title: title, subtitle: subtitle, titleRevealAt: titleRevealAt,
                               onBack: onBack, overlaysContent: overlaysContent, trailing: trailing()))
    }

    /// Height of the back band (status bar + band) — what an
    /// `overlaysContent` page pads its hero by.
    static var backTitleBandHeight: CGFloat {
        ViewConst.safeAreaInsets.top + ViewConst.headerBandHeight
    }
}

// MARK: - Hero capsule button

/// A page hero's action: icon + label in a 40pt capsule. Primary = ink fill,
/// secondary = the control fill. Pass `busy` to swap the glyph for a spinner,
/// `compact` for tighter side padding where a row would otherwise overflow.
struct HeroCapsuleButton: View {
    let title: String
    let icon: LucideIcon.Name
    var primary = false
    var busy = false
    var compact = false
    /// Fill the available width (the playlist page's Play / Shuffle row).
    var expands = false
    let action: () -> Void

    init(_ title: String, icon: LucideIcon.Name, primary: Bool = false, busy: Bool = false,
         compact: Bool = false, expands: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.primary = primary
        self.busy = busy
        self.compact = compact
        self.expands = expands
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).tint(primary ? Color.vOnInverse : Color.vControlLabel)
                } else {
                    LucideIcon(icon, .md)
                }
                Text(title).font(.appSubheadlineSemibold)
            }
            .foregroundStyle(primary ? Color.vOnInverse : Color.vControlLabel)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: CapsuleButtonLabel.heroHeight)
            .background(primary ? Color.vInverse : Color.vControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

// MARK: - Round icon button

/// The web `IconButton`: a round, single-glyph button. Secondary = control
/// fill + ink@0.70 glyph; primary = ink fill + paper glyph; send = accent;
/// inactive = control fill + faint glyph (a done, non-tappable state).
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

    enum Variant { case secondary, primary, send, inactive }

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
        // Ignore taps while busy rather than dimming (optimistic toggles);
        // an inactive button never takes them.
        .allowsHitTesting(!busy && variant != .inactive)
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
        case .inactive: Color.vText
        }
    }

    private var background: Color {
        switch variant {
        case .secondary, .inactive: Color.vControl
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

/// The app's one capsule-button anatomy — icon + label, 36pt, footnote
/// semibold. Primary = ink fill ("+ New", Edit Profile, Play); secondary =
/// the control fill (Share Profile, Add tracks); accent = the send blue
/// (Collab). Workspace, Profile and the
/// playlist page all draw their buttons with it, so they match.
struct CapsuleButtonLabel: View {
    enum Style { case primary, secondary, muted, accent }

    var icon: LucideIcon.Name?
    let title: String
    var style: Style = .primary
    /// Fill the available width (rows of evenly sized buttons).
    var expands = false
    /// The profile hero's buttons run a larger glyph.
    var iconSize: IconSize = .sm
    /// A trailing glyph, e.g. a chevron on a menu button.
    var trailingIcon: LucideIcon.Name? = nil
    /// The profile hero runs taller (`large`) buttons.
    var height: CGFloat = CapsuleButtonLabel.height
    var font: Font = .appFootnoteSemibold
    var spacing: CGFloat = 6

    static let height: CGFloat = 36
    /// The hero-row height — `HeroCapsuleButton` (folder Invite / Upload)
    /// and the profile action bar share it.
    static let heroHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: spacing) {
            if let icon { LucideIcon(icon, iconSize) }
            Text(title).lineLimit(1)
            if let trailingIcon { LucideIcon(trailingIcon, .xs).opacity(0.6) }
        }
        .font(font)
        .foregroundStyle(style.foreground)
        .padding(.horizontal, 14)
        .frame(maxWidth: expands ? .infinity : nil)
        .frame(height: height)
        .background(style.background, in: Capsule())
        .contentShape(Capsule())
    }
}

extension CapsuleButtonLabel.Style {
    var foreground: Color {
        switch self {
        case .primary: Color.vOnInverse
        case .secondary: Color.vText
        case .muted: Color.vText2
        case .accent: Color.vOnColor
        }
    }

    var background: Color {
        switch self {
        case .primary: Color.vInverse
        case .secondary, .muted: Color.vControl
        case .accent: Color.vAccent
        }
    }
}

/// The matching icon-only circle (settings / share / "…").
struct CapsuleIconButtonLabel: View {
    let icon: LucideIcon.Name
    var iconSize: IconSize = .sm
    var style: CapsuleButtonLabel.Style = .secondary
    var size: CGFloat = CapsuleButtonLabel.height

    var body: some View {
        LucideIcon(icon, iconSize)
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(style.background, in: Circle())
            .contentShape(Circle())
    }
}
