//
//  OptionSheetComponents.swift
//  Volspire
//
//  Shared anatomy for the slide-up "…" option sheets, lifted out of
//  `TrackOptionsSheet` (the canonical example) so every sheet reads — and
//  stays — identical:
//  - `OptionSheetRow`: the icon + title action row. By default the glyph is
//    `vText2` and the label `vText`; a `tint` drives both (destructive rows
//    pass a red tint); an optional
//    subtitle and trailing accessory cover the track sheet's spinner rows.
//  - `selfSizedDetent()`: the measured-detent scaffold — the sheet detents to
//    exactly fit its content instead of a fixed `.medium` or hand-computed
//    row math, which leaves dead space (or clips) whenever row metrics change.
//

import DesignSystem
import SwiftUI

// MARK: - OptionSheetRow

/// The standard option-sheet action row: a Lucide glyph in a fixed-width slot,
/// an `.appBody` title, and a trailing spacer — `TrackOptionsSheet`'s exact
/// metrics (24pt icon slot, 20pt horizontal / 14pt vertical padding), shared
/// so the "…" sheets can't drift apart again.
struct OptionSheetRow<Trailing: View>: View {
    private let icon: LucideIcon.Name
    private let title: String
    private let subtitle: String?
    private let tint: Color?
    private let action: () -> Void
    private let trailing: Trailing

    /// The full form — `trailing` renders after the spacer (e.g. the track
    /// sheet's in-flight `ProgressView`).
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LucideIcon(icon, .lg)
                    .foregroundStyle(tint ?? Color.vText2)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appBody)
                        .foregroundStyle(tint ?? Color.vText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                    }
                }

                Spacer(minLength: 0)

                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension OptionSheetRow where Trailing == EmptyView {
    /// The common form — no trailing accessory.
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint, action: action) {
            EmptyView()
        }
    }
}

// MARK: - Self-sized detent

/// The measured-detent scaffold every option sheet repeated by hand: measure
/// the content's natural height, pin it to the sheet's top with a trailing
/// spacer, and size the detent to the measurement (+ home-indicator inset).
private struct SelfSizedDetentModifier: ViewModifier {
    let keyboardSafe: Bool
    /// Pre-measurement fallback — replaced by the real height on first layout.
    @State private var contentHeight: CGFloat = 300
    @State private var hasMeasured = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { height in
                    if !hasMeasured {
                        // First real layout replaces the fallback in any mode.
                        hasMeasured = true
                        contentHeight = height
                    } else if keyboardSafe {
                        // Grow-only: content additions (an error banner) still
                        // fit, but keyboard COMPRESSION is ignored — a shrink
                        // can never re-target the detent, so the measure→detent
                        // →layout loop is impossible by construction.
                        contentHeight = max(contentHeight, height)
                    } else {
                        contentHeight = height
                    }
                })

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(contentHeight + ViewConst.safeAreaInsets.bottom + 8)])
    }
}

extension View {
    /// Sizes the presenting sheet's detent to exactly fit this view — apply to
    /// the sheet's content (header + rows), not to an enclosing `ScrollView`
    /// (measuring the scroll container would feed the granted height back into
    /// the detent). Re-measures live, so sheets whose rows change (e.g. the
    /// report sheet collapsing to its confirmation) resize with their content.
    ///
    /// ⚠️ A sheet that shows the KEYBOARD (text fields, especially auto-focused
    /// ones) MUST pass `keyboardSafe: true`: in live mode, keyboard avoidance
    /// compresses the content, the new measurement re-targets the detent, the
    /// sheet re-lays-out, and the loop hangs the app in an AttributeGraph cycle
    /// (this crashed the listing Respond sheet). `keyboardSafe` measures once
    /// and then only grows, which cannot loop. (Also delay any auto-focus until
    /// the present animation settles — see RespondSheet.)
    func selfSizedDetent(keyboardSafe: Bool = false) -> some View {
        modifier(SelfSizedDetentModifier(keyboardSafe: keyboardSafe))
    }
}

// MARK: - Pop mark (the app's animated check / cross)

/// The one "it worked / it didn't" mark: a disc that pops in on a spring while
/// its check (or cross) draws itself stroke by stroke; turning off eases back
/// to the resting state. Picker rows (`AddedCheck`), sign-up's password rules
/// and username availability all use it, so they feel the same.
struct PopMark: View {
    enum Mark { case check, cross }
    /// What shows while off: the picker's outlined "+", a soft dot, or nothing.
    enum Rest { case plus, dot, none }

    let isOn: Bool
    var mark: Mark = .check
    var rest: Rest = .plus
    var tint: Color = .green
    var size: CGFloat = 26

    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            switch rest {
            case .plus:
                Circle()
                    .strokeBorder(Color.vText3, lineWidth: 1.6)
                    .overlay { LucideIcon(.plus, .sm).foregroundStyle(Color.vText3) }
                    .scaleEffect(isOn ? 0.5 : 1)
                    .opacity(isOn ? 0 : 1)
            case .dot:
                Circle()
                    .fill(Color.ink(0.08))
                    .scaleEffect(isOn ? 0.5 : 1)
                    .opacity(isOn ? 0 : 1)
            case .none:
                EmptyView()
            }

            Circle()
                .fill(tint)
                .overlay {
                    Group {
                        switch mark {
                        case .check: CheckShape().trim(from: 0, to: drawn)
                            .stroke(.white, style: stroke)
                        case .cross: CrossShape().trim(from: 0, to: drawn)
                            .stroke(.white, style: stroke)
                        }
                    }
                    .padding(size * 0.27)
                }
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isOn)
        .onAppear { drawn = isOn ? 1 : 0 }
        .onChange(of: isOn) { _, on in
            if on {
                drawn = 0
                withAnimation(.easeOut(duration: 0.28).delay(0.08)) { drawn = 1 }
            } else {
                withAnimation(.easeIn(duration: 0.15)) { drawn = 0 }
            }
        }
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: max(1.6, size * 0.085), lineCap: .round, lineJoin: .round)
    }
}

/// The spring the marks pop on — for the text that changes alongside them.
extension Animation {
    static let popMark = Animation.spring(response: 0.35, dampingFraction: 0.55)
}

/// A picker row's add / added control (Add to playlist, Add to Workspace): an
/// outlined "+" that, once added, becomes the green pop mark.
struct AddedCheck: View {
    let isOn: Bool

    var body: some View {
        PopMark(isOn: isOn)
            .accessibilityLabel(isOn ? "Added" : "Add")
    }
}

/// An ✕ path in its rect (one stroke, then the other).
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let i = rect.width * 0.1
        p.move(to: CGPoint(x: rect.minX + i, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.maxX - i, y: rect.maxY - i))
        p.move(to: CGPoint(x: rect.maxX - i, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.minX + i, y: rect.maxY - i))
        return p
    }
}

/// A checkmark path in its rect (short leg, then the long one).
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.midY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.14))
        return p
    }
}
