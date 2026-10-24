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
    /// A touch larger (title 15 / subtitle 13) for sheets that are a primary
    /// choice, e.g. New post.
    private let prominent: Bool
    /// The hairline under the header; off for list pickers (Add to
    /// playlist / Workspace), where the rows start right under it.
    private let divider: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        prominent: Bool = false,
        divider: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.subtitle = subtitle
        self.prominent = prominent
        self.divider = divider
        self.onClose = onClose
        self.leading = leading()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(prominent ? .appCalloutSemibold : .appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                    if let subtitle {
                        Text(subtitle)
                            .font(prominent ? .appFootnote : .appCaption)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    LucideIcon(.x, .lg)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            // Extra top padding so the header clears the drag indicator / sheet edge.
            .padding(.top, 24)
            .padding(.bottom, 14)

            if divider {
                Divider().overlay(Color.vSurface2)
            }
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
            .foregroundStyle(Color.vText2)
            .frame(width: 36, height: 36)
            .background(Color.vControl, in: Circle())
    }
}

public extension SheetHeader where Leading == SheetHeaderIcon {
    /// Convenience for the common case: a Lucide-glyph tile as the leading view.
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        prominent: Bool = false,
        divider: Bool = true,
        onClose: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, prominent: prominent, divider: divider, onClose: onClose) {
            SheetHeaderIcon(icon)
        }
    }
}
