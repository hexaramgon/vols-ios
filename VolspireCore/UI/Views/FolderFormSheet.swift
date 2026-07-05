//
//  FolderFormSheet.swift
//  Volspire
//
//  Shared create/edit-folder form. Themed like the other workspace sheets
//  (SheetHeader + frosted background + capsule primary button) so "New Folder" /
//  "Edit Folder" read identically wherever they're presented — Library, the
//  Workspace tab, and a folder's own "…" menu.
//

import DesignSystem
import SwiftUI

struct FolderFormSheet: View {
    var icon: LucideIcon.Name = .folder
    let title: String
    let subtitle: String
    @Binding var name: String
    @Binding var description: String
    let actionTitle: String
    let busy: Bool
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }

            VStack(alignment: .leading, spacing: 14) {
                field(prompt: "Folder name", text: $name)
                field(prompt: "Description (optional)", text: $description)

                Spacer(minLength: 0)

                Button { Task { await onSubmit() } } label: {
                    Group {
                        if busy { ProgressView().tint(.black) }
                        else { Text(actionTitle).font(.appHeadline).foregroundStyle(.black) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(valid && !busy ? Color.white : Color.white.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!valid || busy)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }

    private func field(prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundColor(Color.vText3))
            .font(.appBody)
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vBorder))
    }
}
