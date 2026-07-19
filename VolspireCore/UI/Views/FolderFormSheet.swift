//
//  FolderFormSheet.swift
//  Volspire
//
//  The shared create/edit form sheet (`ItemFormSheet`): SheetHeader + name +
//  description fields + white-capsule submit, with an optional cover-picker
//  block (PhotosPicker + cropper) for playlist forms. The folder and playlist
//  forms were near-identical twins; `FolderFormSheet` remains as the text-only
//  convenience so "New Folder" / "Edit Folder" call sites read unchanged.
//

import DesignSystem
import PhotosUI
import SwiftUI

// MARK: - ItemFormSheet

struct ItemFormSheet: View {
    /// Config for the optional cover block: the picked image bytes plus the
    /// already-saved cover (edit forms) shown until a new one is picked.
    struct CoverPicker {
        let data: Binding<Data?>
        var savedURL: URL? = nil
    }

    var icon: LucideIcon.Name
    let title: String
    let subtitle: String
    let namePrompt: String
    @Binding var name: String
    @Binding var description: String
    var cover: CoverPicker? = nil
    let actionTitle: String
    let busy: Bool
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var coverItem: PhotosPickerItem?
    @State private var cropTarget: CropTarget?

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Hoisted: the PhotosPicker label closure is `@Sendable`, so it can't read
        // the main-actor `cover.data` binding directly — capture plain values first.
        let pickedCover = cover?.data.wrappedValue
        let savedCover = cover?.savedURL
        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }

            VStack(spacing: 16) {
                if cover != nil {
                    PhotosPicker(selection: $coverItem, matching: .images) {
                        EditCoverPreview(pickedData: pickedCover, savedURL: savedCover)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 12) {
                    SheetTextField(prompt: namePrompt, text: $name)
                    SheetTextField(prompt: "Description (optional)", text: $description)
                }

                Spacer(minLength: 0)

                Button { Task { await onSubmit() } } label: {
                    Group {
                        if busy { ProgressView().tint(.black) }
                        else { Text(actionTitle).font(.appHeadline).foregroundStyle(.black) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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
        .presentationDetents([.height(cover == nil ? 360 : 452)])
        .sheetBackground()
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    cropTarget = CropTarget(image: ui.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $cropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in cover?.data.wrappedValue = data; cropTarget = nil },
                onCancel: { cropTarget = nil }
            )
        }
    }
}

// MARK: - SheetTextField

/// The form sheets' text-field chrome — white 6% fill, radius-12 continuous
/// corners, vBorder hairline (was duplicated as a private `field(prompt:text:)`
/// in each form).
struct SheetTextField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color.vText3))
            .font(.appBody)
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vBorder))
    }
}

// MARK: - Cover preview

/// Tappable 104×104 cover preview with a camera badge — shows the freshly
/// picked image, else the saved cover, else a neutral placeholder. Takes plain
/// values so it can be built inside PhotosPicker's `@Sendable` label closure.
private struct EditCoverPreview: View {
    let pickedData: Data?
    let savedURL: URL?

    var body: some View {
        Group {
            if let data = pickedData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let url = savedURL {
                ArtworkView(.webImage(url), cornerRadius: 18)
            } else {
                ZStack {
                    Color.white.opacity(0.07)
                    LucideIcon(.listMusic, .xxl).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.system(size: 12))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
                .offset(x: 5, y: 5)
        }
    }
}

// MARK: - FolderFormSheet (text-only convenience)

/// Shared create/edit-folder form. Themed like the other workspace sheets so
/// "New Folder" / "Edit Folder" read identically wherever they're presented —
/// Home's Workspace tab and a folder's own "…" menu.
struct FolderFormSheet: View {
    var icon: LucideIcon.Name = .folder
    let title: String
    let subtitle: String
    @Binding var name: String
    @Binding var description: String
    let actionTitle: String
    let busy: Bool
    let onSubmit: () async -> Void

    var body: some View {
        ItemFormSheet(
            icon: icon,
            title: title,
            subtitle: subtitle,
            namePrompt: "Folder name",
            name: $name,
            description: $description,
            actionTitle: actionTitle,
            busy: busy,
            onSubmit: onSubmit
        )
    }
}
