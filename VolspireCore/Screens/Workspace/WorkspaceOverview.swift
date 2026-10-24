//
//  WorkspaceOverview.swift
//  Volspire
//
//  The web workspace shell's pieces, ported for the phone (web
//  `workspace-overview.tsx` + the folder column rows). Embeddable views that
//  render from the shared `WorkspaceStore` — the Home Workspace tab mounts
//  them (folders live on the Workspace tab):
//  - `WorkspaceFolderRow` — a flat folder row (FolderArt sm + name + caption).
//

import DesignSystem
import Services
import SwiftUI

// MARK: - Folder row

/// The phone folder-column row: 16×10 padding, FolderArt sm, name (medium,
/// row-idle ink) over a caption — yours: the description or the age; shared:
/// "description · You can edit" / "· View only".
struct WorkspaceFolderRow: View {
    let folder: ApiUserFolder
    /// The row's "…" (folder options) — like the profile's track rows.
    var onMore: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Same 44pt / radius-8 tile as a track row's cover.
                FolderArt(id: folder.folderId, name: folder.name, size: .row)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text(caption)
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let onMore {
                    Button(action: onMore) {
                        LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                            .foregroundStyle(Color.vText3)
                            .frame(width: 34, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Folder options")
                }
            }
            .padding(.leading, ViewConst.screenPaddings)
            // The "…" lands where the profile track rows put theirs (10pt list
            // inset + 4pt row trailing = 14pt to its 34pt target).
            .padding(.trailing, onMore == nil ? ViewConst.screenPaddings : 14)
            // 64pt rows, like the track rows (44pt art + 10pt top / bottom).
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var caption: String {
        let desc = folder.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if folder.role == "owner" {
            return desc.isEmpty ? MessageTime.agoLong(iso: folder.createdAt) : desc
        }
        let access = folder.role == "editor" ? "You can edit" : "View only"
        return desc.isEmpty ? access : "\(desc) · \(access)"
    }
}
