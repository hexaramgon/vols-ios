//
//  LibraryTrackSheet.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct LibraryTrackSheet: View {
    let track: ApiUserLike
    let viewModel: LibraryScreenViewModel
    let router: Router
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isRemoving = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Track Info

            HStack(spacing: 14) {
                ArtworkView(
                    track.coverUrl.flatMap { URL(string: $0) }.map { .webImage($0) } ?? .radio(name: track.title),
                    cornerRadius: 8
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)

                    if let artist = track.artist?.username {
                        Text(artist)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let streams = track.streams {
                        Text("\(streams.formatted()) streams")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 20)

            // MARK: - Actions

            VStack(spacing: 0) {
                // Go to Artist
                if let artist = track.artist {
                    sheetAction(
                        icon: "person.fill",
                        title: "Go to Artist",
                        subtitle: artist.username
                    ) {
                        dismiss()
                        onDismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            router.navigateToProfile(userId: artist.userId)
                        }
                    }
                }

                // Share
                sheetAction(
                    icon: "square.and.arrow.up",
                    title: "Share Track",
                    subtitle: nil
                ) {
                    shareTrack()
                }

                // Remove from Library
                sheetAction(
                    icon: "heart.slash.fill",
                    title: "Remove from Library",
                    subtitle: nil,
                    isDestructive: true,
                    isLoading: isRemoving
                ) {
                    Task {
                        isRemoving = true
                        await viewModel.removeFromLibrary(track)
                        isRemoving = false
                        dismiss()
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Components

    private func sheetAction(
        icon: String,
        title: String,
        subtitle: String?,
        isDestructive: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? .red : .primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(isDestructive ? .red : .primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(.systemGray3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func shareTrack() {
        let shareText = "Check out \"\(track.title)\" on Volspire!"
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController
        {
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            activityVC.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activityVC, animated: true)
        }
    }
}
