//
//  SettingsComponents.swift
//  Volspire
//
//  The settings building blocks: every section page is a stack of
//  `SettingsGroup`s — a section title, an optional caption, then its rows
//  straight on the page (no card, no hairlines), in the root list's anatomy:
//  round icon tile, 15m title over a 14 caption, the control on the right.
//  "bare" groups are forms (fields on the canvas).
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

extension EnvironmentValues {
    /// Inside a (non-bare) `SettingsGroup`: its rows sit straight on the page,
    /// so `SettingsDivider`s between them draw nothing. Off everywhere else —
    /// cards that reuse the divider (pack composer, share sheet) keep theirs.
    @Entry var settingsFlatRows = false
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var caption: String? = nil
    /// No card — for forms, which sit straight on the canvas.
    var bare: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.appFont.sectionTitle)
                .foregroundStyle(Color.vText)
                .padding(.bottom, bare ? 12 : 4)
                .accessibilityAddTraits(.isHeader)
            if let caption {
                Text(caption)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, bare ? 12 : 6)
            }
            if bare {
                content
            } else {
                // Rows keep their own 16pt inset (other screens rely on it);
                // pulled out here so their text lines up with the title on
                // the page column.
                VStack(spacing: 0) { content }
                    .padding(.horizontal, -16)
                    .environment(\.settingsFlatRows, true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The hairline between rows inside a card. Draws nothing between a
/// settings group's flat rows (`settingsFlatRows`).
struct SettingsDivider: View {
    @Environment(\.settingsFlatRows) private var flat

    var body: some View {
        if !flat {
            Rectangle().fill(Color.vDivider).frame(height: 1)
        }
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

/// A settings row, in the root list's anatomy: an optional round 40pt icon
/// tile (glyph tinted by tone; a soft red tile for danger), the shared row
/// pair (15m title / 14 caption), and a trailing control or value.
struct SettingsRow<Trailing: View>: View {
    var icon: LucideIcon.Name? = nil
    var tone: SettingsTone = .neutral
    let title: String
    var caption: String? = nil
    /// Larger type where the row stands alone (e.g. the speed sheet).
    var titleFont: Font = .appFont.trackTitle
    var captionFont: Font = .appFont.trackSubtitle
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                LucideIcon(icon, .md)
                    .foregroundStyle(tone == .neutral ? Color.vText : tone.color)
                    .frame(width: 40, height: 40)
                    .background(tone == .danger ? Color.vDangerSoft : Color.vControl, in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(tone == .danger ? Color.vError : Color.vText)
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
        // 60pt rows with a tile (the root list's), a touch more air without.
        .padding(.vertical, icon == nil ? 12 : 10)
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
            .font(.appCalloutRegular)
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

/// One entry in the Settings root list, laid out like the app's other flat
/// lists (Library, Workspace): a round icon tile (the sheet headers' tile),
/// the shared row pair (`AppFont.trackTitle` / `trackSubtitle`, 15m / 14),
/// and a chevron — straight on the page, no card. `destructive` turns the
/// tile + title red and drops the chevron (Sign out).
struct SettingsNavRow: View {
    let icon: LucideIcon.Name
    let title: String
    var caption: String? = nil
    var destructive = false

    var body: some View {
        HStack(spacing: 14) {
            LucideIcon(icon, .md)
                .foregroundStyle(destructive ? Color.vError : Color.vText)
                .frame(width: 40, height: 40)
                .background(destructive ? Color.vDangerSoft : Color.vControl, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appFont.trackTitle)
                    .foregroundStyle(destructive ? Color.vError : Color.vTextRow)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.appFont.trackSubtitle)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !destructive {
                LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText4)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

// MARK: - Form fields

/// A labelled form field (web `Field`): 14pt semibold label, the control, then
/// an optional 14pt hint.
struct SettingsField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.appSubheadlineSemibold)
                .foregroundStyle(Color.vText2)
            content
            if let hint {
                Text(hint)
                    .font(.appSubheadline)
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
