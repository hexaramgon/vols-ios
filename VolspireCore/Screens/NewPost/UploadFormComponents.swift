//
//  UploadFormComponents.swift
//  Volspire
//
//  Form primitives for the upload flow, mirroring the web app's
//  track-create page: hairline section dividers, tiny tracked labels,
//  dark bordered inputs, the white capsule switch, and bordered
//  select pills.
//

import AVFoundation
import DesignSystem
import SwiftUI

// MARK: - Tokens (web neutral scale on the vBase background)

// MARK: - Flow header

/// The upload-flow header — the shared `SheetHeader` (icon tile + title + subtitle
/// + close + divider), so every create/upload page reads like the workspace and
/// playlist sheets.
struct UploadFlowHeader: View {
    var icon: LucideIcon.Name
    let title: String
    var subtitle: String?
    let onClose: () -> Void

    var body: some View {
        // Full-screen pages: no drag indicator to clear, so just a little air
        // under the status bar.
        SheetHeader(icon: icon, title: title, subtitle: subtitle, topPadding: 8, onClose: onClose)
    }
}

// MARK: - Bottom bar (pinned CTA + always-visible status)

extension UploadState {
    /// The message carried by `.error`, nil otherwise — for feeding the bar.
    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

/// The pinned bar under every create/upload form: an optional error (red) or
/// validation hint (muted) status row above the form's CTA, on the vBar fill
/// with a top hairline. Only the CTA varies per form (PrimaryButton, AuthCTA,
/// the track wizard's Back/Continue row) — everything else is fixed.
struct UploadBottomBar<CTA: View>: View {
    let error: String?
    let hint: String?
    let cta: CTA

    init(error: String?, hint: String?, @ViewBuilder cta: () -> CTA) {
        self.error = error
        self.hint = hint
        self.cta = cta()
    }

    var body: some View {
        VStack(spacing: 10) {
            if let error {
                statusRow(error, color: Color.vError)
                    .transition(.opacity)
            } else if let hint {
                statusRow(hint, color: Color.vText3)
                    .transition(.opacity)
            }

            cta
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Color.vBar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.vBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        }
        // The status row is driven by LIVE validation (hint/error flip to nil
        // the instant a step becomes complete — e.g. right before publish),
        // outside any withAnimation transaction — so the bar's height snapped.
        // Animate on the values themselves so grow/shrink always eases.
        .animation(.smooth(duration: 0.25), value: error)
        .animation(.smooth(duration: 0.25), value: hint)
    }

    private func statusRow(_ message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIcon(.triangleAlert, .sm)
                .foregroundStyle(color)
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section heading (quiet auth-style label)

struct UploadSectionDivider: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        // Matches the sign-in/register section headings (was an uppercase
        // micro-label + hairline).
        Text(label)
            .font(.appCalloutSemibold)
            .foregroundStyle(Color.vText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Field label

struct UploadFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // Soft sentence-case label, like the auth fields.
        Text(text)
            .font(.appFootnoteSemibold)
            .foregroundStyle(Color.vText2)
    }
}

// MARK: - Input shell (borderless field fill)

extension View {
    /// The borderless field: `vField` fill, continuous r12 corners, no ring
    /// (the web revamp's input principle). `invalid` swaps in the soft red
    /// tint (never a red ring).
    func uploadFieldShell(cornerRadius: CGFloat = Radius.card, invalid: Bool = false) -> some View {
        background(invalid ? Color.vDangerSoft : Color.vField,
                   in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Field helpers (char caps, price filtering, keyboard Done)

extension View {
    /// Hard-caps a text binding at `limit` characters as the user types —
    /// the clamp every form's title/description fields apply.
    func charLimited(_ text: Binding<String>, _ limit: Int) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            if newValue.count > limit {
                text.wrappedValue = String(newValue.prefix(limit))
            }
        }
    }

    /// Keyboard accessory with a right-aligned "Done" that clears `focus` —
    /// for the decimal/number pads, which have no return key.
    func doneKeyboardToolbar(_ focus: FocusState<Bool>.Binding) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focus.wrappedValue = false
                }
                .font(.appCallout)
            }
        }
    }
}

extension Binding where Value == String {
    /// A write-filtered view of this binding that strips everything but digits
    /// and the decimal point — for the price fields.
    func decimalFiltered() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { wrappedValue = $0.filter { "0123456789.".contains($0) } }
        )
    }
}

// MARK: - Description field (multiline + live counter, clamped at the limit)

struct UploadDescriptionField: View {
    @Binding var text: String
    let prompt: String
    let limit: Int
    var lines: ClosedRange<Int> = 3...6

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(
                "",
                text: $text,
                prompt: Text(prompt).foregroundStyle(Color.vText3),
                axis: .vertical
            )
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .lineLimit(lines)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()
            .charLimited($text, limit)

            Text("\(text.count)/\(limit)")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
        }
    }
}

// MARK: - Editable lists (single-field rows, two-field rows, add buttons)

/// The quiet inline "+ Add …" footer under an editable list (deliverables,
/// FAQs, package features). `fullWidth`/`indent` reproduce the features
/// editor's stretched, field-aligned variant — hit area included.
struct UploadInlineAddButton: View {
    let label: String
    /// Stretches the row to the full width (leading-aligned).
    var fullWidth = false
    /// Leading inset, to align the label under the text fields past the icon.
    var indent: CGFloat = 0
    let action: () -> Void

    init(_ label: String, fullWidth: Bool = false, indent: CGFloat = 0, action: @escaping () -> Void) {
        self.label = label
        self.fullWidth = fullWidth
        self.indent = indent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(.plus, .xs)
                Text(label)
                    .font(.appFootnote)
            }
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .padding(.leading, indent)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The full-width "add another" button (package tiers, process steps, audio
/// clip rows) — a `vControl` capsule (no dashed outline).
struct UploadDashedAddButton: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIcon(.plus, .sm)
                Text(label)
                    .font(.appCallout)
            }
            .foregroundStyle(Color.vControlLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.vControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One editable single-line string list: check icon + text field + a remove ✕
/// that hides while only one row remains, plus the inline "+ Add …" footer.
/// The deliverables and package-features editors are this same anatomy at two
/// scales — `compact` selects the tighter one (nested inside a package card).
/// Bindings are index-guarded so a row removal mid-edit can't crash a write.
struct UploadEditableList: View {
    @Binding var items: [String]
    let placeholder: String
    let addLabel: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 10) {
                    LucideIcon(.circleCheck, compact ? .xs : .sm)
                        .foregroundStyle(Color.vText3)
                    TextField(
                        "",
                        text: Binding(
                            get: {
                                guard index < items.count else { return "" }
                                return items[index]
                            },
                            set: {
                                guard index < items.count else { return }
                                items[index] = $0
                            }
                        ),
                        prompt: Text(placeholder).foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(Color.vText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, compact ? 9 : 11)
                    .uploadFieldShell()

                    if items.count > 1 {
                        Button {
                            items.remove(at: index)
                        } label: {
                            LucideIcon(.x, compact ? .xs : .sm)
                                .foregroundStyle(Color.vText3)
                                .frame(width: compact ? 32 : 36, height: compact ? 32 : 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Compact indents the add row under the fields (past the icon)
            // with a stretched hit area, like the features editor always did.
            UploadInlineAddButton(addLabel, fullWidth: compact, indent: compact ? 23 : 0) {
                items.append("")
            }
        }
    }
}

/// A "title + multiline detail" editor row (process steps, FAQs): two stacked
/// fields with an optional trailing remove ✕ (pass nil while only one row
/// remains). Row identity/add plumbing stays with the caller.
struct UploadTwoFieldRow: View {
    @Binding var title: String
    @Binding var detail: String
    let titlePlaceholder: String
    let detailPlaceholder: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                TextField(
                    "",
                    text: $title,
                    prompt: Text(titlePlaceholder).foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .uploadFieldShell()

                TextField(
                    "",
                    text: $detail,
                    prompt: Text(detailPlaceholder).foregroundStyle(Color.vText3),
                    axis: .vertical
                )
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .lineLimit(2...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .uploadFieldShell()
            }

            if let onRemove {
                Button(action: onRemove) {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 36)
                        .minimumHitArea(for: 36)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Cover art (picker tile + caption cluster + staged draft)

/// The square cover-art tile: the picked image, or (when editing) the track's
/// existing remote cover, or the dashed "Cover art" placeholder.
struct UploadCoverBox: View {
    var image: UIImage?
    var existingURL: URL? = nil
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let existingURL {
                ArtworkView(.webImage(existingURL), cornerRadius: Radius.panel)
            } else {
                Color.vField
                VStack(spacing: 6) {
                    LucideIcon(.image, .lg)
                        .foregroundStyle(Color.vText3)
                    Text("Cover art")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}

/// The "Optional cover image…" caption + "Remove cover" button cluster shown
/// beside the cover tile on the service and pack identity sections.
struct UploadCoverCaption: View {
    let text: String
    let hasCover: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
                .fixedSize(horizontal: false, vertical: true)

            if hasCover {
                Button(action: onRemove) {
                    HStack(spacing: 6) {
                        LucideIcon(.x, .sm)
                        Text("Remove cover")
                            .font(.appFootnote)
                    }
                    .foregroundStyle(Color.vText3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The track / release "Cover Art" section: the tile beside a caption and a
/// Choose / Change button — either one opens the picker.
struct UploadCoverSection: View {
    var image: UIImage?
    /// The current remote cover when editing.
    var existingURL: URL? = nil
    let caption: String
    let onPick: () -> Void

    var body: some View {
        let hasCover = image != nil || existingURL != nil
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Cover Art")

            HStack(alignment: .center, spacing: 16) {
                Button(action: onPick) {
                    UploadCoverBox(image: image, existingURL: existingURL, size: 112)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Text(caption)
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onPick) {
                        CapsuleButtonLabel(icon: hasCover ? .refreshCw : .image,
                                           title: hasCover ? "Change" : "Choose image",
                                           style: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Title + genre fields (track / release Details)

/// A labeled one-line field in the upload shell, clamped at `limit`.
struct UploadTextField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UploadFieldLabel(label)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Color.vText3))
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .charLimited($text, limit)
        }
    }
}

/// A labeled genre row that opens the picker (`GenrePickerSheet`).
struct UploadGenreField: View {
    var label = "Genre"
    let genre: String
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UploadFieldLabel(label)
            Button(action: onTap) {
                HStack {
                    Text(genre.isEmpty ? "Choose a genre" : genre)
                        .font(.appBody)
                        .foregroundStyle(genre.isEmpty ? Color.vText3 : Color.vText)
                    Spacer()
                    LucideIcon(.chevronDown, .sm).foregroundStyle(Color.vText3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A staged cover image for the view models: the UIImage for display plus the
/// JPEG bytes and generated file name the create/update RPCs take — one
/// compression setting and naming scheme for every form.
struct CoverDraft {
    private(set) var image: UIImage?
    private(set) var data: Data?
    private(set) var fileName: String?

    mutating func set(_ image: UIImage) {
        self.image = image
        data = image.jpegData(compressionQuality: 0.85)
        fileName = "cover_\(UUID().uuidString).jpg"
    }

    mutating func clear() {
        image = nil
        data = nil
        fileName = nil
    }
}

// MARK: - Switch (web Toggle: ink track + paper knob when on)

/// Visual only — wrap it in a tappable row so the whole row is the target.
struct UploadSwitch: View {
    var isOn: Bool
    /// 1 = 44×24; larger where the switch sits alone (Audio only).
    var scale: CGFloat = 1

    var body: some View {
        Capsule()
            .fill(isOn ? Color.vInverse : Color.ink(0.22))
            .frame(width: 44 * scale, height: 24 * scale)
            .overlay {
                Circle()
                    .fill(isOn ? Color.vOnInverse : Color.dynamic(light: .white, dark: UIColor(white: 0.83, alpha: 1)))
                    .frame(width: 16 * scale, height: 16 * scale)
                    .offset(x: (isOn ? 10 : -10) * scale)
            }
    }
}

/// The entire row toggles — a far bigger target than the 44pt switch alone.
struct UploadToggleRow: View {
    let label: String
    var hint: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.appBody)
                        .foregroundStyle(Color.vText2)
                    if let hint {
                        Text(hint)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                    }
                }
                Spacer()
                UploadSwitch(isOn: isOn)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Type tile (web category/type grids: icon above label, white/10 when active)

struct UploadTypeTile: View {
    let label: String
    let icon: LucideIcon.Name
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                LucideIcon(icon, .lg)
                    .opacity(selected ? 1 : 0.4)
                Text(label)
                    .font(.appCaption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    // Inset from the tile edge — long labels ("Mixing /
                    // Mastering") wrap instead of running edge to edge.
                    .padding(.horizontal, 10)
            }
            .foregroundStyle(selected ? Color.vOnInverse : Color.vText2)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.vertical, 6)
            // Selected = ink tile, unselected = control fill (web white vs white/8).
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(selected ? Color.vInverse : Color.vControl)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gradient picker (web GradientPicker: swatch circles, ring when active)

struct UploadGradientOption: Identifiable {
    /// The tailwind gradient string stored in the DB (e.g. "from-violet-900 via-violet-950 to-black").
    let id: String
    let label: String
    /// The gradient's top colour for the swatch — derived from `id`'s first stop via
    /// the canonical Tailwind palette, not hand-converted rgb (which drifted slightly).
    var top: Color { TailwindGradient.colors(from: id)?.first ?? Color(white: 0.2) }
}

struct UploadGradientPicker: View {
    let options: [UploadGradientOption]
    @Binding var value: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        value = option.id
                    } label: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [option.top, .black],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle().strokeBorder(
                                    value == option.id ? Color.vText : Color.clear,
                                    lineWidth: 2
                                )
                            )
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                }
            }
        }
    }
}

// MARK: - Audio clip rows (listing attachments / service portfolio)

/// A draft "titled audio clip" row — used by listings and service portfolios.
struct AudioClipDraft: Identifiable {
    let id = UUID()
    var title: String = ""
    var fileName: String?
    var data: Data?
    /// Set when editing — an already-uploaded clip's storage path, kept as-is
    /// unless the user attaches a replacement (`data`).
    var existingFileUrl: String?

    var hasFile: Bool { data != nil || existingFileUrl != nil }
    var hasTitle: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    var isComplete: Bool { hasFile && hasTitle }
}

// MARK: - Shared attach-file presentation (track upload + listing clips)

/// Soft icon tile used across the upload forms' attach surfaces.
struct UploadIconBox: View {
    let icon: LucideIcon.Name

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.vControl)
            LucideIcon(icon, .md)
                .foregroundStyle(Color.vText2)
        }
        .frame(width: 40, height: 40)
    }
}

/// The "tap to choose" target — the ONE attach look, shared by the track
/// upload's drop zones and the listing's clip rows. Field fill, no dashed
/// outline; a missing required file tints it soft red.
struct UploadDropZone: View {
    let icon: LucideIcon.Name
    let title: String
    let hint: String
    var error: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            UploadIconBox(icon: icon)

            VStack(spacing: 4) {
                Text(title)
                    .font(.appCallout)
                    .foregroundStyle(error ? Color.vError : Color.vText2)
                Text(hint)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(error ? Color.vDangerSoft : Color.vField)
        )
        .contentShape(.rect)
    }
}

/// Attached-file summary (icon tile + name + size + trash) — shared chrome.
struct UploadAttachedFileCard: View {
    let icon: LucideIcon.Name
    let name: String?
    let bytes: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            UploadIconBox(icon: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? "File")
                    .font(.appBodyMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(UploadClipRows.formatBytes(bytes))
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }

            Spacer()

            Button(action: clear) {
                LucideIcon(.trash2, .md)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .uploadFieldShell()
    }
}

/// Card rows of (clip title + attach audio) plus a dashed "add" button.
/// File picking stays with the caller (`onAttach` should open a picker and
/// write the result back into the bound array).
struct UploadClipRows: View {
    @Binding var clips: [AudioClipDraft]
    var titlePlaceholder = "Clip title"
    var addLabel = "Add audio"
    /// Fired when a clip preview starts playing (pause the app's music).
    var onStartPlaying: () -> Void = {}
    let onAttach: (UUID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach($clips) { $clip in
                clipCard($clip)
            }

            UploadDashedAddButton(addLabel) {
                clips.append(AudioClipDraft())
            }
        }
    }

    private func clipCard(_ clip: Binding<AudioClipDraft>) -> some View {
        let row = clip.wrappedValue
        let missingFile = row.hasTitle && !row.hasFile
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: clip.title,
                    prompt: Text(titlePlaceholder).foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                // A file without a title is invalid → soft red fill.
                .uploadFieldShell(invalid: row.hasFile && !row.hasTitle)

                Button {
                    clips.removeAll { $0.id == row.id }
                } label: {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 36)
                        .minimumHitArea(for: 36)
                }
                .buttonStyle(.plain)
            }

            // Attached + empty states use the track upload's exact presentation
            // (shared components), in the track's order: file card, then preview.
            if let data = row.data {
                UploadAttachedFileCard(icon: .fileAudio, name: row.fileName, bytes: data.count) {
                    if let index = clips.firstIndex(where: { $0.id == row.id }) {
                        clips[index].data = nil
                        clips[index].fileName = nil
                    }
                }

                UploadPreviewPlayer(data: data, fileName: row.fileName, isVideo: false, onStartPlaying: onStartPlaying)
                    // Fresh player if a different file is picked into this row.
                    .id(row.fileName)
            } else {
                Button {
                    onAttach(row.id)
                } label: {
                    UploadDropZone(
                        icon: .fileAudio,
                        title: missingFile ? "Audio required" : "Tap to choose an audio file",
                        hint: "MP3, WAV, FLAC, AIFF",
                        error: missingFile
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.vCard)
        )
    }

    static func formatBytes(_ bytes: Int) -> String {
        bytes >= 1_000_000
            ? String(format: "%.1f MB", Double(bytes) / 1_000_000)
            : String(format: "%.0f KB", Double(bytes) / 1_000)
    }
}

// MARK: - Success confirmation

/// Full-screen confirmation card flashed over the app (from OverlaidRootView)
/// after a create/upload form's sheet slides away — an explicit "it worked".
struct UploadSuccessOverlay: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        ZStack {
            Color.vScrim.ignoresSafeArea()
            VStack(spacing: 14) {
                SuccessMark(size: 60)
                VStack(spacing: 3) {
                    Text(title)
                        .font(.appHeadline)
                        .foregroundStyle(Color.vText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 300)
            .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        }
    }
}

// MARK: - Tag input (web TagInput: #chips inside the field + suggestion chips)

/// Suggestion chips shared by the track upload + edit forms.
let trackTagSuggestions = [
    "808", "trap", "melodic", "dark", "drill", "r&b", "lo-fi",
    "chill", "hype", "afro", "soulful", "vocal", "instrumental",
]

struct UploadTagInput: View {
    @Binding var tags: [String]
    var suggestions: [String] = []
    @State private var input = ""

    private func add(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { return }
        tags.append(cleaned)
    }

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespaces) }

    private func commitInput() {
        withAnimation(.snappy(duration: 0.25)) { add(input) }
        input = ""
    }

    // The app's chip language (FilterBar): the field on top, added tags as
    // ink chips with an × (applied filters), suggestions as off chips with a +.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field

            if !tags.isEmpty {
                ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(tags, id: \.self) { tag in addedChip(tag) }
                }
            }

            let remaining = suggestions.filter { !tags.contains($0) }
            if !remaining.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                    ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(remaining, id: \.self) { tag in
                            FilterChip(tag, icon: .plus, isOn: false) {
                                withAnimation(.snappy(duration: 0.25)) { add(tag) }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: tags)
    }

    /// "# tag name" with an Add button once there's something to add.
    private var field: some View {
        HStack(spacing: 8) {
            LucideIcon(.hash, .sm)
                .foregroundStyle(Color.vText3)
            TextField(
                "",
                text: $input,
                prompt: Text("Add a tag").foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit(commitInput)
            // Space commits the tag too (matches the web tag input) — and a
            // pasted "a b c" becomes tags a + b with "c" left editable.
            .onChange(of: input) { _, newValue in
                guard newValue.contains(" ") else { return }
                var pieces = newValue.components(separatedBy: " ")
                let remainder = pieces.removeLast()
                withAnimation(.snappy(duration: 0.25)) { pieces.forEach { add($0) } }
                input = remainder
            }

            if !trimmedInput.isEmpty {
                Button(action: commitInput) {
                    Text("Add")
                        .font(.appFootnoteMedium)
                        .foregroundStyle(Color.vOnInverse)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.vInverse, in: Capsule())
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: trimmedInput.isEmpty)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .uploadFieldShell()
    }

    /// An added tag — the FilterBar's applied-filter chip: tap to remove.
    private func addedChip(_ tag: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { tags.removeAll { $0 == tag } }
        } label: {
            HStack(spacing: 6) {
                Text("#\(tag)").font(.appFootnoteMedium)
                LucideIcon(.x, .sm)
            }
            .foregroundStyle(Color.vOnInverse)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.vInverse, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel("Remove tag \(tag)")
    }
}

// MARK: - Genre picker sheet (web GenreCombobox: searchable, allows custom)

struct GenrePickerSheet: View {
    @Binding var genre: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trackGenres }
        return trackGenres.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var customEntry: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trackGenres.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        return trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            // The app's sheet header (Collab Request / Respond).
            SheetHeader(icon: .music, title: "Genre", subtitle: "Pick one, or type your own") { dismiss() }

            HStack(spacing: 8) {
                LucideIcon(.search, .sm)
                    .foregroundStyle(Color.vText3)
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search genres…").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .uploadFieldShell()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let customEntry {
                        genreRow("Use \"\(customEntry)\"", value: customEntry)
                    }
                    ForEach(filtered, id: \.self) { option in
                        genreRow(option, value: option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .sheetBackground()
    }

    private func genreRow(_ label: String, value: String) -> some View {
        Button {
            genre = value
            dismiss()
        } label: {
            HStack {
                Text(label)
                    .font(.appBody)
                    .foregroundStyle(genre == value ? Color.vText : Color.vText2)
                Spacer()
                if genre == value {
                    LucideIcon(.check, .sm)
                        .foregroundStyle(Color.vText)
                }
            }
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Select pill (web visibility buttons: ink when active, control fill when not)

/// One option of an `UploadSegmentedSwitch`.
struct UploadSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    /// Optional — text-only segments (e.g. the public link's expiry).
    var icon: LucideIcon.Name? = nil
    var id: Value { value }
}

/// A two-or-more-way switch: a control-fill capsule track with an ink thumb
/// that slides to the picked segment. Labels in full ink (paper on the
/// thumb) so the unpicked side still reads.
struct UploadSegmentedSwitch<Value: Hashable>: View {
    let segments: [UploadSegment<Value>]
    let selected: Value
    /// Segment label font — semibold by default; lighter where it sits
    /// under a regular-weight label (the public link's expiry).
    var labelFont: Font = .appSubheadlineSemibold
    let onSelect: (Value) -> Void

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let on = segment.value == selected
                Button {
                    Haptics.selection()
                    onSelect(segment.value)
                } label: {
                    HStack(spacing: 6) {
                        if let icon = segment.icon { LucideIcon(icon, .md) }
                        Text(segment.title).font(labelFont)
                    }
                    .foregroundStyle(on ? Color.vOnInverse : Color.vText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if on {
                            Capsule()
                                .fill(Color.vInverse)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.vControl, in: Capsule())
        .animation(.smooth(duration: 0.25), value: selected)
    }
}

struct UploadPill: View {
    let label: String
    var icon: LucideIcon.Name?
    /// Fills the available width — for equal-width segmented groups.
    var expands: Bool
    let selected: Bool
    let action: () -> Void

    init(
        _ label: String,
        icon: LucideIcon.Name? = nil,
        expands: Bool = false,
        selected: Bool,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.expands = expands
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    LucideIcon(icon, .sm)
                }
                Text(label)
                    .font(.appCallout)
                    .lineLimit(1)
            }
            // Unselected labels in full ink — vControlLabel (70%) on the
            // control fill read washed out.
            .foregroundStyle(selected ? Color.vOnInverse : Color.vText)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: expands ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(selected ? Color.vInverse : Color.vControl)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Visibility picker (Public / Unlisted / Private pills + hint)

/// A track's `tracks.visibility`.
/// - public: listed everywhere, playable by anyone.
/// - unlisted: never listed (feeds, search, profile, others' playlists) —
///   anyone with its link, or a folder's public share link, can listen.
/// - private: you, credited collaborators and folder members.
enum TrackVisibility: String, CaseIterable, Identifiable {
    case `public`, unlisted, `private`

    var id: String { rawValue }

    init(_ raw: String?) { self = TrackVisibility(rawValue: raw ?? "") ?? .public }

    var label: String {
        switch self {
        case .public: "Public"
        case .unlisted: "Unlisted"
        case .private: "Private"
        }
    }

    var icon: LucideIcon.Name {
        switch self {
        case .public: .globe
        case .unlisted: .link
        case .private: .lock
        }
    }

    /// The picker's one-line explanation.
    var hint: String {
        switch self {
        case .public: "Anyone can find and listen to it."
        case .unlisted: "Hidden from feeds, search and your profile. Anyone with the link can listen."
        case .private: "Only you, credited collaborators and folder members can listen."
        }
    }
}

/// Visibility pills. Tracks pass `allowsUnlisted` (Public / Unlisted /
/// Private, with each option's hint); releases, packs and services keep the
/// Public / Private pair with their own optional hints.
struct UploadVisibilityPicker: View {
    @Binding var visibility: String
    var allowsUnlisted = false
    var publicHint: String? = nil
    var privateHint: String? = nil

    private var options: [TrackVisibility] { allowsUnlisted ? TrackVisibility.allCases : [.public, .private] }

    private var hint: String? {
        if allowsUnlisted { return TrackVisibility(visibility).hint }
        return visibility == "public" ? publicHint : privateHint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    UploadPill(option.label, icon: option.icon, expands: true, selected: visibility == option.rawValue) {
                        visibility = option.rawValue
                    }
                }
            }

            if let hint {
                Text(hint)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Attached-media preview (audio + video)

/// Inline preview for a just-picked upload, styled like the app's player:
/// a white play circle (Lucide glyphs) + scrubber transport row. Audio mode
/// is the bare row in a form card; video mode lays the same row over the
/// picture with a legibility scrim. Plays `fileURL` in place (the caller owns
/// it); picked `Data` is staged to a temp file so AVPlayer can stream it, and
/// cleaned up when the preview goes away.
struct UploadPreviewPlayer: View {
    var data: Data? = nil
    var fileURL: URL? = nil
    let fileName: String?
    /// False for audio files AND for videos being uploaded as audio-only.
    let isVideo: Bool
    /// Fired when preview playback starts (used to pause the app's music).
    var onStartPlaying: () -> Void = {}
    /// Audio only: a header inside the card (title over a detail line, on a
    /// music tile) so the picked file and its player read as one thing.
    var title: String? = nil
    var detail: String? = nil
    /// Audio only: just the transport (no card) — for a card that draws its
    /// own header around it (a listing clip with an editable title).
    var bare = false
    /// Video only: the tallest the picture gets (portrait clips narrow to
    /// their own ratio under it). Callers that must leave room below pass less.
    var maxVideoHeight: CGFloat = 460

    @State private var player: AVPlayer?
    @State private var tempURL: URL?
    @State private var isPlaying = false
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var endObserver: (any NSObjectProtocol)?
    /// Set when the preview is dismissed before staging finishes, so the late
    /// staging task cleans up after itself instead of leaking a player + file.
    @State private var tornDown = false
    /// The video's native width/height ratio (transform-corrected), loaded from
    /// the asset — the card's height follows it instead of a fixed widescreen box.
    @State private var videoAspect: CGFloat?
    /// Measured card width, for turning the ratio into a concrete height.
    @State private var cardWidth: CGFloat = 0

    /// The card IS the video's shape — no black bars. Landscape/square: full
    /// width. Portrait: capped height, narrowed to the clip's own ratio (like
    /// the full-screen player shows it), centered. 16:9 placeholder until the
    /// asset reports its size.
    private var videoCardSize: CGSize {
        let width = cardWidth > 0 ? cardWidth : 320
        guard let aspect = videoAspect, aspect > 0 else {
            return CGSize(width: width, height: width * 9 / 16)
        }
        let maxHeight = maxVideoHeight
        let fullWidthHeight = width / aspect
        if fullWidthHeight <= maxHeight { return CGSize(width: width, height: fullWidthHeight) }
        return CGSize(width: maxHeight * aspect, height: maxHeight)
    }

    var body: some View {
        // The container always renders (a loading state until the player is
        // staged) — an empty conditional here would never fire `onAppear`.
        Group {
            if isVideo {
                // The clip on its own (its exact shape, nothing over it), then
                // the transport under it across the full width.
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.vShade)

                        if let player {
                            // Fill in a box of the clip's own ratio = no crop, no bars.
                            PlayerVideoView(player: player, gravity: .resizeAspectFill)
                                .contentShape(.rect)
                                .onTapGesture { toggle() }
                        } else {
                            ProgressView()
                                .tint(Color.vText2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // Paused: a soft play glyph says "tap to play".
                        if player != nil, !isPlaying {
                            LucideIcon(.playFill, .lg)
                                .foregroundStyle(.white)
                                .offset(x: 1)
                                .frame(width: 52, height: 52)
                                .background(.black.opacity(0.35), in: Circle())
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: videoCardSize.width, height: videoCardSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .alwaysDark()
                    .animation(.easeInOut(duration: 0.15), value: isPlaying)
                    // Centered in the full row; the row's width drives the size.
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { cardWidth = $0 })

                    transportRow
                }
                .animation(.smooth(duration: 0.25), value: videoAspect)
            } else if bare {
                transportRow
            } else if let title {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        LucideIcon(.music2, .lg)
                            .foregroundStyle(Color.vText)
                            .frame(width: 52, height: 52)
                            .background(Color.vControlActive,
                                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.appBodyMedium)
                                .foregroundStyle(Color.vText)
                                .lineLimit(2)
                            if let detail {
                                Text(detail)
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.vText2)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    transportRow
                }
                .padding(14)
                .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            } else {
                transportRow
                    .padding(12)
                    .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    /// The shared transport: white play circle (player-style) + scrubber + time.
    private var transportRow: some View {
        HStack(spacing: 11) {
            Button { toggle() } label: {
                ZStack {
                    Circle()
                        .fill(Color.vInverse)
                        .frame(width: 34, height: 34)
                    LucideIcon(isPlaying ? .pauseFill : .playFill, .sm)
                        .foregroundStyle(Color.vOnInverse)
                        .offset(x: isPlaying ? 0 : 1) // optical centre for the triangle
                        .contentTransition(.identity)
                        .animation(nil, value: isPlaying)
                }
            }
            .buttonStyle(.plain)
            .disabled(player == nil)
            .opacity(player == nil ? 0.5 : 1)

            // The player-style bar, not a stock `Slider` — see `.inlineScrub`.
            ElasticSlider(
                value: Binding(get: { current }, set: { current = $0 }),
                in: 0 ... max(duration, 0.1),
                onActive: { active in
                    if active {
                        isSeeking = true
                    } else {
                        seek(to: current)
                    }
                }
            )
            .sliderStyle(.inlineScrub)
            .frame(height: 22)
            .disabled(player == nil)

            Text("\(format(current)) / \(format(duration))")
                .font(.appCaption2)
                .foregroundStyle(Color.vText3)
                .monospacedDigit()
        }
    }

    private func setup() {
        if let fileURL {
            attachPlayer(url: fileURL, owned: false)
            return
        }
        guard let data else { return }
        // Stage to a temp file with the right extension so AVPlayer can sniff
        // the container format.
        let ext = (fileName as NSString?)?.pathExtension.lowercased() ?? ""
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-preview-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? (isVideo ? "mov" : "mp3") : ext)
        let bytes = data
        Task {
            // Write OFF the main thread — a video's Data is tens of MB, and a
            // synchronous write here froze the UI right after compression.
            let staged = await Task.detached(priority: .userInitiated) {
                do { try bytes.write(to: url, options: .atomic); return true }
                catch { return false }
            }.value
            guard staged else { return }
            guard !tornDown else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            attachPlayer(url: url, owned: true)
        }
    }

    /// `owned`: a temp file this preview staged (deleted on teardown).
    private func attachPlayer(url: URL, owned: Bool) {
        if owned { tempURL = url }

        let p = AVPlayer(url: url)
        player = p

        // Both callbacks are delivered on the main queue (`queue: .main`), so
        // hopping onto the main actor is assumption, not a thread switch.
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { time in
            MainActor.assumeIsolated {
                if !isSeeking { current = time.seconds }
            }
        }
        Task {
            guard let item = p.currentItem else { return }
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite {
                duration = d.seconds
            }
            // Phone footage is often stored rotated with a correcting transform,
            // so the display ratio comes from the transformed natural size.
            if isVideo,
               let track = try? await item.asset.loadTracks(withMediaType: .video).first,
               let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                if rect.width != 0, rect.height != 0 {
                    videoAspect = abs(rect.width / rect.height)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isPlaying = false
                current = 0
                p.seek(to: .zero)
            }
        }
    }

    private func teardown() {
        tornDown = true
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        tempURL = nil
    }

    private func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, current >= duration - 0.1 { player.seek(to: .zero); current = 0 }
            onStartPlaying()
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { isSeeking = false; return }
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { _ in
            Task { @MainActor in isSeeking = false }
        }
    }

    private func format(_ seconds: Double) -> String { seconds.durationLabel }
}

// MARK: - Composer (the mobile create flows: track, release, listing)
//
// Built like a phone composer, not a web form: a big tappable cover, a
// borderless title and story written straight onto the page, then
// settings-style rows for the picks. Shared so every create flow matches.

/// The cover, full width (capped at 340 on big phones), tap to choose.
/// Empty, it says what's needed; filled, it carries a small Edit chip.
struct ComposerCoverHero: View {
    let image: UIImage?
    /// The current remote cover when editing.
    var existingURL: URL? = nil
    let caption: String
    let onPick: () -> Void

    private var hasCover: Bool { image != nil || existingURL != nil }

    var body: some View {
        Button(action: onPick) {
            Color.vField
                .aspectRatio(1, contentMode: .fit)
                // Fill images live in an overlay of a sized box so they can't
                // widen the page (fill-images rule).
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let existingURL {
                        ArtworkView(.webImage(existingURL), cornerRadius: 0)
                    } else {
                        VStack(spacing: 10) {
                            LucideIcon(.image, .xxl).foregroundStyle(Color.vText3)
                            VStack(spacing: 3) {
                                Text("Add cover art")
                                    .font(.appSubheadlineSemibold)
                                    .foregroundStyle(Color.vText)
                                Text(caption)
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.vText2)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if hasCover {
                        HStack(spacing: 6) {
                            LucideIcon(.pencil, .sm)
                            Text("Edit").font(.appSubheadlineSemibold)
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(12)
                    }
                }
                .shadow(color: .black.opacity(hasCover ? 0.18 : 0), radius: 18, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        }
        .buttonStyle(CardPress())
        .accessibilityLabel(hasCover ? "Change cover art" : "Add cover art")
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
    }
}

/// The big borderless title. Return finishes it instead of adding a line.
struct ComposerTitleField: View {
    @Binding var text: String
    let prompt: String
    let limit: Int

    var body: some View {
        TextField("", text: $text,
                  prompt: Text(prompt).foregroundStyle(Color.vText4),
                  axis: .vertical)
            .font(.appLargeTitle)
            .foregroundStyle(Color.vText)
            .lineLimit(1...3)
            .charLimited($text, limit)
            .onChange(of: text) { _, value in
                if value.contains("\n") {
                    text = value.replacingOccurrences(of: "\n", with: "")
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
    }
}

/// The borderless story under the title; the counter shows only near the cap.
struct ComposerStoryField: View {
    @Binding var text: String
    let prompt: String
    let limit: Int
    var lines: ClosedRange<Int> = 2...10

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("", text: $text,
                      prompt: Text(prompt).foregroundStyle(Color.vText3),
                      axis: .vertical)
                .font(.appBody)
                .foregroundStyle(Color.vText2)
                .lineLimit(lines)
                .charLimited($text, limit)
                .frame(maxWidth: .infinity, alignment: .leading)
            if text.count > limit * 4 / 5 {
                Text("\(text.count)/\(limit)")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .monospacedDigit()
            }
        }
    }
}

/// A section label above a composer group ("Tracks", "Tags") with an
/// optional trailing count.
struct ComposerHeading: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.appHeadline).foregroundStyle(Color.vText)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .monospacedDigit()
            }
        }
    }
}

/// A card of settings-style rows (put a `SettingsDivider()` between rows).
struct ComposerRowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Icon · title … value ›  — opens a picker. `placeholder` greys the value
/// ("Required", "Optional").
struct ComposerRow: View {
    let icon: LucideIcon.Name
    let title: String
    let value: String
    var placeholder = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIcon(icon, .md).foregroundStyle(Color.vText2)
                Text(title).font(.appSubheadlineMedium).foregroundStyle(Color.vText)
                Spacer(minLength: 8)
                Text(value)
                    .font(.appSubheadline)
                    .foregroundStyle(placeholder ? Color.vText3 : Color.vText2)
                    .lineLimit(1)
                LucideIcon(.chevronRight, .sm).foregroundStyle(Color.vText3)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// "+ Add …" as the last row of a composer group.
struct ComposerAddRow: View {
    let title: String
    var trailing: String? = nil
    /// The circled glyph — "+" to add; a swap glyph where it replaces.
    var icon: LucideIcon.Name = .plus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIcon(icon, .md)
                    .foregroundStyle(Color.vText)
                    .frame(width: 28, height: 28)
                    .background(Color.vControlActive, in: Circle())
                Text(title).font(.appSubheadlineMedium).foregroundStyle(Color.vText)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.appSubheadline).foregroundStyle(Color.vText3)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One option in a `ComposerChipRow`.
struct ComposerChip: Identifiable {
    let id: String
    let label: String
    let icon: LucideIcon.Name
}

/// A single swipeable row of pick-one chips (listing "I'm looking for",
/// pack type) — reads at a glance in one line instead of a tile grid. Runs
/// to the screen edges; call it inside the composer's 20pt-padded column.
struct ComposerChipRow: View {
    let chips: [ComposerChip]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let on = chip.id == selected
                    Button {
                        Haptics.selection()
                        onSelect(chip.id)
                    } label: {
                        HStack(spacing: 6) {
                            LucideIcon(chip.icon, .sm)
                            Text(chip.label).font(.appSubheadlineSemibold)
                        }
                        .foregroundStyle(on ? Color.vOnInverse : Color.vText)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(on ? Color.vInverse : Color.vControl, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}
