//
//  HomeScreen.swift
//  Volspire
//
//  Created by GitHub Copilot on 01.02.2026.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct HomeScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @State private var viewModel = HomeScreenViewModel()
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Loading or Error State
                if case .loading = viewModel.loadingState, viewModel.featuredItems.isEmpty {
                    loadingView
                } else {
                    // Search Bar
                    searchBar
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    // Filter Pills
                    filterPills
                        .padding(.bottom, 12)

                    // Following Section
                    if !viewModel.following.isEmpty {
                        followingSection
                            .padding(.bottom, 20)
                    }

                    // Hero Section
                    heroSection
                        .padding(.top, 8)

                    // Recommended Section
                    horizontalSection(
                        title: "Recommended for you",
                        tracks: viewModel.recommendedTracks
                    )
                    .padding(.top, 24)

                    // Trending Section
                    horizontalSection(
                        title: "Trending Now",
                        tracks: viewModel.trendingTracks
                    )
                    .padding(.top, 24)

                    // New Releases Section
                    horizontalSection(
                        title: "New Releases",
                        tracks: viewModel.newReleases
                    )
                    .padding(.top, 24)

                    // Top Producers Section
                    topProducersSection
                        .padding(.top, 24)

                    // Recently Played Section
                    horizontalSection(
                        title: "Recently Played",
                        tracks: viewModel.recentlyPlayed
                    )
                    .padding(.top, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            await viewModel.loadHomeData()
        }
        .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
        .toolbarTitleDisplayMode(.inlineLarge)
        .gradientBackground()
    }
    
    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
    }
}

// MARK: - Search Bar

private extension HomeScreen {
    var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Search songs, artists, producers...")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Filter Pills

private extension HomeScreen {
    var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.filters) { filter in
                    FilterPillButton(
                        filter: filter,
                        isActive: viewModel.activeFilters.contains(filter.id)
                    ) {
                        viewModel.toggleFilter(filter.id)
                    }
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
        }
    }
}

struct FilterPillButton: View {
    let filter: HomeFilter
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(filter.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isActive 
                        ? Color.primary.opacity(0.9)
                        : Color(.tertiarySystemFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Following Section

private extension HomeScreen {
    var followingSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Following")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    // TODO: Navigate to all following
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.following) { user in
                        FollowingUserView(user: user) {
                            router.navigateToProfile(userId: user.id)
                        }
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }
        }
    }
}

struct FollowingUserView: View {
    let user: FollowingUser
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                if let imageURL = user.profileImageURL {
                    KFImage(imageURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color(.systemBackground), lineWidth: 2)
                        )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                }

                Text(user.username)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero Section

private extension HomeScreen {
    var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, ViewConst.screenPaddings)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.featuredItems) { item in
                        HeroCardView(item: item)
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }
        }
    }
}

struct HeroCardView: View {
    let item: FeaturedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image
            ZStack(alignment: .bottomLeading) {
                if let imageURL = item.imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: 300, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 300, height: 170)
                }

                // Overlay gradient
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Text overlay
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)

                    Text(item.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(12)
            }
            .frame(width: 300, height: 170)
        }
    }
}

// MARK: - Horizontal Section

private extension HomeScreen {
    func horizontalSection(title: String, tracks: [HomeTrack]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Button("See All") {
                    // TODO: Navigate to full list
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, ViewConst.screenPaddings)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tracks) { track in
                        HorizontalTrackCardView(track: track)
                            .onTapGesture {
                                viewModel.playTrack(track)
                            }
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }
        }
    }
}

struct HorizontalTrackCardView: View {
    let track: HomeTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image
            if let coverURL = track.coverURL {
                KFImage(coverURL)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray4))
                    .frame(width: 150, height: 150)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - Top Producers Section

private extension HomeScreen {
    var topProducersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Producers")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Button("See All") {
                    // TODO: Navigate to full list
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, ViewConst.screenPaddings)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.topProducers) { producer in
                        ProducerCardView(producer: producer) {
                            router.navigateToProfile(userId: producer.id)
                        }
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }
        }
    }
}

struct ProducerCardView: View {
    let producer: FollowingUser
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                if let imageURL = producer.profileImageURL {
                    KFImage(imageURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 100, height: 100)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                }

                Text(producer.username)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("Producer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    HomeScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
