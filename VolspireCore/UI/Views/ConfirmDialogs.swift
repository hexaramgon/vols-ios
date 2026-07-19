//
//  ConfirmDialogs.swift
//  Volspire
//
//  Shared confirmation-dialog chrome: the destructive confirm (delete/log out)
//  and the block-user dialog. One home for titleVisibility + Cancel-row
//  conventions — and ONE block-user wording (three variants had drifted).
//

import SwiftUI

extension View {
    /// A destructive confirmation dialog: visible title, one destructive action,
    /// a Cancel row, optional message.
    func destructiveConfirm(
        _ title: String,
        isPresented: Binding<Bool>,
        actionLabel: String = "Delete",
        message: String? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(actionLabel, role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let message { Text(message) }
        }
    }

    /// THE block-user confirmation — canonical title + copy. The service call and
    /// post-block behavior (dismiss / pop / player teardown) stay with the caller.
    func blockUserDialog(
        username: String,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog("Block @\(username)?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Block", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you or see your content, and you won't see theirs. You can unblock from Settings.")
        }
    }
}
