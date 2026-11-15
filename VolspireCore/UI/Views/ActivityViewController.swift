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
    /// `completion` gets true once the file is saved, false if the picker was
    /// cancelled (or couldn't be shown) — so callers can confirm the save.
    static func presentSaveToFiles(_ fileURL: URL, completion: ((Bool) -> Void)? = nil) {
        guard let presenter = topPresenter else { completion?(false); return }
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        let delegate = ExportPickerDelegate(completion: completion)
        picker.delegate = delegate
        // The picker holds its delegate weakly — keep it alive with the picker.
        objc_setAssociatedObject(picker, &ExportPickerDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presenter.present(picker, animated: true)
    }
}

/// Reports whether a Save to Files export finished or was cancelled.
private final class ExportPickerDelegate: NSObject, UIDocumentPickerDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    let completion: ((Bool) -> Void)?
    init(completion: ((Bool) -> Void)?) { self.completion = completion }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion?(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(false)
    }
}

/// Downloading message attachments: to a temp file (Share / Save to Files) or
/// into the photo library (add-only permission).
enum AttachmentDownloads {
    /// Fetches `url` into a temp file named exactly like the attachment (that's
    /// the name Save to Files / the share sheet use) — uniqueness comes from a
    /// per-download folder, never a prefix on the name. The name is sender-
    /// controlled, so only its last path component is used (no `..` escapes).
    static func toTempFile(_ url: URL, name: String?, fallback: String = "attachment") async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(safeFileName(name, fallback: fallback))
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    /// Sign-out: downloaded attachments (Share / Save to Files copies) are
    /// the account's private files — nothing else ever deletes them.
    static func removeAll() {
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
        )
    }

    /// Last path component only, never empty or a dot-name.
    static func safeFileName(_ name: String?, fallback: String) -> String {
        let last = ((name ?? "") as NSString).lastPathComponent
        return last.isEmpty || last == "." || last == ".." ? fallback : last
    }

    /// Saves an image to Photos (asks for add-only access the first time).
    /// Returns false if access was denied or the save failed.
    /// `name` becomes the photo's filename in Photos (else Photos makes one up).
    static func saveToPhotos(_ image: UIImage, name: String? = nil) async -> Bool {
        if let name, let data = image.jpegData(compressionQuality: 0.95) {
            // Re-encoded as JPEG, so the name's extension must say so.
            let base = (safeFileName(name, fallback: "photo") as NSString).deletingPathExtension
            return await saveToPhotos(data: data, name: base + ".jpg")
        }
        guard await canAddToPhotos() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }

    /// Downloads an image attachment and saves its original bytes to Photos
    /// under the attachment's name.
    static func saveToPhotos(from url: URL, name: String? = nil) async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              UIImage(data: data) != nil else { return false }
        return await saveToPhotos(data: data, name: safeFileName(name, fallback: "photo.jpg"))
    }

    private static func saveToPhotos(data: Data, name: String) async -> Bool {
        guard await canAddToPhotos() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = name
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }
            return true
        } catch {
            return false
        }
    }

    private static func canAddToPhotos() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
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
