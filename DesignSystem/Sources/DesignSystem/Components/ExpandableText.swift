//
//  ExpandableText.swift
//  DesignSystem
//
//  A text block that collapses to `lineLimit` lines with a "See more" / "See less"
//  toggle, but only when the content actually overflows. Truncation is detected by
//  measuring the text at the line limit vs. unbounded (two hidden copies) and
//  comparing heights, so the toggle never appears on short text.
//

import SwiftUI

public struct ExpandableText: View {
    private let text: String
    private let lineLimit: Int
    private let font: Font
    private let textColor: Color
    private let moreColor: Color
    private let moreFont: Font

    @State private var expanded = false
    @State private var isTruncated = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    public init(
        _ text: String,
        lineLimit: Int = 5,
        font: Font = .appCalloutRegular,
        textColor: Color = .white.opacity(0.9),
        moreColor: Color = .white.opacity(0.5),
        moreFont: Font = .appFootnoteMedium
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.font = font
        self.textColor = textColor
        self.moreColor = moreColor
        self.moreFont = moreFont
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(font)
                .foregroundStyle(textColor)
                .lineLimit(expanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(measurers)

            if isTruncated {
                Button(expanded ? "See less" : "See more") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .font(moreFont)
                .foregroundStyle(moreColor)
                .buttonStyle(.plain)
            }
        }
    }

    /// Two hidden copies — one clamped to `lineLimit`, one unbounded — laid out at the
    /// visible text's width. A height delta means the text overflows the limit. Uses
    /// `onAppear`/`onChange` (main-actor) rather than `onPreferenceChange` so it stays
    /// clean under Swift 6 strict concurrency.
    private var measurers: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(font)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { update(limited: g.size.height) }
                        .onChange(of: g.size.height) { _, h in update(limited: h) }
                })
            Text(text)
                .font(font)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { update(full: g.size.height) }
                        .onChange(of: g.size.height) { _, h in update(full: h) }
                })
        }
        .hidden()
        .allowsHitTesting(false)
    }

    private func update(limited: CGFloat? = nil, full: CGFloat? = nil) {
        if let limited { limitedHeight = limited }
        if let full { fullHeight = full }
        let truncated = fullHeight > limitedHeight + 1
        if truncated != isTruncated { isTruncated = truncated }
    }
}
