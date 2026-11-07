//
//  ProfileReleasesRail.swift
//  Volspire
//
//  The profile's grouped releases, as a rail of covers above the Tracks
//  list (ReleaseCoverCard: shadowed cover, title, "2026 · 5 tracks"). Hidden
//  when empty (releases are created from New Post). Skeleton until
//  `get_user_releases` answers (defensive empty states).
//

import DesignSystem
import Services
import SharedUtilities
import SwiftUI

struct ProfileReleasesRail: View {
    let userId: String
    /// "Releases" over the rail — off when it's the tab's only content
    /// (no tracks below it).
    var showsTitle = true

    @Environment(LibraryStore.self) private var libraryStore
    @Environment(Router.self) private var router

    private let storage = StorageService()
    private static let coverSide: CGFloat = 128

    private var releases: [ApiRelease] { libraryStore.releases(for: userId) }
    private var loaded: Bool { libraryStore.releasesLoaded(for: userId) }

    var body: some View {
        Group {
            if !loaded {
                skeleton
            } else if !releases.isEmpty {
                populated
            }
        }
        // Every visit refetches (rows already shown stay up meanwhile) —
        // someone else's releases change without this session knowing.
        .task(id: userId) { await libraryStore.loadReleases(userId: userId) }
    }

    private var header: some View {
        ProfileSectionTitle("Releases")
    }

    private var populated: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { header }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(releases.enumerated()), id: \.element.id) { i, release in
                        ReleaseCoverCard(
                            release: release,
                            coverURL: storage.resolveTrackUrl(release.coverUrl).flatMap { URL(string: $0) },
                            coverSide: Self.coverSide
                        ) {
                            router.navigateToRelease(releaseId: release.releaseId, title: release.title)
                        }
                        .staggeredAppear(i, in: "profile.releases-\(userId)")
                    }
                }
                // Room for the cover shadows.
                .padding(.vertical, 6)
            }
            .contentMargins(.horizontal, ViewConst.screenPaddings, for: .scrollContent)
            // Scrolling the rail wins over the profile's tab swipe.
            .excludesTabSwipe()
        }
        .padding(.bottom, 20)
    }

    private var skeleton: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .fill(Color.vSkeleton)
                        .frame(width: Self.coverSide, height: Self.coverSide)
                    RoundedRectangle(cornerRadius: 4).fill(Color.vSkeleton).frame(width: 96, height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(Color.vSkeleton).frame(width: 60, height: 10)
                }
            }
        }
        .shimmering()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.bottom, 20)
        .clipped()
    }
}

// MARK: - Cover card

/// A release on the rail: the square cover with the cover shadow (no panel
/// behind it), then the title and a quiet "2026 · 5 tracks" line ("Coming
/// soon" when it has no tracks yet). Private reads exactly like a private
/// track row: the cover fades back under a lock badge and the line says
/// "Hidden · only you can see it".
struct ReleaseCoverCard: View {
    let release: ApiRelease
    let coverURL: URL?
    let coverSide: CGFloat
    let action: () -> Void

    private var isPrivate: Bool { release.visibility == "private" }

    private var meta: String {
        var parts: [String] = []
        if let year = (release.releaseDate ?? release.createdAt)?.prefix(4), year.count == 4 {
            parts.append(String(year))
        }
        let n = release.trackCount ?? 0
        parts.append(n == 0 ? "Coming soon" : "\(n) track\(n == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Color.vSurface
                    .frame(width: coverSide, height: coverSide)
                    .overlay {
                        if let coverURL {
                            ArtworkView(.webImage(coverURL), cornerRadius: 0)
                        } else {
                            PlaylistCoverFallback(name: release.title)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .coverShadow()
                    // Same as ProfileMediaRow's private track.
                    .opacity(isPrivate ? 0.45 : 1)
                    .overlay {
                        if isPrivate {
                            LucideIcon(.lock, .lg)
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(release.title)
                        .font(.appFont.cardTitle)
                        .foregroundStyle(isPrivate ? Color.vText2 : Color.vText)
                        .lineLimit(1)
                    Text(isPrivate ? "Hidden · only you can see it" : meta)
                        .font(.appFont.cardSubtitle)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
            }
            .frame(width: coverSide, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(CardPress())
        .accessibilityLabel(isPrivate ? "\(release.title), private, \(meta)" : "\(release.title), \(meta)")
    }
}

// MARK: - Section title

/// The profile's section heading ("Releases", "Tracks") — section-title type
/// on the page column.
struct ProfileSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.appFont.sectionTitle)
            .foregroundStyle(Color.vText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ViewConst.screenPaddings)
    }
}
