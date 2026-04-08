//
//  FolderContentsViewModel.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SwiftUI
import UniformTypeIdentifiers

enum FolderContentsLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable @MainActor
final class FolderContentsViewModel {
    var files: [ApiFolderFile] = []
    var loadingState: FolderContentsLoadingState = .idle
    var showFilePicker = false
    var isUploading = false
    var uploadError: String?

    let folderId: String
    let folderName: String

    private let supabaseService: SupabaseService

    init(folderId: String, folderName: String, supabaseService: SupabaseService = SupabaseService()) {
        self.folderId = folderId
        self.folderName = folderName
        self.supabaseService = supabaseService
    }

    func loadFiles() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading

        do {
            files = try await supabaseService.getFolderFiles(folderId: folderId)
            loadingState = .loaded
        } catch {
            print("[FolderContentsVM] Failed to load files: \(error)")
            loadingState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        loadingState = .idle
        await loadFiles()
    }

    func deleteFile(_ file: ApiFolderFile) async {
        do {
            try await supabaseService.deleteFile(fileId: file.fileId, folderId: folderId)
            files.removeAll { $0.id == file.id }
        } catch {
            print("[FolderContentsVM] Failed to delete file: \(error)")
            uploadError = error.localizedDescription
        }
    }

    func uploadFile(url: URL) async {
        isUploading = true
        uploadError = nil
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "FolderContents", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let fileType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

            try await supabaseService.uploadFile(
                folderId: folderId,
                fileName: fileName,
                fileData: fileData,
                fileType: fileType,
                fileSize: fileData.count
            )
            await refresh()
        } catch {
            print("[FolderContentsVM] Upload failed: \(error)")
            uploadError = error.localizedDescription
        }
        isUploading = false
    }

    // MARK: - Display Helpers

    func icon(for file: ApiFolderFile) -> String {
        guard let type = file.fileType?.lowercased() else { return "doc" }
        switch type {
        case let t where t.contains("audio"):
            return "waveform"
        case let t where t.contains("image"), let t where t.contains("png"), let t where t.contains("jpg"), let t where t.contains("jpeg"):
            return "photo"
        case let t where t.contains("video"), let t where t.contains("mp4"):
            return "film"
        case let t where t.contains("pdf"):
            return "doc.text"
        case let t where t.contains("zip"), let t where t.contains("archive"):
            return "archivebox"
        default:
            return "doc"
        }
    }

    func iconColor(for file: ApiFolderFile) -> Color {
        guard let type = file.fileType?.lowercased() else { return .secondary }
        if type.contains("audio") { return .purple }
        if type.contains("image") || type.contains("png") || type.contains("jpg") { return .green }
        if type.contains("video") || type.contains("mp4") { return .red }
        if type.contains("pdf") { return .orange }
        return .blue
    }

    func formattedSize(for file: ApiFolderFile) -> String? {
        guard let bytes = file.fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return dateString }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }

    func formattedDuration(for file: ApiFolderFile) -> String? {
        guard let seconds = file.timespan else { return nil }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
