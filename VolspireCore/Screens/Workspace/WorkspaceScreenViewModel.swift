//
//  WorkspaceScreenViewModel.swift
//  Volspire
//
//

import Observation
import SwiftUI

struct WorkspaceItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let iconColor: Color
    let type: WorkspaceItemType
    let size: String?
    let modifiedDate: String

    enum WorkspaceItemType {
        case folder, audio, project, document, image
    }
}

@Observable @MainActor
final class WorkspaceScreenViewModel {

    var quickAccess: [WorkspaceItem] {
        [
            WorkspaceItem(
                id: "qa1", name: "Summer EP", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Feb 15"
            ),
            WorkspaceItem(
                id: "qa2", name: "Final Mix v3.wav", icon: "waveform",
                iconColor: .purple, type: .audio, size: "48 MB", modifiedDate: "Feb 14"
            ),
            WorkspaceItem(
                id: "qa3", name: "Beat Tape 2026", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Feb 12"
            ),
            WorkspaceItem(
                id: "qa4", name: "Cover Art.png", icon: "photo.fill",
                iconColor: .green, type: .image, size: "3.2 MB", modifiedDate: "Feb 10"
            ),
        ]
    }

    var files: [WorkspaceItem] {
        [
            WorkspaceItem(
                id: "f1", name: "Projects", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Today"
            ),
            WorkspaceItem(
                id: "f2", name: "Samples", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Yesterday"
            ),
            WorkspaceItem(
                id: "f3", name: "Stems", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Feb 14"
            ),
            WorkspaceItem(
                id: "f4", name: "Collabs", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Feb 12"
            ),
            WorkspaceItem(
                id: "f5", name: "Midnight Drive - Master.wav", icon: "waveform",
                iconColor: .purple, type: .audio, size: "52 MB", modifiedDate: "Today"
            ),
            WorkspaceItem(
                id: "f6", name: "Lo-Fi Session 04.wav", icon: "waveform",
                iconColor: .purple, type: .audio, size: "38 MB", modifiedDate: "Yesterday"
            ),
            WorkspaceItem(
                id: "f7", name: "Beat Sketch 17.wav", icon: "waveform",
                iconColor: .purple, type: .audio, size: "24 MB", modifiedDate: "Feb 15"
            ),
            WorkspaceItem(
                id: "f8", name: "Vocal Take 3 - Raw.wav", icon: "waveform",
                iconColor: .purple, type: .audio, size: "18 MB", modifiedDate: "Feb 14"
            ),
            WorkspaceItem(
                id: "f9", name: "Summer EP - Notes.txt", icon: "doc.text.fill",
                iconColor: .gray, type: .document, size: "2 KB", modifiedDate: "Feb 13"
            ),
            WorkspaceItem(
                id: "f10", name: "Album Cover Final.png", icon: "photo.fill",
                iconColor: .green, type: .image, size: "4.8 MB", modifiedDate: "Feb 12"
            ),
            WorkspaceItem(
                id: "f11", name: "Session Recording 02-10.wav", icon: "waveform",
                iconColor: .purple, type: .audio, size: "67 MB", modifiedDate: "Feb 10"
            ),
            WorkspaceItem(
                id: "f12", name: "Mix Reference Tracks", icon: "folder.fill",
                iconColor: .blue, type: .folder, size: nil, modifiedDate: "Feb 8"
            ),
        ]
    }
}
