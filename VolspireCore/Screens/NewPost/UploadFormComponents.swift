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

enum UploadTheme {
    /// Input / card fill — web `bg-neutral-950`, lifted a touch so it reads on vBase.
    static let fieldFill = Color(white: 0.07)
    /// Input borders — web `border-neutral-800`.
    static let border = Color.white.opacity(0.13)
    /// Empty drop zones / cover placeholder — web dashed `border-neutral-800/80`.
    static let dashed = StrokeStyle(lineWidth: 1, dash: [5, 4])
    /// Selected control — web `bg-white/8` + `border-white/20`.
    static let selectedFill = Color.white.opacity(0.08)
    static let selectedBorder = Color.white.opacity(0.22)
    /// Error text — the shared `Color.vError` token (web `text-red-400`).
    static let errorText = Color.vError
    /// Warning text — the shared `Color.vWarning` token (web `text-amber-500/80`).
    static let warningText = Color.vWarning.opacity(0.85)
}

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
        SheetHeader(icon: icon, title: title, subtitle: subtitle, onClose: onClose)
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
            .foregroundStyle(.white)
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

// MARK: - Input shell (dark fill + hairline border, rounded-xl)

extension View {
    /// Matches the workspace / playlist sheet input fields: a soft translucent
    /// fill, continuous corners, and no hard border (`vBorder` is clear).
    func uploadFieldShell(cornerRadius: CGFloat = 16) -> some View {
        // Same card as the auth field groups: white 5% fill, continuous 16pt.
        self
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.vBorder)
            )
    }
}

// MARK: - Switch (web Toggle: white track + black knob when on)

/// Visual only — wrap it in a tappable row so the whole row is the target.
struct UploadSwitch: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.white : Color.white.opacity(0.22))
            .frame(width: 44, height: 24)
            .overlay {
                Circle()
                    .fill(isOn ? Color.black : Color(white: 0.83))
                    .frame(width: 16, height: 16)
                    .offset(x: isOn ? 10 : -10)
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
            }
            .foregroundStyle(selected ? .white : Color.vText3)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.white.opacity(0.1) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.white.opacity(0.3) : UploadTheme.border, lineWidth: 1)
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
                                    value == option.id ? Color.white : UploadTheme.border,
                                    lineWidth: value == option.id ? 2 : 1
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.vBorder, lineWidth: 1)
            LucideIcon(icon, .md)
                .foregroundStyle(Color.vText2)
        }
        .frame(width: 40, height: 40)
    }
}

/// The dashed "tap to choose" target — the ONE attach look, shared by the
/// track upload's drop zones and the listing's clip rows.
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
                    .foregroundStyle(error ? UploadTheme.errorText : Color.vText2)
                Text(hint)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    error ? UploadTheme.errorText.opacity(0.4) : UploadTheme.border,
                    style: UploadTheme.dashed
                )
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
                    .foregroundStyle(.white)
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
        .uploadFieldShell(cornerRadius: 16)
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

            Button {
                clips.append(AudioClipDraft())
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(.plus, .sm)
                    Text(addLabel)
                        .font(.appCallout)
                }
                .foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .uploadFieldShell()

                Button {
                    clips.removeAll { $0.id == row.id }
                } label: {
                    LucideIcon(.x, .sm)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.vBorder, lineWidth: 1)
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
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                LucideIcon(.circleCheck, .hero)
                    .foregroundStyle(Color.brand)
                VStack(spacing: 3) {
                    Text(title)
                        .font(.appHeadline)
                        .foregroundStyle(.white)
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
            .background(Color.vBar, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Tag input (web TagInput: #chips inside the field + suggestion chips)

struct UploadTagInput: View {
    @Binding var tags: [String]
    var suggestions: [String] = []
    @State private var input = ""

    private func add(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { return }
        tags.append(cleaned)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                if !tags.isEmpty {
                    ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("#\(tag)")
                                        .font(.appFootnote)
                                        .foregroundStyle(.white)
                                    LucideIcon(.x, .xs)
                                        .foregroundStyle(Color.vText3)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField(
                    "",
                    text: $input,
                    prompt: Text("Add your own custom tags…").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit {
                    add(input)
                    input = ""
                }
                // Space commits the tag too (matches the web tag input) — and a
                // pasted "a b c" becomes tags a + b with "c" left editable.
                .onChange(of: input) { _, newValue in
                    guard newValue.contains(" ") else { return }
                    var pieces = newValue.components(separatedBy: " ")
                    let remainder = pieces.removeLast()
                    pieces.forEach { add($0) }
                    input = remainder
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .uploadFieldShell()

            let remaining = suggestions.filter { !tags.contains($0) }
            if !remaining.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                    ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(remaining, id: \.self) { tag in
                            Button {
                                add(tag)
                            } label: {
                                Text("+ \(tag)")
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.vText3)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.white.opacity(0.05)))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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
            HStack(spacing: 8) {
                LucideIcon(.search, .sm)
                    .foregroundStyle(Color.vText3)
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search genres…").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .uploadFieldShell()
            .padding(.horizontal, 20)
            .padding(.top, 24)
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
        .presentationBackground(Color(white: 0.08))
        .presentationDragIndicator(.visible)
    }

    private func genreRow(_ label: String, value: String) -> some View {
        Button {
            genre = value
            dismiss()
        } label: {
            HStack {
                Text(label)
                    .font(.appBody)
                    .foregroundStyle(genre == value ? .white : Color.vText2)
                Spacer()
                if genre == value {
                    LucideIcon(.check, .sm)
                        .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Select pill (web visibility buttons: bordered, white/8 when active)

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
            .foregroundStyle(selected ? .white : Color.vText3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: expands ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? UploadTheme.selectedFill : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? UploadTheme.selectedBorder : UploadTheme.border, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Attached-media preview (audio + video)

/// Inline preview for a just-picked upload, styled like the app's player:
/// a white play circle (Lucide glyphs) + scrubber transport row. Audio mode
/// is the bare row in a form card; video mode lays the same row over the
/// picture with a legibility scrim. The picked `Data` is staged to a temp
/// file so AVPlayer can stream it, and cleaned up when the preview goes away.
struct UploadPreviewPlayer: View {
    let data: Data
    let fileName: String?
    /// False for audio files AND for videos being uploaded as audio-only.
    let isVideo: Bool
    /// Fired when preview playback starts (used to pause the app's music).
    var onStartPlaying: () -> Void = {}

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

    /// Full width over the native ratio, capped so portrait videos stay a card.
    private var videoCardHeight: CGFloat {
        guard cardWidth > 0 else { return 220 }
        return min(cardWidth / (videoAspect ?? 16 / 9), 420)
    }

    var body: some View {
        // The container always renders (a loading state until the player is
        // staged) — an empty conditional here would never fire `onAppear`.
        Group {
            if isVideo {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(UploadTheme.fieldFill)

                    if let player {
                        PlayerVideoView(player: player, gravity: .resizeAspect)
                            .contentShape(.rect)
                            .onTapGesture { toggle() }
                    } else {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Legibility scrim under the transport, like the player.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 84)
                    .allowsHitTesting(false)

                    transportRow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                // Full-width card whose height follows the video's native ratio
                // (16:9 until the asset reports its size), capped so portrait
                // videos don't swallow the form — they pillarbox inside while
                // the transport row keeps the card's full width.
                .frame(height: videoCardHeight)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { cardWidth = $0 })
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(UploadTheme.border, lineWidth: 1)
                )
                .animation(.smooth(duration: 0.25), value: videoAspect)
            } else {
                transportRow
                    .padding(12)
                    .background(UploadTheme.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(UploadTheme.border, lineWidth: 1)
                    )
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
                        .fill(.white)
                        .frame(width: 34, height: 34)
                    LucideIcon(isPlaying ? .pauseFill : .playFill, .sm)
                        .foregroundStyle(.black)
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
                .foregroundStyle(isVideo ? Color.white.opacity(0.85) : Color.vText3)
                .monospacedDigit()
        }
    }

    private func setup() {
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
            attachPlayer(url: url)
        }
    }

    private func attachPlayer(url: URL) {
        tempURL = url

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
