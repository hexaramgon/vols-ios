//
//  URL+Extensions.swift
//  SharedUtilities
//
//

import Kingfisher
import UIKit

public extension URL {
    var image: UIImage? {
        get async {
            await ImageLoader.shared.getImage(for: self)
        }
    }

    var isFileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

private actor ImageLoader {
    static let shared = ImageLoader()

    /// Was 1s — on a slow network lock-screen art and the player tint came
    /// back empty. A normal timeout; callers already run this off the UI path.
    private let requestModifier = AnyModifier { request in
        var modifiedRequest = request
        modifiedRequest.timeoutInterval = 10
        return modifiedRequest
    }

    /// Callers are lock-screen artwork and colour extraction — neither needs
    /// the full-res original (~4MB decoded per 1024px cover, kept in the
    /// memory cache on every track change). 800px covers lock-screen art.
    private let processor = DownsamplingImageProcessor(size: CGSize(width: 800, height: 800))

    private var loadingTasks: [URL: Task<UIImage?, Never>] = [:]

    func getImage(for url: URL) async -> UIImage? {
        if let existingTask = loadingTasks[url] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> {
            let result: UIImage?
            do {
                let image = try await KingfisherManager.shared.retrieveImage(
                    with: url,
                    options: [.requestModifier(requestModifier), .processor(processor), .cacheOriginalImage]
                ).image
                result = image
            } catch {
                result = nil
            }
            return result
        }

        loadingTasks[url] = task
        let result = await task.value
        loadingTasks[url] = nil
        return result
    }
}
