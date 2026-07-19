//
//  OptionSheetComponents.swift
//  Volspire
//
//  Shared anatomy for the slide-up "…" option sheets, lifted out of
//  `TrackOptionsSheet` (the canonical example) so every sheet reads — and
//  stays — identical:
//  - `OptionSheetRow`: the icon + title action row. `tint` drives both the
//    glyph and the label (destructive rows pass a red tint); an optional
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
    private let tint: Color
    private let action: () -> Void
    private let trailing: Trailing

    /// The full form — `trailing` renders after the spacer (e.g. the track
    /// sheet's in-flight `ProgressView`).
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        tint: Color = .white,
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
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appBody)
                        .foregroundStyle(tint)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(.secondary)
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
        tint: Color = .white,
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
    /// Pre-measurement fallback — replaced by the real height on first layout.
    @State private var contentHeight: CGFloat = 300

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })

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
    func selfSizedDetent() -> some View {
        modifier(SelfSizedDetentModifier())
    }
}
