//
//  VolspireApp.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import SwiftUI

@main
struct VolspireApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        GeistFont.register()
        Self.configureImageCache()
    }

    /// Bounds Kingfisher's in-memory image cache. Its default cost limit is a
    /// quarter of physical RAM (~1.5GB on a 6GB device), which — combined with
    /// full-res cover decodes — let memory grow until the OS jetsam-killed us.
    /// With covers now downsampled in `ArtworkView`, a tight cap holds plenty.
    private static func configureImageCache() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 80 * 1024 * 1024 // 80 MB
        cache.memoryStorage.config.countLimit = 100
        cache.memoryStorage.config.expiration = .seconds(180)

        // The disk cache was unbounded (Kingfisher defaults `sizeLimit` to 0), so
        // prefetching + browsing let "Documents & Data" balloon to hundreds of MB.
        // Cap it; Kingfisher trims oldest-first past the ceiling (on background/launch).
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024 // 200 MB
        cache.diskStorage.config.expiration = .days(7)
        cache.cleanExpiredDiskCache()
    }

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(appDelegate.dependencies)
                .onOpenURL { url in
                    appDelegate.dependencies?.authManager.handleURL(url)
                }
        }
    }
}
