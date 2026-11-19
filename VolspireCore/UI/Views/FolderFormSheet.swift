//
//  FolderFormSheet.swift
//  Volspire
//
//  The shared create/edit form sheet (`ItemFormSheet`): SheetHeader + name +
//  labeled fields + the app's Cancel / action footer, with an optional cover-picker
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
    /// Name cap — playlists are 50 (the playlist RPCs enforce it too);
    /// releases pass their own.
    var nameLimit = InputLimits.playlistTitle
    /// Description cap — the server's: playlists 300 (default), releases 1000.
    var descriptionLimit = InputLimits.playlistDescription
    let actionTitle: String
    let busy: Bool
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var coverItem: PhotosPickerItem?
    @State private var cropTarget: CropTarget?

    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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

                VStack(alignment: .leading, spacing: 8) {
                    SheetFieldLabel("Name")
                    SheetTextField(prompt: namePrompt, text: $name, maxLength: nameLimit)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SheetFieldLabel("Description", optional: true)
                    // The folder form's description: multi-line with its counter.
                    SheetTextField(prompt: "What's it about?", text: $description,
                                   axis: .vertical, lines: 3, maxLength: descriptionLimit)
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(description.limitCount)/\(descriptionLimit)")
                                .font(.appCaption)
                                .foregroundStyle(Color.vText3)
                                .monospacedDigit()
                                .padding(10)
                        }
                }

                // Straight under the fields (not pinned to the sheet's bottom),
                // so the keyboard never covers it. The app's sheet footer.
                CancelSendButtons(
                    sendTitle: actionTitle,
                    canSend: valid,
                    isSending: busy,
                    onCancel: { dismiss() },
                    onSend: { Task { await onSubmit() } }
                )
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .keyboardSafeForm()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full height from the start; no auto-focus (the keyboard waits for a
        // tap on a field). A short .height detent got stretched to full height and sprung to the top when the
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
                // Scalars, not graphemes — the DB's char_length (InputLimits).
                var value = new
                if axis == .horizontal, value.contains(where: \.isNewline) { value = value.singleLined }
                if let maxLength, value.limitCount > maxLength { value = value.capped(at: maxLength) }
                if value != new { text = value }
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

/// The New Folder form (web `NewFolderModal`): labelled name + description
/// fields (with a counter), Cancel + the white primary. Editing a folder uses
/// the full-screen `EditDetailsScreen`.
struct FolderFormSheet: View {
    var icon: LucideIcon.Name = .folder
    let title: String
    var subtitle: String? = nil
    @Binding var name: String
    @Binding var description: String
    let actionTitle: String
    let busy: Bool
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss

    /// 50 — the server's cap (create_folder / update_folder), as playlists.
    private static let nameMax = InputLimits.folderName
    private static let descriptionMax = InputLimits.folderDescription

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SheetFieldLabel("Folder name")
                    SheetTextField(prompt: "e.g. Album Sessions, Client Work…", text: $name, maxLength: Self.nameMax)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SheetFieldLabel("Description", optional: true)
                    SheetTextField(
                        prompt: "What's this folder for?",
                        text: $description,
                        axis: .vertical,
                        lines: 3,
                        maxLength: Self.descriptionMax
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(description.limitCount)/\(Self.descriptionMax)")
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .monospacedDigit()
                            .padding(10)
                    }
                }

                CancelSendButtons(
                    sendTitle: actionTitle,
                    canSend: !trimmedName.isEmpty,
                    isSending: busy,
                    onCancel: { dismiss() },
                    onSend: { Task { await onSubmit() } }
                )
                .padding(.top, 4)

            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .keyboardSafeForm()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Full height, so the keyboard never springs the sheet to the top when
        // a field is tapped (see ItemFormSheet). No auto-focus on open.
        .presentationDetents([.large])
        .sheetBackground()
    }
}

// MARK: - EditDetailsScreen

/// The full-screen edit page in the Edit Track layout — header, Cover Art
/// (optional), Details (labeled name + description), any extra sections
/// (e.g. Privacy), and the pinned Save Changes, which stays off until
/// something changed. Shared by Edit Release, Edit Playlist and Edit Folder.
/// No Delete here on purpose — deleting lives in each item's "…" menu only.
struct EditDetailsScreen<Extra: View>: View {
    struct Cover {
        let data: Binding<Data?>
        var savedURL: URL? = nil
        let caption: String
    }

    var icon: LucideIcon.Name = .squarePen
    let title: String
    let subtitle: String
    var cover: Cover? = nil
    var nameLabel = "Name"
    let namePrompt: String
    var nameLimit = InputLimits.playlistTitle
    @Binding var name: String
    var descriptionPrompt = "What's it about?"
    var descriptionLimit = InputLimits.playlistDescription
    @Binding var description: String
    /// Whether anything differs from what was loaded.
    let hasChanges: Bool
    let busy: Bool
    var error: String? = nil
    let onSave: () async -> Void
    @ViewBuilder var extra: () -> Extra

    @Environment(\.dismiss) private var dismiss
    @State private var showCoverPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverCropTarget: CropTarget?

    private var nameMissing: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            UploadFlowHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if let cover {
                        UploadCoverSection(
                            image: cover.data.wrappedValue.flatMap(UIImage.init(data:)),
                            existingURL: cover.savedURL,
                            caption: cover.caption
                        ) { showCoverPicker = true }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        UploadSectionDivider("Details")
                        UploadTextField(label: nameLabel, text: $name, prompt: namePrompt, limit: nameLimit)
                        VStack(alignment: .leading, spacing: 8) {
                            UploadFieldLabel("Description (optional)")
                            UploadDescriptionField(text: $description, prompt: descriptionPrompt,
                                                   limit: descriptionLimit)
                        }
                    }

                    extra()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .tapToDismissKeyboard()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UploadBottomBar(error: error, hint: nameMissing ? "Add a \(nameLabel.lowercased()) to save" : nil) {
                    PrimaryButton("Save Changes", busy: busy, enabled: !nameMissing && hasChanges) {
                        Task { await onSave() }
                    }
                }
            }
        }
        .background(Color.vBase.ignoresSafeArea())
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    coverCropTarget = CropTarget(image: image.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $coverCropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in
                    cover?.data.wrappedValue = data
                    coverCropTarget = nil
                },
                onCancel: { coverCropTarget = nil }
            )
        }
        .interactiveDismissDisabled(busy)
    }
}

extension EditDetailsScreen where Extra == EmptyView {
    init(icon: LucideIcon.Name = .squarePen, title: String, subtitle: String, cover: Cover? = nil,
         nameLabel: String = "Name", namePrompt: String, nameLimit: Int = InputLimits.playlistTitle, name: Binding<String>,
         descriptionPrompt: String = "What's it about?", descriptionLimit: Int = InputLimits.playlistDescription,
         description: Binding<String>, hasChanges: Bool, busy: Bool, error: String? = nil,
         onSave: @escaping () async -> Void) {
        self.init(icon: icon, title: title, subtitle: subtitle, cover: cover, nameLabel: nameLabel,
                  namePrompt: namePrompt, nameLimit: nameLimit, name: name,
                  descriptionPrompt: descriptionPrompt, descriptionLimit: descriptionLimit,
                  description: description, hasChanges: hasChanges, busy: busy, error: error,
                  onSave: onSave) { EmptyView() }
    }
}
