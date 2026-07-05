//
//  SheetHeader.swift
//  DesignSystem
//
//  The shared header for slide-up bottom sheets — a leading icon/avatar tile, a
//  title + optional subtitle, and a trailing "X" close button, capped by a
//  hairline divider. Mirrors the CollabRequestSheet look so every sheet reads as
//  one family. Use the `icon:` convenience for a Lucide-glyph tile, or the
//  trailing-closure form to supply a custom leading view (e.g. an avatar).
//

import SwiftUI

public struct SheetHeader<Leading: View>: View {
    private let title: String
    private let subtitle: String?
    private let onClose: () -> Void
    private let leading: Leading

    public init(
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.leading = leading()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appCalloutSemibold)
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appCaption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    LucideIcon(.x, .lg)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            // Extra top padding so the header clears the drag indicator / sheet edge.
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.08))
        }
    }
}

/// The default leading element — a Lucide glyph in a soft circular tile,
/// matching the 36pt avatar used by the collab sheet.
public struct SheetHeaderIcon: View {
    private let name: LucideIcon.Name

    public init(_ name: LucideIcon.Name) { self.name = name }

    public var body: some View {
        LucideIcon(name, .md)
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.08), in: Circle())
    }
}

public extension SheetHeader where Leading == SheetHeaderIcon {
    /// Convenience for the common case: a Lucide-glyph tile as the leading view.
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, onClose: onClose) {
            SheetHeaderIcon(icon)
        }
    }
}
