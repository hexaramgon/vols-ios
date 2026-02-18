//
//  SearchScreen.swift
//  Volspire
//
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct SearchScreen: View {
    @State private var viewModel = SearchScreenViewModel()
    @Environment(Dependencies.self) var dependencies
    @Environment(Router.self) var router
    @State private var isSearchPresented = false

    var body: some View {
        content
            .navigationTitle("Search")
            .toolbarTitleDisplayMode(.inlineLarge)
            .searchable(
                text: $viewModel.searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("Search your music...")
            )
            .task {
                viewModel.mediaState = dependencies.mediaState
                viewModel.player = dependencies.mediaPlayer
            }
    }
}

private extension SearchScreen {
    var content: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Searching...")
                    .padding()
            } else if let errorMessage = viewModel.errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
            }

            if viewModel.searchResults.isEmpty, !viewModel.isLoading, viewModel.errorMessage == nil {
                ContentUnavailableView.search
            } else {
                List(viewModel.searchResults) { track in
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
                                    .foregroundColor(.secondary)
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
                }
                .listStyle(.plain)
                .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
            }
        }
        .gradientBackground()
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub

    SearchScreen()
        .withRouter()
        .environment(dependencies)
}
