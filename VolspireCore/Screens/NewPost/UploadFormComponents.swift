//
//  UploadFormComponents.swift
//  Volspire
//
//  Form primitives for the upload flow, mirroring the web app's
//  track-create page: hairline section dividers, tiny tracked labels,
//  dark bordered inputs, the white capsule switch, and bordered
//  select pills.
//

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

// MARK: - Flow header (centered title, close button top-right)

struct UploadFlowHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(.white)

            HStack {
                Spacer()
                Button(action: onClose) {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText2)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.vBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - Section divider (tiny uppercase label + hairline)

struct UploadSectionDivider: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.appLabel)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color.vText3)
                .fixedSize()
            Rectangle()
                .fill(Color.vBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - Field label

struct UploadFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.appLabel)
            .textCase(.uppercase)
            .tracking(1.0)
            .foregroundStyle(Color.vText3)
    }
}

// MARK: - Input shell (dark fill + hairline border, rounded-xl)

extension View {
    func uploadFieldShell(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(UploadTheme.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(UploadTheme.border, lineWidth: 1)
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
    /// Approximation of the gradient's top colour for the swatch.
    let top: Color
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

/// Card rows of (clip title + attach audio) plus a dashed "add" button.
/// File picking stays with the caller (`onAttach` should open a picker and
/// write the result back into the bound array).
struct UploadClipRows: View {
    @Binding var clips: [AudioClipDraft]
    var titlePlaceholder = "Clip title"
    var addLabel = "Add audio"
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

            if let data = row.data {
                HStack(spacing: 10) {
                    LucideIcon(.fileAudio, .sm)
                        .foregroundStyle(Color.vText2)
                    Text(row.fileName ?? "Audio file")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(Self.formatBytes(data.count))
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)

                    Spacer()

                    Button {
                        if let index = clips.firstIndex(where: { $0.id == row.id }) {
                            clips[index].data = nil
                            clips[index].fileName = nil
                        }
                    } label: {
                        LucideIcon(.trash2, .sm)
                            .foregroundStyle(Color.vText3)
                            .frame(width: 36, height: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 4)
            } else {
                Button {
                    onAttach(row.id)
                } label: {
                    HStack(spacing: 8) {
                        LucideIcon(.upload, .sm)
                        Text(missingFile ? "Audio required" : "Attach audio")
                            .font(.appFootnote)
                    }
                    .foregroundStyle(missingFile ? UploadTheme.errorText : Color.vText3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                missingFile ? UploadTheme.errorText.opacity(0.4) : UploadTheme.border,
                                style: UploadTheme.dashed
                            )
                    )
                    .contentShape(.rect)
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
                                        .foregroundStyle(Color.vText2)
                                    LucideIcon(.x, .xs)
                                        .foregroundStyle(Color.vText3)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                                .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField(
                    "",
                    text: $input,
                    prompt: Text("Type and press return…").foregroundStyle(Color.vText3)
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .uploadFieldShell()

            let remaining = suggestions.filter { !tags.contains($0) }
            if !remaining.isEmpty {
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
                                .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
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
