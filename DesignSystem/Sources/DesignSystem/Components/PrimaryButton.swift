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
    private let size: Size
    private let expands: Bool
    private let busy: Bool
    private let enabled: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - expands: false renders a hugging capsule instead of full width.
    ///   - busy: shows a spinner in place of the label and blocks taps.
    ///   - enabled: false blocks taps and shows the disabled capsule.
    public init(
        _ title: String,
        size: Size = .full,
        expands: Bool = true,
        busy: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
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
                    Text(title).font(size.font)
                }
            }
            .foregroundStyle(enabled ? Color.vOnInverse : Color.vText4)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, expands ? 0 : 32)
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
