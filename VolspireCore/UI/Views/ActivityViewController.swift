//
//  ActivityViewController.swift
//  Volspire
//
//

import Photos
import Services
import SwiftUI
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension UIApplication {
    /// Top-most presented view controller — the correct anchor for presenting a
    /// share/activity sheet above whatever is currently on screen.
    static var topPresenter: UIViewController? {
        guard let scene = shared.connectedScenes.first as? UIWindowScene,
              let root = (scene.windows.first { $0.isKeyWindow } ?? scene.windows.first)?.rootViewController
        else { return nil }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        return presenter
    }

    /// Presents a system share sheet from the top-most presenter (wiring the iPad
    /// popover anchor). Centralises the block previously copy-pasted across the
    /// track / collection / file share actions.
    static func presentActivitySheet(_ items: [Any]) {
        guard let presenter = topPresenter else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = presenter.view
        presenter.present(vc, animated: true)
    }

    /// "Save to Files": the system export picker for a local file (copied out,
    /// so the temp original can go).
    static func presentSaveToFiles(_ fileURL: URL) {
        guard let presenter = topPresenter else { return }
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        presenter.present(picker, animated: true)
    }
}

/// Downloading message attachments: to a temp file (Share / Save to Files) or
/// into the photo library (add-only permission).
enum AttachmentDownloads {
    /// Fetches `url` into a uniquely-named temp file. The name is sender-
    /// controlled, so only its last path component is used (no `..` escapes).
    static func toTempFile(_ url: URL, name: String?, fallback: String = "attachment") async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)
        let safeName = ((name ?? fallback) as NSString).lastPathComponent
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(safeName.isEmpty ? fallback : safeName)")
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    /// Saves an image to Photos (asks for add-only access the first time).
    /// Returns false if access was denied or the save failed.
    static func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }

    /// Downloads an image attachment and saves it to Photos.
    static func saveToPhotos(from url: URL) async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return false }
        return await saveToPhotos(image)
    }
}

enum ShareActions {
    /// THE share-a-track flow: canonical copy + the track's web link + the
    /// analytics event. (Three hand-rolled variants had drifted — one shared
    /// without the link, one without logging the event.)
    @MainActor
    static func shareTrack(title: String, trackId: String?) {
        AnalyticsService.shared?.log(
            .shareClicked,
            trackId: trackId,
            metadata: ["kind": "track", "method": "share_sheet"]
        )
        var text = "Check out \"\(title)\" on Volspire!"
        if let trackId {
            text += " https://volspire.com/track/\(trackId)"
        }
        UIApplication.presentActivitySheet([text])
    }
}
