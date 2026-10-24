//
//  StorageService.swift
//  Services
//
//  Mirrors the URL signing logic from volspire-ui-v2/lib/storage.ts
//  and supabase-route.ts. Resolves raw Supabase storage paths into
//  usable public or signed URLs.
//

import Foundation
import SharedUtilities
import Supabase

// MARK: - Bucket Configuration

public enum StorageBucket: String, Sendable {
    case postUploads = "post-uploads"
    case files = "files"
    case messageAttachments = "message-attachments"
    case userAvatars = "user-avatars"
    case userBanners = "user-banners"
    case packs = "packs"
    case applicationUploads = "application-uploads"
    case trackAssets = "track-assets"

    /// Private buckets require signed URLs; public buckets use getPublicURL.
    public var isPrivate: Bool {
        switch self {
        case .files, .messageAttachments, .trackAssets: return true
        default: return false
        }
    }
}

extension SupabaseStorageClient {
    /// Type-safe bucket selection so call sites reference the `StorageBucket`
    /// enum (single source of truth) rather than raw bucket-name strings.
    func from(_ bucket: StorageBucket) -> StorageFileApi { from(bucket.rawValue) }
}

// MARK: - Storage Service

public final class StorageService: Sendable {
    private let client: SupabaseClient

    /// Signed URL expiry in seconds (1 hour, matching the web app).
    public static let signedUrlExpiry: Int = 3600

    public init(client: SupabaseClient = supabaseClient) {
        self.client = client
    }

    // MARK: - Path Extraction

    /// Extracts the bare storage path from a value that may be a full Supabase URL.
    ///
    /// Handles all three Supabase object URL forms (matching the web app's
    /// `extractPath` in `lib/storage.ts`):
    ///   - public:        `…/storage/v1/object/public/<bucket>/<path>`
    ///   - authenticated: `…/storage/v1/object/authenticated/<bucket>/<path>`
    ///   - signed:        `…/storage/v1/object/sign/<bucket>/<path>?token=…`
    public static func extractPath(bucket: StorageBucket, from pathOrUrl: String) -> String {
        let bucketName = bucket.rawValue

        // Any of the object URL forms — strip the prefix (and trailing query).
        for marker in [
            "/object/public/\(bucketName)/",
            "/object/authenticated/\(bucketName)/",
            "/object/sign/\(bucketName)/",
        ] {
            if let range = pathOrUrl.range(of: marker) {
                let rest = String(pathOrUrl[range.upperBound...])
                let pathWithoutQuery = rest.components(separatedBy: "?").first ?? rest
                return pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
            }
        }

        // Already a bare path
        return pathOrUrl
    }

    // MARK: - Public URLs

    /// Returns the public URL for a path in a public bucket. No network call.
    public func publicUrl(bucket: StorageBucket, pathOrUrl: String?) -> String? {
        guard let pathOrUrl, !pathOrUrl.isEmpty else { return nil }
        let path = Self.extractPath(bucket: bucket, from: pathOrUrl)
        return try? client.storage
            .from(bucket.rawValue)
            .getPublicURL(path: path)
            .absoluteString
    }

    // MARK: - Signed URLs (Private Buckets)

    /// path → (signed url, wall-clock expiry) memo. Signing is a network
    /// round-trip; without this every folder open (and every folder-change
    /// event) re-signed the whole file list even when the RPC itself was a
    /// cache hit. Entries live for the signature's validity minus a 5-minute
    /// safety margin; sign-out clears it via `clearSignedUrlMemo()`.
    private actor SignedUrlMemo {
        private var entries: [String: (url: String, expiresAt: Date)] = [:]

        func lookup(_ key: String) -> String? {
            guard let entry = entries[key] else { return nil }
            guard entry.expiresAt > Date() else {
                entries.removeValue(forKey: key)
                return nil
            }
            return entry.url
        }

        func store(_ key: String, url: String, validFor seconds: TimeInterval) {
            // Sweep opportunistically so dead entries can't accumulate.
            if entries.count > 512 {
                let now = Date()
                entries = entries.filter { $0.value.expiresAt > now }
            }
            entries[key] = (url, Date().addingTimeInterval(seconds))
        }

        func clear() { entries.removeAll() }
    }

    /// Static: view models create their own StorageService instances, and the
    /// memo must be shared across all of them (and clearable at sign-out).
    private static let signedUrlMemo = SignedUrlMemo()

    /// Drops all memoized signed URLs (call on sign-out).
    public static func clearSignedUrlMemo() async {
        await signedUrlMemo.clear()
    }

    private var memoValidity: TimeInterval { TimeInterval(Self.signedUrlExpiry - 300) }

    /// Creates a signed URL for a private bucket. Returns nil on failure.
    public func signUrl(bucket: StorageBucket, pathOrUrl: String?) async -> String? {
        guard let pathOrUrl, !pathOrUrl.isEmpty else { return nil }
        let path = Self.extractPath(bucket: bucket, from: pathOrUrl)
        let key = "\(bucket.rawValue)/\(path)"
        if let memoized = await Self.signedUrlMemo.lookup(key) { return memoized }
        do {
            let url = try await client.storage
                .from(bucket.rawValue)
                .createSignedURL(path: path, expiresIn: Self.signedUrlExpiry)
            await Self.signedUrlMemo.store(key, url: url.absoluteString, validFor: memoValidity)
            return url.absoluteString
        } catch {
            debugLog("[StorageService] Failed to sign \(bucket.rawValue)/\(path): \(error)")
            return nil
        }
    }

    /// Batch-signs an array of paths for a private bucket. Memo-served paths
    /// skip the request entirely; only genuine misses go in the batch call.
    public func signUrls(bucket: StorageBucket, paths: [String?]) async -> [String?] {
        var results: [String?] = paths.map { _ in nil }
        var misses: [(index: Int, path: String, key: String)] = []
        for (i, p) in paths.enumerated() {
            guard let p, !p.isEmpty else { continue }
            let path = Self.extractPath(bucket: bucket, from: p)
            let key = "\(bucket.rawValue)/\(path)"
            if let memoized = await Self.signedUrlMemo.lookup(key) {
                results[i] = memoized
            } else {
                misses.append((i, path, key))
            }
        }

        guard !misses.isEmpty else { return results }

        do {
            let signedData = try await client.storage
                .from(bucket.rawValue)
                .createSignedURLs(paths: misses.map(\.path), expiresIn: Self.signedUrlExpiry)

            for (i, miss) in misses.enumerated() where i < signedData.count {
                let url = signedData[i].absoluteString
                results[miss.index] = url
                await Self.signedUrlMemo.store(miss.key, url: url, validFor: memoValidity)
            }
            return results
        } catch {
            debugLog("[StorageService] Batch sign failed for \(bucket.rawValue): \(error)")
            return results
        }
    }

    // MARK: - Resolve URL (Auto public/signed)

    /// Resolves a storage path or URL into a usable URL.
    /// Uses public URL for public buckets, signed URL for private buckets.
    public func resolveUrl(bucket: StorageBucket, pathOrUrl: String?) async -> String? {
        guard let pathOrUrl, !pathOrUrl.isEmpty else { return nil }
        if bucket.isPrivate {
            return await signUrl(bucket: bucket, pathOrUrl: pathOrUrl)
        } else {
            return publicUrl(bucket: bucket, pathOrUrl: pathOrUrl)
        }
    }

    // MARK: - Track URL Signing

    /// Resolves audio_url and cover_url paths into full public URLs.
    /// `post-uploads` is a public bucket, so no signing is needed — just URL construction.
    /// Matches the behavior of `signTracksServer()` in the Next.js app.
    public func resolveTrackUrl(_ pathOrUrl: String?) -> String? {
        publicUrl(bucket: .postUploads, pathOrUrl: pathOrUrl)
    }

    // MARK: - Folder File URL Signing

    /// Signs folder file URLs:
    /// - Regular files (private `files` bucket) → signed URLs
    /// - Track references → public `post-uploads` URLs for audio/cover
    public func signFolderFileUrls(files: [ApiFolderFile]) async -> [ApiFolderFile] {
        var results = files

        // Separate regular files from track references
        let regularIndices = files.indices.filter { files[$0].type != "track" }
        let trackIndices = files.indices.filter { files[$0].type == "track" }

        // Sign private file URLs in batch
        if !regularIndices.isEmpty {
            let paths = regularIndices.map { files[$0].fileUrl }
            let signed = await signUrls(bucket: .files, paths: paths)
            for (i, fileIndex) in regularIndices.enumerated() {
                results[fileIndex] = results[fileIndex].withSignedFileUrl(signed[i])
            }
        }

        // Resolve public URLs for track references
        for idx in trackIndices {
            let file = results[idx]
            results[idx] = file
                .withSignedTrackCoverUrl(publicUrl(bucket: .postUploads, pathOrUrl: file.trackCoverUrl))
                .withSignedTrackAudioUrl(publicUrl(bucket: .postUploads, pathOrUrl: file.trackAudioUrl))
        }

        return results
    }

    // MARK: - Message Attachment URL Signing

    /// Signs a message attachment URL from the private `message-attachments` bucket.
    public func signAttachmentUrl(pathOrUrl: String?) async -> String? {
        await signUrl(bucket: .messageAttachments, pathOrUrl: pathOrUrl)
    }

    /// Batch-signs message attachment URLs.
    public func signAttachmentUrls(paths: [String?]) async -> [String?] {
        await signUrls(bucket: .messageAttachments, paths: paths)
    }

    // MARK: - Profile Image URLs

    /// Resolves a user avatar URL (public bucket).
    public func avatarUrl(pathOrUrl: String?) -> String? {
        publicUrl(bucket: .userAvatars, pathOrUrl: pathOrUrl)
    }

    /// Resolves a user banner URL (public bucket).
    public func bannerUrl(pathOrUrl: String?) -> String? {
        publicUrl(bucket: .userBanners, pathOrUrl: pathOrUrl)
    }
}

// MARK: - ApiFolderFile Signing Helpers

extension ApiFolderFile {
    func withSignedFileUrl(_ url: String?) -> ApiFolderFile {
        ApiFolderFile(
            fileId: fileId, name: name, fileUrl: url, fileType: fileType,
            fileSize: fileSize, timespan: timespan, ownerId: ownerId,
            createdAt: createdAt, uploaderUsername: uploaderUsername,
            uploaderProfileImageUrl: uploaderProfileImageUrl, type: type,
            trackId: trackId, trackTitle: trackTitle, trackArtist: trackArtist,
            trackArtistId: trackArtistId, trackCoverUrl: trackCoverUrl,
            trackAudioUrl: trackAudioUrl, trackVisibility: trackVisibility
        )
    }

    func withSignedTrackCoverUrl(_ url: String?) -> ApiFolderFile {
        ApiFolderFile(
            fileId: fileId, name: name, fileUrl: fileUrl, fileType: fileType,
            fileSize: fileSize, timespan: timespan, ownerId: ownerId,
            createdAt: createdAt, uploaderUsername: uploaderUsername,
            uploaderProfileImageUrl: uploaderProfileImageUrl, type: type,
            trackId: trackId, trackTitle: trackTitle, trackArtist: trackArtist,
            trackArtistId: trackArtistId, trackCoverUrl: url,
            trackAudioUrl: trackAudioUrl, trackVisibility: trackVisibility
        )
    }

    func withSignedTrackAudioUrl(_ url: String?) -> ApiFolderFile {
        ApiFolderFile(
            fileId: fileId, name: name, fileUrl: fileUrl, fileType: fileType,
            fileSize: fileSize, timespan: timespan, ownerId: ownerId,
            createdAt: createdAt, uploaderUsername: uploaderUsername,
            uploaderProfileImageUrl: uploaderProfileImageUrl, type: type,
            trackId: trackId, trackTitle: trackTitle, trackArtist: trackArtist,
            trackArtistId: trackArtistId, trackCoverUrl: trackCoverUrl,
            trackAudioUrl: url, trackVisibility: trackVisibility
        )
    }
}
