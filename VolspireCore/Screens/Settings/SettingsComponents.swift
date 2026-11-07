//
//  SettingsComponents.swift
//  Volspire
//
//  The settings building blocks, mirroring the web's `settings-ui.tsx`:
//  every section page is a stack of `SettingsGroup`s — a section title, an
//  optional caption, then a raised `vCardSolid` card of `SettingsRow`s split
//  by hairlines (or "bare" for forms, which sit straight on the canvas).
//

import DesignSystem
import SwiftUI

// MARK: - Page

/// A pushed settings section: the standard nav band titled with the section
/// name, content at 16pt gutters, 24 top, groups 32 apart.
struct SettingsSectionPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                content
            }
            .frame(maxWidth: 672, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 16)
            .padding(.bottom, playerController.contentBottomInset + 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .appNavBar(title: title) { dismiss() }
    }
}

// MARK: - Group

struct SettingsGroup<Content: View>: View {
    let title: String
    var caption: String? = nil
    /// No card — for forms, which sit straight on the canvas.
    var bare: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.appTitle3)
                .foregroundStyle(Color.vText)
                .padding(.bottom, caption == nil ? 12 : 4)
            if let caption {
                Text(caption)
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
            if bare {
                content
            } else {
                VStack(spacing: 0) { content }
                    .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The hairline between rows inside a group card.
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.vDivider).frame(height: 1)
    }
}

// MARK: - Row

enum SettingsTone {
    case neutral, danger, positive, warning

    var color: Color {
        switch self {
        case .neutral: .vText2
        case .danger: .vError
        case .positive: .vSuccessText
        case .warning: .vWarning
        }
    }
}

/// A flat row inside a group card: optional plain 20pt glyph (tinted by tone),
/// title over caption, and a trailing control or value.
struct SettingsRow<Trailing: View>: View {
    var icon: LucideIcon.Name? = nil
    var tone: SettingsTone = .neutral
    let title: String
    var caption: String? = nil
    /// Larger type where the row stands alone (e.g. the speed sheet).
    var titleFont: Font = .appSubheadlineMedium
    var captionFont: Font = .appCaption
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                LucideIcon(icon, .lg).foregroundStyle(tone.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(captionFont)
                        .foregroundStyle(Color.vText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(icon: LucideIcon.Name? = nil, tone: SettingsTone = .neutral, title: String, caption: String? = nil) {
        self.init(icon: icon, tone: tone, title: title, caption: caption) { EmptyView() }
    }
}

/// A plain value on the right of a row (email, a date).
struct SettingsRowValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.appSubheadline)
            .foregroundStyle(Color.vText2)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// The trailing glyph on a row that leaves the app or opens a document.
struct SettingsExternalGlyph: View {
    var body: some View {
        LucideIcon(.externalLink, .md).foregroundStyle(Color.vText4)
    }
}

// MARK: - Root list row

/// One entry in the Settings root list: plain glyph, name over caption,
/// chevron — one row of the root's grouped card (SettingsScreen).
struct SettingsNavRow: View {
    let icon: LucideIcon.Name
    let title: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            LucideIcon(icon, .lg).foregroundStyle(Color.vTextRow)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appSubheadlineMedium).foregroundStyle(Color.vTextRow)
                Text(caption).font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

// MARK: - Form fields

/// A labelled form field (web `Field`): 12pt semibold label, the control, then
/// an optional hint.
struct SettingsField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.appLabel)
                .foregroundStyle(Color.vText2)
            content
            if let hint {
                Text(hint)
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// The borderless field fill (web `INPUT_CLS`): `vField` → `vFieldFocus`,
    /// r12, 16×12 padding; `invalid` tints it red instead of ringing it.
    func settingsFieldStyle(focused: Bool = false, invalid: Bool = false) -> some View {
        self
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                invalid ? Color.vError.opacity(focused ? 0.15 : 0.10) : (focused ? Color.vFieldFocus : Color.vField),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
