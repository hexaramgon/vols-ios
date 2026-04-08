//
//  WorkspaceScreenViewModel.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SwiftUI

enum WorkspaceLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable @MainActor
final class WorkspaceScreenViewModel {
    var folders: [ApiUserFolder] = []
    var loadingState: WorkspaceLoadingState = .idle
    var showCreateFolder = false
    var newFolderName = ""
    var newFolderDescription = ""
    var isCreatingFolder = false
    var editingFolder: ApiUserFolder? = nil
    var editFolderName = ""
    var editFolderDescription = ""
    var isEditingFolder = false

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    func loadFolders() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading

        do {
            folders = try await supabaseService.getUserFolders()
            loadingState = .loaded
        } catch {
            print("[WorkspaceVM] Failed to load folders: \(error)")
            loadingState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        loadingState = .idle
        await loadFolders()
    }

    func createFolder() async {
        guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isCreatingFolder = true
        do {
            let desc = newFolderDescription.trimmingCharacters(in: .whitespaces)
            try await supabaseService.createFolder(
                name: newFolderName.trimmingCharacters(in: .whitespaces),
                description: desc.isEmpty ? nil : desc
            )
            newFolderName = ""
            newFolderDescription = ""
            showCreateFolder = false
            await refresh()
        } catch {
            print("[WorkspaceVM] Failed to create folder: \(error)")
        }
        isCreatingFolder = false
    }

    func startEditing(_ folder: ApiUserFolder) {
        editingFolder = folder
        editFolderName = folder.name
        editFolderDescription = folder.description ?? ""
    }

    func editFolder() async {
        guard let folder = editingFolder,
              !editFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isEditingFolder = true
        do {
            let desc = editFolderDescription.trimmingCharacters(in: .whitespaces)
            try await supabaseService.editFolder(
                folderId: folder.folderId,
                name: editFolderName.trimmingCharacters(in: .whitespaces),
                description: desc.isEmpty ? nil : desc
            )
            editingFolder = nil
            await refresh()
        } catch {
            print("[WorkspaceVM] Failed to edit folder: \(error)")
        }
        isEditingFolder = false
    }

    // MARK: - Display Helpers

    func iconColor(for folder: ApiUserFolder) -> Color {
        folder.role == "owner" ? .blue : .orange
    }

    func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateString) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString)
        }()
        guard let date else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: .now)
    }
}
