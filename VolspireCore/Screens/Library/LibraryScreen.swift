//
//  LibraryScreen.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

struct LibraryScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @State private var viewModel = LibraryScreenViewModel()
    @State private var selectedTrack: ApiUserLike? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Library")
                    .font(.system(size: 26, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 8)
            .padding(.bottom, 12)

            switch viewModel.loadingState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView(
                    "Something went wrong",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded where viewModel.likedTracks.isEmpty:
                ContentUnavailableView(
                    "No Liked Songs",
                    systemImage: "heart",
                    description: Text("Songs you like will appear here")
                )
            case .loaded:
                List(viewModel.likedTracks) { track in
                    HStack(spacing: 12) {
                        ArtworkView(
                            track.coverUrl.flatMap { URL(string: $0) }.map { .webImage($0) } ?? .radio(name: track.title),
                            cornerRadius: 4
                        )
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 15))
                                .lineLimit(1)
                            if let artist = track.artist?.username {
                                Text(artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if let activity = viewModel.mediaActivity(MediaID(track.trackId)) {
                            MediaActivityIndicator(state: activity)
                                .foregroundStyle(Color.brand)
                        }

                        Button {
                            selectedTrack = track
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 56)
                    .contentShape(.rect)
                    .onTapGesture {
                        viewModel.play(track)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
                .refreshable {
                    await viewModel.refreshLikes()
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationBarHidden(true)
        .gradientBackground()
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            await viewModel.loadLikes()
        }
        .sheet(item: $selectedTrack) { track in
            LibraryTrackSheet(track: track, viewModel: viewModel, router: router) {
                selectedTrack = nil
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    LibraryScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
