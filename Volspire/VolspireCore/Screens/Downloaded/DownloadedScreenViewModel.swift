//
//  DownloadedScreenViewModel.swift
//  Volspire
//
//

import MediaLibrary
import Observation
import SwiftUI

@Observable @MainActor
final class DownloadedScreenViewModel {
    var mediaState: MediaState?
    var items: [Media] {
        mediaState?.allTracks() ?? []
    }
}
