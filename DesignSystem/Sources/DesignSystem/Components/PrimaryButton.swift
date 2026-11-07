//
//  PrimaryButton.swift
//  Volspire
//
//  The app's primary CTA — an ink capsule with a paper label (white/black in
//  dark, inverted in light: `Color.vInverse` / `Color.vOnInverse`). Exactly two
//  sizes: `.full` (52pt, the bottom CTA of forms and sheets) and `.inline`
//  (42pt, CTAs sitting inside page content). Busy swaps the label for a
//  spinner; disabled swaps to a quiet `vControl` capsule with a `vText4`
//  label at full opacity (a 30% ink capsule read as nothing on light) — the
//  one disabled treatment, shared with `SecondaryButton` (never per-site).
//

import SwiftUI

/// Label sizing shared by `PrimaryButton` / `SecondaryButton`. A hugging
/// capsule takes the label's natural width; a full-width one keeps the label
/// inside with side padding — shrinking slightly, then truncating — instead of
/// letting a long title spill past the capsule.
struct CapsuleLabelFit: ViewModifier {
    let expands: Bool

    func body(content: Content) -> some View {
        if expands {
            content
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 16)
        } else {
            content.fixedSize()
        }
    }
}

public struct PrimaryButton: View {
    public enum Size {
        /// 52pt full-width — the bottom CTA of forms and sheets.
        case full
        /// 42pt — CTAs inline with page content (detail pages, empty states).
        case inline

        var height: CGFloat { self == .full ? 52 : 42 }
        var font: Font { self == .full ? .appHeadline : .appSubheadlineSemibold }
    }

    private let title: String
    private let icon: LucideIcon.Name?
    private let size: Size
    private let expands: Bool
    private let busy: Bool
    private let enabled: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - icon: optional leading Lucide glyph (same slot as `SecondaryButton`'s).
    ///   - expands: false renders a hugging capsule instead of full width.
    ///   - busy: shows a spinner in place of the label and blocks taps.
    ///   - enabled: false blocks taps and shows the disabled capsule.
    public init(
        _ title: String,
        icon: LucideIcon.Name? = nil,
        size: Size = .full,
        expands: Bool = true,
        busy: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.size = size
        self.expands = expands
        self.busy = busy
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(Color.vOnInverse)
                } else {
                    HStack(spacing: 6) {
                        if let icon { LucideIcon(icon, .md) }
                        Text(title).font(size.font).lineLimit(1)
                    }
                    .modifier(CapsuleLabelFit(expands: expands))
                }
            }
            .foregroundStyle(enabled ? Color.vOnInverse : Color.vText4)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: size.height)
            // Hugging: the glyph already widens it, so less side padding.
            .padding(.horizontal, expands ? 0 : (icon == nil ? 32 : 20))
            .background(enabled ? Color.vInverse : Color.vControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .animation(.easeInOut(duration: 0.18), value: enabled)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton("Save Changes") {}
        PrimaryButton("Saving", busy: true) {}
        PrimaryButton("Respond", size: .inline) {}
        PrimaryButton("Unblock", size: .inline, expands: false) {}
        PrimaryButton("Submit report", enabled: false) {}
    }
    .padding()
    .background(Color.vBase)
}
