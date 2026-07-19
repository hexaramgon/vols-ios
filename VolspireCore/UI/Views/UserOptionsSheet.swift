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
    /// Measured so the sheet detents to exactly fit its rows (no empty tail).
    @State private var contentHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(icon: .user, title: "@\(username)") { dismiss() }

                VStack(spacing: 0) {
                    if let onRemoveCollaborator {
                        row(icon: .circleMinus, title: "Remove Collaborator", tint: .white, action: onRemoveCollaborator)
                    }
                    row(icon: .flag, title: "Report", tint: .white, action: onReport)
                    row(icon: .ban, title: "Block @\(username)", tint: .vDestructive, action: onBlock)
                }
                .padding(.top, 6)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(contentHeight + ViewConst.safeAreaInsets.bottom + 8)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }

    private func row(icon: LucideIcon.Name, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LucideIcon(icon, .lg)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                Text(title).font(.appBody).foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
