//
//  DownloadedScreen.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct DownloadedScreen: View {
    @Environment(Dependencies.self) var dependencies
    @State private var viewModel = DownloadedScreenViewModel()

    var body: some View {
        content
            .navigationTitle("Downloaded")
            .task {
                viewModel.mediaState = dependencies.mediaState
            }
    }
}

private extension DownloadedScreen {
    @ViewBuilder
    var content: some View {
        if viewModel.items.isEmpty {
            empty
                .padding(.horizontal, 40)
                .offset(y: -ViewConst.compactNowPlayingHeight)
        } else {
            MediaListScreen(items: viewModel.items)
                .id(viewModel.items.count)
        }
    }

    var empty: some View {
        EmptyScreenView(
            systemImage: "icloud.and.arrow.down",
            title: "Download Music to Listen Offline",
            description: "Downloaded tracks will appear here."
        )
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    DownloadedScreen()
        .environment(dependencies)
}
