//
//  MarketplaceModel.swift
//  Volspire
//
//  The Home Marketplace tab's data: beats for sale (tracks with a paid
//  license, cheapest price), sample packs and services (`get_explore_data`).
//  Display-ready values only, so the tab's cards don't touch API types.
//
//  While monetization is off the live tables are nearly empty, so the DEBUG
//  design preview (`FeatureFlags.marketplacePreview`) falls back to sample
//  listings — clearly flagged (`isSample`), never navigable, never shipped.
//

import Foundation
import Services
import SharedUtilities

struct MarketBeat: Identifiable, Hashable {
    var id: String { track.id }
    let track: HomeTrack
    let price: Double
    let currency: String?
}

struct MarketPack: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let price: Double
    let fileCount: Int?
    let rating: Double?
    let coverURL: URL?
    let gradient: String?
    let creator: String
    /// The live row (nil for preview samples), for the detail screen.
    let api: ApiMarketplacePack?
}

struct MarketService: Identifiable, Hashable {
    let id: String
    let title: String
    let type: String
    let price: Double
    let deliveryDays: Int?
    let rating: Double?
    let coverURL: URL?
    let gradient: String?
    let artist: String
    let artistAvatarURL: URL?
    let api: ApiMarketplaceService?
}

@MainActor @Observable
final class MarketplaceModel {
    private(set) var beats: [MarketBeat] = []
    private(set) var packs: [MarketPack] = []
    private(set) var services: [MarketService] = []
    /// Flips on the first response (success or failure) — skeletons until then.
    private(set) var loaded = false
    /// Showing preview samples instead of live listings.
    private(set) var isSample = false

    private let storage = StorageService()

    func loadIfNeeded(_ service: SupabaseService) async {
        guard !loaded else { return }
        await load(service)
    }

    func load(_ service: SupabaseService) async {
        async let explore = try? service.getExploreData()
        async let prices = try? service.getForSaleTrackPrices()
        let (data, priceRows) = await (explore, prices)

        var liveBeats: [MarketBeat] = []
        if let priceRows, !priceRows.isEmpty {
            let byId = Dictionary(uniqueKeysWithValues: priceRows.map { ($0.trackId, $0) })
            let tracks = (try? await service.getTracksByIds(Array(byId.keys))) ?? []
            liveBeats = tracks.compactMap { t in
                guard let p = byId[t.trackId] else { return nil }
                let track = HomeTrack(
                    id: t.trackId,
                    title: t.title ?? "Untitled",
                    artist: t.artistUsername ?? "unknown",
                    coverURL: storage.resolveTrackUrl(t.coverUrl).flatMap { URL(string: $0) },
                    audioURL: storage.resolveTrackUrl(t.audioUrl).flatMap { URL(string: $0) },
                    streams: nil,
                    durationMs: nil,
                    artistId: t.artistUserId,
                    artistAvatarURL: storage.publicUrl(bucket: .userAvatars, pathOrUrl: t.artistImageUrl).flatMap { URL(string: $0) }
                )
                return MarketBeat(track: track, price: p.price, currency: p.currency)
            }
            .sorted { $0.price < $1.price }
        }
        let livePacks = (data?.packs ?? []).map(pack)
        let liveServices = (data?.services ?? []).map(serviceItem)

        if FeatureFlags.marketplacePreview, livePacks.isEmpty, liveServices.isEmpty {
            // Nothing's published yet: show the design with samples (keeping
            // any real beats — those play).
            beats = liveBeats.isEmpty ? MarketplaceSamples.beats : liveBeats
            packs = MarketplaceSamples.packs
            services = MarketplaceSamples.services
            isSample = true
        } else {
            beats = liveBeats
            packs = livePacks
            services = liveServices
            isSample = false
        }
        loaded = true
    }

    private func pack(_ p: ApiMarketplacePack) -> MarketPack {
        MarketPack(
            id: p.packId, name: p.name, type: p.packType ?? "Pack", price: p.price ?? 0,
            fileCount: p.fileCount, rating: p.avgRating,
            coverURL: storage.resolveTrackUrl(p.coverUrl).flatMap { URL(string: $0) },
            gradient: p.gradient, creator: p.creator?.username ?? "unknown", api: p
        )
    }

    private func serviceItem(_ s: ApiMarketplaceService) -> MarketService {
        MarketService(
            id: s.serviceId, title: s.title, type: s.serviceType ?? "Service", price: s.price ?? 0,
            deliveryDays: s.deliveryTimeDays, rating: s.avgRating,
            coverURL: storage.resolveTrackUrl(s.coverUrl).flatMap { URL(string: $0) },
            gradient: s.gradient, artist: s.artist?.username ?? "unknown",
            artistAvatarURL: storage.publicUrl(bucket: .userAvatars, pathOrUrl: s.artist?.profileImageUrl).flatMap { URL(string: $0) },
            api: s
        )
    }
}

/// Sample listings for the DEBUG design preview only.
enum MarketplaceSamples {
    static let beats: [MarketBeat] = [
        ("Night Drive", "nvs", 29.0), ("Glass Hours", "joolyuh", 35.0), ("Static Bloom", "dalawsofmusic", 49.0),
        ("Low Tide", "psyknick", 25.0), ("Paper Planes Pt. 2", "clovisreyes", 60.0),
    ].enumerated().map { i, b in
        MarketBeat(
            track: HomeTrack(id: "sample-beat-\(i)", title: b.0, artist: b.1, coverURL: nil, audioURL: nil, streams: nil, durationMs: nil),
            price: b.2, currency: "USD"
        )
    }

    // Packs: name, type, price, files, rating, creator, description, formats, tags.
    private static let packRows: [(String, String, Double, Int, Double?, String, String, [String], [String])] = [
        ("Dusty Keys Vol. 1", "Loop Kit", 24, 48, 4.8, "nvs",
         "Warm, tape-saturated piano and Rhodes loops recorded through a 4-track. Every loop is tempo and key labelled, ready to flip.",
         ["WAV"], ["lofi", "keys", "soul"]),
        ("808 Survival Kit", "Drum Kit", 19, 120, 4.6, "dalawsofmusic",
         "120 hard-hitting 808s, kicks, snares and hats tuned for trap and drill. Mixed loud so they sit right out of the box.",
         ["WAV"], ["trap", "drill", "808"]),
        ("Velvet Vox", "Vocal Pack", 29, 64, 4.9, "joolyuh",
         "Dry and wet vocal chops, ad-libs and full hooks from a session singer. Royalty-free for any release.",
         ["WAV", "MIDI"], ["vocals", "rnb", "hooks"]),
        ("Analog Dreams", "Presets", 15, 32, nil, "psyknick",
         "32 Serum presets modelled on vintage polysynths: lush pads, plucks and leads.",
         ["FXP"], ["serum", "synth", "presets"]),
    ]

    // Services: title, type, price, delivery days, rating, artist, description.
    private static let serviceRows: [(String, String, Double, Int, Double?, String, String)] = [
        ("Radio-ready mix in 5 days", "Mixing", 120, 5, 4.9, "nvs",
         "I'll mix your song to sit next to anything on the radio: balanced, punchy and wide, with clear vocals. Send stems and a reference track."),
        ("Loud, clean masters for streaming", "Mastering", 45, 2, 4.7, "dalawsofmusic",
         "Streaming-ready masters hitting −9 to −11 LUFS without crushing your dynamics. Includes a clean and a loud version."),
        ("Feature verse — melodic rap", "Feature", 200, 7, nil, "joolyuh",
         "A 16-bar melodic rap verse written and recorded for your track, with two rounds of revisions."),
        ("Custom beat from scratch", "Production", 150, 10, 4.8, "psyknick",
         "A beat built around your references, with full stems and an exclusive license."),
    ]

    static let packs: [MarketPack] = packRows.enumerated().map { i, p in
        let id = "sample-pack-\(i)"
        return MarketPack(id: id, name: p.0, type: p.1, price: p.2, fileCount: p.3, rating: p.4,
                          coverURL: nil, gradient: nil, creator: p.5,
                          api: decode(["pack_id": id, "name": p.0, "pack_type": p.1, "price": p.2, "file_count": p.3,
                                       "avg_rating": orNull(p.4), "creator": ["username": p.5]]))
    }

    static let services: [MarketService] = serviceRows.enumerated().map { i, s in
        let id = "sample-service-\(i)"
        return MarketService(id: id, title: s.0, type: s.1, price: s.2, deliveryDays: s.3, rating: s.4,
                             coverURL: nil, gradient: nil, artist: s.5, artistAvatarURL: nil,
                             api: decode(["service_id": id, "title": s.0, "service_type": s.1, "price": s.2,
                                          "delivery_time_days": s.3, "avg_rating": orNull(s.4),
                                          "artist": ["username": s.5]]))
    }

    static func isSample(_ id: String) -> Bool { id.hasPrefix("sample-") }

    /// The full pack page for a sample (description, files, reviews).
    static func packDetail(_ id: String) -> ApiPackDetail? {
        guard let i = Int(id.replacingOccurrences(of: "sample-pack-", with: "")), packRows.indices.contains(i) else { return nil }
        let p = packRows[i]
        let ext = p.7.first?.lowercased() ?? "wav"
        let files: [[String: Any]] = (1 ... min(p.3, 12)).map { n in
            ["file_id": "\(id)-f\(n)", "name": "\(p.0) \(String(format: "%02d", n)).\(ext)", "format": p.7.first ?? "WAV",
             "is_preview": n <= 3]
        }
        return decode([
            "pack_id": id, "name": p.0, "pack_type": p.1, "description": p.6, "price": p.2, "currency": "USD",
            "formats": p.7, "tags": p.8, "file_count": p.3, "downloads": 340 + i * 57, "likes": 88 + i * 13,
            "saves": 41 + i * 9, "avg_rating": orNull(p.4), "review_count": p.4 == nil ? 0 : 12 + i * 3,
            "created_at": "2026-09-1\(i)T12:00:00Z", "creator_username": p.5,
            "seller_reputation": ["avg_rating": 4.8, "review_count": 37], "files": files,
            "reviews": p.4 == nil ? [] : sampleReviews(id), "is_published": true,
        ])
    }

    /// The full service page for a sample (packages, process, FAQs, reviews).
    static func serviceDetail(_ id: String) -> ApiServiceDetail? {
        guard let i = Int(id.replacingOccurrences(of: "sample-service-", with: "")), serviceRows.indices.contains(i) else { return nil }
        let s = serviceRows[i]
        let packages: [[String: Any]] = [
            ["name": "Basic", "price": s.2, "delivery": s.3, "revisions": 1, "features": ["1 song", "1 revision", "WAV + MP3"]],
            ["name": "Standard", "price": s.2 * 1.6, "delivery": s.3, "revisions": 3, "features": ["1 song", "3 revisions", "Stems included", "Alt versions"]],
            ["name": "Pro", "price": s.2 * 2.5, "delivery": max(1, s.3 - 2), "revisions": 5, "features": ["Up to 3 songs", "5 revisions", "Priority delivery", "Video call review"]],
        ]
        return decode([
            "service_id": id, "title": s.0, "service_type": s.1, "long_description": s.6, "price": s.2,
            "currency": "USD", "delivery_time_days": s.3, "revisions": 3, "tags": [s.1.lowercased(), "hiphop", "rnb"],
            "avg_rating": orNull(s.4), "review_count": s.4 == nil ? 0 : 20 + i * 4, "likes": 64 + i * 11, "saves": 30 + i * 7,
            "created_at": "2026-08-2\(i)T12:00:00Z",
            "artist": ["username": s.5,
                       "bio": "Engineer and producer. Credits across indie, rap and R&B releases."],
            "packages": packages,
            "process": [
                ["step": "Send your files", "description": "Stems or a session, plus a reference track."],
                ["step": "First pass", "description": "I deliver a first version within the delivery time."],
                ["step": "Revisions", "description": "Notes back and forth until it's right."],
                ["step": "Final delivery", "description": "Final files in the formats you need."],
            ],
            "deliverables": ["Final WAV (24-bit)", "MP3 for previews", "Instrumental version"],
            "faqs": [
                ["q": "What do you need from me?", "a": "Consolidated stems from bar 1, labelled, at the session's sample rate."],
                ["q": "Do you work in any genre?", "a": "Mostly hip-hop, R&B and pop, but send anything over."],
            ],
            "seller_reputation": ["avg_rating": 4.9, "review_count": 52],
            "reviews": s.4 == nil ? [] : sampleReviews(id),
        ])
    }

    private static func sampleReviews(_ id: String) -> [[String: Any]] {
        [
            ["review_id": "\(id)-r1", "rating": 5, "body": "Exactly what I needed — fast and easy to work with.",
             "created_at": "2026-10-02T12:00:00Z", "verified": true, "reviewer": ["username": "clovisreyes"]],
            ["review_id": "\(id)-r2", "rating": 4, "body": "Great quality. Would book again.",
             "created_at": "2026-09-20T12:00:00Z", "verified": true, "reviewer": ["username": "chidashiii"]],
        ]
    }

    /// Sample rows are built as the API's own JSON and decoded the way real
    /// payloads are (snake_case → camelCase), so the detail screen can't tell.
    private static func decode<T: Decodable>(_ json: [String: Any]) -> T? {
        let cleaned = json.filter { !($0.value is NSNull) }
        guard let data = try? JSONSerialization.data(withJSONObject: cleaned) else { return nil }
        return try? JSONDecoder.api.decode(T.self, from: data)
    }

    private static func orNull(_ v: Double?) -> Any { v.map { $0 as Any } ?? NSNull() }
}
