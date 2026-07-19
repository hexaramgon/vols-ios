//
//  UserOptionsSheet.swift
//  Volspire
//
//  Slide-up options sheet for another user — Report / Block — matching the
//  folder / listing / track option sheets (SheetHeader + Lucide rows, sized
//  detent, sheetBackground). Used from a profile header and a conversation
//  header. The caller stages the follow-up (report sheet / block confirm) in
//  the presenting sheet's `onDismiss`, same as the listing admin options.
//

import DesignSystem
import SwiftUI

struct UserOptionsSheet: View {
    let username: String
    /// Present only while the viewer has an ACCEPTED collaboration with this
    /// user — ends it (and archives their DM) after the caller's confirmation.
    var onRemoveCollaborator: (() -> Void)? = nil
    let onReport: () -> Void
    let onBlock: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .user, title: "@\(username)") { dismiss() }

            VStack(spacing: 0) {
                if let onRemoveCollaborator {
                    OptionSheetRow(icon: .circleMinus, title: "Remove Collaborator", action: onRemoveCollaborator)
                }
                OptionSheetRow(icon: .flag, title: "Report", action: onReport)
                OptionSheetRow(icon: .ban, title: "Block @\(username)", tint: .vDestructive, action: onBlock)
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}
