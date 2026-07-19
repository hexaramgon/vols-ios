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

    private let requestModifier = AnyModifier { request in
        var modifiedRequest = request
        modifiedRequest.timeoutInterval = 1
        return modifiedRequest
    }

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
                    options: [.requestModifier(requestModifier)]
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
