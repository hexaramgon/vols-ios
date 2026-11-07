//
//  UserOptionsSheet.swift
//  Volspire
//
//  Slide-up options sheet for another user — Report / Block — matching the
//  folder / listing / track option sheets (SheetHeader + Lucide rows, sized
//  detent, sheetBackground). Used from a profile header and a conversation
//  header. Block and Remove Collaborator close the sheet and open the
//  centered confirm modal; `onBlock` / `onRemoveCollaborator` run once
//  confirmed. Report is staged by the caller in the presenting sheet's
//  `onDismiss`.
//

import DesignSystem
import SwiftUI

struct UserOptionsSheet: View {
    let username: String
    /// Present only while the viewer has an ACCEPTED collaboration with this
    /// user — ends it (and archives their DM) after the caller's confirmation.
    var onRemoveCollaborator: (() -> Void)? = nil
    /// Share their profile link (the profile's "…"; absent in a conversation).
    var onShare: (() -> Void)? = nil
    let onReport: () -> Void
    let onBlock: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingConfirm: DestructiveConfirm?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .user, title: "@\(username)") { dismiss() }

            VStack(spacing: 0) {
                if let onShare {
                    OptionSheetRow(icon: .share2, title: "Share Profile", action: onShare)
                }
                if let onRemoveCollaborator {
                    OptionSheetRow(icon: .circleMinus, title: "Remove Collaborator") {
                        pendingConfirm = DestructiveConfirm(
                            icon: .circleMinus,
                            title: "Remove @\(username) as a collaborator?",
                            message: "You'll no longer be collaborators, and your conversation moves to your inbox's Archived section. You can send a new collab request anytime.",
                            actionLabel: "Remove"
                        ) { onRemoveCollaborator() }
                    }
                }
                OptionSheetRow(icon: .flag, title: "Report", action: onReport)
                OptionSheetRow(icon: .ban, title: "Block @\(username)", tint: .vDestructive) {
                    pendingConfirm = .block(username: username) { onBlock() }
                }
            }
            .padding(.top, 6)
            .confirmModal($pendingConfirm)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}
