//
//  LibraryScreen.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import MediaLibrary
import SwiftUI

struct LibraryScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @State private var viewModel = LibraryScreenViewModel()

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

            if viewModel.allSongs.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your library is empty")
                )
            } else {
                List(viewModel.allSongs) { track in
                    HStack(spacing: 12) {
                        ArtworkView(
                            track.meta.artwork.map { .webImage($0) } ?? .radio(name: track.meta.title),
                            cornerRadius: 4
                        )
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.meta.title)
                                .font(.system(size: 15))
                                .lineLimit(1)
                            if let artist = track.meta.artist {
                                Text(artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if let activity = viewModel.mediaActivity(track.id) {
                            MediaActivityIndicator(state: activity)
                                .foregroundStyle(Color.brand)
                        }
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
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationBarHidden(true)
        .gradientBackground()
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
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
