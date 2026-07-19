//
//  ActivityViewController.swift
//  Volspire
//
//

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
