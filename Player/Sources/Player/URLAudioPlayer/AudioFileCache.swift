//
//  AudioFileCache.swift
//  Volspire
//
//  Played (and read-ahead) tracks kept on disk, LRU and size-capped, so
//  Previous, replay, repeat-all and re-tapping a recent track play at once
//  instead of re-signing the link and re-downloading the whole file.
//
//  Keyed by the stable `volspire-media:///<path>` URL only — never a signed
//  link (its token changes per signing, so it could never hit). Track media
//  can be private, so the whole cache is wiped at sign-out (`clear()`).
//  A video track is two entries under one URL: the video (`.whole`, for the
//  muted display player) and its extracted audio (`.extractedAudio`, .m4a,
//  what AudioKit plays) — both must be present for a cached video play.
//

import CryptoKit
import Foundation

enum AudioFileCache {
    /// Same scheme as `StorageService.trackMediaScheme` (Player can't import Services).
    private static let cacheableScheme = "volspire-media"
    static let maxBytes: Int64 = 500 * 1024 * 1024

    private static let directory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("played-audio", isDirectory: true)

    enum Part {
        /// The downloaded file itself (audio, or a video's video).
        case whole
        /// A video's audio track, extracted to .m4a.
        case extractedAudio
    }

    static func isCacheable(_ url: URL) -> Bool {
        url.scheme == cacheableScheme
    }

    /// The cached file for `url`, marked as just used; nil on a miss.
    static func file(for url: URL, part: Part = .whole) -> URL? {
        guard isCacheable(url) else { return nil }
        let file = path(for: url, part: part)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        touch(file)
        return file
    }

    /// Takes ownership of a fully downloaded `file` for `url` (moves it in).
    /// Returns false when it didn't — the caller still owns and deletes it.
    @discardableResult
    static func adopt(_ file: URL, for url: URL, part: Part = .whole) -> Bool {
        guard isCacheable(url) else { return false }
        let fm = FileManager.default
        let dest = path(for: url, part: part)
        // Already the cached copy (it was played from the cache).
        if file.standardizedFileURL == dest.standardizedFileURL { return true }
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: file)
            touch(dest)
            return true
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.moveItem(at: file, to: dest)
        } catch {
            return false
        }
        trimInBackground()
        return true
    }

    /// Drops both cached parts for `url` (a copy that failed to play).
    static func remove(_ url: URL) {
        guard isCacheable(url) else { return }
        for part in [Part.whole, .extractedAudio] {
            try? FileManager.default.removeItem(at: path(for: url, part: part))
        }
    }

    /// Sign-out: the next account must not inherit this one's (possibly
    /// private) audio.
    @MainActor static func clear() {
        generation += 1
        try? FileManager.default.removeItem(at: directory)
    }

    /// Bumped by `clear()`. A read-ahead started before a sign-out checks it
    /// before handing its file over, so it can't refill the cache afterwards.
    @MainActor static private(set) var generation = 0

    // MARK: - Private

    private static func path(for url: URL, part: Part) -> URL {
        let key = part == .extractedAudio ? url.absoluteString + "#extracted-audio" : url.absoluteString
        let digest = Insecure.SHA1.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        let ext = part == .extractedAudio ? "m4a"
            : url.pathExtension.isEmpty ? "mp3" : url.pathExtension.lowercased()
        return directory.appendingPathComponent(name).appendingPathExtension(ext)
    }

    /// LRU order is the file's modification date.
    private static func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    /// Deletes least-recently-used files until the cache fits `maxBytes`.
    /// The file just adopted or played is the newest, so it goes last.
    private static func trimInBackground() {
        Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys
            ) else { return }
            var entries = files.compactMap { file -> (URL, Int64, Date)? in
                guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
                return (file, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
            var total = entries.reduce(Int64(0)) { $0 + $1.1 }
            guard total > maxBytes else { return }
            entries.sort { $0.2 < $1.2 }
            for (file, size, _) in entries where total > maxBytes {
                try? FileManager.default.removeItem(at: file)
                total -= size
            }
        }
    }
}
