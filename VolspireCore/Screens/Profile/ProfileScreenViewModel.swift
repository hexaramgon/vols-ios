//
//  ProfileScreenViewModel.swift
//  Volspire
//
//

import Combine
import DesignSystem
import MediaLibrary
import Observation
import Player
import Services
import SwiftUI

// MARK: - UI Models

struct ProfileTrack: Identifiable {
    let id: String
    let title: String
    let coverURL: URL?
    let audioURL: URL?
    let streams: Int
}

struct ProfileService: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let serviceType: String
    let price: String
}

enum ProfileLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - ViewModel

@Observable @MainActor
final class ProfileScreenViewModel {
    var username: String = ""
    var bio: String = ""
    var profileImageURL: URL?
    var bannerImageURL: URL?
    var location: String = ""
    var followersCount: Int = 0
    var monthlyListenersCount: Int = 0
    var trackCount: Int = 0
    var tracks: [ProfileTrack] = []
    var services: [ProfileService] = []
    var loadingState: ProfileLoadingState = .idle
    var isFollowing: Bool = false
    var isTogglingFollow: Bool = false
    var showCreateService: Bool = false
    var isCreatingService: Bool = false
    var editingService: ProfileService? = nil
    var isEditingService: Bool = false

    var latestRelease: ProfileTrack? {
        tracks.first
    }

    var curatedTracks: [ProfileTrack] {
        Array(tracks.dropFirst())
    }

    weak var mediaState: MediaState?
    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
    var cancellables = Set<AnyCancellable>()
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    func loadProfile(userId: String) async {
        guard loadingState != .loading else { return }
        loadingState = .loading

        do {
            let profile = try await supabaseService.getUserProfile(userId: userId)

            username = profile.username ?? "Unknown"
            bio = profile.bio ?? ""
            profileImageURL = profile.profileImageUrl.flatMap { URL(string: $0) }
            bannerImageURL = profile.bannerImageUrl.flatMap { URL(string: $0) }
            location = profile.location ?? ""
            followersCount = profile.followersCount ?? 0
            monthlyListenersCount = profile.monthlyListenersCount
            trackCount = profile.trackCount
            tracks = profile.tracks.map { track in
                ProfileTrack(
                    id: track.id,
                    title: track.title,
                    coverURL: track.coverUrl.flatMap { URL(string: $0) },
                    audioURL: track.audioUrl.flatMap { URL(string: $0) },
                    streams: track.streams ?? 0
                )
            }
            services = profile.services.map { mapService($0) }
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
        }
    }

    func createService(title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async {
        guard !isCreatingService else { return }
        isCreatingService = true
        do {
            let svc = try await supabaseService.createUserService(
                title: title,
                description: description,
                serviceType: serviceType,
                price: price,
                currency: currency,
                deliveryTimeDays: deliveryTimeDays
            )
            services.append(mapService(svc))
            showCreateService = false
        } catch {
            print("[ProfileVM] Failed to create service: \(error)")
        }
        isCreatingService = false
    }

    func updateService(serviceId: String, title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async {
        guard !isEditingService else { return }
        isEditingService = true
        do {
            let svc = try await supabaseService.updateUserService(
                serviceId: serviceId,
                title: title,
                description: description,
                serviceType: serviceType,
                price: price,
                currency: currency,
                deliveryTimeDays: deliveryTimeDays,
                isActive: nil
            )
            if let idx = services.firstIndex(where: { $0.id == serviceId }) {
                services[idx] = mapService(svc)
            }
            editingService = nil
        } catch {
            print("[ProfileVM] Failed to update service: \(error)")
        }
        isEditingService = false
    }

    private func mapService(_ svc: ApiUserService) -> ProfileService {
        let priceStr: String
        if let p = svc.price {
            let sym = svc.currency ?? "USD"
            priceStr = "\(sym == "USD" ? "$" : sym) \(String(format: p == p.rounded() ? "%.0f" : "%.2f", p))"
        } else {
            priceStr = "N/A"
        }
        return ProfileService(
            id: svc.id,
            title: svc.title,
            description: svc.description ?? "",
            serviceType: svc.serviceType ?? "",
            price: priceStr
        )
    }

    func toggleFollow(userId: String) async {
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        do {
            try await supabaseService.toggleFollow(targetUser: userId)
            isFollowing.toggle()
        } catch {
            print("[ProfileVM] Failed to toggle follow: \(error)")
        }
        isTogglingFollow = false
    }

    func play(_ track: ProfileTrack) {
        guard let player else { return }
        let media = mediaFor(track)
        Task { await mediaState?.addTrack(media) }
        let queueIDs = tracks.map { MediaID($0.id) }
        player.play(media.id, of: queueIDs)
    }

    private func mediaFor(_ track: ProfileTrack) -> Media {
        Media(
            id: MediaID(track.id),
            meta: MediaMeta(
                artwork: track.coverURL,
                title: track.title,
                artist: username,
                audioURL: track.audioURL
            )
        )
    }

    var profileUpdateError: String? = nil

    func uploadAvatar(userId: String, imageData: Data) async -> Bool {
        do {
            let publicURL = try await supabaseService.uploadAvatar(userId: userId, imageData: imageData)
            let _ = try await supabaseService.updateUserProfile(
                userId: userId,
                username: nil,
                bio: nil,
                accountType: nil,
                location: nil,
                profileImageUrl: publicURL.absoluteString,
                bannerImageUrl: nil,
                tags: nil
            )
            profileImageURL = publicURL
            return true
        } catch {
            print("[ProfileVM] Failed to upload avatar: \(error)")
            return false
        }
    }

    func uploadBanner(userId: String, imageData: Data) async -> Bool {
        do {
            let publicURL = try await supabaseService.uploadBanner(userId: userId, imageData: imageData)
            let _ = try await supabaseService.updateUserProfile(
                userId: userId,
                username: nil,
                bio: nil,
                accountType: nil,
                location: nil,
                profileImageUrl: nil,
                bannerImageUrl: publicURL.absoluteString,
                tags: nil
            )
            bannerImageURL = publicURL
            return true
        } catch {
            print("[ProfileVM] Failed to upload banner: \(error)")
            return false
        }
    }

    func updateProfile(userId: String, username: String, bio: String, location: String) async -> Bool {
        do {
            let result = try await supabaseService.updateUserProfile(
                userId: userId,
                username: username,
                bio: bio,
                accountType: nil,
                location: location,
                profileImageUrl: nil,
                bannerImageUrl: nil,
                tags: nil
            )
            self.username = result.username ?? username
            self.bio = result.bio ?? bio
            self.location = result.location ?? location
            profileUpdateError = nil
            return true
        } catch {
            profileUpdateError = error.localizedDescription
            print("[ProfileVM] Failed to update profile: \(error)")
            return false
        }
    }
}

extension ProfileScreenViewModel: PlayerStateObserving {}
