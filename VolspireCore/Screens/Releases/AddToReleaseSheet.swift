//
//  AddToReleaseSheet.swift
//  Volspire
//
//  "Add to Release" for one of your own tracks: your releases, each a toggle
//  (a track can be in several) — membership from `get_releases_for_track`,
//  changes through LibraryStore so the profile rail stays in step.
//

import DesignSystem
import Services
import SharedUtilities
import SwiftUI

struct AddToReleaseSheet: View {
    let trackId: String
    let trackTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(LibraryStore.self) private var libraryStore

    @State private var memberships: [ApiReleaseMembership] = []
    @State private var contains: Set<String> = []
    @State private var loaded = false
    /// The releases load failed (offline) — Try again, not "No releases yet".
    @State private var loadFailed = false
    @State private var busyId: String?
    @State private var error: String?

    private let storage = StorageService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .layers, title: "Add to Release", subtitle: trackTitle) { dismiss() }

            if let error { ErrorBanner(error).padding(.horizontal, 20).padding(.top, 10) }

            if !loaded {
                SkeletonRows(count: 3, thumb: .rounded(size: 44, radius: Radius.tile), horizontalPadding: 20)
                    .padding(.top, 12)
            } else if loadFailed {
                LoadErrorView(icon: .layers, title: "Couldn't load your releases") {
                    Task {
                        loaded = false
                        await load()
                    }
                }
                .padding(.top, 24)
            } else if memberships.isEmpty {
                VStack(spacing: 16) {
                    EmptyStateView(icon: .layers, title: "No releases yet",
                                   message: "Create one from New post → Release to group tracks.")
                    PrimaryButton("Create a release", size: .inline, expands: false) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .openNewPost, object: "release")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(memberships) { row($0) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .sheetBackground()
        .task { await load() }
    }

    private func row(_ release: ApiReleaseMembership) -> some View {
        let isIn = contains.contains(release.releaseId)
        return Button {
            Task { await toggle(release) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(.placeholder(storage.resolveTrackUrl(release.coverUrl).flatMap { URL(string: $0) },
                                         name: release.title), cornerRadius: Radius.tile)
                    .frame(width: 44, height: 44)
                Text(release.title).font(.appFont.trackTitle).foregroundStyle(Color.vText).lineLimit(1)
                Spacer(minLength: 8)
                if busyId == release.releaseId {
                    ProgressView().tint(Color.vText).controlSize(.small)
                } else {
                    AddedCheck(isOn: isIn)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        .disabled(busyId != nil)
    }

    private func load() async {
        do {
            let rows = try await dependencies.supabaseService.getReleasesForTrack(trackId: trackId)
            memberships = rows
            contains = Set(rows.filter(\.contains).map(\.releaseId))
            loadFailed = false
        } catch {
            debugLog("[AddToReleaseSheet] load: \(error)")
            loadFailed = memberships.isEmpty
        }
        loaded = true
    }

    private func toggle(_ release: ApiReleaseMembership) async {
        guard busyId == nil else { return }
        busyId = release.releaseId
        error = nil
        let isIn = contains.contains(release.releaseId)
        do {
            if isIn {
                try await libraryStore.removeTrack(fromRelease: release.releaseId, trackId: trackId)
                contains.remove(release.releaseId)
            } else {
                try await libraryStore.addTracks(toRelease: release.releaseId, trackIds: [trackId])
                contains.insert(release.releaseId)
                Haptics.impact(.soft)
            }
        } catch {
            debugLog("[AddToReleaseSheet] toggle: \(error)")
            self.error = "Couldn't update the release. Please try again."
        }
        busyId = nil
    }
}
