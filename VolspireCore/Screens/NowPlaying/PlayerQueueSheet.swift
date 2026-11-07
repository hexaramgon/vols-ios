//
//  PlayerQueueSheet.swift
//  Volspire
//
//  The expanded player's queue: what already played (dimmed, above), the
//  current item, and what's up next — in the player's live play order, so
//  shuffle reorders it. Tap a row to jump there; Up next rows drag by their
//  handle to reorder; × removes a row. The queue itself is owned by
//  `MediaPlayer.items`; edits route through PlayerController.
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct PlayerQueueSheet: View {
    @Environment(PlayerController.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var currentIndex: Int? {
        model.state.currentMediaID.flatMap { model.queue.firstIndex(of: $0) }
    }

    private var earlier: [MediaID] {
        guard let currentIndex else { return [] }
        return Array(model.queue[..<currentIndex])
    }

    private var upNext: [MediaID] {
        guard let currentIndex else { return model.queue }
        return Array(model.queue[(currentIndex + 1)...])
    }

    /// Where `upNext` starts in the full queue — drag offsets are relative to it.
    private var upNextBase: Int { (currentIndex ?? -1) + 1 }

    private var subtitle: String {
        let count = model.queue.count
        let base = count == 1 ? "1 track" : "\(count) tracks"
        return model.isShuffleOn ? "\(base) · Shuffled" : base
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: .listMusic, title: "Queue", subtitle: subtitle, divider: true) { dismiss() }

            ScrollViewReader { proxy in
                List {
                    if !earlier.isEmpty {
                        sectionLabel("Played")
                        ForEach(earlier, id: \.self) { id in
                            row(id).opacity(0.5).moveDisabled(true)
                        }
                    }
                    if let current = model.state.currentMediaID, currentIndex != nil {
                        sectionLabel("Now playing")
                        row(current).id(current).moveDisabled(true)
                    }
                    upNextHeader
                    if upNext.isEmpty {
                        Text(model.repeatMode == .off
                             ? "Nothing up next — playback stops after this track."
                             : "Repeat is on — the queue starts over after this track.")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .listRowStyle()
                            .moveDisabled(true)
                    } else {
                        ForEach(upNext, id: \.self) { row($0) }
                            .onMove { source, destination in
                                model.moveQueueItems(
                                    fromOffsets: IndexSet(source.map { $0 + upNextBase }),
                                    toOffset: destination + upNextBase
                                )
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                // Always editing, so every Up next row shows its drag handle
                // (the Release reorder sheet's pattern). No onDelete → no red
                // minus circles; rows remove with their own ×.
                .environment(\.editMode, .constant(.active))
                .contentMargins(.bottom, 24, for: .scrollContent)
                // Open on the current track, history above it.
                .onAppear {
                    if let current = model.state.currentMediaID {
                        proxy.scrollTo(current, anchor: .top)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheetBackground(alwaysDark: true)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.appSubheadlineMedium)
            .foregroundStyle(Color.vText2)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowStyle()
            .moveDisabled(true)
    }

    private var upNextHeader: some View {
        HStack {
            Text("Up next")
                .font(.appSubheadlineMedium)
                .foregroundStyle(Color.vText2)
            Spacer()
            if !upNext.isEmpty, currentIndex != nil {
                Button("Clear") { withAnimation { model.clearUpNext() } }
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(Color.vText)
                    .buttonStyle(.plain)
                    .minimumHitArea(for: 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .listRowStyle()
        .moveDisabled(true)
    }

    private func row(_ id: MediaID) -> some View {
        let meta = model.meta(for: id)
        let title = meta?.title ?? ""
        let isCurrent = id == model.state.currentMediaID
        return TrackListRow(
            artwork: .placeholder(meta?.artwork, name: title),
            title: title,
            subtitle: meta?.artist.map(handle),
            activity: isCurrent ? activity : nil,
            artworkSize: 44,
            horizontalPadding: 20,
            onTap: { if !isCurrent { model.skip(to: id) } }
        ) {
            if !isCurrent {
                Button {
                    withAnimation { model.removeFromQueue(id) }
                } label: {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText3)
                        .minimumHitArea(for: IconSize.md.rawValue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from queue")
            }
        }
        .listRowStyle()
    }

    private var activity: MediaActivity {
        if model.isLoadingTrack { return .buffering }
        return model.state.isPlaying ? .playing : .paused
    }

    /// "@name" for a username; display names with spaces stay as-is (same
    /// rule as the player's byline).
    private func handle(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.hasPrefix("@") else { return name }
        return "@\(trimmed)"
    }
}

private extension View {
    /// Bare list row: no separators, inset or background — rows draw their own.
    func listRowStyle() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
