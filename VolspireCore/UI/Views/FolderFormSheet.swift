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
    let subtitle: String?
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
                    SheetTextField(prompt: namePrompt, text: $name, autoFocus: true)
                    SheetTextField(prompt: "Description (optional)", text: $description)
                }

                // Straight under the fields (not pinned to the sheet's bottom),
                // so the keyboard never covers it.
                PrimaryButton(actionTitle, busy: busy, enabled: valid) {
                    Task { await onSubmit() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full height from the start, name field auto-focused. A short .height
        // detent got stretched to full height and sprung to the top when the
        // keyboard came up (overshoot, text lagging its fields); a .large sheet
        // doesn't move when the keyboard arrives.
        .presentationDetents([.large])
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

/// The form sheets' text-field chrome — borderless `vField` fill (brightens
/// to `vFieldFocus` while editing), radius-12 continuous corners.
struct SheetTextField: View {
    let prompt: String
    @Binding var text: String

    var axis: Axis = .horizontal
    var lines: Int = 1
    var maxLength: Int? = nil
    /// Focus shortly after the sheet appears (keyboard comes straight up).
    var autoFocus = false

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color.vText3), axis: axis)
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .lineLimit(lines, reservesSpace: lines > 1)
            .focused($focused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(focused ? Color.vFieldFocus : Color.vField,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onChange(of: text) { _, new in
                if let maxLength, new.count > maxLength { text = String(new.prefix(maxLength)) }
            }
            // Delayed past the sheet's presentation (focusing mid-present can
            // hang — see the keyboarded-sheet rules); the .large sheet doesn't
            // move when the keyboard arrives, so the delay is invisible.
            .task {
                guard autoFocus else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focused = true
            }
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
                ArtworkView(.webImage(url), cornerRadius: Radius.panel)
            } else {
                ZStack {
                    Color.vField
                    LucideIcon(.listMusic, .xxl).foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            LucideIcon(.camera, .sm)
                .foregroundStyle(Color.vOnInverse)
                .frame(width: 30, height: 30)
                .background(Color.vInverse, in: Circle())
                .offset(x: 5, y: 5)
        }
    }
}

// MARK: - FolderFormSheet

/// Shared create/edit-folder form (web `NewFolderModal` / `FolderEditModal`):
/// labelled name + description fields (with a counter), Cancel + the white
/// primary; edit mode adds a danger-soft "Delete Folder". Presented from
/// Home's Workspace tab and a folder's own "…" menu.
struct FolderFormSheet: View {
    var icon: LucideIcon.Name = .folder
    let title: String
    var subtitle: String? = nil
    @Binding var name: String
    @Binding var description: String
    let actionTitle: String
    let busy: Bool
    /// Edit mode: "Save changes" stays disabled until something changed, and
    /// the danger-soft Delete row shows (when `onDelete` is set).
    var isEdit: Bool = false
    var originalName: String = ""
    var originalDescription: String = ""
    var onDelete: (() -> Void)? = nil
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private static let nameMax = 80
    private static let descriptionMax = 300

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dirty: Bool {
        trimmedName != originalName.trimmingCharacters(in: .whitespacesAndNewlines)
            || description.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSubmit: Bool { !trimmedName.isEmpty && (!isEdit || dirty) && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Folder name *")
                    SheetTextField(prompt: "e.g. Album Sessions, Client Work…", text: $name, maxLength: Self.nameMax,
                                   autoFocus: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Description")
                    SheetTextField(
                        prompt: "What's this folder for? (optional)",
                        text: $description,
                        axis: .vertical,
                        lines: 3,
                        maxLength: Self.descriptionMax
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(description.count)/\(Self.descriptionMax)")
                            .font(.appCaption2)
                            .foregroundStyle(Color.vText4)
                            .monospacedDigit()
                            .padding(10)
                    }
                }

                HStack(spacing: 10) {
                    SecondaryButton("Cancel", size: .inline) { dismiss() }
                    primaryButton
                }
                .padding(.top, 4)

                if isEdit, let onDelete {
                    Button(action: onDelete) {
                        HStack(spacing: 8) {
                            LucideIcon(.trash2, .md)
                            Text("Delete Folder").font(.appSubheadlineSemibold)
                        }
                        .foregroundStyle(Color.vError)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.vDangerSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full height + auto-focused name field, so the keyboard never springs
        // the sheet to the top (see ItemFormSheet).
        .presentationDetents([.large])
        .sheetBackground()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.appFootnoteMedium).foregroundStyle(Color.vText2)
    }

    /// White capsule; "Create Folder" carries a Plus and reads "Creating…" while busy.
    private var primaryButton: some View {
        Button { Task { await onSubmit() } } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(Color.vOnInverse).controlSize(.small)
                } else if !isEdit {
                    LucideIcon(.plus, .md)
                }
                Text(busy && !isEdit ? "Creating…" : actionTitle).font(.appSubheadlineSemibold)
            }
            .foregroundStyle(Color.vOnInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.vInverse, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .opacity(canSubmit || busy ? 1 : 0.3)
    }
}
