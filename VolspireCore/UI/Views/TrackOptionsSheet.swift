//
//  TrackOptionsSheet.swift
//  Volspire
//
//  The single track "…" options sheet, used everywhere a track shows options so
//  they all match: a header (cover + title + artist + meta) over a divider and a
//  list of chevron action rows (the Library "Recently saved" style).
//

import DesignSystem
import MediaLibrary
import Player
import Services
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
        /// Destructive rows: the sheet closes and the centered confirm modal
        /// opens (`.confirmModal`); the confirm's own `perform` runs if the
        /// user confirms, so such rows leave `perform` at its default.
        var confirm: DestructiveConfirm? = nil
        var perform: () async -> Void = {}
    }

    let artwork: Artwork
    let title: String
    var artist: String? = nil
    var meta: String? = nil
    let actions: [Action]
    /// When set, a "Report" row is appended (App Store 1.2 UGC safety). Omit for
    /// the viewer's own tracks, which get edit / hide / delete instead.
    var reportTargetId: String? = nil
    /// When set (a single playable track), "Play next" and "Add to queue"
    /// rows lead the list.
    var queueMedia: Media? = nil

    @Environment(\.dismiss) private var dismiss
    /// Optional: the sheet is used app-wide, and a missing environment object
    /// must not crash it — the queue rows just don't appear.
    @Environment(PlayerController.self) private var player: PlayerController?
    @State private var showReport = false
    @State private var loadingID: UUID?
    @State private var pendingConfirm: DestructiveConfirm?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, subtitle: headerSubtitle) { dismiss() } leading: {
                ArtworkView(artwork, cornerRadius: Radius.tile)
                    .frame(width: 40, height: 40)
            }

            VStack(spacing: 0) {
                ForEach(queueActions + actions) { row($0) }
                if reportTargetId != nil { reportRow }
            }
            .padding(.top, 8)
            .confirmModal($pendingConfirm)
        }
        .selfSizedDetent()
        .sheet(isPresented: $showReport) {
            ReportSheet(targetType: .track, targetId: reportTargetId ?? "", subject: title)
        }
    }

    /// "Play next" / "Add to queue" for `queueMedia` (none without audio).
    private var queueActions: [Action] {
        guard let player, let media = queueMedia, media.meta.audioURL != nil else { return [] }
        return [
            Action(icon: .listStart, title: "Play next") { player.enqueue(media, .next) },
            Action(icon: .listEnd, title: "Add to queue") { player.enqueue(media, .last) },
        ]
    }

    /// Appended "Report" row — presents the report sheet over this one.
    private var reportRow: some View {
        OptionSheetRow(icon: .flag, title: "Report track") { showReport = true }
            .disabled(loadingID != nil)
    }

    /// Artist and meta collapsed onto the single subtitle line the header allows.
    private var headerSubtitle: String? {
        let parts = [artist, meta].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ action: Action) -> some View {
        OptionSheetRow(
            icon: action.icon,
            title: action.title,
            subtitle: action.subtitle,
            tint: action.isDestructive ? Color.vError : Color.vText
        ) {
            if let confirm = action.confirm {
                pendingConfirm = confirm
            } else if action.awaitsCompletion {
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
        } trailing: {
            if loadingID == action.id {
                ProgressView().controlSize(.small)
            }
        }
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
    /// The label's font — the host sheet's row-title font, so the row reads
    /// as one of the list.
    var titleFont: Font = AppFont.trackTitle
    /// Name cap — 50, the server's cap for playlists and folders alike.
    var maxLength = 50
    let onCreate: (String) async -> Bool

    @State private var expanded = false
    @State private var name = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // The + tile doubles as the cancel (×) while the field is open.
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    expanded.toggle()
                    if !expanded { name = "" }
                }
                // Focus once the field is mounted (same-tick focus doesn't land).
                if expanded { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
            } label: {
                tile
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel(expanded ? "Cancel" : label)

            if expanded {
                field
                    .transition(.opacity)
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { expanded = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                } label: {
                    HStack {
                        Text(label)
                            .font(titleFont)
                            .foregroundStyle(Color.vText)
                        Spacer(minLength: 8)
                    }
                    .frame(height: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    /// The app's standard field (vField card, body text) with the create
    /// action as an ink pill inside it.
    private var field: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $name,
                prompt: Text(placeholder).foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit { submit() }
            .disabled(busy)
            .charLimited($name, maxLength)

            Button { submit() } label: {
                ZStack {
                    Text("Create").font(.appFootnoteMedium).opacity(busy ? 0 : 1)
                    if busy { ProgressView().controlSize(.small).tint(Color.vOnInverse) }
                }
                .foregroundStyle(Color.vOnInverse)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.vInverse, in: Capsule())
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || busy)
            .opacity(canSubmit ? 1 : 0.4)
            .animation(.smooth(duration: 0.15), value: canSubmit)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(Color.vControl)
            LucideIcon(expanded ? .x : .plus, .lg)
                .foregroundStyle(Color.vText2)
                .contentTransition(.opacity)
        }
        .frame(width: 48, height: 48)
        .contentShape(.rect)
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
