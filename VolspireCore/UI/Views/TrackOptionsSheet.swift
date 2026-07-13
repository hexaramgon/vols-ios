//
//  TrackOptionsSheet.swift
//  Volspire
//
//  The single track "…" options sheet, used everywhere a track shows options so
//  they all match: a header (cover + title + artist + meta) over a divider and a
//  list of chevron action rows (the Library "Recently saved" style).
//

import DesignSystem
import SwiftUI

struct TrackOptionsSheet: View {
    struct Action: Identifiable {
        let id = UUID()
        var icon: LucideIcon.Name
        var title: String
        var subtitle: String? = nil
        var isDestructive: Bool = false
        /// `true`: show a spinner on the row while `perform` runs, then dismiss.
        var awaitsCompletion: Bool = false
        /// `true` (default): dismiss the sheet first, then run `perform` (for
        /// navigation / presenting another sheet). `false`: run `perform` now
        /// without dismissing — for share, which presents over this sheet.
        var dismissesSheet: Bool = true
        var perform: () async -> Void
    }

    let artwork: Artwork
    let title: String
    var artist: String? = nil
    var meta: String? = nil
    let actions: [Action]

    @Environment(\.dismiss) private var dismiss
    @State private var loadingID: UUID?
    /// Measured natural height of the header + rows: the sheet detents to
    /// exactly fit its content instead of a fixed `.medium`, which left a
    /// half-screen sheet with dead space under two or three rows.
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SheetHeader(title: title, subtitle: headerSubtitle) { dismiss() } leading: {
                    ArtworkView(artwork, cornerRadius: 8)
                        .frame(width: 40, height: 40)
                }

                VStack(spacing: 0) {
                    ForEach(actions) { row($0) }
                }
                .padding(.top, 8)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(contentHeight + ViewConst.safeAreaInsets.bottom + 8)])
        .environment(\.colorScheme, .dark)
    }

    /// Artist and meta collapsed onto the single subtitle line the header allows.
    private var headerSubtitle: String? {
        let parts = [artist, meta].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ action: Action) -> some View {
        Button {
            if action.awaitsCompletion {
                Task {
                    loadingID = action.id
                    await action.perform()
                    loadingID = nil
                    dismiss()
                }
            } else if action.dismissesSheet {
                dismiss()
                Task {
                    // Let the sheet finish dismissing before navigating / presenting.
                    try? await Task.sleep(for: .seconds(0.3))
                    await action.perform()
                }
            } else {
                // Present over this sheet (e.g. share) — don't dismiss.
                Task { await action.perform() }
            }
        } label: {
            HStack(spacing: 14) {
                LucideIcon(action.icon, .lg)
                    .foregroundStyle(action.isDestructive ? Color.red : .primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.appBody)
                        .foregroundStyle(action.isDestructive ? Color.red : .primary)
                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if loadingID == action.id {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingID != nil)
    }
}

// MARK: - InlineCreateRow

/// A picker-list row that expands into an inline "name → create" field — used by
/// the add-to-playlist / add-to-workspace sheets to create a new container
/// without leaving the sheet. `onCreate` returns whether creation succeeded:
/// on success the row collapses and clears; on failure it stays open so the
/// caller's error banner can explain what happened.
struct InlineCreateRow: View {
    /// Collapsed-row label, e.g. "New playlist".
    let label: String
    /// Text-field prompt while expanded, e.g. "Playlist name".
    let placeholder: String
    let onCreate: (String) async -> Bool

    @State private var expanded = false
    @State private var name = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if expanded {
                HStack(spacing: 12) {
                    tile
                    TextField(
                        "",
                        text: $name,
                        prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35))
                    )
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.white)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    .disabled(busy)

                    Spacer(minLength: 8)

                    if busy {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Button { submit() } label: {
                            LucideIcon(.circleCheck, .lg)
                                .foregroundStyle(canSubmit ? Color.green : Color.vText3)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { expanded = true }
                    // Focus once the field is mounted (same-tick focus doesn't land).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                } label: {
                    HStack(spacing: 12) {
                        tile
                        Text(label)
                            .font(.appCalloutSemibold)
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(MenuRowStyle())
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.08))
            LucideIcon(.plus, .lg)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 48, height: 48)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        busy = true
        Task {
            let ok = await onCreate(trimmed)
            busy = false
            if ok {
                withAnimation(.smooth(duration: 0.2)) {
                    expanded = false
                    name = ""
                }
            }
        }
    }
}
